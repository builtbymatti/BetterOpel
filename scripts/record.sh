#!/bin/zsh
# Usage: scripts/record.sh [light|dark] [output.mp4] [seconds] [launch args...]
set -euo pipefail
cd "$(dirname "$0")/.."
output="${2:-captures/betteropel.mp4}"
mkdir -p "$(dirname "$output")"
xcrun simctl ui booted appearance "${1:-dark}"
xcrun simctl terminate booted com.example.betteropel >/dev/null 2>&1 || true
xcrun simctl io booted recordVideo --codec h264 --force "$output" >/dev/null 2>&1 &
recorder=$!
trap 'kill -INT "$recorder" 2>/dev/null || true; wait "$recorder" 2>/dev/null || true' EXIT
sleep 1
xcrun simctl launch booted com.example.betteropel -server none -resetDemo "${@:4}" >/dev/null
sleep "${3:-10}"
