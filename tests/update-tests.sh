#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=11.0 \
  -framework Foundation "$ROOT_DIR/tests/update-tests.m" \
  "$ROOT_DIR/StayAwakeMenu/UpdateRelease.m" -o "$TEST_DIR/UpdateTests"
"$TEST_DIR/UpdateTests"
