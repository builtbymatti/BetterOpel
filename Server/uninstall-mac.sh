#!/bin/zsh
# Stops and removes the BetterOpel server service. Your MyOpel session and the
# recorded trips stay in place unless you pass --purge.

set -euo pipefail

LABEL="com.example.betteropel.server"
ROOT="$HOME/Library/Application Support/BetterOpelServer"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
PORT="${PSACC_PORT:-5055}"

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
rm -f "$PLIST"

TS="$(command -v tailscale || true)"
[[ -z "$TS" && -x "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]] && TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
[[ -n "$TS" ]] && "$TS" serve --https=443 off 2>/dev/null || true

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$ROOT" "$HOME/Library/Logs/BetterOpelServer"
  print "Removed the service and all of its data."
else
  print "Removed the service. Data kept in: $ROOT"
fi
