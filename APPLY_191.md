# Bundle 191 – call echo: turn on the phone's echo cancel (3.0.22+93)

## Problem (user test, 2026-11-02)
- Realme in one room, ZTE in another room on **speaker** (volume 6/6).
- A glass noise made next to the Realme came **back** to the Realme quickly (echo).
- So the ZTE plays the sound loud, its mic hears it again, and sends it back.

## Cause
- LinkUp opened the call mic in voice call mode and **relied on the phone** to cancel echo.
- It never turned on Android's own echo cancel / noise reduction tools, and never logged if the phone has them.

## Change (option A only)
- `CallMicEffects.kt` (new): when the call mic starts, turn on
  `AcousticEchoCanceler` and `NoiseSuppressor` for the mic session, if the phone offers them.
  Every step is guarded – a failure never stops the call. Released before the mic is released.
- `CallMicEffectsPolicy.kt` (new, pure): words for the log line.
- `LocalLinkTransportService.kt`: attach after the mic is created; release on stop and on start failure.
- New log line (one per call):
  `CALL_MIC_EFFECTS call=<id> echo_cancel=<word> noise_cut=<word> session=<n>`
  - `none` = phone does not offer it, `already` = phone had it on, `on` = LinkUp turned it on,
    `off` = would not turn on, `fail` = Android error.
  - Logged as a warning (`!`) when echo cancel is not working (none / off / fail).
- Version 3.0.22+93, stamp `v3 · 3.0.22 · bundles 104-191 (2026-11-02)`.

## Not changed
- No change to speaker/earpiece, volume, voice buffers, UDP, Nearby, call screens.
- Option B (lower the mic while far voice plays loud) was NOT done.

## Test on phones
1. Same test: Realme in one room, ZTE in the other on speaker. Glass noise near the Realme.
2. Then swap: hold the ZTE, Realme on speaker in the other room.
3. Send both logs. Check `CALL_MIC_EFFECTS` on each phone:
   - ZTE `echo_cancel=on/already` and echo gone → fixed.
   - ZTE `echo_cancel=none` → the ZTE has no echo cancel tool; next step would be option B or lower ZTE speaker volume.
4. Voice must stay as good as the 18:40 call: played ≥97 %, cut_talk ≈0.

## Checks here
- Kotlin compile clean; Kotlin tests 313 passed (incl. `Mic191Test`, 8 new).
- flutter analyze 0 errors; `nearby_190_test` passes (version group updated to 191).
- Audio effects themselves can only be proved on a real phone.
