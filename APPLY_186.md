# Bundle 186 - Answering a call is faster (3.0.17+88)

Plan: TODO_186.md. Problem: answering from the notification on the Realme works but is slow
(about 4.2 s from tapping Accept until both people hear each other).
**Apply 184 and 185 first** if you have not pushed them yet (186 is built on top of 185).

## What changed
A. **Measure (new log lines)**
- `CALL_ANSWER_STEP` per step and `CALL_ANSWER_DONE total_ms= since_tap_ms= slowest=` on the answering phone.
- `CALL_AUDIO_STEP name= ms= waited_ms=` for each audio job (audio mode, mic start, stop).
- `CALL_MEDIA_START_MS total= slowest= steps=` (where the native mic/speaker start time goes).
- Caller: `CALL_CONNECT_MS invite_to_accept_ms= accept_to_audio_ms=`. Both phones: `CALL_FIRST_VOICE ms_after_start=`.

B. **Accept is sent at once**
- After the quick checks (link up, identity OK), "accept" goes to the caller BEFORE our mic starts.
  Both phones now start their sound at the same time. Before, the caller kept ringing until our sound was running.
- If our mic then fails, the caller gets the normal call end.

C. **Slow audio work off the main thread**
- Audio mode + earpiece/speaker choice, mic + speaker start and stop: on one "call audio" thread, in order.
  The screen and Dart no longer freeze for them. The mic permission check stays first, on the main thread.
- Audio mode and mic start are asked together (not one after the other).

Not in this bundle (your answers): answering before the app opens (D1, test B + C first), and no
warm-up while ringing (D2, memory on the 2 GB ZTE).

## Files (14)
New:
- android/app/src/main/kotlin/com/sajjad/locallink/CallAudioQueue.kt
- android/app/src/main/kotlin/com/sajjad/locallink/CallAudioThread.kt
- android/app/src/test/kotlin/com/sajjad/locallink/Answer186Test.kt
- lib/features/calls/data/services/call_answer_timer.dart
- test/bundle186_test.dart

Changed:
- android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt
- android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt
- lib/app/local_link_app.dart (stamp: bundles 104-186)
- lib/features/calls/data/services/call_notification_platform_service.dart
- lib/features/calls/data/services/call_session_manager.dart
- lib/features/calls/data/transport/call_transport.dart
- lib/features/calls/data/transport/native_mesh_call_transport.dart
- pubspec.yaml (3.0.17+88)
- test/bundle185_test.dart (version check moved to 186)

## Apply (PowerShell)
```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes186_2026-11-01.zip" .
git add -A
git add -f APPLY_186.md
git reset -q -- android/local.properties
git commit -m "v3 186: faster call answer - accept sent at once, call audio off the main thread, answer timing logs - 3.0.17+88"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter pub get
flutter build apk --release
```

## Phone checks (install on BOTH phones)
1. Realme with the app closed: ZTE calls, tap Accept on the notification. Count the seconds until you hear each other.
   Log: `CALL_ANSWER_DONE since_tap_ms=` (was about 2600 before) and on the ZTE `CALL_CONNECT_MS`.
2. Same with the Realme screen locked.
3. The other way round: Realme calls, ZTE answers from the notification.
4. Answer inside the open app: not slower than before; speaker button on/off still works during the call.
5. Hang up right after Accept (within 1 s): both phones end the call, nothing keeps ringing.

## Tested here (not on a phone)
- Kotlin: clean compile, 288 tests pass (7 new).
- Flutter: analyze no errors (150 issues, same as before); all 836 tests pass (10 new).
- The real time saved can only be proven on the phones.
