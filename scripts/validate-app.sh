#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_PATH="${1:-$PROJECT_DIR/dist/Spotmoji.app}"

if [[ ! -d "$APP_PATH" ]]; then
    print -u2 "App bundle not found: $APP_PATH"
    exit 1
fi

plutil -lint "$APP_PATH/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

RESOURCE_OUTPUT="$("$APP_PATH/Contents/MacOS/Spotmoji" --validate-resources)"
if [[ "$RESOURCE_OUTPUT" != Loaded\ *\ emoji\ records ]]; then
    print -u2 "Unexpected resource validation output: $RESOURCE_OUTPUT"
    exit 1
fi

print "$RESOURCE_OUTPUT"
