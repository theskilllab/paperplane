#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter 3.47.9 (the repo pin) is required on PATH." >&2
  exit 1
fi

xcode_path="$(xcode-select -p 2>/dev/null || true)"
if [[ "$xcode_path" != *"Xcode.app"* ]]; then
  echo "Full Xcode 15.0 or later is required (macOS 13.5 or later)." >&2
  echo "If Xcode is installed, run:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

profile=0
if [[ "${1:-}" == "--profile" ]]; then
  profile=1
  shift
fi

flutter pub get

device_id="${IOS_DEVICE_ID:-}"
if [[ -z "$device_id" ]]; then
  device_id="$({
    flutter devices --machine 2>/dev/null || true
  } | python3 -c '
import json
import sys

try:
    devices = json.load(sys.stdin)
except Exception:
    sys.exit(0)

for device in devices:
    platform = str(device.get("targetPlatform", ""))
    if not device.get("emulator") and platform.startswith("ios"):
        print(device.get("id", ""))
        break
')"
fi

if [[ -z "$device_id" ]]; then
  echo "No physical iPhone or iPad found." >&2
  echo "Connect the device, trust this Mac, and turn on Developer Mode." >&2
  echo "Set IOS_DEVICE_ID=<id> to choose a device from 'flutter devices'." >&2
  exit 1
fi

if ! grep -q 'DEVELOPMENT_TEAM = [A-Z0-9]' ios/Runner.xcodeproj/project.pbxproj; then
  cat >&2 <<'MSG'
No Apple development team is set. Do this once:
  1. open ios/Runner.xcworkspace
  2. select the Runner target > Signing & Capabilities
  3. choose your Personal Team; keep "Automatically manage signing" on
  4. run ./tool/run_ios.sh again
MSG
  exit 1
fi

if [[ "$profile" == "1" ]]; then
  flutter run --profile -d "$device_id" "$@"
else
  flutter run -d "$device_id" "$@"
fi
