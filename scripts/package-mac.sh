#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
WORK_DIR="$DIST_DIR/.mac-build"
APP_NAME="StretchWatch.app"

VERSION="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT_DIR/project.yml" | head -1)"
VERSION="${VERSION:-0.1.0}"
ZIP_PATH="$DIST_DIR/StretchWatch-mac-v${VERSION}-universal.zip"

if [[ "$ROOT_DIR" != */StretchWatch || ! -f "$ROOT_DIR/project.yml" ]]; then
  printf 'Refusing to package from unexpected root: %s\n' "$ROOT_DIR" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -rf "$WORK_DIR" "$DIST_DIR/$APP_NAME" "$ZIP_PATH"
mkdir -p "$WORK_DIR/arm64" "$WORK_DIR/x86_64"

cd "$ROOT_DIR"
xcodegen generate

build_arch() {
  local arch="$1"
  local output_dir="$WORK_DIR/$arch/products"
  mkdir -p "$output_dir"
  xcodebuild build \
    -project StretchWatch.xcodeproj \
    -scheme "StretchWatch Mac" \
    -configuration Release \
    -sdk macosx \
    -derivedDataPath "$WORK_DIR/$arch/derived" \
    CONFIGURATION_BUILD_DIR="$output_dir" \
    ARCHS="$arch" \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO
}

build_arch arm64
build_arch x86_64

ARM_APP="$WORK_DIR/arm64/products/$APP_NAME"
INTEL_APP="$WORK_DIR/x86_64/products/$APP_NAME"
UNIVERSAL_APP="$DIST_DIR/$APP_NAME"

if [[ ! -d "$ARM_APP" || ! -d "$INTEL_APP" ]]; then
  printf 'Expected architecture-specific app bundles were not produced.\n' >&2
  exit 1
fi

ditto "$ARM_APP" "$UNIVERSAL_APP"
MAIN_BINARY="$UNIVERSAL_APP/Contents/MacOS/StretchWatch"
lipo -create \
  "$ARM_APP/Contents/MacOS/StretchWatch" \
  "$INTEL_APP/Contents/MacOS/StretchWatch" \
  -output "$MAIN_BINARY"

ditto -c -k --sequesterRsrc --keepParent "$UNIVERSAL_APP" "$ZIP_PATH"
SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"

printf '\nCreated: %s\n' "$ZIP_PATH"
printf 'SHA-256: %s\n' "$SHA256"
printf 'Architectures: '
lipo -info "$MAIN_BINARY"
printf '\nUnsigned release note: right-click the app and choose Open on first launch.\n'
