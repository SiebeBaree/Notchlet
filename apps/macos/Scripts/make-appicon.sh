#!/usr/bin/env bash
#
# Renders AppIcon.appiconset from Scripts/AppIcon.svg.
#
# sips is the only dependency, which is why the pipeline goes through a single
# 1024px master rather than rasterising the SVG once per size: asked for a small
# canvas directly, sips drops the clipped background gradient and returns just
# the dark glass panel. Downsampling the master keeps every layer.
#
# Run after editing the artwork, then commit the PNGs.

set -euo pipefail

cd "$(dirname "$0")/.."

SRC="Scripts/AppIcon.svg"
OUT="Notchlet/Resources/Assets.xcassets/AppIcon.appiconset"
MASTER="$(mktemp -t notchlet-appicon).png"
trap 'rm -f "$MASTER"' EXIT

sips -s format png "$SRC" --out "$MASTER" >/dev/null

# point size followed by the pixel size of its 1x and 2x renders
for spec in 16:16:32 32:32:64 128:128:256 256:256:512 512:512:1024; do
    IFS=: read -r pt one two <<<"$spec"
    sips -s format png -Z "$one" "$MASTER" --out "$OUT/icon_${pt}x${pt}.png" >/dev/null
    sips -s format png -Z "$two" "$MASTER" --out "$OUT/icon_${pt}x${pt}@2x.png" >/dev/null
done

echo "wrote $(ls "$OUT"/*.png | wc -l | tr -d ' ') icons to $OUT"
