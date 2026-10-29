#!/bin/zsh
# Adds timed starts to a BetterOpel server that install-mac.sh has set up.
#
#   ./install-warmups.sh
#
# It runs warmup_scheduler.py as its own launchd agent next to
# psa_car_controller, bound to this Mac only, and, if Tailscale Serve is
# already publishing the car server, publishes the scheduler under /scheduler
# on the same address. It does not touch or restart the car server.
# Safe to run again: it replaces the script and restarts only the scheduler.

set -euo pipefail

PORT="${WARMUPS_PORT:-5056}"
PSACC_PORT="${PSACC_PORT:-5055}"
LABEL="com.example.betteropel.warmups"

ROOT="${BETTEROPEL_SERVER_HOME:-$HOME/Library/Application Support/BetterOpelServer}"
LOGS="${BETTEROPEL_SERVER_LOGS:-$HOME/Library/Logs/BetterOpelServer}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
HERE="${0:A:h}"

say() { print -P "%F{yellow}==>%f $1"; }

[[ -x "$ROOT/venv/bin/python3" ]] || { print "Run install-mac.sh first: $ROOT/venv is missing."; exit 1; }
mkdir -p "$ROOT/data" "$LOGS"

say "Installing the scheduler"
cp "$HERE/warmup_scheduler.py" "$ROOT/warmup_scheduler.py"
cat > "$ROOT/run-warmups.sh" <<RUN
#!/bin/zsh
# Started by launchd. Timed starts for BetterOpel, next to the car server.
export PYTHONUNBUFFERED=1
exec "$ROOT/venv/bin/python3" "$ROOT/warmup_scheduler.py" --host 127.0.0.1 --port $PORT --psacc http://127.0.0.1:$PSACC_PORT --state "$ROOT/data/warmups.json"
RUN
chmod +x "$ROOT/run-warmups.sh"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/zsh</string><string>$ROOT/run-warmups.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$LOGS/warmups.log</string>
  <key>StandardErrorPath</key><string>$LOGS/warmups.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
sleep 2
curl -fsS -m 5 "http://127.0.0.1:$PORT/health" >/dev/null && say "Scheduler is answering on 127.0.0.1:$PORT"

# Publish beside the car server, with whichever Tailscale this Mac has.
TS=""
if [[ -x "$ROOT/tailscale/tailscale" ]]; then
  TS=("$ROOT/tailscale/tailscale" "--socket=$ROOT/tailscale/tailscaled.sock")
elif command -v tailscale >/dev/null; then
  TS=(tailscale)
fi
if [[ -n "$TS" ]] && "${TS[@]}" serve status 2>/dev/null | grep -q "127.0.0.1:$PSACC_PORT"; then
  "${TS[@]}" serve --bg --set-path /scheduler "http://127.0.0.1:$PORT" >/dev/null
  say "Published under /scheduler on the car server's address"
else
  print "    Tailscale Serve is not publishing the car server here; the app reaches the scheduler at <server>/scheduler."
fi
