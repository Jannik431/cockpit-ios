#!/usr/bin/env bash
# Builds Cockpit for the connected iPhone, installs and launches it.
# Also the fix when the free 7-day signature has expired: just run it again,
# the app's data stays on the phone.
#
# Usage: scripts/deploy-device.sh            (first connected iPhone)
#        DEVICE=<identifier> scripts/deploy-device.sh
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="de.jannikpasch.cockpit"
# Builds go to Xcode's default DerivedData so SourceKit-LSP (buildServer.json) sees the same index.

# devicectl and xcodebuild use different IDs: CoreDevice identifier vs. hardware UDID.
json="$(mktemp)"
xcrun devicectl list devices --json-output "$json" >/dev/null
read -r DEVICE UDID < <(/usr/bin/python3 -I -c '
import json, sys
wanted = sys.argv[2]
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    hw, conn = d.get("hardwareProperties", {}), d.get("connectionProperties", {})
    # Since Xcode 27, devicectl also lists simulators; only real devices count.
    if hw.get("deviceType") != "iPhone" or hw.get("reality") == "simulated" or conn.get("pairingState") != "paired":
        continue
    if wanted in ("", d["identifier"], hw.get("udid")):
        print(d["identifier"], hw.get("udid")); break
' "$json" "${DEVICE:-}") || true
rm -f "$json"

if [[ -z "${UDID:-}" ]]; then
  echo "Kein gekoppeltes iPhone gefunden. Per Kabel anschließen, entsperren und erneut versuchen." >&2
  exit 1
fi

xcodegen generate --quiet

if ! xcodebuild -project Cockpit.xcodeproj -scheme Cockpit -showdestinations 2>/dev/null | grep -q "id:${UDID}"; then
  echo "iPhone ist gekoppelt, aber gerade nicht erreichbar. Per Kabel anschließen, entsperren und erneut versuchen." >&2
  exit 1
fi

BUILD_ARGS=(-project Cockpit.xcodeproj -scheme Cockpit -configuration Debug -destination "id=${UDID}")
xcodebuild build "${BUILD_ARGS[@]}" -allowProvisioningUpdates | xcbeautify

PRODUCTS_DIR="$(xcodebuild -showBuildSettings "${BUILD_ARGS[@]}" 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR = / { print $2; exit }')"
APP="${PRODUCTS_DIR}/Cockpit.app"
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" \
  || echo "Installiert. Falls der Start scheitert: Einstellungen → Allgemein → VPN & Geräteverwaltung → Entwickler vertrauen."
