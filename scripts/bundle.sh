#!/bin/sh
# Builds Branches.app into dist/.
#   scripts/bundle.sh                 # ad-hoc signed, for local use
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/bundle.sh   # for release
set -eu
cd "$(dirname "$0")/.."

# Universal binary (Apple silicon + Intel).
ARCHS="--arch arm64 --arch x86_64"
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/Branches"

APP="dist/Branches.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Branches"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] || scripts/make-icon.sh
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${SIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp \
        --entitlements Resources/Branches.entitlements --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP"
