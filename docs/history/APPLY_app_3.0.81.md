# APPLY app 3.0.81+152 (TODO 265)

Zip: `locallink_app_3.0.81_2026-11-14.zip`, on top of 3.0.80+151 (push 3.0.80 FIRST).
No backend change.

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_3.0.81_2026-11-14.zip" .
flutter pub get
flutter test
git add -A
git add -f docs/history/TODO_265.md docs/history/APPLY_app_3.0.81.md
git commit -m "v3 3.0.81+152 bundle 265: small safety fixes from the review - a server search reply can only send the phone to the address it came from or a private address (A), the search no longer counts packets that were never sent (B), opening the app clears an account upload lock left by the background engine so the upload does not wait up to 90 s (C)"
git push
flutter build apk --release --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true
```
IMPORTANT: keep `--dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true` on the build line. Without it a release APK refuses plain HTTP, and since 3.0.79 (HTTP only) it can't reach the server at all (see the regression report, bug R268-1).

## What changes
- A. Server search: if a reply names a public address or a host name, the phone uses the address the reply came from. Your server (192.168.18.x) is private, so nothing changes for you. Log `SERVER_SEARCH host_ignored from=..` (only if it happens). First trust of a new server is logged `SERVER_FIRST_TRUST`.
- B. Server search counts only packets really sent, so `sent=` and `reason=` in `SERVER_SEARCH` lines are right.
- C. Opening the app clears a leftover upload lock from the background engine. Log `OFFLINE_ACCOUNT_LEASE cleared=bg`; no more `OFFLINE_ACCOUNT_BUSY` for 90 s after opening.
- No screen change.

## Old tests changed
- Only the version lines in `test/bundle223_logs_test.dart` and `test/nearby_190_test.dart`.

## Tests
- New `test/bundle265_test.dart`: 12 tests, pass.
- Full Flutter suite on the final 3.0.83 tree: 2695 tests, all pass (11 chunks); Kotlin 470 tests pass; flutter analyze 0 errors (the same 9 old warnings).
