#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
BUILD_DIR="$ROOT_DIR/.build"
APP_PATH="$BUILD_DIR/Moda.app"
VERSION="${1:-$(plutil -extract CFBundleShortVersionString raw "$ROOT_DIR/Packaging/Info.plist")}"
DMG_ROOT="$BUILD_DIR/Moda-dmg"
DMG_PATH="$BUILD_DIR/Moda-v${VERSION}.dmg"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: $APP_PATH does not exist; run ./Scripts/build-app.sh first" >&2
  exit 1
fi

rm -rf "$DMG_ROOT" "$DMG_PATH"
mkdir -p "$DMG_ROOT"
ditto "$APP_PATH" "$DMG_ROOT/Moda.app"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "Moda" \
  -srcfolder "$DMG_ROOT" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG_PATH"

codesign --verify --deep --strict --verbose=2 "$DMG_ROOT/Moda.app"
shasum -a 256 "$DMG_PATH"
echo "$DMG_PATH"
