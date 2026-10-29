#!/bin/zsh
# Installs psa_car_controller on a Mac as an always-on service for BetterOpel.
#
#   ./install-mac.sh
#
# Safe to run again: it upgrades in place and picks up where it left off, for
# example after you have signed in to Tailscale.
#
# What it does, all inside your user account and without sudo:
#   1. installs psa_car_controller into its own Python environment
#   2. keeps it running with a launchd agent, restarting it if it stops
#   3. binds it to this Mac only (127.0.0.1), so nothing on the network can
#      reach it directly
#   4. if Tailscale is signed in, publishes it over HTTPS to your own devices
#
# Settings, via environment variables:
#   PSACC_PORT         local port (default 5055; macOS AirPlay already uses 5000)
#   PSACC_VIN_PREFIX   first ten characters of your VIN, to register the model
#   PSACC_REFRESH_MIN  how often to fetch the car's state, in minutes (default 5)

set -euo pipefail

PORT="${PSACC_PORT:-5055}"
VIN_PREFIX="${PSACC_VIN_PREFIX:-}"
REFRESH_MIN="${PSACC_REFRESH_MIN:-5}"
LABEL="com.example.betteropel.server"

ROOT="${BETTEROPEL_SERVER_HOME:-$HOME/Library/Application Support/BetterOpelServer}"
VENV="$ROOT/venv"
DATA="$ROOT/data"
LOGS="${BETTEROPEL_SERVER_LOGS:-$HOME/Library/Logs/BetterOpelServer}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

say() { print -P "%F{yellow}==>%f $1"; }
note() { print "    $1"; }

mkdir -p "$ROOT" "$DATA" "$LOGS"

# --- 1. Python environment ---------------------------------------------------

UV="$(command -v uv || true)"
[[ -z "$UV" && -x "$HOME/.local/bin/uv" ]] && UV="$HOME/.local/bin/uv"
if [[ -z "$UV" ]]; then
  say "Installing uv (Python tooling) into ~/.local/bin"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  UV="$HOME/.local/bin/uv"
fi

if [[ ! -x "$VENV/bin/python" ]]; then
  say "Creating a Python 3.12 environment"
  "$UV" venv --python 3.12 "$VENV"
fi

say "Installing psa_car_controller"
"$UV" pip install --quiet --python "$VENV/bin/python" --upgrade psa-car-controller playwright
note "version: $("$VENV/bin/psa-car-controller" --version 2>/dev/null || echo unknown)"

# The MyOpel sign-in can run by itself in a headless browser. Without it the
# setup page falls back to copying a code out of the browser's developer tools.
say "Installing the headless browser used for the MyOpel sign-in"
"$VENV/bin/playwright" install --only-shell chromium >/dev/null 2>&1 \
  || note "skipped (sign-in will use the manual copy-a-code flow instead)"

# --- 2. Register this car's model --------------------------------------------
# psa_car_controller looks a car up by the first ten characters of its VIN. The
# Optional: register a model prefix supplied locally by the owner.

"$VENV/bin/python" - "$VIN_PREFIX" <<'PY'
import sys, pathlib
import psa_car_controller.psacc.repository.car_model as car_model
from psa_car_controller.psacc.repository.car_model import CarModelRepository

prefix = sys.argv[1].strip().upper()[:10]
if len(prefix) == 10:
    known = any(m.match(prefix) for m in CarModelRepository().models)
    if not known:
        path = pathlib.Path(car_model.MODELS_FILE).resolve()
        entry = (
            "- !CarModel\n"
            "  name: Grandland Electric\n"
            "  battery_power: 73\n"
            "  fuel_capacity: 0\n"
            "  abrp_name: opel:grandland:25:74\n"
            f"  reg: {prefix}\n"
            "  max_elec_consumption: 70\n"
            "  max_fuel_consumption: 0\n"
        )
        text = path.read_text(encoding="utf-8")
        path.write_text(text.rstrip("\n") + "\n" + entry, encoding="utf-8")
        print(f"    registered {prefix} as Grandland Electric (73 kWh)")
    else:
        print(f"    {prefix} is already a known model")
PY

# --- 3. The service ----------------------------------------------------------

cat > "$ROOT/run.sh" <<EOF
#!/bin/zsh
# Started by launchd. caffeinate keeps the Mac from idle-sleeping while the
# server runs; it changes no system setting.
cd "$DATA"
export PYTHONUNBUFFERED=1
exec /usr/bin/caffeinate -i "$VENV/bin/psa-car-controller" --web-conf -c -r -R $REFRESH_MIN -l 127.0.0.1 -p $PORT
EOF
chmod +x "$ROOT/run.sh"

if [[ -n "${BETTEROPEL_SKIP_SERVICE:-}" ]]; then
  say "Skipping launchd and Tailscale (BETTEROPEL_SKIP_SERVICE is set)"
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/zsh</string><string>$ROOT/run.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$LOGS/server.log</string>
  <key>StandardErrorPath</key><string>$LOGS/server.log</string>
</dict>
</plist>
EOF

say "Starting the service"
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST"

print -n "    waiting for it to answer"
ready=""
for i in {1..90}; do
  if [[ "$(curl -s -o /dev/null -m 2 -w '%{http_code}' "http://127.0.0.1:$PORT/" || true)" == "200" ]]; then
    ready=1; break
  fi
  print -n "."; sleep 2
done
print
if [[ -z "$ready" ]]; then
  note "It has not answered yet. Check the log: $LOGS/server.log"
  exit 1
fi
note "running at http://localhost:$PORT (this Mac only)"

# --- 4. Reach it from outside, encrypted -------------------------------------

TS="$(command -v tailscale || true)"
[[ -z "$TS" && -x "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]] && TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"

URL=""
if [[ -n "$TS" ]] && "$TS" status >/dev/null 2>&1; then
  say "Publishing over HTTPS to your Tailscale devices"
  if "$TS" serve --bg "$PORT" 2>&1 | sed 's/^/    /'; then
    HOST="$("$TS" status --json | "$VENV/bin/python" -c 'import sys,json; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || true)"
    [[ -n "$HOST" ]] && URL="https://$HOST"
  fi
else
  say "Tailscale is not signed in on this Mac yet"
  note "Install Tailscale (free for personal use) from https://tailscale.com/download,"
  note "sign in, then run this script again. Do the same on your iPhone."
fi

print
say "Next"
if [[ -n "$URL" ]]; then
  note "1. Open $URL (or http://localhost:$PORT here) and sign in with MyOpel:"
else
  note "1. Open http://localhost:$PORT on this Mac and sign in with MyOpel:"
fi
note "   brand Opel, your e-mail, password and country code (DE), then the SMS"
note "   code and your four-digit MyOpel PIN."
if [[ -n "$URL" ]]; then
  note "2. In BetterOpel, Settings, Connection: enter $URL"
else
  note "2. After Tailscale is set up, run this script again to get the address"
  note "   for BetterOpel."
fi
note "Log: $LOGS/server.log"
