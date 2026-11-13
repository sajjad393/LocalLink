# APPLY app 3.0.89+160: bundle 280

Zip: `locallink_app_3.0.89_2026-11-14.zip`, on top of the **3.0.88+159** commit (bundle 279 app part).
**Order:** backend 279, then 3.0.87, then 3.0.88, then this zip. No backend change in 280.

## What changed
- Adding a friend from or to a phone-only account (made with the server off) now works phone to
  phone at once, not only when the server comes back.
  - F-1: the friend-link code uses my user id = the server id, else the phone-only `offline_...` id
    (a phone-only account has no server id yet). Used when sending a link, sending it again,
    the "got it" answer, checking a link is for me, and the name question.
  - F-2: a dropped link now shows in the log: `CONTACT_EDGE_SKIP reason=no_self_id`,
    `CONTACT_EDGE_NOT_MINE ttl=` (no ids).
- After the account goes on the server, the existing 218 id move sends waiting links again with the
  new id (unchanged).
- Not changed: sealing rules (strangers still send only friend links), pairing, server contacts,
  server accounts (they keep using their server id).
- Search answer "rows=0" (TODO_280 fact 2) is a different cause (the answering phone searches only
  the people it saved, not itself); not changed here.

## Files
`lib/features/directory/data/repositories/directory_repository.dart` (`_myUserId`), version files,
new `test/bundle280_test.dart` (5 tests).
Old tests changed: only the version lines in `bundle223_logs_test.dart`, `nearby_190_test.dart`.

## Checks here
- `flutter test` all 285 files in 12 chunks: 2762 passed, 0 failed (2757 + 5 new); the friend-link
  tests `friend_of_friend_195b/195c` pass unchanged.
- The new test fails on the old `directory_repository.dart` (3 failed) and passes on the new one.
- `flutter analyze`: 175 issues, 0 errors (same as before).
- Release APK `flutter build apk --release --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true`: the first try
  stopped with "No space left on device" here (sandbox disk, not the code); after freeing space the
  retry gave BUILD_EXIT=0, 109.7 MB; aapt2: `com.sajjad.linkup` versionCode 160 / 3.0.89.

## Not verified
- On phones: make a phone-only account with the server off, add a server friend both ways, check
  `CONTACT_EDGE_SENT` / `CONTACT_EDGE_APPLIED` right away (before the server comes back).

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_3.0.89_2026-11-14.zip" .
git add -A
git add -f docs/history/TODO_280.md docs/history/APPLY_app_3.0.89.md
git commit -m "v3 3.0.89 bundle 280: friend links work from and to a phone-only account before the server is back (my id = server id or the offline id for send, resend, ack, for-me check and name question), CONTACT_EDGE_SKIP / CONTACT_EDGE_NOT_MINE logs"
git push
```
Then GitHub > LocalLink > Actions > App CI should be green. Install the new APK over the old app on all phones.
