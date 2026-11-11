# APPLY app 3.0.80+151 (TODO 263)

Zip: `locallink_app_3.0.80_2026-11-12.zip`, on top of GitHub `9d223ef` (3.0.79+150).
No backend change, no backend zip.

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_3.0.80_2026-11-12.zip" .
flutter pub get
flutter test
git add -A
git add -f docs/history/TODO_263.md docs/history/APPLY_app_3.0.80.md
git commit -m "v3 3.0.80+151 bundle 263: no messages a normal user does not need - the Chats tab shows no server cards (carried by N phones, Account saved Publish, Waiting for the server, You're on the server now, Couldn't sync) except the name was taken note, no Account published snack, no Find server now on Account and Add friend, no server status line, no phone id in the Add sheet, no Saved on this phone dialog and no server words while signing up, profile saves just say Profile saved (A, B); the work behind them runs by itself and opening Add friend or Account or pulling Chats tries the upload (F); the security code change is a small note inside the chat like WhatsApp, it stays and opens the code page (C)"
git push
flutter build apk --release --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true
```
IMPORTANT (added 14 Nov): keep `--dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true` on the build line. Without it a release APK refuses plain HTTP, and since 3.0.79 (HTTP only) it can't reach the server (regression report, bug R268-1).

## Install
- Install on all 4 phones over the old app. Do NOT clear data.

## What is gone (only the showing - the work goes on by itself)
Chats tab (A):
- "Waiting for the server - carried by N phones" (log `UI_HIDDEN_263|card=carried n=N`).
- "Account saved - it will publish itself... Publish" (log `card=publish`).
- "Waiting for the server to be updated" (log `card=wait_server`). The "Can't join - ask the admin" and "pairing code" cards stay.
- "You're on the server now" - only "@old was taken, so you are @new" still shows (log `card=done kind=..`).
- "Couldn't sync right now..." chip (log `card=sync_notice`).
- Snack "Account published to the server."

Other screens (B):
- Profile save: always "Profile saved". Private profile: always "Your profile is private / public again".
- Account page: no "on this phone only + Find server now" box, no "Can't reach LinkUp" box. A real error while the server is connected still shows.
- Add friend: no "Server connected / No server - searching nearby phones" line.
- Add sheet: no "device ...id" + Copy device id.
- Sign-up: no "Saved on this phone" dialog (log `card=signup_saved`); the button says only "Creating your account..." / "Signing you in...".
- First sign-in: no "Could not check your account history" snack (log `RESTORE_MANIFEST fail ..`).

Kept: recovery code changed, new password only on this phone, can't join (admin / code), signed out - sign in again, blocked, update needed, allow nearby devices. Errors after something you tapped.

## Runs by itself (F)
- The phone-only account upload keeps its 60 s / 5 min tries + Wi-Fi back / app open / server found. New: opening Add friend (`why=add_open`), opening Account (`why=account_open`) and pulling down Chats (`why=refresh`) try at once.
- Carrying through nearby phones, profile push, chats reload, security code re-check: unchanged.

## Security code (C)
- No bar on top of the chat any more.
- A small centred pill in the messages at the time of the change: "Noshad's security code changed. Tap to learn more." (waiting for proof: "Tap to check."). Tap = Security code page. It stays in the chat (max 20 per person, 1 year).
- Changes from the last 24 h before the update show too (made from what the phone kept).
- Log `KEY_EVENT_263|user=.. waiting=y|n`.

## Old tests changed (only these)
- `test/bundle218e_test.dart`: the line that wanted the old "Account saved" banner now wants it gone.
- `test/bundle245_test.dart`: the line that wanted the top bar now wants the in-chat note.
- `test/bundle183_test.dart`: the Account offline box is now expected to be gone.
- `test/bundle223_logs_test.dart`, `test/nearby_190_test.dart`: version 3.0.80+151.

## Tests
- New `test/bundle263_test.dart`: 20 tests, all pass.
- Related test files (49, one by one): all pass.
- Full Flutter suite: 2650 tests, all pass (11 chunks).
- `flutter analyze`: 0 errors (only the old warnings in the calls files).
- No Kotlin change.

## What to check (your steps)
1. A phone with a phone-only account: Chats shows only the chats. The log has `UI_HIDDEN_263|card=..` and `OFFLINE_ACCOUNT_CHECK ... from=timer` every 60 s / 5 min.
2. Open Add friend: no server line, no phone id in the sheet; the log has `from=add_open` when a phone-only account waits.
3. Account page with the server off: no box, the profile shows.
4. A friend reinstalls: a small pill "X's security code changed. Tap to learn more." between the messages; tap opens the code page; the pill stays.
5. Save the profile with the server off: "Profile saved".
6. New sign-up with no server: no dialog; the app opens.
7. Still shown when needed: recovery code changed, signed out - sign in again, blocked, update needed, allow nearby devices.
