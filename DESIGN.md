# StretchWatch — Design System (watchOS / SwiftUI)

The product is the *opposite* of Apple's Stand reminder: not a red-ring "STAND UP"
nag, but a calm, bodily nudge to ease one part of your body while you stay seated.
Every visual choice serves **calm, breath, and glanceability on a 40–49mm screen
while your eyes are half off the wrist.**

## Thesis
Calm bodily reset. Warm, low-urgency, breathing. Never a fitness metric, never a scold.

## Signature
The **breathing arc**: the countdown is not a number or a standard activity ring —
it's an arc that depletes with an ease that mimics an exhale, wrapped around a
**movement glyph** that gently animates the stretch. Completion is a **bloom**
(the accent radiates outward) + a `.success` haptic, never a checkmark tick.

## Color tokens (warm-tinted dark — NOT pure black, NOT Apple activity red/green)
```
ink        #0E0B12   // base — warm near-black plum, OLED-friendly, calmer than #000
ink2       #171320   // raised surface
haze       #A9A2B8   // secondary text / labels (muted lavender-grey)
paper      #F3EEF6   // primary text (soft warm white, not #FFF)
ember      #F2A65A   // primary accent — warm amber (muscle/warmth, the "active" color)
ember2     #E9683E   // accent deep — coral, for the bloom gradient end
calm       #6FB6A6   // rare secondary — muted teal, only for "resting/idle" states
```
Accent is used with restraint: only the active movement, the arc, and the reward
bloom carry `ember`. Everything else is ink/haze/paper. Do NOT color the whole UI.

## Type
System **SF Rounded** (`.rounded` design) — rounded reads as soft/bodily/coach, not
drill-sergeant; a deliberate departure from default SF that most watch apps ship.
- Instruction (the movement): `.title3`–`.title2`, `.semibold`, rounded. The hero.
- Labels / captions: `.caption2`, `.regular`, rounded, `haze`.
- Numbers (count/seconds): `.rounded` + `.monospacedDigit()` so they don't jitter.

## Motion
- Breathing arc: ease that slows at the ends (a breath), not linear.
- Movement glyph: a slow, looping mirror of the stretch (e.g. a head-tilt arc), NOT a spinner.
- Reward bloom: one radial expansion of `ember`→`ember2`, ~500ms, then settle.
- Honor **Reduce Motion**: replace the breathing loop with a static glyph + a
  crossfade; the arc still depletes but without the breath overshoot.
- Restraint: no scattered effects. The arc + glyph + bloom are the whole motion budget.

## Copy tone (warm brief coach — no guilt, no imperative nag)
- Instruction: "Ease your neck right · 10s" — plain, second-person, specific. NOT "STRETCH NOW".
- Notification body carries the actual move so it's doable from the banner, varied per fire.
- Completion: "Nice." / "That's one." / "Your neck thanks you." — never "COMPLETED".
- Skipped / missed: never scold. Empty streak reads as an invitation, not a failure.
- Errors: interface voice, problem + fix. "Reminders are off. Turn them on in Settings ›".

## Hard bans (always apply)
- **No emoji as an icon.** Use SF Symbols or drawn shapes for the movement glyphs.
- **No Apple activity-ring red/green** as UI color, and **no pure `#000`/`#FFF`** — use ink/paper.
- **No generic spinner.** Loading = a calm skeleton or the breathing glyph at rest.
- **Every screen specs loading / empty / error / permission-denied.** No dead ends.
- **Glanceable-first:** the instruction must be readable in <1s; the arc readable in peripheral vision.
- **Reduce Motion + Dynamic Type** honored on every screen.
- **No numbered markers (01/02/03)** unless the content is a real sequence.

## Named presets per surface
- **StretchSession** (the moment): bold — the signature breathing arc + glyph + bloom live here.
- **Complication / Dashboard / Settings**: calm + precise — quiet ink/haze, one `ember`
  highlight for the single number that matters (today's count / time to next).
