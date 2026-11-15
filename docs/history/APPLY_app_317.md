# APPLY app 315 + 316 + 317 - files come by themselves, Ready only when here, crash fix (3.0.108+179)

Base: app 314 (3.0.107+178) = `5bad575` (pushed, CI 43792729654 success). Backend 317 goes FIRST
(`APPLY_backend_317.md`). Plans: `docs/history/TODO_315.md`, `TODO_316.md`, `TODO_317.md` ("As built").

## What changes for the user
- **315:** the "Server PC clock" banner is gone everywhere; the clock check still runs hidden.
- **316 (ayesha crash loop):** the phone no longer loads every stored part at once (light reads, one part body
  at a time when sending); a repeated own part gets the signed ack; parts carried for others: max **8 MB**.
- **317 A:** "Ready" only when every part is here; before that "kiran's phone answered · on the way" at 0 %.
  No buzz before Ready.
- **317 B:** group events ("kiran created group Friends") show as a centred grey line, never code.
- **317 C:** deleted messages: faded bubble + small red "Deleted 11:41".
- **317 D/G:** no Get button. After the chat is here every photo / video / voice / file comes by itself, 2 files
  (16 MB) at a time; middle phones carry up to 6 MB of file parts (text first), parts expire after 3 days.
  Rows: Next in line / Coming x / y / shows (tap opens) / Not on kiran's phone any more / Too big to bring
  (over 50 MB). Video icon + size; the same file once.
- **Notification + admin card:** after "Chat ready" the card goes on: "Chat ready · files coming", "3/13",
  trips bar, "from kiran's phone · via ayesha", waiting (orange), "all files here" (green, silent);
  buttons Open chat + Stop files. Request row chip "Files 3/13".
- **317 E:** My links map hint fades after 4 s; nodes stay out of the buttons column.
- **317 F:** start freeze: seen packets load on a background thread.

## Files (34 + 4 docs)
- 316: `lib/core/services/hidden_store_221.dart`, `chat_answer_carrier.dart`, `chat_answer_builder.dart`,
  `chat_answer_reader.dart`
- 315: `lib/features/admin/presentation/widgets/admin_kit216.dart`, `admin_conversations_screen.dart`
- 317: NEW `lib/features/admin/data/actions/file_queue_317.dart`, `admin_action_book.dart`,
  `admin_action_doers.dart`, `admin_action_service.dart`, `request_step_307.dart`,
  `chat_request_notifier_307.dart`, `lib/app/app_dependencies.dart`, `admin_chat_viewer_screen.dart`,
  `conversations_kit307.dart`, `link_paths_full_screen.dart`; Kotlin `ChatRequestNotifier307.kt`,
  `LocalLinkTransportService.kt`, NEW `res/drawable/ic_req317_file.xml`
- Words: `app_en.arb`, `app_ur.arb` (39 keys) + `lib/l10n/gen/*` (3)
- Version: `pubspec.yaml`, `lib/core/config/app_build.dart`, `test/bundle223_logs_test.dart`, `test/nearby_190_test.dart`
- Old tests changed (listed, no Get button / "Deleted 14:02" / carriers take file parts):
  `test/bundle221a_test.dart`, `test/bundle221b_test.dart`, `test/conversations_310_test.dart`
- NEW tests: `test/bundle317_test.dart` (31), `test/carrier_316_test.dart` (6),
  `android/app/src/test/kotlin/com/sajjad/locallink/ChatRequest317Test.kt` (8)
- `docs/history/TODO_315.md`, `TODO_316.md`, `TODO_317.md`, `APPLY_app_317.md`

## Tests (Linux sandbox)
| Check | Result |
|---|---|
| New Dart tests | bundle317 31 + carrier_316 6 pass |
| Full app suite, 330 files | 3261 pass (3224 old + 37 new), 0 fail. 7 listed old tests failed first, changed, then pass |
| Viewer tests after the last viewer fix | 221b + 317 + conversations_310 +56; 255_ui + conversations_307 +43 |
| Version tests after bump | bundle223_logs + nearby_190 +19 |
| Kotlin | 519 OK (511 old + 8) |
| Analyze | 314 issues, same list as 314 base, 0 errors, 0 new |

## Known limitations
- Mocks only: no real phones. Trips via middle phones, 8 MB cap, Android 16 trip segments, swipe-away: NOT VERIFIED.
- A trip loads at about 1.9 MB per minute of contact; the queue moves only while the Owner's LinkUp runs.
- Middle phones use more battery and storage (max 6 MB of files each).

## Phone checks
1. Get chat kiran: card stays "on the way" until the chat is really here, then one buzz "Chat ready".
2. Then files come by themselves: notification "files coming 3/13", viewer rows Next in line / Coming / shows.
3. A deleted file says "Not on kiran's phone any more"; a 60 MB video "Too big to bring (over 50 MB)".
4. ayesha (RMX3938): no crash loop while carrying; logcat `LocalLinkBoot SEEN_MESH_LOADED`, no `MAIN_STALL` at start.
5. No server clock banner anywhere.
