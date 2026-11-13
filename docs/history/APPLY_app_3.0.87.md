# APPLY app 3.0.87+158: bundle 278

Zip: `locallink_app_3.0.87_2026-11-14.zip`, on top of the **3.0.86+157** commit `de70ef7`.
No backend change in 278 (the backend 279 zip can go first; it does not matter for 278).

## What changed
- Offline sign-in (server off) now says why it did not work:
  - nothing saved on this phone: "This phone has no saved sign-in yet. Turn the server on and sign in once."
  - another account was used last on this phone: "This phone can sign in offline only with the last
    account used on it."
  - wrong password: the same words as before ("That username and password do not match.").
- Log line: `AUTH_OFFLINE_LOGIN bad reason=<no_copy|other_user|bad_password>` (no username).
- No change to: what is saved, Reset, the password maths, server sign-in, the one-phone-one-account rule.

## Files
`lib/core/crypto/password_kdf.dart` (`OfflineLoginReason278`, `offlineLoginText278`),
`lib/features/authentication/data/repositories/authentication_repository.dart` (`offlineLoginReason278`),
`lib/features/authentication/bloc/authentication_bloc.dart` (`_offlineFallback` words + log),
version files, new `test/bundle278_test.dart` (5 tests).
Old tests changed: only the version lines in `bundle223_logs_test.dart`, `nearby_190_test.dart`.

## Checks here
- `flutter test` all 283 files in 12 chunks: 2755 passed, 0 failed (2750 + 5 new); `bundle214g_test` passes.
- `flutter analyze`: 175 issues, 0 errors (same as 3.0.86).
- Release APK `flutter build apk --release --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true` -> BUILD_EXIT=0,
  109.7 MB; aapt2: `com.sajjad.linkup` versionCode 158 / 3.0.87.

## Not verified
- On phones (needs a phone with the server off: a new phone, another account, a wrong password).

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_3.0.87_2026-11-14.zip" .
git add -A
git add -f docs/history/TODO_278.md docs/history/APPLY_app_3.0.87.md
git commit -m "v3 3.0.87 bundle 278: offline sign-in says why it failed - no saved sign-in on this phone, only the last account works offline, or wrong password (same words as before); AUTH_OFFLINE_LOGIN bad reason= log without names"
git push
```
Then GitHub > LocalLink > Actions > App CI should be green. Then the 3.0.88 zip.
