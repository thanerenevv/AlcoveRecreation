#!/bin/zsh
# Builds the app and zips it as the asset the in-app updater looks for, then (when the GitHub CLI
# is installed and logged in) publishes it as a GitHub release tagged v<version>.
# Bump CFBundleShortVersionString and CFBundleVersion in Resources/Info.plist first.
# Usage: Scripts/release.sh [--publish]
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
ZIP="$ROOT/build/Alcove-Recreation-$VERSION.zip"

"$ROOT/Scripts/build-app.sh" release
rm -f "$ZIP"
# --keepParent keeps "Alcove Recreation.app" as the single top-level entry the updater expects.
ditto -c -k --keepParent "$ROOT/build/Alcove Recreation.app" "$ZIP"
echo "Built $ZIP"

if [[ "${1:-}" == "--publish" ]]; then
    command -v gh >/dev/null || { echo "Install the GitHub CLI (brew install gh) to publish from here."; exit 1; }
    gh release create "v$VERSION" "$ZIP" --title "Alcove Recreation $VERSION" --generate-notes
else
    echo "Upload it to a GitHub release tagged v$VERSION, or rerun with --publish."
fi
