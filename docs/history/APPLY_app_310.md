# APPLY app 310 - voice in answers, no more stuck "Sent", viewer like Messages (3.0.103+174)

Base: app 308 (3.0.102+173) = `52769c6` (pushed, CI OK). Push backend 310 first.
Scope: TODO 310 V1, V4, P1, P2 (app side). V2, V3, P3, P4, E1 are web (backend zip).

## What changes for the user
- **V1:** a chat answer carries each voice note's length + bars (40 digits), so the web and the admin phone draw the same
  bars as the chat. Only for voice notes this phone has already shown (the bars are saved); others: flat bars + size.
- **V4:** the admin answer viewer on the phone looks like Messages: grey bubbles (light + dark), time inside at the bottom,
  names only in groups on the first bubble of a run, day pill. Voice notes are a voice row: Get -> ring with parts -> Play /
  Pause right in the viewer. Long file names are shortened. The played copy is deleted when you leave.
- **P1:** "No copy here" is told to the server at once (not at the next 10-minute sync). A sync asked while one is running
  now runs right after it (before, it was lost).
- **P2:** when the phone's server connection comes back it checks for requests at once (at most once per 30 s).

## Files (12)
- `lib/features/admin/data/actions/chat_answer_builder.dart` - `voice: {ms, bars}`
- `lib/app/app_dependencies.dart` - voice bars from VoiceWaveBook; socket state to the action service
- `lib/features/admin/data/actions/admin_action_service.dart` - P1 + P2
- `lib/features/admin/presentation/screens/admin_chat_viewer_screen.dart` - V4 bubbles + voice row
- `lib/features/admin/presentation/widgets/viewer_bubbles310.dart` (NEW)
- `lib/core/config/app_build.dart`, `pubspec.yaml` - 3.0.103+174
- `test/conversations_310_test.dart` (NEW, 18 tests)
- `test/bundle223_logs_test.dart`, `test/nearby_190_test.dart` - version
- `docs/history/TODO_310.md`, `docs/history/APPLY_app_310.md`

## Tests
| Check | Command | Result |
|---|---|---|
| New tests | `flutter test --no-pub test/conversations_310_test.dart` | 18 pass, EXIT 0 |
| Fix proof | P1 lines taken out -> run again | both P1 tests fail; back in -> pass |
| Full app suite | 317 files in 11 chunks | 3121 pass, 0 fail, all EXIT 0, `[E]`=0 |
| Analyze | `flutter analyze --no-pub` | 361 issues, all old; 0 in the 310 files |
| Backend | `go vet ./...`, `go test ./...` | OK, all packages ok, EXIT 0 |

## Not checked
- Real phones: voice bars in a real answer, playback on the admin phone, kiran/ayesha after update. NOT VERIFIED.
- Real Android build: CI builds it.

## Phone checks
1. Update kiran + ayesha to 3.0.103. Make a Get chat for them: within about 1 minute the web card shows each phone's reason or the answer.
2. On a phone, play a voice note in a chat once, then Get chat that chat: web + admin viewer show real bars and 0:07.
3. Admin phone viewer: tap the voice button -> ring -> Play -> Pause; leave and come back: still Ready.
4. Turn the server off and on: the phone asks for requests right away (log `ADMIN_ACT` sync), not after 10 minutes.
5. Regression: Get full photo, Delete completely, copy text, Ready banner, calls and chats unchanged.
