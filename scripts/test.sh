#!/usr/bin/env bash
# Generates the Xcode project and runs the unit tests in the simulator.
# Usage: scripts/test.sh [simulator name]   (default: iPhone 17)
set -euo pipefail
cd "$(dirname "$0")/.."

SIMULATOR="${1:-iPhone 17}"

xcodegen generate --quiet
xcodebuild test \
  -project Cockpit.xcodeproj \
  -scheme Cockpit \
  -destination "platform=iOS Simulator,name=${SIMULATOR}" \
  | xcbeautify
