#!/bin/bash
set -euo pipefail

# LazyTune DMG Build Script
# Builds LazyTune.app using CommandLineTools and packages a drag-to-Applications DMG.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/LazyTune.app"
DMG_STAGING="$BUILD_DIR/dmg-staging"
DMG_PATH="$BUILD_DIR/LazyTune.dmg"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "==> Building LazyTune.app..."
    "$SCRIPT_DIR/build-local-app.sh"
fi

echo "==> Preparing DMG staging directory..."
rm -rf "$DMG_STAGING" "$DMG_PATH"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/LazyTune.app"
ln -s /Applications "$DMG_STAGING/Applications"

echo "==> Creating compressed LazyTune.dmg..."
hdiutil create \
    -volname "LazyTune" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"

echo "==> Done! DMG created at: $DMG_PATH"
ls -lh "$DMG_PATH"
