#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-release}"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="$BUILD_DIR/Moda.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE_DIR="$BUILD_DIR/ModuleCache"
ICONSET_DIR="$BUILD_DIR/Moda.iconset"
ICON_SOURCE="$ROOT_DIR/icon-iOS-Default-1024@1x.png"
CODE_SIGN_IDENTITY="${MODA_CODE_SIGN_IDENTITY:-}"

export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

cd "$ROOT_DIR"

mkdir -p "$MODULE_CACHE_DIR"

if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null \
    | grep -F '"Moda Local Development"' >/dev/null
  then
    CODE_SIGN_IDENTITY="Moda Local Development"
  else
    CODE_SIGN_IDENTITY="-"
    echo "warning: Moda Local Development identity not found; using ad-hoc signing"
  fi
fi

swift test --disable-sandbox
swift build --disable-sandbox -c "$CONFIGURATION"

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"
cp "$BUILD_DIR/$CONFIGURATION/Moda" "$MACOS_DIR/Moda"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Toolbar Icon.svg" "$RESOURCES_DIR/ModaToolbarIcon.svg"

sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
xcrun iconutil --convert icns --output "$RESOURCES_DIR/Moda.icns" "$ICONSET_DIR"

codesign \
  --force \
  --deep \
  --sign "$CODE_SIGN_IDENTITY" \
  --timestamp=none \
  "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "$APP_DIR"
