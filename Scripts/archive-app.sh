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
# Day-to-day building does not need any of this: Scripts/build-app.sh is faster and does not
# involve Xcode at all.
set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID="${TEAM_ID:?Set TEAM_ID to your Apple Developer team identifier}"
BUNDLE_ID="app.notchotp"
ARCHIVE="build/NotchOTP.xcarchive"
EXPORT="build/export"

command -v xcodegen >/dev/null || {
  echo "xcodegen is missing — brew install xcodegen" >&2
  exit 1
}

# The Xcode project is generated, never committed: project.yml is the source of truth.
xcodegen generate

# -allowProvisioningUpdates lets Xcode create or refresh the Mac App Store profile and the
# distribution certificate on your account. It is what the *user* runs, on their own team.
xcodebuild -project NotchOTP.xcodeproj -scheme NotchOTP \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  -allowProvisioningUpdates \
  archive

rm -rf "$EXPORT"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist Scripts/ExportOptions-AppStore.plist \
  -exportPath "$EXPORT" \
  -allowProvisioningUpdates

echo
echo "Exported:"
ls -1 "$EXPORT"

if [[ "${1:-}" == "--upload" ]]; then
  # An App Store Connect API key (App Store Connect → Users and Access → Integrations).
  # Transporter.app does the same thing from a GUI, if that is more comfortable.
  : "${ASC_KEY_ID:?Set ASC_KEY_ID (App Store Connect API key id)}"
  : "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID (App Store Connect API issuer id)}"

  xcrun altool --upload-app --type macos \
    --file "$EXPORT/$BUNDLE_ID.pkg" \
    --api-key "$ASC_KEY_ID" \
    --api-issuer "$ASC_ISSUER_ID"
  echo "Uploaded. The build appears in App Store Connect after processing."
fi
