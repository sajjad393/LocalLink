# TODO 248 - Video call brought back (Phase 12)

## What "paused" was
Bundle 97 hid the camera button from the in-call pill. All the plumbing stayed:
native `CallVideoSession.kt`, `CallSessionManager.toggleVideo / acceptVideoSwitch /
switchCamera`, `CallVideoView` (full remote + draggable PiP + flip), the
"Switch to video call?" dialog on the other phone, CAMERA + FOREGROUND_SERVICE_CAMERA
in the manifest, and the camera permission prompt in `MainActivity` ("Allow it, then tap video again").

## Done (app only, Dart only)
- `call_action_bar.dart`: camera button (`Key('call_video_toggle_248')`) between Speaker and End.
  - Shows only when the call is `connected` AND `directMode` (Wi-Fi Direct / LAN) - `showVideoButton248()`.
  - Icon `videocam_off` (grey) when off, `videocam` (white) when on. Tap = `CallBloc.toggleVideo`.
  - Errors (no camera permission, camera busy, changed security key) show as the existing call-screen snackbar.
- Receive side unchanged (the "Switch to video call?" dialog, Not now, camera-off accept mode).
- No native (Kotlin) change, no new setting, no start-a-video-call button in the chat (voice call first, then camera - WhatsApp style).
- Tests: `test/bundle248_test.dart` (2). Mock: `mocks/mock_248_video_button.jpg`.

## Still blocking / needs phone tests
1. ZTE Blade A35 (2 GB): camera + encoder + Flutter may be killed by the ZTE memory cleaner. Test a 2 min video call ZTE <-> C71; if killed, a later bundle lowers the capture size for low-RAM phones (needs logs).
2. Wi-Fi Direct bandwidth: video + voice on one WD link while chats sync. Check voice gaps (`CALL_AUDIO` totals) during video.
3. Server-relayed calls (P9 / Phase 15) have no video - button hidden there on purpose.
4. Group voice (Phase 14) - video stays 1:1 only.

## Phone test (user)
- Nearby call, tap camera -> camera permission once -> own picture in PiP; other phone gets "Switch to video call?" -> Switch -> both see video.
- Tap camera again -> back to voice; End works; tap PiP flips the camera.
- Logs to send after: one from each phone.
