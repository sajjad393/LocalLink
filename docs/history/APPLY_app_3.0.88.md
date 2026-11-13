# APPLY app 3.0.88+159: bundle 279 (app part)

Zip: `locallink_app_3.0.88_2026-11-14.zip`, on top of the **3.0.87+158** commit (bundle 278).
**Order:** backend 279 zip first (`APPLY_backend_279.md`, restart the server), then 3.0.87, then this zip.

## What changed
- A-1: the phone no longer reports an old offline card to the server ("Not on server yet") when the
  same phone already has a server card, or when the offline id has moved (the same rule the app's own
  Admin -> Users list uses since 238).
- A-2: no code change needed: the app's Admin -> Users list already puts such a phone under
  "Show hidden" (`split238`), checked in code.
- The backend 279 part removes the old web rows at once; this app part stops new ones.

## Files
`lib/features/admin/data/services/admin_offline_users_222.dart` (`reportList`), version files,
new `test/bundle279_test.dart` (2 tests).
Old tests changed: only the version lines in `bundle223_logs_test.dart`, `nearby_190_test.dart`.

## Checks here
- `flutter test` all 284 files in 12 chunks: 2757 passed, 0 failed (2755 + 2 new).
- The new test fails on the old `admin_offline_users_222.dart` (1 failed) and passes on the new one.
- `flutter analyze`: 175 issues, 0 errors (same as before).
- Release APK `flutter build apk --release --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true` -> BUILD_EXIT=0,
  109.7 MB; aapt2: `com.sajjad.linkup` versionCode 159 / 3.0.88.

## Not verified
- On phones / the web: after backend 279 + this app, web Users should show kiran and sumaira once.

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_3.0.88_2026-11-14.zip" .
git add -A
git add -f docs/history/TODO_279.md docs/history/APPLY_app_3.0.88.md
git commit -m "v3 3.0.88 bundle 279: phone does not report an old offline card to the server when the same phone already has a server card or the id moved (no Not on server yet twin on web Users)"
git push
```
Then GitHub > LocalLink > Actions > App CI should be green. Then the 3.0.89 zip.
