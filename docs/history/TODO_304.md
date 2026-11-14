# TODO 304 (3.0.100+171) - thicker voice lines + "unread messages" bar + Urdu (ur-PK)

Status: BUILT 15 Nov (zip locallink_app_304_2026-11-15.zip, 3041 tests pass). App only, no backend change. Base = 303 pushed `29e4de5`.

## H1. Voice note lines a little thicker (user pick: 2.5 px)
- `lib/features/messaging/presentation/voice/voice_recording_widgets.dart` `_WavePainter`:
  `barWidth` 2 -> 2.5, `step` 3 -> 3.5 (gap stays 1 px). Corner radius 1 -> 1.25.
- About 48 lines in a bubble (was ~56). Same in the message box (holding / locked / paused) - one painter.
- Heights, colours, the dot, the "turns blue after its middle" rule: unchanged.
- Test: `test/voice_wave_303_test.dart` source lock (`barWidth = 2;` / `step = 3;`) updated to the new numbers +
  the "2 px lines, 1 px gaps" widget test reads the new width (listed test change).

## H2. "N unread messages" bar in the chat (like WhatsApp; new)
Today: opening a chat marks everything read at once (`chat_screen.dart` `_load` ->
`markDirectConversationRead`; groups `group_chat_screen.dart` `_load` -> `markGroupConversationRead` + `_markRead`).
Nothing shows where the new messages start.

- **When:** you open a chat (1:1 or group) that has unread messages from the other side.
  - Before marking them read, take the first unread message id + the count
    (`store.unreadMessagesForConversation(id)` / `store.unreadGroupMessages(gid)` - already used for the badges).
- **What:** a full-width soft band right above the first unread message with a small pill:
  "1 unread message" / "5 unread messages" (primary colour text; light + dark).
  It sits under the date line if that message starts a new day.
- **Scroll:** the chat opens at the bar (bar near the top) when the unread part is longer than the screen;
  otherwise at the bottom as today. A jump from search / notification / reply still wins.
- **Stays** while the chat is open. **Goes away:** when you send a message, or leave the chat
  (next open: no bar, all read). Messages that come while the chat is open do not add a bar (they are read at once).
- Read ticks / read receipts / badge counts: unchanged (still marked read on open).
- Not in: the Chats list, calls, system lines; my own messages are never "unread".
- Files: `chat_screen.dart`, `group_chat_screen.dart`, new small widget `unread_bar_304.dart`.
- Tests (new `test/unread_bar_304_test.dart`): bar above the first unread + right count (1 / many) in 1:1 and
  group; no bar when nothing unread; gone after send; gone on reopen; jump target wins; light + dark.

## H3. Urdu (Pakistan) - the app becomes multilingual
User picks: Flutter standard system, Noto Naskh font, whole app + notifications, Settings > Language with Phone language.
Today (29e4de5): no language system at all. ~2,000 English texts written straight in 508 Dart files (542 `Text('...')`,
79 toasts), 18 notification texts in Kotlin, no `.arb` files, no `flutter_localizations`, Roboto only.

**H3.1 Base**
- `pubspec.yaml`: `flutter_localizations` (Flutter SDK) + `intl` (the version Flutter pins) + `flutter: generate: true`.
  These 2 packages are the only new deps (user OK'd: "Flutter's standard system").
- `l10n.yaml`: arb-dir `lib/l10n`, template `app_en.arb`, output in `lib/l10n/gen/` (committed).
- `lib/l10n/app_en.arb` (all English texts, same words as today) + `lib/l10n/app_ur.arb` (Urdu).
  Language tag `ur` with region PK in the picker (`ur_PK` falls back to `ur`; Flutter has Material/Cupertino `ur`).
- `context.l10n` helper: if a screen is shown without the language setup (old tests), English is used, so the
  3018 tests keep working in English.
- `MaterialApp`: `localizationsDelegates` (app + GlobalMaterial/Widgets/Cupertino), `supportedLocales` en + ur,
  `locale` from the language setting. Copy / paste menu, date picker, back tooltip also in Urdu.

**H3.2 Language choice**
- Settings > **Language**: "Phone language" (default) / "English" / "اردو". Each name in its own script.
- Phone language = Urdu phone -> Urdu app; any other language -> English.
- Changes at once (no restart), saved in the app settings (`app_language_304`), kept after restart and update.
- Login / sign-up screens follow the same setting (the phone language before anyone logs in).

**H3.3 Font**
- Noto Naskh Arabic (Google Fonts, OFL licence, Urdu letters ٹ ڈ ڑ ں ے ھ included). The variable font is cut into
  static Regular / Medium / SemiBold / Bold files at build time (fonttools, NOT an app package). About +0.3 MB APK.
- Urdu UI: Naskh first, Roboto for Latin letters/digits. A bit more line height for Urdu so letters are not cut.
- Urdu typed in messages also uses Naskh in the English UI.

**H3.4 Layout stays left-to-right (user, 15 Nov: "just need urdu don't change right to left")**
- NO mirroring anywhere: same layout as English (back arrow, rows, icons, padding, bubbles, composer, call buttons).
  `MaterialApp.builder` forces `Directionality(ltr)` even when Urdu is on (Flutter would flip it for `ur`).
- Every Urdu text keeps its own right-to-left READING order inside the left-to-right screen (Unicode isolate
  RLI...PDI added by the language layer), still left-aligned. Without this, "اس فون پر LinkUp کی زبان چنیں" and
  "کہاں ہو؟" come out scrambled (seen in the pictures).
- Inside Urdu text, numbers / sizes / @username / times / codes are wrapped left-to-right ("0 B" not "B 0",
  "@sajjad" not "sajjad@").
- Chat messages and the Chats last-message line: Urdu typed by people gets the same right-to-left reading order
  (detected from the first letter), bubbles and alignment unchanged.

**H3.4b User picks (15 Nov)**
- Chat bubbles keep their sides (then superseded: the whole layout stays left-to-right, see H3.4).
- Times stay "5:40 PM" with digits 0-9.
- Urdu pictures first (Settings > Language, Chats, a chat, call screen; light + dark), then Build.

**H3.4c Found while making the Urdu pictures (real screens, scratch only)**
- 12+ separate "h:mm AM/PM" makers (chat, bubbles, calls, groups, storage, chat preview, ...): one shared time
  helper (keeps "11:56 PM" readable inside Urdu text).
- "@username", sizes ("0 B"), and similar must be wrapped left-to-right inside Urdu text.
- App bar titles and button styles set their own font: the Urdu font must be added to EVERY style in
  `app_theme.dart` (otherwise boxes instead of letters).
- Font size: 4 weights = ~800 KB raw; plan Regular + Bold only (~400 KB raw, less in the APK); Medium/SemiBold
  text uses the nearest one.
- Pictures: `mock_304_urdu.jpg` v2 (left-to-right layout; Language, Settings with the new Language row, Chats,
  chat, call screen; light + dark). Scripts in `~/m304src/` (ur_scratch.py + build_tests.py).

**H3.5 Translate everything (in groups)**
- Start / login / sign-up / recovery / forgot password; Chats + home; chat, composer, bubbles, message options,
  voice; groups; Calls list, call screen, call card; People / Add Contact / Nearby / QR; profile, settings, storage,
  privacy, blocked; update sheets + silent update; all toasts + dialogs; admin / owner / auditor screens.
- Kotlin notifications: the app tells Android the chosen language (`language304` on `locallink/device`);
  `Words304.kt` keeps it and gives the Urdu words (one English→Urdu map, `%s` for a name or count).
  Not `values-ur/strings.xml`: that follows the PHONE language, not the in-app choice.
  Incoming call, messages, friend requests, "LinkUp is running".
- Not translated: LinkUp, user names, @usernames, server error text that comes from the backend as English
  (shown as is; known ones are mapped to Urdu), the PC web dashboard.
- Words: modern spoken Pakistani Urdu, short, English words where people use them (کال، میسج، پروفائل،
  سیٹنگز، اپ ڈیٹ، سرور، پاس ورڈ، کوڈ، وائی فائی).

**H3.6 Tests + review**
- New `test/urdu_304_test.dart`: every English key has an Urdu text with the same {placeholders}; switching
  English <-> Urdu updates open screens; choice saved after restart; Urdu = layout still LTR + Naskh + right-to-left reading order per Urdu text; numbers/@names inside stay LTR;
  message direction per text; key screens pumped in Urdu at 360 px and 320 px wide (light + dark) with no overflow.
- Listed test changes: ~24 old tests that read English words in source files (~42 locks) will read them from
  `app_en.arb` (the words stay the same).
- Real-app pictures of every main screen in Urdu (light + dark) are compared by eye for cut text and wording.
- `URDU_REVIEW_304.md`: every English text next to its Urdu, with the unsure ones marked for a native Pakistani
  Urdu speaker (security words like "link key", "sealed", "mesh", roles Owner / Operator / Security / Auditor, etc.).

## Version
- 3.0.100+171 (`pubspec.yaml`, `app_build.dart`, version lines in `bundle223_logs_test.dart`, `nearby_190_test.dart`).

## Not verified / notes
- 303 CI run `43596729675` was in progress when this was written.
- 303 commit also carried `GeneratedPluginRegistrant.java` (+integration_test lines, regenerated by your PC's
  `flutter pub get`). Harmless: Flutter rewrites this file on every build.

**User answers (ask_user, after LTR pictures):** BUILD = yes (all 3 parts, one zip, one commit, 3.0.100+171).
H2: open at the unread bar (if the unread part fits on one screen, open at the bottom); bar goes away when I send a
message or leave the chat; 1:1 AND group chats.

