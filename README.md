# StretchWatch

A watchOS app that nudges you to do **one seated stretch** when you've been sitting
too long — the opposite of Apple's "stand up and move" ring. Stay in your chair, tilt
your neck, roll a shoulder, and get back to work.

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

## Layout

```
Shared/       models + logic (Stretch, StretchStore, Settings, TriggerEngine config, Theme)
WatchApp/     watch UI + TriggerEngine + notification/sync plumbing
iOSApp/       read-only dashboard + WatchConnectivity receiver
Complication/ WidgetKit face complication
Tests/        unit tests for the pure logic
```

Project file is generated (not committed) — always `xcodegen generate` after pulling.

## Status

v1 in progress. Builds green (watch + iOS + complication), 11 unit tests passing. The one
thing only real hardware can validate is the background suppression hit-rate — read it
in-app via **Settings → Spike #1 data** after wearing it a few days.
