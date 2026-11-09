# TODO 227 - The app jumps to the Welcome screen while you are logged in

Status: **BUILT 2026-11-09** (your answer "Build 227 now").
Base: app 226 (`33e36ff`, 3.0.66+137, waiting for push). Version 3.0.67+138. App only, Dart only. No backend, no Kotlin, no new permission.

## 1. What you saw
- Sometimes the app shows the Welcome (login) screen even though you are logged in.
- Example: A calls B, A cuts the call after a few seconds -> A's app shows Welcome.

## 2. Causes (checked in the code and proven with a test)

### Cause 1 - a hidden Welcome screen sits under Home
- The route names are `welcome = '/'` and `home = '/home'` (`app_routes.dart`).
- When an already logged-in app opens, it starts with `initialRoute: '/home'` (`local_link_app.dart:722`).
- Flutter splits `'/home'` into `'/'` + `'/home'`, so it builds **two** screens: **[Welcome, Home]**. Welcome is hidden under Home.
- Back on Home is blocked (press back twice to exit), so normally you never see it.
- **But `popUntil(route.isFirst)` skips that block.** "First" is the hidden Welcome, so Home is removed. This happens in:
  - a message notification tap (`local_link_app.dart:454`, groups `:478`);
  - the chat that opens by itself after Add friend (`:183`).
- After that the screens are **[Welcome, Chat]**. Pressing back from that chat, or anything that closes the chat, shows **Welcome**.
- Test result: `after popUntil isFirst: welcome=1 home=0`.

### Cause 2 - the call screen closes more than once
- When a call ends, `call_screen.dart` (lines 134-149) closes the screen in **every** rebuild. Only the 2-second "no nearby connection" case has a guard.
- After you hang up, the call sends 2-3 updates (call ended -> call saved in history -> call cleared). That means 2-3 closes.
- `maybePop()` closes **whatever screen is on top**, not only the call screen. So:
  - 1st close: the call screen.
  - 2nd close: **the chat under it**.
  - 3rd close: Home (blocked: you see "Press back again to exit"; two of these in 2 s can even close the app).
- Test results:
  - Chat opened from a notification -> call -> hang up -> **Welcome** (`welcome=1 chat=0`). **This is your case.**
  - Normal chat from Home -> call -> hang up -> **the chat also closes**, you land on Home (`home=1 chat=0`). A second, smaller bug from the same cause.

### Not the cause (checked)
- Login data is not lost: sign out happens only from Profile -> Sign out or an admin sign-out. Nothing clears the login after a call. On the next app start you are logged in.

## 3. Fix (minimal, 3 files)

- [x] **F1 - no hidden Welcome** (`local_link_app.dart`): build only ONE start screen (`onGenerateInitialRoutes` -> Home **or** Welcome, never both).
- [x] **F2 - sign-out still reaches Welcome** (`local_link_app.dart`): Profile -> Sign out and admin sign-out used the hidden Welcome. Now, after sign-out, the app opens Welcome on purpose (`pushNamedAndRemoveUntil(welcome)`).
  - This probably also fixes an old hidden bug. After a fresh login (no restart) the screen list is only [Home], so Sign out would stay on Home. The code shows this, but it has not been seen on a phone; phone test 6 checks it.
- [x] **F3 - notification tap / new friend chat** (`local_link_app.dart`): "back to Home first" stops at Home by name (`route.settings.name == home`), never deeper.
- [x] **F4 - the call screen closes once, and only itself** (`call_screen.dart`):
  - one flag, so it closes one time;
  - closes its **own** route: if it is on top -> `pop`; if something is on top of it (for example the "Switch to video call?" box) -> `removeRoute` of the call screen only;
  - the 2-second hold stays as it is.
- [x] Version 3.0.67+138 (`pubspec.yaml`, `app_build.dart`, version pins in `bundle223_logs_test` and `nearby_190_test`).

Not changed: login, sign-out data, call logic, Nearby, the server.

## 4. Tests
- [x] New `test/welcome_jump_227_test.dart`:
  - logged-in start -> only Home (no Welcome under it);
  - notification tap -> chat -> back -> Home (not Welcome);
  - call screen with 3 finished updates -> closes once; the chat under it stays;
  - call ends while the video box is open -> the call screen goes, the chat stays;
  - sign out (also after a fresh login) -> Welcome.
- [x] Full suite + analyze.

## 5. Phone tests (227)
1. Open the app (logged in) -> Home -> press back once -> "Press back again to exit" (never Welcome).
2. Get a message notification from B, tap it -> chat -> press back -> **Home**.
3. Same chat (opened from the notification) -> call B -> cut after 3 s -> **you stay in B's chat**.
4. Normal chat from Home -> call -> cut -> **you stay in the chat** (before: the chat closed too).
5. Call ends while "Switch to video call?" is open -> back to the chat.
6. Profile -> Sign out -> Welcome. Also once right after a fresh login (no restart).
7. Add a new friend -> the chat opens -> back -> Home.

## 6. Time
About 1-1.5 h including tests.

## As built (227)
- F1: `AppRouter.oneStartScreen` + `onGenerateInitialRoutes` in `local_link_app.dart`.
- F2: `_signedOut()` opens Welcome when the phone is no longer logged in. The admin sign-out uses the same path (its old `popUntil(isFirst)` line is removed).
- F3: the 3 "back to Home first" lines use `AppRouter.isHomeOrFirst`.
- F4: `_closeOnce()` in `call_screen.dart` (one flag; pops its own route, or removes it when a box is on top; closes that box too). New log `CALL_SCREEN_CLOSE call=... state=...`.
- Proof: with the OLD call screen, 3 of the new call tests fail (the chat closes / Welcome shows). With the fix, all 14 new tests pass.
- Old tests: only the version pins (`bundle223_logs_test`, `nearby_190_test`). Nothing else.
- Files: `lib/app/local_link_app.dart`, `lib/core/routing/app_router.dart`, `lib/features/calls/presentation/screens/call_screen.dart`, `pubspec.yaml`, `lib/core/config/app_build.dart`, NEW `test/welcome_jump_227_test.dart`.
