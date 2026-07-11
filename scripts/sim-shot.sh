#!/bin/bash
# Build the watch app for the simulator, (re)install, launch, and screenshot.
# Usage: scripts/sim-shot.sh <outname>
set -e
WATCH_ID="${WATCH_ID:-E494FCB2-940E-40F2-93E8-D2E0865A2C9C}"
OUT_DIR="${OUT_DIR:-/private/tmp/claude-501/-Users-seungwonkim-orca-projects-StretchWatch/2282540f-44a4-4dee-8220-a21f690572db/scratchpad}"
NAME="${1:-shot}"
BUNDLE="com.goosull.stretchwatch.watchkitapp"

cd "$(dirname "$0")/.."
xcodebuild -project StretchWatch.xcodeproj -scheme "StretchWatch Watch App" \
  -destination "platform=watchOS Simulator,id=$WATCH_ID" \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -5

APP=$(find ~/Library/Developer/Xcode/DerivedData/StretchWatch-*/Build/Products/Debug-watchsimulator -maxdepth 1 -name "*.app" 2>/dev/null | head -1)
xcrun simctl boot "$WATCH_ID" 2>/dev/null || true
xcrun simctl terminate "$WATCH_ID" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$WATCH_ID" "$APP" >/dev/null 2>&1
xcrun simctl launch "$WATCH_ID" "$BUNDLE" >/dev/null 2>&1 || true
for i in $(seq 1 20); do xcrun simctl spawn "$WATCH_ID" true 2>/dev/null; done
xcrun simctl io "$WATCH_ID" screenshot "$OUT_DIR/$NAME.png" 2>&1 | tail -1
echo "-> $OUT_DIR/$NAME.png"
