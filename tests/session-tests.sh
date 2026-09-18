#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/SessionTests.app/Contents/MacOS" "$TEST_DIR/SessionTests.app/Contents/Resources"
ditto "$ROOT_DIR/StayAwakeMenu/Resources/en.lproj" "$TEST_DIR/SessionTests.app/Contents/Resources/en.lproj"
ditto "$ROOT_DIR/StayAwakeMenu/Resources/zh-Hans.lproj" "$TEST_DIR/SessionTests.app/Contents/Resources/zh-Hans.lproj"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=11.0 \
  -framework AppKit -framework UserNotifications "$ROOT_DIR/tests/session-tests.m" \
  -o "$TEST_DIR/SessionTests.app/Contents/MacOS/SessionTests"
for locale in en zh-Hans; do
  "$TEST_DIR/SessionTests.app/Contents/MacOS/SessionTests" "$ROOT_DIR/StayAwakeMenu/Resources/Scripts/stay-awake" "$locale"
done
