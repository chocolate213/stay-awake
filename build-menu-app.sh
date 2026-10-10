#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT_DIR/dist/Stay Awake.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUILD_DIR="$ROOT_DIR/build"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
APP_ICON_SOURCE="$ROOT_DIR/StayAwakeMenu/Assets/AppIconSource.png"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$BUILD_DIR"

xcrun clang \
  -fobjc-arc \
  -fblocks \
  -Wall \
  -Wextra \
  -framework CoreGraphics \
  -framework Foundation \
  -framework ImageIO \
  "$ROOT_DIR/tools/prepare_app_icon.m" \
  -o "$BUILD_DIR/prepare_app_icon"

"$BUILD_DIR/prepare_app_icon" "$APP_ICON_SOURCE" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

xcrun clang \
  -fobjc-arc \
  -Wall \
  -Wextra \
  -mmacosx-version-min=11.0 \
  -framework AppKit \
  -framework UserNotifications \
  "$ROOT_DIR/StayAwakeMenu/main.m" \
  "$ROOT_DIR/StayAwakeMenu/UpdateRelease.m" \
  -o "$MACOS_DIR/StayAwakeMenu"

cp "$ROOT_DIR/StayAwakeMenu/Info.plist" "$CONTENTS_DIR/Info.plist"
ditto "$ROOT_DIR/StayAwakeMenu/Resources" "$RESOURCES_DIR"
chmod +x "$RESOURCES_DIR/Scripts/stay-awake"
chmod +x "$MACOS_DIR/StayAwakeMenu"

/usr/bin/codesign --force --sign - "$APP_DIR" >/dev/null

printf '%s\n' "$APP_DIR"
