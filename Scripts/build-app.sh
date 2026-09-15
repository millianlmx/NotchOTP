#!/bin/bash
# Assembles NotchOTP.app around the SwiftPM binary.
#
#   Scripts/build-app.sh            release build
#   Scripts/build-app.sh --debug    debug build (enables the -demo harness)
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION=release
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

if [[ "${1:-}" == "--debug" ]]; then
  CONFIGURATION=debug
fi

swift build -c "$CONFIGURATION" --product NotchOTP

# The icon is a generated artefact: draw it once, then keep it.
if [[ ! -f Resources/AppIcon.icns ]]; then
  ./Scripts/make-icon.sh
fi

BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP="build/NotchOTP.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/NotchOTP" "$APP/Contents/MacOS/NotchOTP"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Localizations. French is the development region — the literals in the code are French and
# need no file — so only English ships, and SwiftUI's lookups happen against Bundle.main.
if [[ -d Resources/en.lproj ]]; then
  cp -R Resources/en.lproj "$APP/Contents/Resources/en.lproj"
fi

codesign --force --options runtime --timestamp=none \
  --sign "$SIGN_IDENTITY" \
  --entitlements Resources/NotchOTP.entitlements \
  "$APP"

echo "Built $APP"
