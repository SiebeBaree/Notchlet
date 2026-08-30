#!/usr/bin/env bash
#
# Re-signs Sparkle's nested executables with the Developer ID identity.
#
# Sparkle ships its XPC services, Updater.app and Autoupdate ad-hoc signed, and
# Xcode's copy phase signs the framework bundle without recursing into them. An
# ad-hoc signature with no secure timestamp fails notarization, which shows up
# as a bare "status: Invalid" that names no file.
#
# Usage: Scripts/sign-sparkle.sh <path-to-.app> <signing-identity>

set -euo pipefail

APP="${1:?usage: sign-sparkle.sh <app> <identity>}"
IDENTITY="${2:?usage: sign-sparkle.sh <app> <identity>}"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"

test -d "$SPARKLE" || { echo "no Sparkle.framework in $APP"; exit 1; }

# Innermost first. Signing a nested bundle invalidates every signature above it,
# so the app itself has to be re-signed last.
for component in \
    "$SPARKLE/XPCServices/Downloader.xpc" \
    "$SPARKLE/XPCServices/Installer.xpc" \
    "$SPARKLE/Updater.app" \
    "$SPARKLE/Autoupdate"; do
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$component"
done

codesign --force --sign "$IDENTITY" --options runtime --timestamp \
    "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$APP"

codesign --verify --deep --strict "$APP"
