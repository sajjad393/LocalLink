# APPLY app 3.0.82+153 (TODO 266)

Zip: `locallink_app_3.0.82_2026-11-14.zip`, on top of 3.0.81+152.
No backend change: the server voice relay (backend 251) is already on your server (`ca4f41c`).

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_3.0.82_2026-11-14.zip" .
flutter pub get
flutter test
git add -A
git add -f docs/history/TODO_266.md docs/history/APPLY_app_3.0.82.md
git commit -m "v3 3.0.82+153 bundle 266: calls on every path - the call also rings through the server and accept, busy, reject and end go both ways (A), voice goes through the server, locked with a key only the two phones know, when there is no nearby way (B), when the link goes quiet for 2.5 s during a call the voice moves to another link and comes back when the old one talks again (C), a call that rings through the server with no nearby way wakes Nearby for that friend for 60 s (D)"
git push
flutter build apk --release --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true
```
IMPORTANT: keep `--dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true` on the build line. Without it a release APK refuses plain HTTP, and since 3.0.79 (HTTP only) it can't reach the server at all (see the regression report, bug R268-1).

## What changes
- A. Ring through the server: when the server is connected, the call invite also goes through the server (once). Accept, busy, reject and end of such a call go both ways. Logs `CALL_INVITE_SERVER`, `CALL_SIGNAL_SERVER_COPY`, `CALL_RING_MS ... via=server|mesh`, `CALL_ANSWER_VIA_SERVER`.
- B. Voice through the server when there is no nearby way. Each voice piece is locked with a key made from your link key with that friend (HKDF, per call); the server can't hear it. Plain voice never goes to the server. Logs `CALL_VOICE_SERVER at=on|off|first_rx|stop`, native `VOICE_SERVER ..`.
- C. During a call, when voice and the link are quiet for 2.5 s, the phone tries the other links; the first one that answers in 1 s carries the voice. It goes back if the old link talks again. Log `CALL_LINK_SWITCH call=.. from=.. to=.. quiet_ms=..`.
- D. A call that rings through the server with no nearby way wakes the Nearby search for that friend for up to 60 s. Log `CALL_NEARBY_WAKE start|end why=..`.
- Server voice works only between two phones on 3.0.82+. An older phone still calls nearby as before.
- Video: not touched.

## Old tests changed
- Only the version lines in `test/bundle223_logs_test.dart` and `test/nearby_190_test.dart`.

## Tests
- New `test/bundle266_test.dart`: 15 tests, pass. New Kotlin `Call266Test.kt`: 10 tests; Kotlin suite 470 tests pass.
- Call-related Flutter test files (58, one by one): all pass.
- Full Flutter suite on the final 3.0.83 tree: 2695 tests, all pass (11 chunks); Kotlin 470 tests pass; flutter analyze 0 errors (the same 9 old warnings).

## Phone check
1. Same router, both on the server: call rings in under 2 s (`CALL_RING_MS`).
2. One phone on another Wi-Fi that reaches the server: the call rings and you can talk (`CALL_VOICE_SERVER at=on`).
3. Server off: calls work as in 3.0.81.
