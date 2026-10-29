#!/bin/zsh
# Usage: SIMULATOR_NAME="iPhone 17 Pro" ./scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project BetterOpel.xcodeproj -scheme BetterOpel -configuration Debug \
  -destination "platform=iOS Simulator,name=${SIMULATOR_NAME:-iPhone 17 Pro}" \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
