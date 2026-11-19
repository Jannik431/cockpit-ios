#!/usr/bin/env bash
# Renders the daily card with synthetic data (light + dark) into docs/screenshots.
# Usage: scripts/screenshots.sh [simulator name]   (default: iPhone 17)
set -euo pipefail
cd "$(dirname "$0")/.."

SIMULATOR="${1:-iPhone 17}"
OUT="$(pwd)/docs/screenshots"
mkdir -p "$OUT"

xcodegen generate --quiet
TEST_RUNNER_SCREENSHOT_DIR="$OUT" xcodebuild test \
  -project Cockpit.xcodeproj \
  -scheme Cockpit \
  -destination "platform=iOS Simulator,name=${SIMULATOR}" \
  -only-testing:CockpitTests/ScreenshotTests \
  | xcbeautify

echo "Screenshots in $OUT"
