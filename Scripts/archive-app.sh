#!/bin/bash
# Builds the Mac App Store package.
#
#   TEAM_ID=ABCDE12345 Scripts/archive-app.sh            archive + export the .pkg
#   TEAM_ID=ABCDE12345 Scripts/archive-app.sh --upload   ... then send it to App Store Connect
#
# Needs: Xcode, `xcodegen` (brew install xcodegen), a paid Apple Developer Program account
# with Xcode signed in, an app record in App Store Connect, and the bundle identifier
# app.notchotp registered to that team. See docs/app-store.md.
#
# Optional environment, all read by the release workflow (.github/workflows/release.yml):
#
#   VERSION=1.1 BUILD_NUMBER=7      stamp CFBundleShortVersionString / CFBundleVersion
#                                   without touching Resources/Info.plist
#   ASC_KEY_ID, ASC_ISSUER_ID,      an App Store Connect API key (Users and Access →
#   ASC_KEY_PATH                    Integrations); xcodebuild then signs, provisions and
#                                   uploads with it instead of Xcode's account session
#
# Day-to-day building does not need any of this: Scripts/build-app.sh is faster and does not
# involve Xcode at all.
set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID="${TEAM_ID:?Set TEAM_ID to your Apple Developer team identifier}"
ARCHIVE="build/NotchOTP.xcarchive"
EXPORT="build/export"
UPLOAD=0
if [[ "${1:-}" == "--upload" ]]; then
  UPLOAD=1
fi

command -v xcodegen >/dev/null || {
  echo "xcodegen is missing — brew install xcodegen" >&2
  exit 1
}

# The Xcode project is generated, never committed: project.yml is the source of truth.
xcodegen generate

# Version and build number. The plist in Resources is what the SwiftPM bundle copies as is,
# so a release stamps a derived copy rather than the tracked file.
INFOPLIST=Resources/Info.plist
if [[ -n "${VERSION:-}" || -n "${BUILD_NUMBER:-}" ]]; then
  mkdir -p build
  INFOPLIST=build/Info-AppStore.plist
  cp Resources/Info.plist "$INFOPLIST"
  if [[ -n "${VERSION:-}" ]]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$INFOPLIST"
  fi
  if [[ -n "${BUILD_NUMBER:-}" ]]; then
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$INFOPLIST"
  fi
fi

# -allowProvisioningUpdates lets Xcode create or refresh the Mac App Store profile and the
# distribution certificate on your account. With an API key it does so without an account
# session, which is what makes the script runnable on a machine nobody is signed into.
AUTH=()
if [[ -n "${ASC_KEY_ID:-}" ]]; then
  : "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID (App Store Connect API issuer id)}"
  : "${ASC_KEY_PATH:?Set ASC_KEY_PATH to the absolute path of the AuthKey_*.p8 file}"
  AUTH=(
    -authenticationKeyPath "$ASC_KEY_PATH"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  )
fi

xcodebuild -project NotchOTP.xcodeproj -scheme NotchOTP \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  INFOPLIST_FILE="$INFOPLIST" \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} \
  archive

EXPORT_OPTIONS=Scripts/ExportOptions-AppStore.plist
if (( UPLOAD )); then
  # Hand the upload to xcodebuild itself: with the API key above, or else with the account
  # Xcode is signed into — the same thing Transporter.app does from a GUI.
  export_dir="$(mktemp -d)"
  EXPORT_OPTIONS="$export_dir/ExportOptions.plist"
  sed 's|<string>export</string>|<string>upload</string>|' \
    Scripts/ExportOptions-AppStore.plist > "$EXPORT_OPTIONS"
fi

rm -rf "$EXPORT"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT" \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}

echo
if (( UPLOAD )); then
  echo "Uploaded to App Store Connect: the build shows up on the version page once Apple has"
  echo "finished processing it (a few minutes)."
else
  echo "Exported:"
  ls -1 "$EXPORT"
fi
