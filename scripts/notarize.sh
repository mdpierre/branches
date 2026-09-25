#!/bin/sh
# Signs, notarizes and zips Branches for a GitHub Release.
#
# One-time setup (needs an Apple Developer account):
#   xcrun notarytool store-credentials branches-notary --apple-id you@example.com --team-id TEAMID
# Then:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/notarize.sh
set -eu
cd "$(dirname "$0")/.."
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}"
PROFILE="${NOTARY_PROFILE:-branches-notary}"

scripts/bundle.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
ZIP="dist/Branches-$VERSION.zip"

ditto -c -k --keepParent dist/Branches.app "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple dist/Branches.app
rm "$ZIP"
ditto -c -k --keepParent dist/Branches.app "$ZIP"
echo "Ready to upload: $ZIP"
