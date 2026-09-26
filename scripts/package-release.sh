#!/bin/sh
# Builds Branches.app and zips it for upload as a GitHub Release asset.
#   scripts/package-release.sh 0.1.0
# Produces dist/Branches-v0.1.0-macos-universal.zip containing Branches.app.
# Signing is whatever scripts/bundle.sh does (ad-hoc unless SIGN_IDENTITY is set).
set -eu
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'; then
    echo "usage: scripts/package-release.sh <version>   (semantic version, e.g. 0.1.0)" >&2
    exit 1
fi

# The zip name must match the version inside the app.
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
if [ "${VERSION%%-*}" != "$PLIST_VERSION" ]; then
    echo "error: version $VERSION does not match CFBundleShortVersionString $PLIST_VERSION in Resources/Info.plist" >&2
    exit 1
fi

scripts/bundle.sh

APP="dist/Branches.app"
[ -d "$APP" ] || { echo "error: $APP was not built" >&2; exit 1; }

codesign --verify --deep --strict --verbose=2 "$APP"
for ARCH in arm64 x86_64; do
    lipo "$APP/Contents/MacOS/Branches" -verify_arch "$ARCH" \
        || { echo "error: binary is missing $ARCH" >&2; exit 1; }
done

ZIP="dist/Branches-v$VERSION-macos-universal.zip"
rm -f "$ZIP"
# ditto keeps the bundle's permissions and symlinks. --norsrc leaves out local-only extended
# attributes (com.apple.provenance), which would otherwise add ._* files to the zip.
ditto -c -k --norsrc --keepParent "$APP" "$ZIP"

SIZE=$(du -h "$ZIP" | cut -f1 | tr -d ' ')
echo "Created $ZIP ($SIZE, $(stat -f%z "$ZIP") bytes)"
