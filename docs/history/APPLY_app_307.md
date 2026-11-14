# APPLY app 307 - Get chat fixes + new Conversations (bold cards) + live request card (3.0.101+172)

Zip: `locallink_app_307_2026-11-15.zip`. It goes on top of 304 (3.0.100+171, pushed `228ed49`).
Plan: `docs/history/TODO_307.md`. Mock (approved v2): `mocks/conversations_307_v2.html`.
**Push the backend 307 first** (`APPLY_backend_307.md`), then this app.

## What changes
### A. Get chat fixes
- **A9 (main fix): kiran & ayesha's chat comes back with its messages.** The reader only looked at the friend's CURRENT phone
  ids, so messages kept under a friend's old phone ids (one chat per friend, bundle 237) were missed -> "No messages".
  It now includes the person's other / old phones and this phone's past ids. NOT VERIFIED on the real phone DB.
- **A1:** "no copy here" notes are uploaded in the normal admin sync (a relay phone uploads the notes it carried).
- **A2:** server requests that nobody has close as "No messages" (the app reads `empty`).
- **A3 / A5:** the admin phone uploads the final state of its offline request once (done / cancelled / No messages).
- **A6:** finished rows show no "since ..." and no path note.
- **A7:** the request sheet: swap the two people, and a note when you pick yourself.

### B. Conversations screen (bold iOS-style cards, light + dark, LinkUp colours)
- Header: round back + crown, big title, server pill (turns grey within 10 s when the server drops).
- **Live card carousel** at the top: one card per running request (Sent -> 1 of 2 phones -> 12 of 40 parts -> Ready), swipe,
  dots, auto-advance (stops 10 s after a touch). Ready cards get a green edge.
- Chats / Requests switch with counts; search; "In progress" cards (ring + Cancel); "Finished" rows with tags.
- Request sheet and answer viewer redone in the same style (date chips, blue right bubbles, "Deleted by" tag, progress card
  that turns into "Ready to read"). No "Wi-Fi Direct" / path words on these screens.

### C. Phone card (notifications + lock screen)
- **One card per request, grouped** ("3 chat requests · 1 ready").
- **Android 16+:** Live Update (bar with stops at Reached / Answer / Ready, "12/40" chip next to the clock). It needs the
  new normal permission `POST_PROMOTED_NOTIFICATIONS` (no pop-up). If you turn Live Updates off in Settings, it shows as a
  normal card.
- **Android 7-15 (ZTE):** the same words with a plain bar.
- Updates are silent; **Ready buzzes once** (message tone + one short buzz) and has **"Open chat"** (opens the viewer).
- No messages: grey, goes away after 10 s. Cancelled / opened / logged out / not owner any more: the card goes.
- Only on the phone that made the request (owner).
- Two channels: "LinkUp chat requests" (silent) and "Chat ready" (tone + buzz). Note: the plan had one channel; a second one
  is needed so the updates never ring while Ready still can (no VIBRATE permission is added).

### E. Animations
- Cards come in one by one, the switch knob slides, the marker glides, the next stop pulses, numbers count up, Ready pops
  green, No messages fades grey, the carousel slides and the dot stretches, a new request drops in from above, viewer
  messages fade in by 3s, shimmer while loading, the server dot breathes.
- "Remove animations" (Android) shows the end state with no movement.

### F. Words
- All new words in English + Urdu (left-to-right, as in 304).

## Files
35 files:
- Android: `AndroidManifest.xml` (+1 normal permission, 26 -> 27), `MainActivity.kt` + `BackgroundChannels.kt` (3 channel
  methods + the tap), new `ChatRequestNotifier307.kt`, new test `ChatRequest307Test.kt`.
- App shell (wiring only): `lib/app/app_dependencies.dart`, `lib/app/local_link_app.dart` (tap opens the viewer; cards
  cleared on logout), `lib/core/notifications/local_link_notification_platform.dart` (the tap event).
- Admin: `admin_action_book.dart`, `admin_action_server.dart`, `admin_action_service.dart`, `chat_answer_reader.dart`,
  `hidden_store_221.dart` (A9), new `request_step_307.dart`, new `chat_request_notifier_307.dart`,
  `admin_conversations_screen.dart`, `admin_chat_request_sheet.dart`, `admin_chat_viewer_screen.dart`,
  new `conversations_kit307.dart`.
- Words: `app_en.arb`, `app_ur.arb` + the 3 generated `lib/l10n/gen/*.dart`.
- Version: `pubspec.yaml`, `lib/core/config/app_build.dart` (3.0.101+172).
- Tests: new `conversations_307_test.dart`, new `chat_request_notifier_307_test.dart`; changed (allowed): `bundle210f_screen_test.dart`
  (permissions 26 -> 27), `bundle221b_test.dart` (new screen keys), `bundle223_logs_test.dart` + `nearby_190_test.dart` (version),
  `test/support/b220_fakes.dart` (fake server records seen / closed uploads).
- Docs: `docs/history/TODO_307.md`, `docs/history/APPLY_app_307.md` (git add -f).

## Tests (run here, Linux)
- **Full Flutter suite: 315 files, 3084 tests, all passed, 0 `[E]`** (13 chunks, each EXIT 0; run before the version bump,
  then the version tests + the 307 tests again after it: all passed).
- New: `conversations_307_test.dart` 32 passed (A1-A9, RequestStep307, B screens, E animations);
  `chat_request_notifier_307_test.dart` 11 passed (arguments per step, 1 update per second, Ready buzzes once also after a
  restart, max 100 ids, No messages once, not owner -> all cards go, tap -> viewer, channel names, wiring, mine307).
- Kotlin (kotlinc 2.2 + JUnit, Android 36 stubs): **505 tests OK** (6 new in `ChatRequest307Test`).
- `flutter analyze`: no errors; no new warnings (the old ones in calls / golden / 2 old tests stay).
- `flutter gen-l10n`: up to date. Urdu test green (every new word has Urdu).
- **NOT checked here:** the real Android build (no Android SDK / Gradle in the sandbox; CI builds it), how the Live Update
  looks on a real Android 16 phone, the ZTE plain bar, sound / buzz, real phones and the real DB (A9).

## After you install (phone checks)
1. **Online request** (server on): the live card moves Sent -> 1 of 2 -> parts -> Ready. One buzz; "Open chat" opens the viewer.
2. **Offline request** (server off): the same; later it shows on the web with names (A4).
3. **Ask for kiran & ayesha's chat again:** it comes back with their messages, old ones too (A9).
4. **Ask for a chat nobody has:** "No messages", then it goes away; the web closes it too (A1 / A2).
5. **Route it through the ZTE as a relay:** it still closes (A1).
6. **3 requests at once:** grouped "3 chat requests · 1 ready", Ready on top, the carousel has 3 cards.
7. **Android 16 phone:** a "12/40" chip next to the clock. **ZTE (Android 14):** a plain bar with the same words.
8. **Server off while the screen is open:** the pill turns grey within 10 s.
9. **Urdu:** all new words in Urdu, left-to-right, no cut text.
10. **Web, light + dark:** live row, list, viewer; the quiet refresh animates.
11. **Regression:** calls, messages, Add Contact and the admin map work as before.
