# APPLY app 3.0.76+147 (TODO 257 + TODO 258)

Zip: `locallink_app_3.0.76_2026-11-11.zip`, on top of GitHub `1eec747` (3.0.74+145).
It has BOTH 3.0.75 (TODO 257) and 3.0.76 (TODO 258), because 3.0.75 was not pushed yet.
You do not need the 3.0.75 zip any more. No backend change.

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_3.0.76_2026-11-11.zip" .
flutter pub get
flutter test
git add -A
git add -f docs/history/TODO_257.md docs/history/APPLY_app_3.0.75.md docs/history/TODO_258.md docs/history/APPLY_app_3.0.76.md
git commit -m "v3 3.0.76+147 bundles 257-258: friends no longer locked out of Wi-Fi Direct and Local Wi-Fi after a reinstall or new keys, link keys rebuilt when a card or key changes (257); a friend's new security code is taken by itself when his own phone or the server proves it, with a grey line in the chat and no button, a phone that can't open a friend's locked message asks for his card in the open, held codes are checked again when the server is back, no Unknown user after a fresh login (last known name kept, contacts sync retried every 30 s, chat list names refresh when a card comes), the person's name instead of the phone model in chat, calls, notifications and storage, any profile change goes to every friend directly and again when seen, also after a restart (258)"
git push
flutter build apk --release
```

## Install
Install on ALL 3 phones (C71, Note, TECNO). Install over the old app. Do NOT clear data.

## What to check
1. Links (257): the phones link over Wi-Fi Direct / Local Wi-Fi within about 1 minute. No `LINK_AUTH reject ... reason=auth_required`.
2. Security code (258 A): no red "Check" banner. If a friend's code changed, the chat shows a grey line "X's security code changed" (tap it = Security code screen, then it goes away).
   Logs: `KEY_AUTO_258 user=.. phone=.. why=owner` or `why=server`. A held one: `KEY_CHANGE_245`, then `KEY_CARD_ASK_258`, `KEY_CARD_IN_258 ... saved=y`.
3. Names (258 B/C): log out and log in again on one phone (or reinstall it). Friends show their real names, never "Unknown user" and never "RMX3938" / "realme C71".
   Logs: `CONTACTS_SYNC_RETRY in=30s try=N` if the server was slow; `NAME_MISSING peer=.. why=..` says which friend still has no name.
4. Profile (258 D): change your name with the server OFF. The other phones show the new name when they are linked.
   Logs on your phone: `PEER_CARD_TO_FRIENDS|count=N why=profile`, `PEER_CARD_SENT to=.. why=profile` (or `why=seen` later).

## Old tests changed
- `android/app/src/test/kotlin/com/sajjad/locallink/mesh/Scale160Test.kt`: 2 lines (from 257): "passed before + no shared key" now expects `LEGACY "rekey"`.
- `test/bundle223_logs_test.dart`, `test/nearby_190_test.dart`: version 3.0.76+147 (normal bump).
- No other old test changed. New tests: `test/link_257_test.dart`, `Link257Test.kt`, `test/bundle258_test.dart`.
