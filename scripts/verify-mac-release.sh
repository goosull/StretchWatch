#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT="${1:-$ROOT_DIR/dist/StretchWatch.app}"
TEMP_DIR=""

cleanup() {
  if [[ -n "$TEMP_DIR" ]]; then
    hdiutil detach "$TEMP_DIR" >/dev/null 2>&1 || true
    rm -rf "$TEMP_DIR"
  fi
}
trap cleanup EXIT

if [[ -f "$INPUT" && "$INPUT" == *.zip ]]; then
  TEMP_DIR="$(mktemp -d)"
  ditto -x -k "$INPUT" "$TEMP_DIR"
  APP_PATH="$TEMP_DIR/StretchWatch.app"
elif [[ -f "$INPUT" && "$INPUT" == *.dmg ]]; then
  TEMP_DIR="$(mktemp -d)"
  hdiutil attach "$INPUT" -nobrowse -readonly -mountpoint "$TEMP_DIR" >/dev/null
  APP_PATH="$TEMP_DIR/StretchWatch.app"
  [[ -L "$TEMP_DIR/Applications" ]] || {
    printf 'DMG is missing the Applications shortcut.\n' >&2
    exit 1
  }
else
  APP_PATH="$INPUT"
fi

if [[ ! -d "$APP_PATH" ]]; then
  printf 'App bundle not found: %s\n' "$APP_PATH" >&2
  exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
BINARY="$APP_PATH/Contents/MacOS/StretchWatch"
[[ -f "$INFO_PLIST" ]] || { printf 'Missing Info.plist\n' >&2; exit 1; }
[[ -x "$BINARY" ]] || { printf 'Missing executable: %s\n' "$BINARY" >&2; exit 1; }

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
MIN_OS="$(otool -l "$BINARY" | awk '/LC_BUILD_VERSION/{found=1} found && /minos/{print $2; exit}')"

[[ "$BUNDLE_ID" == "com.goosull.stretchwatch.mac" ]] || {
  printf 'Unexpected bundle identifier: %s\n' "$BUNDLE_ID" >&2
  exit 1
}
[[ "$MIN_OS" == "14.0" ]] || {
  printf 'Unexpected minimum macOS: %s\n' "${MIN_OS:-missing}" >&2
  exit 1
}

ARCH_INFO="$(lipo -info "$BINARY")"
[[ "$ARCH_INFO" == *arm64* && "$ARCH_INFO" == *x86_64* ]] || {
  printf 'Expected arm64 + x86_64 universal binary, got: %s\n' "$ARCH_INFO" >&2
  exit 1
}

SIGNING_INFO="$(codesign -dvv "$APP_PATH" 2>&1 || true)"
if [[ "$SIGNING_INFO" == *Authority=* || "$SIGNING_INFO" != *"Signature=adhoc"* ]]; then
  printf 'Unexpected Developer ID signing metadata found; P0 artifact should be unsigned/ad-hoc.\n' >&2
  exit 1
fi

printf 'Verified unsigned StretchWatch Mac release\n'
printf 'Bundle ID: %s\n' "$BUNDLE_ID"
printf 'Version: %s\n' "$VERSION"
printf 'Minimum macOS: %s\n' "$MIN_OS"
printf 'Architectures: %s\n' "$ARCH_INFO"
printf 'First launch: right-click StretchWatch.app → Open, then confirm Open.\n'
printf 'Alternative: System Settings → Privacy & Security → Open Anyway.\n'
