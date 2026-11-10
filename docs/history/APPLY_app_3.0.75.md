# APPLY app 3.0.75+146 (TODO 257)

Zip: `locallink_app_3.0.75_2026-11-10.zip`, on top of GitHub `1eec747` (3.0.74+145).
No backend change.

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_3.0.75_2026-11-10.zip" .
flutter pub get
flutter test
git add -A
git add -f docs/history/TODO_257.md docs/history/APPLY_app_3.0.75.md
git commit -m "v3 3.0.75+146 bundle 257: friends no longer locked out of Wi-Fi Direct and Local Wi-Fi - a friend who passed the link check once but has no matching key now (reinstall, new keys, account moved) links the old way instead of being refused, a changed key resets the check, link keys are rebuilt when a friend card arrives or a new code is accepted or a key or id changes, refused links back off, LINK_AUTH logs show the end of the id, LINK_KEY_MISSING says why a friend has no key, an old offline card of a moved friend is not saved again and the server card is read first"
git push
flutter build apk --release
```

## Install
Install on ALL 3 phones (C71, Note, TECNO). Install over the old app. Do NOT clear data.

## What to check (server OFF)
1. The phones link again over Wi-Fi Direct / Local Wi-Fi within about 1 minute.
2. Logs: no `LINK_AUTH reject ... reason=auth_required`. At most a few `LINK_AUTH legacy peer=<last 8> ... reason=rekey`, then `verified` once the keys match.
3. `LINK_AUTH verified_reset ... why=key_changed` may show once per friend after the update (normal).
4. `LINK_KEY_MISSING peer=... why=...` shows why a friend still has no key (send me these lines).
5. `ID_MOVED` once, not on every start. `ID_MOVED_OLD_CARD_SKIP` may show once.
6. Chats to each other go through with the server off (`MESSAGE_ROUTE_AVAILABLE transport=wifi_direct` or `lan`).

## Old tests changed
- `android/app/src/test/kotlin/com/sajjad/locallink/mesh/Scale160Test.kt`: 2 lines. "passed before + no shared key" now expects `LEGACY "rekey"` (was `REJECT "auth_required"`).
- `bundle223_logs_test.dart`, `nearby_190_test.dart`: version 3.0.75+146 (normal bump).
