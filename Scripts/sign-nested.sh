#!/usr/bin/env bash
#
# Re-signs the nested executables with the Developer ID identity.
#
# Sparkle ships its XPC services, Updater.app and Autoupdate ad-hoc signed, and
# Xcode's copy phase signs the framework bundle without recursing into them.
# The betterleaks helper arrives unsigned from its GitHub release. An ad-hoc or
# missing signature with no secure timestamp fails notarization, which shows up
# as a bare "status: Invalid" that names no file.
#
# Usage: Scripts/sign-nested.sh <path-to-.app> <signing-identity>

set -euo pipefail

APP="${1:?usage: sign-nested.sh <app> <identity>}"
IDENTITY="${2:?usage: sign-nested.sh <app> <identity>}"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
HELPER="$APP/Contents/MacOS/betterleaks"

test -d "$SPARKLE" || { echo "no Sparkle.framework in $APP"; exit 1; }
test -x "$HELPER" || { echo "no betterleaks helper in $APP"; exit 1; }

# Innermost first. Signing a nested bundle invalidates every signature above it,
# so the app itself has to be re-signed last.
for component in \
    "$SPARKLE/XPCServices/Downloader.xpc" \
    "$SPARKLE/XPCServices/Installer.xpc" \
    "$SPARKLE/Updater.app" \
    "$SPARKLE/Autoupdate" \
    "$HELPER"; do
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$component"
done

codesign --force --sign "$IDENTITY" --options runtime --timestamp \
    "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$APP"

codesign --verify --deep --strict "$APP"
