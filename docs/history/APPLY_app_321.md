# APPLY app 321 - login true reasons, fast screens, files "Ready" rule, new messages screen, notification B (3.0.112+183)

Base: app 320 (3.0.111+182) = `56cffbc`. **Backend 321 too** (web owner page R9) - push the backend FIRST.
Plan: `docs/history/PLAN_321.md`, details: `docs/history/TODO_321.md`.

## What changes for the user
- **Login (Phase 1):** every failure shows plain words + a code under the button (L-01 ... L-13, table in PLAN_321). A step line: "Looking for the server..." -> "Server found · address · checking..." -> "Signing in...". A server that answered 500 never says "could not connect"; a timeout never says "retrying". Saved address and the Wi-Fi search run at the same time; one more search round before giving up. The address is saved only after it passes the check (L6). "Reset setup" keeps the last server address (as a search candidate only, key pin still cleared) and the last hour of logs. Signed in from the saved account -> one note on Home (L-13).
- **Log share before sign-in (L4):** 5 fast taps on the app bar title "Log in" / "Create account". No visible link.
- **Forgot password / Confirm account (Phase 2):** a real server check (saved / last address + search), "Checking server..." while it runs, Ask the admin searches then sends, offline reset only after a fresh search found nothing, one note only.
- **Speed (Phase 3 + 5):** saved parts list no longer reads message bodies; one counted read for all requests; never-opened copies are removed after 7 days (kept copies untouched); sync list copied before the loop. Chats, Conversations and the viewer show saved data at once; the server fills in behind (8 s max).
- **Server link (Phase 4):** websocket ping every 20 s; one server status for every screen ("off" only after 15 s without an answer). L19b: on the server Wi-Fi with no server for 2 min, the phone leaves its own Wi-Fi Direct group once and makes no own group for 15 min. **D4 = L19b only - L19a (no new group at all while the server answers) was NOT done.**
- **Files + "Ready" rule (Phase 6):** a file with no new part for 10 min is asked once more, then marked gone. Kept voice notes play. Conversations words: blue "Messages here · 3 of 7 files coming", green "Ready to read" only when all files are here (or none), grey "N files not available".
- **Messages screen redesign (R4, mock `messages_redesign_321.html`):** header icon line, green "Kept here until ...", files card with one piece per file + Stop pill, "Coming" card, photo / video tiles (ring % + "Coming by itself" / "Next in line" / removed), voice button with mic ring.
- **Notification B (N1-N4, mock `notification_short_321.html`):** title only ("ayesha & kiran · 3/7" / "sumaira · waiting" / "Pricesess ✓"), no text line, no buttons, thumbnail of the coming file, one bar piece per file + green points. Android 16+ = ProgressStyle; Android 15 and older = the same look with a custom card. Group = "N chats". Only Ready buzzes.
- **F6:** Home "My links" shows my own letter (not "Y").
- Not changed: sealing, calls, video, grey bubbles, 318 kept copy, 320 Conversations rows / buttons.

## Files (63 + docs)
- `android/app/src/main/kotlin/com/sajjad/locallink/ChatCard321.kt`
- `android/app/src/main/kotlin/com/sajjad/locallink/ChatRequestNotifier307.kt`
- `android/app/src/main/res/drawable/ic_req321_doc.xml`
- `android/app/src/main/res/drawable/ic_req321_mic.xml`
- `android/app/src/main/res/drawable/ic_req321_video.xml`
- `android/app/src/main/res/drawable/ic_req321_wait.xml`
- `android/app/src/main/res/layout/notif321_card.xml`
- `android/app/src/test/kotlin/com/sajjad/locallink/ChatRequest307Test.kt`
- `android/app/src/test/kotlin/com/sajjad/locallink/ChatRequest314Test.kt`
- `android/app/src/test/kotlin/com/sajjad/locallink/ChatRequest317Test.kt`
- `android/app/src/test/kotlin/com/sajjad/locallink/ChatRequest321Test.kt`
- `lib/app/app_dependencies.dart`
- `lib/app/local_link_app.dart`
- `lib/core/config/app_build.dart`
- `lib/core/crypto/password_kdf.dart`
- `lib/core/diagnostics/app_log_file.dart`
- `lib/core/services/hidden_store_221.dart`
- `lib/core/services/local_store.dart`
- `lib/core/services/locallink_api.dart`
- `lib/core/services/websocket_service.dart`
- `lib/core/state/server_status_321.dart`
- `lib/features/admin/data/actions/admin_action_service.dart`
- `lib/features/admin/data/actions/chat_answer_carrier.dart`
- `lib/features/admin/data/actions/chat_answer_reader.dart`
- `lib/features/admin/data/actions/chat_request_notifier_307.dart`
- `lib/features/admin/data/actions/file_queue_317.dart`
- `lib/features/admin/presentation/screens/admin_chat_viewer_screen.dart`
- `lib/features/admin/presentation/screens/admin_conversations_screen.dart`
- `lib/features/admin/presentation/widgets/viewer_bubbles310.dart`
- `lib/features/admin/presentation/widgets/viewer_kit321.dart`
- `lib/features/authentication/bloc/authentication_bloc.dart`
- `lib/features/authentication/data/repositories/authentication_repository.dart`
- `lib/features/authentication/domain/login_problem_321.dart`
- `lib/features/authentication/presentation/screens/setup_screen.dart`
- `lib/features/connectivity/data/services/server_group_repair_321.dart`
- `lib/features/connectivity/data/services/wifi_direct_fallback_service.dart`
- `lib/features/home/bloc/home_bloc.dart`
- `lib/features/home/presentation/screens/home_screen.dart`
- `lib/features/recovery/bloc/account_recovery_bloc.dart`
- `lib/features/recovery/data/repositories/recovery_repository.dart`
- `lib/features/recovery/presentation/screens/account_recovery_screen.dart`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_ur.arb`
- `lib/l10n/gen/app_localizations.dart`
- `lib/l10n/gen/app_localizations_en.dart`
- `lib/l10n/gen/app_localizations_ur.dart`
- `pubspec.yaml`
- `test/bundle223_logs_test.dart`
- `test/bundle317_test.dart`
- `test/bundle318_test.dart`
- `test/bundle320_test.dart`
- `test/bundle321_db_test.dart`
- `test/bundle321_files_test.dart`
- `test/bundle321_link_test.dart`
- `test/bundle321_login_test.dart`
- `test/bundle321_notify_test.dart`
- `test/bundle321_recovery_test.dart`
- `test/bundle321_redesign_test.dart`
- `test/bundle321_saved_test.dart`
- `test/chat_request_notifier_307_test.dart`
- `test/conversations_310_test.dart`
- `test/forgot_password_222_test.dart`
- `test/nearby_190_test.dart`
- `docs/history/PLAN_321.md`, `docs/history/TODO_321.md`, `docs/history/APPLY_app_321.md` (git add -f)

## Old tests changed (listed)
- Version: `bundle223_logs_test`, `nearby_190_test`.
- R4: `conversations_310_test` (voice label "Coming · 1 / 3"), `bundle320_test` B6, `bundle318_test` (kept line "Kept here until").
- N (Dart): `bundle317_test` G7 x3 (titles), `bundle318_test` K7 (`cardTitle321`), `chat_request_notifier_307_test` (one-line titles, "2 chats", "kiran & ayesha · No messages").
- N (Kotlin): `ChatRequest307Test` (Ready / Up to date: no Open button), `ChatRequest314Test` (Android ≤15 sliding line -> piece bar + ChatCard321), `ChatRequest317Test` (no Open / Stop buttons, no addAction).
- L10: `forgot_password_222_test` ("needs the server" refusal now searches first).
- New: `test/bundle321_login/recovery/db/link/saved/files/redesign/notify_test.dart` (79; F6 = group "321 F6" in `bundle321_redesign_test`), Kotlin `ChatRequest321Test.kt`.

## Tests (Linux sandbox)
| Check | Result |
|---|---|
| New Dart tests | 8 files, 79 pass |
| Full app suite, 341 files (chunks of 15) | 3399 pass + 2 fail: `bundle210a_server_test` (known flaky; alone 12/12 pass) and `server_proof_231_test` (a lock: the key check must sit near the top of `serverOnline222`; code reordered, the check itself unchanged; then 39/39 pass with bundle321_recovery + forgot_password_222) |
| Regression in every phase | login/auth locks, recovery 222/231, 316-320 + conv 307-314, viewer 12 files, nearby/WD 20 files, home 5 files |
| Kotlin | 529 OK (520 + 9 new) |
| Analyze | 365 issues = base 361 + 4 infos in new tests; 0 errors, 0 warnings |
| Urdu | 36 new words, all 2464 keys present in `app_ur.arb` |

## Status: READY WITH KNOWN LIMITATIONS
- NOT VERIFIED on phones (all of 3.0.108-3.0.112).
- D4: only L19b; L19a not done.
- Android 15 and older: same picture, but the system draws the frame around the card (app name line), as on every custom notification.
- TECNO POP 8 crash (~15 min) not part of 321.

## Phone checks
1. Server OFF -> Log in: words + code (L-01 / L-02x), step line; no "turn the server on" when the password is right.
2. Wrong password with the server ON -> "Wrong username or password" L-03; it never opens offline.
3. 5 fast taps on "Log in" -> logs share sheet.
4. Forgot password with no saved address and the server ON -> online (no "Offline").
5. Owner: Chats + Conversations open at once (no long shimmer); Conversations shows "Messages here · x of y files coming" until all files are here, then "Ready to read".
6. Open a chat with files coming: files card + pieces, photo tile ring %, "Next in line", voice mic ring; kept copy shows "Kept here until ...".
7. Notification on Android 16 (C71) AND Android 14/15 (ZTE, TECNO): the same title-only card with the piece bar; only Ready buzzes.
8. ayesha Home "My links": own letter.
9. Regression: calls, kept copy (318), 320 rows / buttons, Urdu + dark + big text.
