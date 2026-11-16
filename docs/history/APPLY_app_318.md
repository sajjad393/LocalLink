# APPLY app 318 - Get new messages only (3.0.109+180)

Base: app 317 (3.0.108+179) = `2707612` (pushed, CI success). Backend 318 goes FIRST (`APPLY_backend_318.md`).
Plan: `docs/history/TODO_318.md` ("As built"). UI = mock `repeat_mock.html` (shown before "Build").

## What changes for the user (Owner phone)
- A Get chat you opened stays on your phone **7 days, locked** (or until Close / Delete completely).
- Get chat again for the same chat: green box **"Already here · Full chat"**, big button **Get new messages only**,
  **Open it**, and **Get all again** under ⋮. A shorter range inside the copy opens at once ("No card, no phone is asked.").
- Get new messages only: their phone sends only what is new (plus messages deleted since and new reactions).
  Nothing new = one tiny answer: **"Up to date · no new messages"**, green, **no buzz**. New ones =
  **"Chat ready · 12 new"** (one buzz).
- Card "Get chat · new only" with footer **"Your copy: full chat · got 15 Nov 10:05 · kept until 22 Nov"**;
  chips "Up to date" / "12 new" + "New only"; the full request shows "Kept · 7 days".
- Viewer: one chat, header "Full chat · got 15 Nov 10:05 · +12 new today 10:43", the **"12 new messages"** bar,
  opened at the bar.
- Photos / videos / voice already here are **never fetched again**.
- **Fix:** opened copies are now really removed after the keep time even if the app restarted (before, a restart
  meant they stayed until Close).
- Web owner: unchanged (always the full chat).

## Files (25 + 4 docs)
- NEW `lib/features/admin/data/actions/kept_copy_318.dart`, NEW `lib/core/services/kept_sql_318.dart`
- `chat_answer_builder.dart`, `chat_answer_reader.dart`, `file_queue_317.dart`, `request_step_307.dart`,
  `chat_request_notifier_307.dart`, `lib/app/app_dependencies.dart`
- `admin_chat_request_sheet.dart`, `admin_conversations_screen.dart`, `admin_chat_viewer_screen.dart`,
  `widgets/conversations_kit307.dart`, `lib/core/widgets/unread_bar_304.dart`
- Kotlin `ChatRequestNotifier307.kt` (up_to_date card), test `ChatRequest307Test.kt` (+1)
- Words: `app_en.arb`, `app_ur.arb` (27 keys) + `lib/l10n/gen/*` (3)
- Version: `pubspec.yaml`, `lib/core/config/app_build.dart`, `test/bundle223_logs_test.dart`, `test/nearby_190_test.dart`
- NEW test `test/bundle318_test.dart` (25). No other old test changed.
- `docs/history/TODO_318.md`, `APPLY_app_318.md`, `APPLY_backend_318.md` (+ backend copy)

## Tests (Linux sandbox)
| Check | Result |
|---|---|
| New Dart tests | bundle318 25 pass |
| Full app suite, 331 files | 3286 pass (3261 old + 25 new), 0 fail |
| Version tests after bump | bundle223_logs + nearby_190 +19 |
| Kotlin | 520 OK (519 old + 1) |
| Analyze | 361 issues = same count as base `2707612` (361), 0 errors |
| Go | `go test ./...` ok, vet ok, gofmt clean |

## Known limitations
- File cap 300 MB of kept files (assumed, not answered). Oldest kept file goes first.
- The SQLCipher store (`kept_sql_318.dart`) has no unit test (no SQLite in the test runner, no new deps); its
  logic is tested through the memory store. NOT VERIFIED on phones.
- Answering phone on an old LinkUp sends everything (still merged, no duplicates shown).
- Kept copies use storage on the Owner phone.
- Mocks / tests only: no real phones.

## Phone checks
1. Get chat kiran (Full) → open it. Get chat again same chat: green "Already here", Get new messages only.
2. Tap it with no new messages: card "Up to date", green, no sound.
3. Send 2 messages kiran↔ayesha, Get new messages only: "Chat ready · 2 new", one buzz; viewer bar "2 new messages".
4. Pick Last 7 days while a Full copy is here: "Open it" opens at once, no card.
5. A photo already seen: not fetched again (no "Coming" row, shows at once).
6. Restart the Owner phone after 7 days: the copy is gone (logcat `KEPT318_SWEEP`).
