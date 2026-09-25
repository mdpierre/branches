#!/bin/sh
# Builds Resources/AppIcon.icns from the 1024 × 1024 master, Resources/AppIcon.png.
# Usage: scripts/make-icon.sh
set -eu
cd "$(dirname "$0")/.."
SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$SET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double Resources/AppIcon.png --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
rm -rf "$(dirname "$SET")"
echo "Built Resources/AppIcon.icns"
