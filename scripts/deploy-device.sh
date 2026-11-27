#!/usr/bin/env bash
# Builds Cockpit for the connected iPhone, installs and launches it.
# Also the fix when the free 7-day signature has expired: just run it again,
# the app's data stays on the phone. Each run renews the signature for 7 days.
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

# Free accounts get 7-day profiles, and Xcode keeps using a still-valid profile instead of renewing it.
# The 7 days would then count from the first install, not this one. So an existing profile with less
# than RENEW_DAYS left is removed first, and the build below creates a fresh one.
RENEW_DAYS="${RENEW_DAYS:-6}"
PROFILES_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
profile_expiry() {
  security cms -D -i "$1" 2>/dev/null | /usr/bin/python3 -I -c '
import plistlib, sys
p = plistlib.loads(sys.stdin.buffer.read())
if p.get("Name", "").endswith(sys.argv[1]):
    print(p["ExpirationDate"].timestamp())
' "$BUNDLE_ID" 2>/dev/null || true
}
if [[ -d "$PROFILES_DIR" ]]; then
  for profile in "$PROFILES_DIR"/*.mobileprovision; do
    [[ -e "$profile" ]] || continue
    expiry="$(profile_expiry "$profile")"
    [[ -n "$expiry" ]] || continue
    if (( ${expiry%.*} - $(date +%s) < RENEW_DAYS * 86400 )); then
      echo "Profil läuft am $(date -r "${expiry%.*}" '+%d.%m. %H:%M') ab – wird erneuert."
      rm -f "$profile"
    fi
  done
fi

BUILD_ARGS=(-project Cockpit.xcodeproj -scheme Cockpit -configuration Debug -destination "id=${UDID}")
xcodebuild build "${BUILD_ARGS[@]}" -allowProvisioningUpdates | xcbeautify

for profile in "$PROFILES_DIR"/*.mobileprovision; do
  [[ -e "$profile" ]] || continue
  expiry="$(profile_expiry "$profile")"
  [[ -n "$expiry" ]] && echo "Signatur gültig bis $(date -r "${expiry%.*}" '+%d.%m. %H:%M'). Danach dieses Skript erneut ausführen."
done

PRODUCTS_DIR="$(xcodebuild -showBuildSettings "${BUILD_ARGS[@]}" 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR = / { print $2; exit }')"
APP="${PRODUCTS_DIR}/Cockpit.app"
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" \
  || echo "Installiert. Falls der Start scheitert: Einstellungen → Allgemein → VPN & Geräteverwaltung → Entwickler vertrauen."
