# StretchWatch

A watchOS app and a lightweight Mac menu-bar coach that nudge you to do **one seated
stretch** when a computer session runs long — the opposite of Apple's "stand up and
move" ring. Stay in your chair, tilt your neck, roll a shoulder, and get back to work.

## Why

Born from a real problem: sitting through long agentic-coding sessions (in the chair,
not typing) wrecks your neck. The owner went to the hospital for a pinched disc. The
failure mode isn't *not knowing* stretches — it's forgetting in the moment and the
friction of deciding what to do. So StretchWatch removes both: it interrupts you and
hands you one specific move, no decision required.

**The wedge is delivery, not content.** Stretch content is everywhere; nobody does
"detect sitting → guide a seated stretch entirely on the wrist." The differentiator is
the wrist haptic you can't ignore (the owner ignores phone/Mac notifications but always
checks the wrist) and finishing the whole thing on-watch.

## How it works

- **Trigger:** a rolling one-shot scheduler. One pending notification always fires (the
  reliable floor). When watchOS grants a background wake, it checks the pedometer and, if
  you moved recently, pushes the next nudge back (best-effort suppression). Sitting can't
  be read directly on Apple Watch — no API distinguishes sitting from standing — so this
  is honest movement-proxy + a timer, which is what the platform actually allows.
- **The moment:** notification → tap → a *ready* beat → a **breathing countdown arc** with
  a movement glyph you mirror → it **auto-completes** with a bloom. You only ever tap to
  skip (so a dropped wrist mid-stretch never gets logged as a miss).
- **Reflection:** the complication shows today's count on your face; the iPhone app is a
  read-only mirror with cliff-free weekly consistency (a missed day never reads as failure).

See **[DESIGN.md](DESIGN.md)** for the visual system (warm ink + one ember accent, SF
Rounded, the breathing-arc signature — calm, not a red-ring nag).

## Build & run

```bash
brew install xcodegen
xcodegen generate          # generates StretchWatch.xcodeproj from project.yml
open StretchWatch.xcodeproj
```

Set your signing Team on all three targets, pick your watch, and Run. Full device setup
(signing, App Group capability, fast testing, reading the Spike #1 hit-rate) is in
**[WEEKEND-TEST.md](WEEKEND-TEST.md)**.

```bash
# simulator build
xcodebuild -project StretchWatch.xcodeproj -scheme "StretchWatch Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)" \
  CODE_SIGNING_ALLOWED=NO build
# unit tests (pure logic: streak, quiet hours, move selection)
xcodebuild test -project StretchWatch.xcodeproj -scheme "StretchWatchTests" \
  -destination "platform=iOS Simulator,name=iPhone 17" CODE_SIGNING_ALLOWED=NO
```

### Mac menu-bar app

The Mac target uses a 40-minute computer-session heuristic. Quartz's read-only global
idle clock ends an automatic session after 10 minutes without input; it does not read
keystrokes, windows, screenshots, or posture. Click **Enable reminders** in the menu
bar to grant notification permission, then leave the app running in the menu bar.

```bash
xcodegen generate
xcodebuild build -project StretchWatch.xcodeproj -scheme "StretchWatch Mac" \
  -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO

# Build the unsigned Apple-silicon + Intel release zip
./scripts/package-mac.sh
./scripts/verify-mac-release.sh dist/StretchWatch-mac-v0.1.0-universal.zip
```

The GitHub artifact is intentionally unsigned in P0. On first launch, extract the zip,
right-click `StretchWatch.app`, choose **Open**, and confirm **Open**. If macOS still
blocks it, use **System Settings → Privacy & Security → Open Anyway**. A Developer ID
certificate and notarization can remove this step later; they are not required for this
dogfood release.

## Layout

```
Shared/       models + logic (Stretch, StretchStore, Settings, TriggerEngine config, Theme)
WatchApp/     watch UI + TriggerEngine + notification/sync plumbing
iOSApp/       read-only dashboard + WatchConnectivity receiver
Complication/ WidgetKit face complication
MacApp/       menu-bar session coach, local notifications, SQLite state, guided panel
Tests/        unit tests for the pure logic
scripts/      icon helpers, simulator capture, Mac release packaging/verification
```

Project file is generated (not committed) — always `xcodegen generate` after pulling.

## Status

Mac P0 is implemented: automatic 40-minute sessions, 10-minute idle expiry, local
notification actions, sleep/wake recovery, SQLite persistence, the guided `neck-right`
overlay, and an unsigned universal release script. The Mac unit suite covers 47 tests.
Notification response is still a dogfood question, so the next product check is whether
the owner completes the intervention loop over several real work sessions.
