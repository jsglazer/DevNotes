#!/usr/bin/env bash
# MakeiOSDeploy.sh — build an iOS app target with Development signing and install
# it directly onto a paired iPhone via `xcrun devicectl`. No App Store Connect
# record, no TestFlight, no name-uniqueness constraint — the app never touches
# the store. Re-run any time to push an updated build (same bundle id overwrites
# the installed copy in place).
#
# Reusable across iOS apps under 2-Projects/Apps: copy this file into the project
# and change the PROJECT / SCHEME / BUNDLE_ID block below. The device is
# auto-detected when exactly one iPhone is paired; otherwise set DEVICE_ID.
#
# Usage:
#   ./MakeiOSDeploy.sh                 # build + install (+ launch) on the paired iPhone
#   ./MakeiOSDeploy.sh --no-launch     # build + install, don't auto-launch
#   ./MakeiOSDeploy.sh --device <UDID> # target a specific paired device
#   ./MakeiOSDeploy.sh --build-only    # build + sign, skip install
set -euo pipefail

# ── Project config ────────────────────────────────────────────────────────────
PROJ_DIR="/Users/josh/Dev/2-Projects/Apps/DevNotes"
PROJECT="$PROJ_DIR/DevNotes.xcodeproj"
SCHEME="DevNotes-iOS"
APPNAME="DevNotes.app"
BUNDLE_ID="com.jsglazer.DevNotes"
CONFIG="Release"
LOG="$PROJ_DIR/build_log.txt"

# ── Options ───────────────────────────────────────────────────────────────────
DEVICE_ID=""
LAUNCH=1
INSTALL=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)     DEVICE_ID="${2:-}"; shift 2 ;;
    --no-launch)  LAUNCH=0; shift ;;
    --build-only) INSTALL=0; LAUNCH=0; shift ;;
    -h|--help)    grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# ── 0. Resolve target device ──────────────────────────────────────────────────
if [[ -z "$DEVICE_ID" ]]; then
  echo "==> Detecting paired device..."
  # Pull all paired/available device identifiers from devicectl's JSON output.
  TMP_DEV=$(mktemp)
  xcrun devicectl list devices --json-output "$TMP_DEV" >/dev/null 2>&1 || true
  # UDIDs of connected/paired iOS devices (hardware, not simulators), one per line.
  DEVS=$(/usr/bin/python3 - "$TMP_DEV" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for dev in d.get("result", {}).get("devices", []):
    props = dev.get("deviceProperties", {})
    hw = dev.get("hardwareProperties", {})
    if hw.get("platform") == "iOS":
        print(f'{dev.get("identifier","")}\t{props.get("name","?")}')
PY
)
  rm -f "$TMP_DEV"
  N=$(printf '%s\n' "$DEVS" | grep -c . || true)
  if [[ "$N" -eq 0 ]]; then
    echo "ERROR: no paired iOS device found. Plug in / pair an iPhone, or pass --device <UDID>." >&2
    exit 1
  elif [[ "$N" -gt 1 ]]; then
    echo "ERROR: multiple paired devices — pass --device <UDID>:" >&2
    printf '%s\n' "$DEVS" | sed 's/^/   /' >&2
    exit 1
  fi
  DEVICE_ID="${DEVS%%$'\t'*}"
  DEVICE_NAME="${DEVS#*$'\t'}"
  echo "    $DEVICE_NAME ($DEVICE_ID)"
fi

# ── 1. Regenerate project from project.yml (keep .xcodeproj in sync) ───────────
if command -v xcodegen >/dev/null 2>&1 && [[ -f "$PROJ_DIR/project.yml" ]]; then
  echo "==> xcodegen generate"
  ( cd "$PROJ_DIR" && xcodegen generate >/dev/null )
fi

# ── 2. Build + sign for the device ────────────────────────────────────────────
DERIVED="$PROJ_DIR/.build/ios-deploy"
echo "==> Building $SCHEME ($CONFIG) for device..."
# Generic destination so the build does not require the phone to be awake/connected;
# only the install step below needs the device.
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  build \
  2>&1 | tee "$LOG" | grep -iE "error:|BUILD (SUCCEEDED|FAILED)|Signing Identity|Provisioning Profile" || true

if ! grep -q "BUILD SUCCEEDED" "$LOG"; then
  echo "" ; echo "ERROR: build failed — see $LOG" >&2 ; exit 1
fi

APP="$DERIVED/Build/Products/$CONFIG-iphoneos/$APPNAME"
if [[ ! -d "$APP" ]]; then
  echo "ERROR: built app not found at $APP" >&2 ; exit 1
fi
echo "==> Built: $APP"

[[ $INSTALL -eq 1 ]] || { echo "Done (build-only)."; exit 0; }

# ── 3. Install onto the device ────────────────────────────────────────────────
# Wait for the device to report a connected/available state. A paired-but-asleep
# or disconnected phone lists as "unavailable" and devicectl install fails (1011).
echo "==> Waiting for device to connect (unlock your iPhone / plug it in)..."
device_ready() {
  xcrun devicectl list devices 2>/dev/null \
    | grep -i "$DEVICE_ID" | grep -iqvE "unavailable"
}
for i in $(seq 1 30); do
  device_ready && break
  [[ $i -eq 30 ]] && {
    echo "" >&2
    echo "ERROR: device $DEVICE_ID is not connected (shows 'unavailable')." >&2
    echo "  • Unlock the iPhone and tap 'Trust' if prompted." >&2
    echo "  • Connect via USB, or ensure it's on Wi-Fi with Xcode wireless debugging enabled." >&2
    echo "  • The build is already done — just re-run this script once connected." >&2
    exit 1
  }
  sleep 2
done

echo "==> Installing onto $DEVICE_ID..."
if ! xcrun devicectl device install app --device "$DEVICE_ID" "$APP" 2>&1 \
     | tee -a "$LOG" | grep -iE "installing|installed|Bundle ID|App installed|error"; then
  : # grep may match nothing on success; real failure is caught by PIPESTATUS below
fi
if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then
  echo "ERROR: install failed — see $LOG" >&2 ; exit 1
fi

# ── 4. Launch ─────────────────────────────────────────────────────────────────
if [[ $LAUNCH -eq 1 ]]; then
  echo "==> Launching $BUNDLE_ID..."
  xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" 2>&1 \
    | grep -iE "launched|error" || true
fi

echo ""
echo "Done: $APPNAME deployed to device $DEVICE_ID"
