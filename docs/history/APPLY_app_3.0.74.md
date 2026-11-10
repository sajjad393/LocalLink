# APPLY app 3.0.74+145 (TODO 255 + TODO 256)

Zip: `locallink_app_3.0.74_2026-11-10.zip`, on top of GitHub `0561b07` (3.0.73+144).
No backend change. The backend stays at `2416f0e` (plus the ws test fix zip, if you pushed it).

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_3.0.74_2026-11-10.zip" .
flutter pub get
flutter test
git add -A
git add -f docs/history/TODO_255.md docs/history/TODO_256.md docs/history/APPLY_app_3.0.74.md
git commit -m "<the commit message from the reply>"
git push
flutter build apk --release
```

## What to check on the phones
1. Sign-up on a fresh install on the server Wi-Fi: the line "Looking for the LinkUp server..." then "Server found" shows; the account is made on the server (log `AUTH_RESULT what=create mode=server`).
2. Sign-up with the server off: the "Saved on this phone" dialog shows. Turn the server on: within about 1 minute the account goes up by itself (log `OFFLINE_ACCOUNT_NEXT_TRY in=60s why=timer`, then `OFFLINE_ACCOUNT_DONE`).
3. Account page of a phone-only account: "Your account is on this phone only" and "Find server now".
4. Profile: a wrong phone number turns Save off and shows "Use 03xx xxxxxxx or +92 3xx xxxxxxx".
5. Add Contact: the status line at the top; under Nearby, the chips; turn Wi-Fi off: the "Wi-Fi went off" card; a phone that leaves stays greyed with "Seen .. s ago" for 2 minutes.
6. Crown about 18 % smaller everywhere except the network map.
7. Logs: `SERVER_SEARCH`, `AUTH_RESULT`, `SERVER_HINT`, `NEARBY_LIST`, `FRIEND_ADD_START/FAIL`, `CONTACT_PUSH`, `HTTP_ERROR_RESPONSE ... error="..."`.

## Old tests changed
- `bundle223_logs_test.dart`, `nearby_190_test.dart`: version 3.0.74+145 (normal bump).
- From TODO 255: `group_design_test.dart` ('5 Jan 2025' day label), `calls_group_171_test.dart` (missed calls grouped alone: [1,2,1]), `bundle217d`/`216a`/`214d` (where listed in the reply).
- Note: the admin Network screen now says "Online" (was "Server") for a phone on the server (255 B9).
