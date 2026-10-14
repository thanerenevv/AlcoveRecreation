#!/bin/zsh
# Builds the app and wraps it in an installer package that puts it in /Applications,
# replacing any version that is already installed there.
# Usage: Scripts/build-pkg.sh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/Alcove Recreation.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ROOT/Resources/Info.plist")"
PKG="$ROOT/build/Alcove Recreation $VERSION.pkg"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

"$ROOT/Scripts/build-app.sh" release

mkdir -p "$WORK/root/Applications"
ditto "$APP" "$WORK/root/Applications/Alcove Recreation.app"

# Without this the installer "relocates": it finds any other copy of the bundle on disk
# (such as the one in ./build) and updates that instead of installing to /Applications.
pkgbuild --analyze --root "$WORK/root" "$WORK/components.plist"
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/components.plist"
# Always replace an installed copy, even when the version number has not changed.
plutil -replace 0.BundleIsVersionChecked -bool NO "$WORK/components.plist"

# Scripts/pkg holds preinstall (quit + remove the installed version) and postinstall (relaunch),
# so opening a newer package replaces the old app instead of merging into it.
pkgbuild --root "$WORK/root" --component-plist "$WORK/components.plist" --scripts "$ROOT/Scripts/pkg" \
    --identifier "$IDENTIFIER.pkg" --version "$VERSION" --install-location / \
    "$WORK/component.pkg"

# productbuild adds the standard Installer UI (title, destination, summary) around the payload.
productbuild --package "$WORK/component.pkg" --identifier "$IDENTIFIER.installer" --version "$VERSION" "$PKG"

echo "Built $PKG"
