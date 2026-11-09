# Bundle 199b - v3 3.0.34+105

WhatsApp mic lock (mock `mock_199b_mic_lock.html` v2, option A, style S1).
Base: `a1a2697` (bundle 199). One zip, one commit.

## Apply (PowerShell)

```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes199b_2026-11-03.zip" .
git add -A
git add -f APPLY_199b.md
git reset -q -- android/local.properties
git commit -m "v3 3.0.34 bundle 199b: WhatsApp mic lock - slide 2 cm, lock box gets shorter, lock closes blue, then the panel"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter pub get
flutter build apk --release
```

## The fix
Before: the mic locked after about 1 cm, the mic slid under the lock box, and the panel replaced the bar at once, so the mic and the lock just vanished.

Now:
1. Slide up **about 2 cm** (125 px) to lock. Less than that and let go = sent (as before). Slide left = cancel (as before).
2. **The lock box sits straight above the mic** (it was 11 px to the right). It is white with a soft shadow and no grey line, an **open lock** at the top and an up arrow in the middle.
3. While you slide, **the mic follows your finger**. The box gets shorter from the bottom, always 10 px above the mic, so **the mic never covers the lock**.
4. At 2 cm only the round lock is left: it turns into the **app's blue gradient with a white closed lock**, plus **one small vibration**.
5. **1/4 second later** the panel (bin / pause / send) shows. Lifting your finger during that moment keeps recording.
6. "Remove animations" setting: no bobbing arrow and no pop; the rest is the same.
7. Only the 1-to-1 chat has a mic (groups don't), so only that chat changes.

## Files
- `lib/features/messaging/presentation/voice/voice_levels.dart`: `lockDistance` from 60 to 125
- `lib/features/messaging/presentation/voice/voice_recorder_controller.dart`: `lockClosing` + `lockShowTime` (250 ms); cleared on reset, pause (a call) and close; `lock()` called from code has no moment
- `lib/features/messaging/presentation/voice/voice_recording_widgets.dart`: `VoiceLockBox`: gets shorter with the slide, open/closed lock, S1 look
- `lib/features/messaging/presentation/widgets/chat_composer.dart`: the box centred over the big mic, its bottom rising with the mic; the closed lock shows before the panel
- `pubspec.yaml` 3.0.34+105; `lib/app/local_link_app.dart` stamp `bundles 104-199b`
- Tests: new `test/voice_lock_199b_test.dart`; updated `test/bundle181_test.dart`, `test/voice_slide_198_test.dart`, `test/nearby_190_test.dart`

## Phone tests (L1-L9)
- L1 Hold the mic: a white box with a soft shadow sits straight above the mic (centred), with an open lock and an up arrow.
- L2 Slide up 1 cm: still recording, NO panel; the mic moves up and never covers the lock.
- L3 Slide to 2 cm: the lock circle turns blue with a white closed lock, one small vibration.
- L4 About 1/4 s later the panel shows; lift your finger: still recording.
- L5 Send from the panel: sent.
- L6 Slide up 1 cm and let go: sent at once (as before).
- L7 Slide left: cancelled (as before).
- L8 ZTE with the keyboard open and closed: the whole lock box is on screen.
- L9 Phone setting "Remove animations" on: still works, no bobbing.
