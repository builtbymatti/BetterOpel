#!/usr/bin/env python3
"""A stand-in for psa_car_controller, for developing BetterOpel without a car.

It answers the same endpoints with the same JSON shapes the real server sends
(checked against psa_car_controller 3.7.9), and keeps a little state so that
commands have a visible effect.

    python3 fake_psacc.py [port]        # default 5055

In the iOS simulator, point BetterOpel at http://127.0.0.1:5055.
"""

import json
import sys
import time
from datetime import datetime, timedelta, timezone
from email.utils import format_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

VIN = "DEMO0000000000000"

state = {
    "level": 58.0,
    "plugged": True,
    "charging": True,
    "delayed": [22, 30],
    "climate": False,
    "locked": True,
    "threshold": 80,
    "stop_hour": [6, 0],
    "ticked": time.time(),
}


def advance():
    """Charge at roughly 11 kW on a 73 kWh pack, sped up sixty times."""
    now = time.time()
    hours = (now - state["ticked"]) / 3600 * 60
    state["ticked"] = now
    if state["charging"] and state["plugged"]:
        state["level"] = min(float(state["threshold"]), state["level"] + 11 * hours / 73 * 100)
        if state["level"] >= state["threshold"]:
            state["charging"] = False


def iso_duration(minutes):
    return f"PT{int(minutes) // 60}H{int(minutes) % 60}M"


def vehicle_info():
    advance()
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S+00:00")
    if not state["plugged"]:
        status = "Disconnected"
    elif state["charging"]:
        status = "InProgress"
    elif state["level"] >= state["threshold"]:
        status = "Finished"
    else:
        status = "Stopped"
    missing_kwh = max(0.0, state["threshold"] - state["level"]) / 100 * 73
    return {
        "embedded": None,
        "links": None,
        "battery": {"current": 0.0, "voltage": 92.0},
        "doors_state": {"locked_state": ["Locked" if state["locked"] else "Unlocked"], "opening": None, "updated_at": now},
        "energy": [
            {"updated_at": now, "created_at": None, "autonomy": None, "battery": None, "charging": None,
             "consumption": None, "level": 0.0, "residual": None, "type": "Fuel"},
            {
                "updated_at": now, "created_at": None,
                "autonomy": round(state["level"] / 100 * 505),
                "battery": {"capacity": None, "health": {"capacity": None, "resistance": 97.0}},
                "charging": {
                    "charging_mode": "Slow" if state["charging"] else "No",
                    "charging_rate": 72 if state["charging"] else 0,
                    "next_delayed_time": iso_duration(state["delayed"][0] * 60 + state["delayed"][1]),
                    "plugged": state["plugged"],
                    "remaining_time": iso_duration(missing_kwh / 11 * 60) if state["charging"] else "PT0S",
                    "status": status,
                },
                "consumption": None, "level": float(int(state["level"])), "residual": None, "type": "Electric",
            },
        ],
        "environment": {"created_at": now, "air": {"temp": 11.5}, "luminosity": {"day": True}},
        "ignition": {"created_at": now, "type": "Stop"},
        "kinetic": {"created_at": now, "acceleration": None, "moving": False, "pace": None, "speed": None},
        "last_position": {
            "type": "Feature",
            "geometry": {"coordinates": [8.41262, 49.99212, 88], "type": "Point"},
            "properties": {"updated_at": now, "created_at": None, "heading": 204.0, "signal_quality": 9, "type": "Acquire"},
        },
        "preconditionning": {"air_conditioning": {"failure_cause": None, "status": "Enabled" if state["climate"] else "Disabled", "updated_at": now, "created_at": None}},
        "privacy": {"created_at": now, "state": "None"},
        "safety": None,
        "service": {"type": "Electric", "updated_at": now},
        "timed_odometer": {"updated_at": now, "mileage": 12486.4},
    }


def http_date(dt):
    return format_datetime(dt.astimezone(timezone.utc), usegmt=True)


def trips():
    base = datetime.now(timezone.utc).replace(hour=7, minute=58, second=0, microsecond=0)
    lat = [49.99212, 49.9987, 50.0149, 50.0331, 50.0502, 50.0716, 50.0884, 50.1001]
    lon = [8.41262, 8.4466, 8.4903, 8.5302, 8.5711, 8.6102, 8.6455, 8.6721]
    out = []
    for i in range(6):
        outbound = i % 2 == 0
        start = base - timedelta(days=i // 2) + (timedelta() if outbound else timedelta(hours=9, minutes=20))
        distance = 25.6 + (i % 3) * 0.4
        consumption_km = 16.2 + (i % 4) * 0.7
        out.append({
            "consumption_km": consumption_km,
            "start_at": http_date(start),
            "consumption_by_temp": None,
            "positions": {"lat": lat if outbound else lat[::-1], "long": lon if outbound else lon[::-1]},
            "duration": 27.0 + i,
            "speed_average": distance / ((27.0 + i) / 60),
            "distance": distance,
            "mileage": 12486.4 - i * 25.6,
            "altitude_diff": 14 if outbound else -14,
            "id": 6 - i,
            "consumption": consumption_km * distance / 100,
        })
    return out[::-1]


def chargings():
    base = datetime.now(timezone.utc).replace(hour=22, minute=30, second=0, microsecond=0)
    rows = []
    for i, (start_level, end_level, kw, mode) in enumerate([(38, 80, 31.4, "Slow"), (52, 80, 21.0, "Slow"), (21, 82, 46.1, "Quick")]):
        start = base - timedelta(days=1 + i * 2)
        stop = start + timedelta(minutes=170 if mode == "Slow" else 26)
        rows.append({
            "start_at": http_date(start), "stop_at": http_date(stop), "VIN": VIN,
            "start_level": start_level, "end_level": end_level, "co2": 310 + i * 12, "kw": kw,
            "price": round(kw * (0.24 if mode == "Slow" else 0.59), 2), "charging_mode": mode,
            "mileage": 12486.4 - i * 60,
            "duration_min": (stop - start).total_seconds() / 60, "duration_str": str(stop - start),
        })
    return rows[::-1]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.command, self.path))

    def send(self, payload, status=200):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        parts = [p for p in url.path.split("/") if p]
        query = {k: v[0] for k, v in parse_qs(url.query).items()}
        time.sleep(0.35)

        if parts == ["get_vehicles"]:
            return self.send([{
                "vin": VIN, "vehicle_id": "fake", "label": "Grandland Electric", "brand": "C",
                "abrp_name": "opel:grandland:25:74", "battery_power": 73, "fuel_capacity": 0,
                "max_elec_consumption": 70, "max_fuel_consumption": 0,
            }])
        if parts[:1] == ["get_vehicleinfo"]:
            return self.send(vehicle_info())
        if parts[:1] == ["wakeup"]:
            return self.send(True)
        if parts[:1] == ["charge_now"]:
            advance()
            state["charging"] = parts[2] != "0" and state["plugged"] and state["level"] < state["threshold"]
            return self.send(True)
        if parts == ["charge_hour"]:
            state["delayed"] = [int(query["hour"]), int(query["minute"])]
            return self.send(True)
        if parts == ["charge_control"]:
            if "percentage" in query:
                advance()
                state["threshold"] = int(query["percentage"])
                if state["plugged"] and state["level"] < state["threshold"] and not state["charging"]:
                    state["charging"] = True
            if "hour" in query and "minute" in query:
                hour = [int(query["hour"]), int(query["minute"])]
                state["stop_hour"] = None if hour == [0, 0] else hour
            return self.send({
                "vin": query.get("vin", VIN), "percentage_threshold": state["threshold"],
                "_stop_hour": state["stop_hour"], "_next_stop_hour": None, "retry_count": 0, "wakeup_timeout": 10,
            })
        if parts[:1] == ["preconditioning"]:
            state["climate"] = parts[2] != "0"
            return self.send(True)
        if parts[:1] == ["lock_door"]:
            state["locked"] = parts[2] != "0"
            return self.send(True)
        if parts[:1] in (["horn"], ["lights"]):
            return self.send(True)
        if parts == ["vehicles", "trips"]:
            return self.send(trips())
        if parts == ["vehicles", "chargings"]:
            return self.send(chargings())
        if parts[:2] == ["battery", "soh"]:
            return self.send({"soh": 97.0})
        self.send({"error": "not found"}, 404)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 5055
    print(f"fake psa_car_controller on http://127.0.0.1:{port}")
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
