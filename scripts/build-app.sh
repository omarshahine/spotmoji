#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
DIST_DIR="$PROJECT_DIR/dist"
APP_PATH="$DIST_DIR/Spotmoji.app"
export SWIFT_MODULECACHE_PATH="$PROJECT_DIR/.build/swift-module-cache"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-module-cache"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

cd "$PROJECT_DIR"
swift build -c release --disable-sandbox
BIN_DIR="$(swift build -c release --disable-sandbox --show-bin-path)"

if [[ -e "$APP_PATH" ]]; then
    /usr/bin/trash "$APP_PATH"
fi

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
ditto "$BIN_DIR/Spotmoji" "$APP_PATH/Contents/MacOS/Spotmoji"
ditto "$PROJECT_DIR/scripts/Info.plist" "$APP_PATH/Contents/Info.plist"

if [[ -n "${APP_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_PATH/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"
fi

if [[ -d "$BIN_DIR/Spotmoji_Spotmoji.bundle" ]]; then
    ditto "$BIN_DIR/Spotmoji_Spotmoji.bundle" "$APP_PATH/Contents/Resources/Spotmoji_Spotmoji.bundle"
fi

ditto "$PROJECT_DIR/Assets/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$APP_PATH"
else
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_PATH"
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "$APP_PATH"
