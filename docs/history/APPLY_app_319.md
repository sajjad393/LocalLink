# APPLY app 319 - Owner phone stuck loading (3.0.110+181)

Base: app 318 (3.0.109+180) = `e6473ed` (pushed, CI success). **App only** - backend stays `8110af0`.
Plan + proof: `docs/history/TODO_319.md` ("As built").

## What changes for the user
- Owner phone: Conversations, the chat viewer and the Block list no longer stay loading for minutes while
  answer parts come in (16 Nov 19:01 log: the phone database was locked 26,100 times, a read took 192 s).
- A chat you closed no longer flows in again from ayesha's phone; her phone gets the stop and drops it.
- Phones near you stop re-sending the same parts every minute (max once per 3 min per phone).
- Old "got it" records (acks / stops) older than 7 days are cleaned up (start + every 6 h).
- Nothing new on screen. No sound / design change.

## Files (6 + 1 test + docs)
- `lib/features/admin/data/actions/chat_answer_carrier.dart` (F1, F4, F5, F6, F8, `MergedRun319`)
- `lib/core/services/hidden_store_221.dart` (F2 memory acks/stops, F3 `forgetOld`)
- `lib/features/admin/presentation/screens/admin_chat_viewer_screen.dart`, `admin_conversations_screen.dart` (F7)
- `lib/app/app_dependencies.dart` (1 line: F3 in the sweep)
- Version: `pubspec.yaml`, `lib/core/config/app_build.dart`, `test/bundle223_logs_test.dart`, `test/nearby_190_test.dart`
- NEW test `test/bundle319_test.dart` (13). No other old test changed.
- `docs/history/TODO_319.md`, `docs/history/APPLY_app_319.md`

## Tests (Linux sandbox)
| Check | Result |
|---|---|
| New Dart tests | bundle319 13 pass (8 runs in a row, 0 fail) |
| Carrier / viewer / Conversations regression (221a/b, 316, 317, 318, conv 307/310/313/314) | 176 pass |
| Full app suite, 332 files | 3298 pass + 1 fail = `bundle210a_server_test` (known flaky; alone 12/12 pass). 3299 = 3286 old + 13 new |
| Version tests after bump | bundle223_logs + nearby_190 +19 |
| Kotlin | 520 OK (unchanged) |
| Analyze | 361 issues = base `e6473ed` (361), 0 errors |

## Known limitations
- NOT VERIFIED on phones. The SQL store is tested with a fake database (no SQLite in the test runner).
- The TECNO POP 8 crash after ~15 min fits the same jam, but there is no TECNO log: NOT VERIFIED.
- Phones still on 3.0.109 or older keep re-sending until they update (the Owner now refuses + answers the stop).
- Parts already held stay until their own clean-up; the first start after the update cleans old acks once.

## Phone checks
1. Owner (C71) + ayesha: Get chat kiran, let it come, then wait 20 min with Conversations open: no endless shimmer.
2. Close a Get chat while parts are still coming: logcat `ADMIN_ANSWER_STOP_BACK`, ayesha stops (`ADMIN_ANSWER_STOP`).
3. ayesha log: `ADMIN_ANSWER_PARTS_SENT parts=.. answer=.. to=..` - the same answer not again within 3 min.
4. Owner log: no `database has been locked`, no `STORE_OP_SLOW` minutes long, no `ADMIN_PROGRESS_SLOW`.
5. TECNO POP 8 (kiran): keep the app open 30 min; send the log if it still closes.
6. Regression: chat requests, kept copy (318), files trips (317), calls.
