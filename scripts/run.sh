#!/bin/zsh
# Build and capture a demo on a simulator you have already booted.
# Usage: scripts/run.sh [light|dark] [output.png] [seconds] [launch args...]
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/BetterOpel.app
exec ./scripts/shot.sh "$@"
