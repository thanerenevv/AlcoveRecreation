#!/bin/zsh
# Builds "Alcove Recreation.app" into ./build using SwiftPM (no Xcode project needed).
# Usage: Scripts/build-app.sh [debug|release]
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIG="${1:-release}"
APP="$ROOT/build/Alcove Recreation.app"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/AlcoveRecreation"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AlcoveRecreation"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# Regenerate the icon with: swift Scripts/make-icon.swift
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Sign with a real identity when one exists: macOS ties privacy grants (Accessibility,
# Automation, Calendar) to the signature, and an ad-hoc signature changes with every build,
# which silently invalidates them. Override with CODESIGN_IDENTITY, or set it to "-" for ad-hoc.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development|Developer ID Application/ { print $2; exit }')}"
IDENTITY="${IDENTITY:--}"
codesign --force --sign "$IDENTITY" --entitlements "$ROOT/Resources/AlcoveRecreation.entitlements" "$APP"
[[ "$IDENTITY" == "-" ]] && echo "Signed ad-hoc: permissions will need re-granting after each build."

echo "Built $APP"
