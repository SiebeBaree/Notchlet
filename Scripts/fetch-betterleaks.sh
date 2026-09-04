#!/usr/bin/env bash
#
# Downloads the pinned betterleaks release into Vendor/betterleaks, which the
# app target copies into Contents/MacOS. Run once after cloning; until then
# the build fails with "Build input file cannot be found:
# .../Vendor/betterleaks/betterleaks". CI runs it before archiving.
#
# arm64 only: no Intel Mac has a notch, and a universal helper would double
# the download. Bumping betterleaks is editing the two values below.

set -euo pipefail

VERSION=1.8.1
SHA256=8e80f33b5f2a7426b390347b9fd466033723cb94b6bdffa7572632e2eaec964e

cd "$(dirname "$0")/.."
DEST=Vendor/betterleaks

if [ -x "$DEST/betterleaks" ] && [ "$(cat "$DEST/VERSION" 2>/dev/null)" = "$VERSION" ]; then
    echo "betterleaks $VERSION already in $DEST"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

URL="https://github.com/betterleaks/betterleaks/releases/download/v$VERSION/betterleaks_${VERSION}_darwin_arm64.tar.gz"
curl -fsSL "$URL" -o "$TMP/betterleaks.tar.gz"
echo "$SHA256  $TMP/betterleaks.tar.gz" | shasum -a 256 -c -
tar -xzf "$TMP/betterleaks.tar.gz" -C "$TMP" betterleaks LICENSE

mkdir -p "$DEST"
mv "$TMP/betterleaks" "$DEST/betterleaks"
mv "$TMP/LICENSE" "$DEST/betterleaks-LICENSE"
echo "$VERSION" > "$DEST/VERSION"
xattr -d com.apple.quarantine "$DEST/betterleaks" 2>/dev/null || true
echo "betterleaks $VERSION fetched into $DEST"
