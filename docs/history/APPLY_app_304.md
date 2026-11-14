# APPLY app 304 - thicker voice lines + "N unread messages" bar + Urdu (ur-PK) (3.0.100+171)

Zip: `locallink_app_304_2026-11-15.zip`. It goes on top of 303 (3.0.99+170, pushed `29e4de5`).
Plan: `docs/history/TODO_304.md`. Urdu review list: `docs/history/URDU_REVIEW_304.md`. App only, no backend change.

## What changes
- **H1. Voice note lines are a little thicker:** 2.5 px lines with 1 px gaps (was 2 px), so a bubble has about 48 lines.
  The bubble and the recorder in the message box share one painter, so both change.
  Heights, colours, the dot and the blue-after-the-middle rule are unchanged.
- **H2. "N unread messages" bar (like WhatsApp), in 1:1 and group chats:**
  - When you open a chat with unread messages, a full-width soft band with a pill sits right above the first unread
    message: "1 unread message" / "5 unread messages".
  - The chat opens at the bar when the unread part is longer than the screen. Otherwise it opens at the bottom as
    before. A jump from search, a notification or a reply still wins.
  - The bar goes away when you send a message or leave the chat. Messages that arrive while the chat is open do not
    add a bar.
  - Ticks, read receipts and badges are unchanged (messages are still marked read on open).
- **H3. Urdu (Pakistan):**
  - **Settings > Language:** Phone language (default) / English / اردو. The words change at once on every open
    screen. The choice is saved (`app_language_304`) and kept after a restart or update.
  - "Phone language" means: an Urdu phone gets Urdu, any other phone gets English.
  - **The whole app is translated:** 2,280 texts, including the admin / owner / auditor screens, toasts, dialogs and
    the Android notifications. The PC web dashboard stays English.
  - **Font:** Noto Naskh Arabic (Regular + Bold, OFL licence, about 400 KB). It is the fallback after Roboto, so
    English looks exactly as before.
  - **The layout stays left-to-right** (your 15 Nov choice): no mirroring, and the same rows, icons, back arrow,
    bubbles and buttons.
    - Each Urdu text still reads right-to-left inside the screen.
    - Numbers, @usernames, sizes, times ("5:40 PM", digits 0-9), emails and URLs stay readable left-to-right
      inside Urdu sentences.
    - Urdu typed in messages also reads right-to-left.
  - **Notifications:** the app tells Android the chosen language, and the new `Words304.kt` gives the Urdu words. This
    covers incoming call, Accept/Decline, messages, friend requests and "LinkUp is running".
    - Channel names change the next time LinkUp starts.
    - Not `values-ur/strings.xml`, because that follows the PHONE language instead of the in-app choice.
  - **Not translated:** LinkUp, names, @usernames, "My Android Phone", phone-settings menu names (they match the
    phone's own menus), Android's own "Connect?" pop-up words, logs, and server messages Urdu doesn't know about
    (known ones are shown in Urdu).
  - English is unchanged. Code that compares words (roles, statuses, toast kinds) still works with English.
  - Month names follow the language too ("2 جنوری 2026").
- Version 3.0.100+171.

## Files (about 275)
- `pubspec.yaml` (adds `flutter_localizations` + `intl` (Flutter SDK), `generate: true`, the Naskh font, and the
  version), `l10n.yaml`, `analysis_options.yaml` (generated Urdu file excluded from analyze).
- New `lib/l10n/`: `l10n.dart` (language layer + choice), `app_en.arb`, `app_ur.arb`, `by_english_304.dart`, and
  `gen/` (generated, committed).
- New `assets/fonts/NotoNaskhArabic-Regular.ttf`, `-Bold.ttf`, and `NotoNaskhArabic-OFL.txt` (needs `git add -f`).
- New `lib/core/widgets/unread_bar_304.dart`, `lib/features/home/presentation/screens/language_settings_screen.dart`.
- About 215 `lib` files: the English text was replaced by `L.t.<key>`. The words themselves are unchanged in English.
- `lib/app/local_link_app.dart`: languages, the saved choice, and the left-to-right lock.
- `chat_screen.dart`, `group_chat_screen.dart` (H2), `voice_recording_widgets.dart` (H1), `app_build.dart` (version).
- Android: new `Words304.kt`; `CallNotificationManager.kt`, `LocalLinkNotificationManager.kt`,
  `LocalLinkTransportService.kt`, `MainActivity.kt` (the `language304` call).
- New tests:
  - `test/unread_bar_304_test.dart` (10)
  - `test/urdu_304_test.dart` (13)
  - `test/support/l10n_source_304.dart`
- Changed tests:
  - `voice_wave_303_test.dart` (new line width).
  - `bundle223_logs_test.dart` and `nearby_190_test.dart` (version lines).
  - 33 old tests that read English words from the code now read it through `readEnglish304()`, which turns
    `L.t.key` back into the English words. The checks themselves are unchanged, except:
    - `const` was dropped from 8 expected lines in `bundle183`, `groups_g1` and `bundle218e`. A translated text can't
      be `const`.
    - `labels_footer_302`: one `const MaterialApp` became non-const.
    - `link_paths_zoom_222`: the map-code hash was updated. The only differences are words (L.en, font fallback, no
      const on the Blocked tag); lines, colours and motion are unchanged.
- `docs/history/TODO_304.md`, `APPLY_app_304.md`, `URDU_REVIEW_304.md` (git add -f).

## Tests
- `flutter analyze`: **0 errors**. 363 issues: the 175 old ones, plus about 186 "prefer const" infos that come from
  translated texts no longer being const, plus 2 deprecation infos in the Language screen (same radio style as the
  Appearance screen).
- Full Flutter suite (`-j 1` chunks), final code, 313 files: **3041 tests, all passed, 0 failed**
  (3018 old + 10 `unread_bar_304_test.dart` + 13 `urdu_304_test.dart`).
- Kotlin: all app Kotlin files were compiled with kotlinc 2.1 + android-35 `android.jar` (R stub): **exit 0**.
  This caught and fixed one bug (`this` inside `apply {}` in `LocalLinkTransportService`). The full Gradle APK build
  was NOT run here.
- Urdu pictures of the real screens: Language, Settings, Chats, a chat, the call screen, unread bars, and the
  clear/delete chat sheets. Light + dark: no overflow, and the words are in the right order.
- **NOT VERIFIED here:** real phones, an Urdu phone (Phone language), the notification words on a phone, CI.

## Needs a native Pakistani Urdu speaker
`docs/history/URDU_REVIEW_304.md`:
- §1: 36 words to check first.
- §2: notes (joined sentences, dropped plural words, kept-English words, and the notification words).
- §3: all 2,280 texts by screen, English next to Urdu.

Fixes from the review go into the next build.
