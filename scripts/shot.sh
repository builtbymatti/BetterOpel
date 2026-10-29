#!/bin/zsh
# Capture demo data only. Always disconnects a saved server before launch.
# Usage: scripts/shot.sh [light|dark] [output.png] [seconds] [launch args...]
set -euo pipefail
cd "$(dirname "$0")/.."
appearance="${1:-light}"
output="${2:-captures/betteropel.png}"
delay="${3:-3}"
mkdir -p "$(dirname "$output")"
xcrun simctl ui booted appearance "$appearance"
xcrun simctl status_bar booted override --time '9:41' --dataNetwork wifi \
  --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
trap 'xcrun simctl status_bar booted clear >/dev/null 2>&1 || true' EXIT
xcrun simctl terminate booted com.example.betteropel >/dev/null 2>&1 || true
xcrun simctl launch booted com.example.betteropel -server none -resetDemo "${@:4}" >/dev/null
sleep "$delay"
xcrun simctl io booted screenshot "$output"
