#!/usr/bin/env python3
"""Timed warm-ups for BetterOpel.

Keeps a list of times the cabin should be ready by, and starts the car's
climate ten minutes ahead of each by asking psa_car_controller, the same way
the app's own button does. It does not use the programmes stored in the car.

Runs next to psa_car_controller and needs nothing but Python's standard
library.

    warmup_scheduler.py --port 5056 --psacc http://127.0.0.1:5055 --state /path/state.json

API (also answered under a /scheduler prefix, for a shared HTTPS address):

    GET /health      {"ok": true, "version": 1}
    GET /schedules   everything the app shows
    PUT /schedules   {"vin": "...", "schedules": [{"id", "hour", "minute", "days", "enabled"}]}
    POST /run        start the climate now, the same careful way a timed start does
    GET /run         how that start is going: waking, sending, waiting, then
                     confirmed, sent (no word from the car) or failed

`hour` and `minute` are the time to be ready by, in this machine's local time.
`days` are 1 (Monday) to 7 (Sunday). A schedule with no days runs once, at its
next time, and then switches itself off.
"""

import argparse
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = 1
# One climate cycle of the car, and so how far ahead of the ready time it starts.
LEAD = timedelta(minutes=10)
# A start that was missed, say because this machine was asleep, is still worth
# making for this long. After that the cabin would not be ready in time anyway.
GRACE = timedelta(minutes=8)
TICK_SECONDS = 15
MAX_SCHEDULES = 12


def log(message):
    print(f"{datetime.now().isoformat(timespec='seconds')} {message}", flush=True)


def stamp(moment):
    """A local time with its offset, so the app can place it exactly."""
    return moment.astimezone().isoformat(timespec="seconds")


class Car:
    """The few psa_car_controller calls a warm-up needs."""

    def __init__(self, base):
        self.base = base.rstrip("/")

    def get(self, path, timeout):
        with urllib.request.urlopen(f"{self.base}/{path}", timeout=timeout) as response:
            return response.read().decode("utf-8", "replace")

    def wake(self, vin):
        try:
            self.get(f"wakeup/{urllib.parse.quote(vin)}", 30)
        except (urllib.error.URLError, OSError, ValueError) as error:
            log(f"wake-up not accepted: {error}")

    def start_climate(self, vin):
        """True once the command is on its way to the car."""
        body = self.get(f"preconditioning/{urllib.parse.quote(vin)}/1", 45).strip()
        return body != "false" and '"error"' not in body

    def climate_is_on(self, vin):
        body = self.get(f"get_vehicleinfo/{urllib.parse.quote(vin)}?from_cache=0", 30)
        info = json.loads(body)
        air = ((info.get("preconditionning") or {}).get("air_conditioning") or {})
        return air.get("status") == "Enabled"


class Scheduler:
    def __init__(self, state_path, car, pace=1.0):
        self.path = state_path
        self.car = car
        # Shortens the waits inside a run; only the tests set it.
        self.pace = pace
        self.lock = threading.RLock()
        self.state = {"vin": "", "schedules": [], "fired": {}}
        # The latest start asked for by hand, for the app to follow.
        self.manual = None
        self.load()

    # --- storage ---------------------------------------------------------------

    def load(self):
        try:
            with open(self.path, encoding="utf-8") as handle:
                stored = json.load(handle)
            if isinstance(stored, dict):
                self.state.update(stored)
        except FileNotFoundError:
            pass
        except (OSError, ValueError) as error:
            log(f"could not read {self.path}: {error}")

    def save(self):
        directory = os.path.dirname(self.path)
        if directory:
            os.makedirs(directory, exist_ok=True)
        temporary = self.path + ".tmp"
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(self.state, handle, indent=1)
        os.replace(temporary, self.path)

    # --- the list --------------------------------------------------------------

    def replace(self, payload):
        """Takes the app's whole list. Returns an error text, or None."""
        if not isinstance(payload, dict) or not isinstance(payload.get("schedules"), list):
            return "Expected a list of schedules."
        incoming = payload["schedules"]
        if len(incoming) > MAX_SCHEDULES:
            return f"No more than {MAX_SCHEDULES} schedules."

        cleaned, seen = [], set()
        for entry in incoming:
            try:
                identifier = str(entry["id"])[:64]
                hour, minute = int(entry["hour"]), int(entry["minute"])
                days = sorted({int(day) for day in entry.get("days", [])})
                enabled = bool(entry.get("enabled", True))
            except (KeyError, TypeError, ValueError):
                return "A schedule is missing its id or time."
            if not identifier or identifier in seen:
                return "Each schedule needs its own id."
            if not (0 <= hour <= 23 and 0 <= minute <= 59) or any(day < 1 or day > 7 for day in days):
                return "A schedule has a time or day that does not exist."
            seen.add(identifier)
            cleaned.append({"id": identifier, "hour": hour, "minute": minute, "days": days, "enabled": enabled})

        now = datetime.now()
        with self.lock:
            before = {entry["id"]: entry for entry in self.state["schedules"]}
            for entry in cleaned:
                old = before.get(entry["id"])
                same = old and all(old.get(key) == entry[key] for key in ("hour", "minute", "days", "enabled"))
                # A run-once schedule counts from when it was last set.
                entry["armed_at"] = old.get("armed_at") if same and old.get("armed_at") else stamp(now)
                if old and old.get("last_run"):
                    entry["last_run"] = old["last_run"]
            self.state["schedules"] = cleaned
            vin = str(payload.get("vin") or "").strip().upper()
            if vin:
                self.state["vin"] = vin
            self.save()
        log(f"list replaced: {len(cleaned)} schedules")
        return None

    def view(self):
        now = datetime.now()
        with self.lock:
            schedules = []
            for entry in self.state["schedules"]:
                upcoming = self.next_ready(entry, now)
                schedules.append({
                    "id": entry["id"],
                    "hour": entry["hour"],
                    "minute": entry["minute"],
                    "days": entry["days"],
                    "enabled": entry["enabled"],
                    "next_start": stamp(upcoming - LEAD) if upcoming else None,
                    "next_ready": stamp(upcoming) if upcoming else None,
                    "last_run": entry.get("last_run"),
                })
            return {
                "version": VERSION,
                "now": stamp(now),
                "lead_minutes": int(LEAD.total_seconds() // 60),
                "has_car": bool(self.state.get("vin")),
                "schedules": schedules,
            }

    # --- timing ----------------------------------------------------------------

    @staticmethod
    def armed_at(entry):
        try:
            return datetime.fromisoformat(entry["armed_at"]).astimezone().replace(tzinfo=None)
        except (KeyError, TypeError, ValueError):
            return datetime.min

    def candidates(self, entry, now, days_ahead):
        """Ready times around now, soonest first, on the days the schedule covers."""
        for offset in range(-1, days_ahead + 1):
            day = (now + timedelta(days=offset)).date()
            ready = datetime(day.year, day.month, day.day, entry["hour"], entry["minute"])
            if entry["days"] and ready.isoweekday() not in entry["days"]:
                continue
            yield ready

    def key(self, entry, ready):
        return f"{entry['id']}@{ready.isoformat(timespec='minutes')}"

    def next_ready(self, entry, now):
        if not entry["enabled"]:
            return None
        armed = self.armed_at(entry)
        for ready in self.candidates(entry, now, 8):
            if ready - LEAD + GRACE <= now or self.key(entry, ready) in self.state["fired"]:
                continue
            if not entry["days"] and ready - LEAD + GRACE <= armed:
                continue
            return ready
        return None

    def due(self, now):
        """Schedules whose start has come and has not been made yet."""
        with self.lock:
            found = []
            for entry in self.state["schedules"]:
                if not entry["enabled"]:
                    continue
                armed = self.armed_at(entry)
                for ready in self.candidates(entry, now, 1):
                    start = ready - LEAD
                    if not (start <= now < start + GRACE):
                        continue
                    if self.key(entry, ready) in self.state["fired"]:
                        continue
                    if not entry["days"] and start + GRACE <= armed:
                        continue
                    found.append((dict(entry), ready))
                    break
            return found

    def tick(self):
        now = datetime.now()
        for entry, ready in self.due(now):
            with self.lock:
                self.state["fired"][self.key(entry, ready)] = stamp(now)
                # Old marks are of no use after a few days.
                limit = (now - timedelta(days=3)).isoformat()
                self.state["fired"] = {k: v for k, v in self.state["fired"].items() if k.split("@")[-1] >= limit}
                if not entry["days"]:
                    for stored in self.state["schedules"]:
                        if stored["id"] == entry["id"]:
                            stored["enabled"] = False
                self.save()
            threading.Thread(target=self.run, args=(entry, ready), daemon=True).start()

    # --- one warm-up -----------------------------------------------------------

    def run(self, entry, ready):
        started = datetime.now()
        label = f"{entry['hour']:02d}:{entry['minute']:02d}"
        log(f"warm-up for {label} starts")
        outcome, detail = self.sequence(self.state.get("vin", ""), lambda phase: None, check_every=20)

        with self.lock:
            for stored in self.state["schedules"]:
                if stored["id"] == entry["id"]:
                    stored["last_run"] = {
                        "at": stamp(started),
                        "ready": stamp(ready),
                        "outcome": outcome,
                        "detail": detail,
                    }
            self.save()
        log(f"warm-up for {label}: {outcome} {detail}".rstrip())

    def start_now(self, vin):
        """Begins a start by hand, unless one is already under way."""
        with self.lock:
            if vin:
                self.state["vin"] = vin.strip().upper()
                self.save()
            running = self.manual and self.manual["phase"] in ("waking", "sending", "waiting")
            if running and time.monotonic() - self.manual["clock"] < 240:
                return self.manual_view()
            self.manual = {"phase": "waking", "detail": "", "started": stamp(datetime.now()), "clock": time.monotonic()}
        threading.Thread(target=self.run_manual, daemon=True).start()
        return self.manual_view()

    def run_manual(self):
        log("start by hand begins")

        def report(phase):
            with self.lock:
                self.manual["phase"] = phase

        # Someone is waiting on this one, so look for the car's answer more often.
        outcome, detail = self.sequence(self.state.get("vin", ""), report, check_every=8)
        with self.lock:
            self.manual["phase"] = outcome
            self.manual["detail"] = detail
        log(f"start by hand: {outcome} {detail}".rstrip())

    def manual_view(self):
        with self.lock:
            if not self.manual:
                return None
            return {key: self.manual[key] for key in ("phase", "detail", "started")}

    def sequence(self, vin, report, check_every):
        """Wakes the car, starts its climate and waits for it to say so."""
        if not vin:
            return "failed", "No car is set. Open the app once while connected."

        # The car is usually asleep; give it a moment to come up first.
        report("waking")
        self.car.wake(vin)
        time.sleep(12 * self.pace)
        report("sending")
        sent = self.send(vin)
        outcome = "sent" if sent else "failed"
        detail = "" if sent else "The server could not pass the command on."
        report("waiting")

        # Look for the car's own word that the climate is running. Half way
        # through, ask once more: a sleeping car often misses the first try.
        deadline = time.monotonic() + 150 * self.pace
        half = time.monotonic() + 70 * self.pace
        asked_again = False
        while time.monotonic() < deadline:
            time.sleep(check_every * self.pace)
            try:
                if self.car.climate_is_on(vin):
                    return "confirmed", ""
            except (urllib.error.URLError, OSError, ValueError) as error:
                log(f"could not read the car: {error}")
            if not asked_again and time.monotonic() >= half:
                asked_again = True
                if self.send(vin) and outcome == "failed":
                    outcome, detail = "sent", ""
        if outcome == "sent":
            detail = "The car did not confirm."
        return outcome, detail

    def send(self, vin):
        try:
            return self.car.start_climate(vin)
        except (urllib.error.URLError, OSError, ValueError) as error:
            log(f"climate start failed: {error}")
            return False

    def loop(self):
        while True:
            try:
                self.tick()
            except Exception as error:  # the loop must outlive any one bad pass
                log(f"tick failed: {error!r}")
            time.sleep(TICK_SECONDS * self.pace)


def handler_for(scheduler):
    class Handler(BaseHTTPRequestHandler):
        server_version = "BetterOpelWarmUps/1"

        def log_message(self, fmt, *args):
            pass

        def route(self):
            path = urllib.parse.urlparse(self.path).path.rstrip("/")
            if path.startswith("/scheduler"):
                path = path[len("/scheduler"):]
            return path or "/"

        def reply(self, payload, status=200):
            body = json.dumps(payload).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            route = self.route()
            if route == "/health":
                self.reply({"ok": True, "version": VERSION})
            elif route == "/schedules":
                self.reply(scheduler.view())
            elif route == "/run":
                self.reply({"run": scheduler.manual_view()})
            else:
                self.reply({"error": "Not found."}, 404)

        def do_POST(self):
            if self.route() != "/run":
                self.reply({"error": "Not found."}, 404)
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                payload = json.loads(self.rfile.read(min(length, 4000)) or b"{}")
            except ValueError:
                payload = {}
            vin = str(payload.get("vin") or "") if isinstance(payload, dict) else ""
            self.reply({"run": scheduler.start_now(vin)})

        def do_PUT(self):
            if self.route() != "/schedules":
                self.reply({"error": "Not found."}, 404)
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if length > 64_000:
                    raise ValueError("too large")
                payload = json.loads(self.rfile.read(length) or b"{}")
            except ValueError:
                self.reply({"error": "That was not readable."}, 400)
                return
            problem = scheduler.replace(payload)
            if problem:
                self.reply({"error": problem}, 400)
            else:
                self.reply(scheduler.view())

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5056)
    parser.add_argument("--psacc", default="http://127.0.0.1:5055", help="where psa_car_controller listens")
    parser.add_argument("--state", default="warmups.json", help="file the list is kept in")
    parser.add_argument("--pace", type=float, default=1.0, help=argparse.SUPPRESS)
    options = parser.parse_args()

    scheduler = Scheduler(options.state, Car(options.psacc), pace=options.pace)
    threading.Thread(target=scheduler.loop, daemon=True).start()
    server = ThreadingHTTPServer((options.host, options.port), handler_for(scheduler))
    log(f"listening on {options.host}:{options.port}, car server at {options.psacc}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
