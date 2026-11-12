# APPLY app 3.0.86+157: bundle 277

Zip: `locallink_app_3.0.86_2026-11-14.zip`, on top of the **3.0.85+156** commit (bundles 272-276).
**Apply 3.0.85 first** (`APPLY_app_3.0.85.md`: backend 272-276, then the 3.0.85 app zip + commit),
then this zip. No backend change in 277.

## What changed
- **277-A group voice / photo delivery** (the 12 Nov 15:50 voice note waited with the server ON):
  - A-1: a group message that the server did not take goes to Nearby by itself, once per message
    (upload failed, no answer in 45 s, or the server went away while it waited). It still waits for
    the server too; members drop the 2nd copy by id. Not for server-only groups, left groups, or a
    message a member already got Nearby.
  - A-2: a voice note / photo in a Nearby group also goes Nearby at once to members who are near
    now (the server copy still goes).
  - A-3: no more silent upload failure: log line `GROUP_FILE_UPLOAD_FAILED reason=<timeout|socket|
    http_NNN|...> ms=<time>`; one upload holds the group send loop 45 s at most.
    New log lines: `GROUP_HANDOFF_277 why=<upload_fail|server_down> n=`, `GROUP_NEAR_FIRST_277`.
- **277-B group chat order:** by the time written, then server number, then id (was server number
  first, so a Nearby/waiting message with number 0 jumped to the top). New messages in an open chat
  go in their time place.
- **277-C video:** the camera button is hidden for caller and callee. The "Switch to video call?"
  question is never shown; an old phone's camera request is declined quietly. No other video work.

## Files
`lib/core/models/group.dart` (`compareGroupOrder277`), `lib/core/services/local_store.dart`
(`groupMessages` sort), `lib/features/groups/bloc/group_chat_bloc.dart` (`_upsert`),
`lib/features/groups/data/services/group_messaging_service.dart` (hand-off, 45 s, log),
`lib/features/groups/data/services/group_nearby_service.dart` (`fanOut(..., only:)`),
`lib/features/calls/presentation/widgets/call_action_bar.dart`, `.../screens/call_screen.dart`,
version files, `test/bundle277_test.dart` (13 new tests).

## Old tests changed (listed in TODO_277)
- `bundle248_test.dart:32` isTrue -> isFalse; `:43-48` the button is not found in any state.
- Version lines: `bundle223_logs_test.dart`, `nearby_190_test.dart`.

## Checks here
- `flutter test` all 282 files in 12 chunks: 2750 passed, 0 failed (2737 + 13 new).
- `flutter analyze`: 175 issues, 0 errors (was 176).
- Release APK: `flutter build apk --release --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true` -> BUILD_EXIT=0,
  109.7 MB; aapt2: `com.sajjad.linkup` versionCode 157 / 3.0.86, REQUEST_INSTALL_PACKAGES,
  provider `com.sajjad.linkup.update275`.

## Not verified
- On phones: needs the group voice test (server on, then off) on C71 / Note / TECNO.
- Server-side reason for the 15:50 upload stall: still NOT VERIFIED (server lines for
  `POST /api/v1/files` at 15:50 would show it).

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_3.0.86_2026-11-14.zip" .
git add -A
git add -f docs/history/TODO_277.md docs/history/APPLY_app_3.0.86.md
git commit -m "v3 3.0.86 bundle 277: group voice/photo goes Nearby once when the server does not take it (upload fail, 45 s no answer, server gone), files go Nearby first to near members, GROUP_FILE_UPLOAD_FAILED log, group chat ordered by time, video call button hidden and no switch-to-video question"
git push
```
Then GitHub > LocalLink > Actions > App CI should be green. Install the new APK over the old app.
