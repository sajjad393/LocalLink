# APPLY 227 - no more jump to the Welcome screen while logged in (app 3.0.67+138, app only, Dart only)

**Order:** push 224 -> 225 -> 226 first, then this 227 zip.
**No backend, no database, no Kotlin, no new permission.**

## PowerShell

```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force -Path "C:\Users\sajjad Ahmed\Downloads\locallink_app_227_2026-11-09.zip" -DestinationPath .
flutter pub get
flutter test -j 1
git add -A
git add -f APPLY_227.md TODO_227.md
git commit -m "v3 3.0.67+138 bundle 227: no jump to Welcome while logged in (one start screen, back to Home stops at Home, sign-out opens Welcome), the call screen closes once and only itself"
git push
```

## Why it happened (short)
1. **A hidden Welcome under Home.** A logged-in app started with the route `/home`. Flutter splits that into `/` + `/home`, so the list was [Welcome, Home]. A message notification tap, or the chat that opens after Add friend, did "back to the first screen", and the first screen was that hidden Welcome. Home was removed, so the next back showed Welcome.
2. **The call screen closed 2-3 times.** After a hang-up the call sends 2-3 updates, and each one closed the screen on top: first the call, then the chat, then (in case 1) Welcome showed.

## What changes for the user
- After a call you stay in the chat you called from. Before, the chat closed too, or Welcome showed.
- Back from a chat opened by a notification goes to Home, never Welcome.
- Profile -> Sign out still opens Welcome (now also right after a fresh login).

## Log
- `CALL_SCREEN_CLOSE call=... state=canceled|ended|...`: one line per call end. If you ever see it twice for one call, send me the log.

## Files
- `lib/app/local_link_app.dart`, `lib/core/routing/app_router.dart`, `lib/features/calls/presentation/screens/call_screen.dart`
- `pubspec.yaml`, `lib/core/config/app_build.dart` (3.0.67+138)
- NEW `test/welcome_jump_227_test.dart` (14 tests). Old tests: only the version pins in `test/bundle223_logs_test.dart` and `test/nearby_190_test.dart`.

## Phone tests (227)
1. Open the app (logged in) -> Home -> press back once -> "Press back again to exit" (never Welcome).
2. Get a message notification from B, tap it -> chat -> press back -> **Home**.
3. Same chat (opened from the notification) -> call B -> cut after 3 s -> **you stay in B's chat**.
4. Normal chat from Home -> call -> cut -> **you stay in the chat**.
5. B turns on the camera (the "Switch to video call?" box shows), then the call ends -> back to the chat, and the box is gone.
6. Profile -> Sign out -> Welcome. Do it once right after a fresh login (no restart) too.
7. Add a new friend -> the chat opens -> back -> Home.
