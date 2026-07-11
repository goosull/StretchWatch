# StretchWatch — Weekend Device Test Guide

The app builds and runs (watch + iOS + complication), and the pure logic is unit-tested.
The one thing only a real Apple Watch can validate is **Spike #1: does watchOS wake us
often enough for the movement-suppression to matter** (the simulator has no background
budget or pedometer). This guide gets it onto your wrist and shows you what to watch.

## 0. One-time setup

```bash
cd ~/orca/projects/StretchWatch
brew install xcodegen        # if not already
xcodegen generate            # writes StretchWatch.xcodeproj from project.yml
open StretchWatch.xcodeproj
```

In Xcode, for **each** of the 3 targets (StretchWatch, StretchWatch Watch App,
StretchWatch Complication) → Signing & Capabilities:
- Set **Team** to your Apple Developer account (the $99 one).
- The bundle IDs use the prefix `com.goosull.stretchwatch`. If Xcode says the ID is
  taken, change the prefix (e.g. `com.<you>.stretchwatch`) consistently across all 3
  targets **and** the App Group (`group.com.<you>.stretchwatch`) in
  `Shared/AppGroup.swift` + each target's entitlement.

**Capabilities that need a PAID team** (a free personal Apple ID can't do these):
- **App Groups** — lets the complication read the same count the app writes. Without it
  the app still runs (it falls back to a local container), but the complication won't
  show your live count. Turn it on for both the Watch App and the Complication.
- Notifications work on any team. Motion & Background App Refresh work on any team.

## 1. Run on your watch

1. Unlock your iPhone + Apple Watch, keep them paired and nearby.
2. In Xcode, pick the **StretchWatch Watch App** scheme, choose your physical watch as
   the destination, and Run (⌘R). First install to a real watch can take a minute.
3. On first launch you'll see **Ease up, seated** → tap **Turn on reminders** (allow
   notifications, then allow Motion & Fitness when prompted).
4. **Add the complication to your active watch face** (long-press face → Edit → add
   "StretchWatch"). This is what unlocks the background-refresh budget — the suppression
   check barely runs without it.

## 2. Test the experience fast (don't wait 40 min)

The real cadence is 40 min. To exercise the flow quickly:
- **Stretch now** on the home screen runs a session immediately (no waiting).
- To make the *scheduled* reminder fire fast, drop the interval: open
  `Shared/Config.swift`, set `interval` to `3 * 60`, re-run. (Set it back to `40 * 60`
  for the real multi-day test.) Or use **Settings → Nudge every → 20 min** in-app.
- When a notification arrives: tap it → the guided stretch opens (ready beat → breathing
  arc → auto-completes). Or use the **Did it / Not now** buttons right on the banner.

## 3. What to actually watch for (the weekend questions)

- **Does the buzz land and feel un-ignorable?** (Your whole thesis: wrist > screen.)
- **Does completing feel good?** The bloom + haptic + count bump — is it satisfying
  enough to want again? (Habituation is the #1 killer.)
- **Does the auto-complete feel right,** or do you wish you'd confirmed? (We inverted it:
  finishing the countdown = done; you only tap to skip.)
- **Spike #1 — the real reason to test on device:** open **Settings (gear) → Spike #1
  data**. After a day of wear it shows:
  - **Hit-rate** — of the times you'd moved, how often we woke early enough to suppress
    the next buzz. This is the number that decides whether the "smart" layer is worth
    keeping or whether we ship the pure timer.
  - **Wakes/hr** and **median lead** — how generous watchOS is being with background time.
  - Wear it with the complication on-face for a couple of days, charging/sleeping as
    normal, then read these.

## 4. If reminders never fire in the background

That's the expected watchOS risk, not a bug — the pure timer path still fires the
scheduled notification even with zero background wakes. If the *suppression* (skipping a
buzz right after you walked) rarely happens, that's the spike telling us to ship the
timer and drop the smart layer. Note the hit-rate and we decide from data.

## Build / test commands (reference)

```bash
xcodegen generate
# watch build (simulator):
xcodebuild -project StretchWatch.xcodeproj -scheme "StretchWatch Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)" \
  CODE_SIGNING_ALLOWED=NO build
# unit tests:
xcodebuild test -project StretchWatch.xcodeproj -scheme "StretchWatchTests" \
  -destination "platform=iOS Simulator,name=iPhone 17" CODE_SIGNING_ALLOWED=NO
# screenshot a screen in the sim: scripts/sim-shot.sh
```
