# APPLY app 302 - right labels, new footer, banner, update sheet (3.0.98+169)

Zip: `locallink_app_302_2026-11-14.zip`, on top of GitHub `5e34ade` (3.0.97+168). App only, no backend change.
Plan: `docs/history/TODO_302.md`. Mock: approved `labels_footer_302.html`.

## What changes
- **A: right label for each case.** Before, the app used "Blocked" for three different cases. Now:
  | Case | Chats / Calls row | Chat header | Footer | Unblock |
  |---|---|---|---|---|
  | I blocked them | red "Blocked", grey photo | Blocked | "You blocked X." + Unblock | yes |
  | Admin blocked them | red "Admin blocked", grey photo | "Blocked by admin" | "X is blocked by admin" | no |
  | Their LinkUp is old (version stopped) | normal row + amber "Old LinkUp", normal photo | "Old LinkUp" | "X has an old LinkUp" | no |
  - The "You blocked ayesha" chip now shows only when you really blocked them.
  - The info sheet shows Unblock only for your own block.
  - Contacts' "Blocked" group already lists only people you blocked, so it is unchanged.
- **B: new footer.** Rounded card with an icon, a title and a short line. It is used in chats and group chats.
  - My LinkUp is old: red card, "Your LinkUp is old" + Update.
  - Admin blocked me: red card, "Blocked by admin".
- **C: Chats banner.** Same card style: "Stopped by admin" / "Read chats only. Update to send and call." + Update.
- **D: update sheet.** Bigger round icon, "16.0 of 34.6 MB · 46%" progress, pill buttons. "Could not get it now" has
  OK + **Try again**.
- **E: stopped phones keep their link.** A phone whose version is stopped is no longer cut at the link layer (no native
  block and its link keys are kept). This lets it still get the new APK from nearby phones. The app still refuses its
  messages and calls (same send/receive gates as before). Bug A, the stall at 3.2 MB: **NOT VERIFIED** on phones.

## Files (20)
- new `lib/core/widgets/peer_mark_302.dart`, `lib/core/widgets/chat_notice_bar_302.dart`
- `lib/core/widgets/admin_blocked_banner.dart`, `version_banner.dart`, `messenger_conversation_tile.dart`
- `lib/features/messaging/presentation/screens/chat_screen.dart`
- `lib/features/groups/presentation/screens/group_chat_screen.dart`
- `lib/features/home/presentation/screens/home_screen.dart`
- `lib/features/calls/presentation/widgets/call_history_tile.dart`
- `lib/features/share_app/presentation/update_sheet.dart`
- `lib/core/services/local_store.dart` (new `linkBlockedPeerIds`)
- `lib/features/connectivity/data/services/sealing_peer_transport.dart`, `lib/app/app_dependencies.dart`
- `pubspec.yaml`, `lib/core/config/app_build.dart` (3.0.98+169)
- new `test/labels_footer_302_test.dart` (17 tests)
- `test/bundle223_logs_test.dart`, `test/nearby_190_test.dart` (version lines only)
- `docs/history/TODO_302.md`, `docs/history/APPLY_app_302.md` (git add -f)

## Tests
- `flutter analyze`: 0 errors, no issues in the changed or new files.
- Full Flutter suite: 309 files, 13 chunks, **2990 tests, all passed** (2973 + 17 new).
- Real widgets drawn light + dark (test pictures) match the mock.
- **NOT checked here:** real phones and CI.

## Phone checks
1. On Sajjad (3.0.98), set the minimum to 3.0.98 while Ayesha is still on 3.0.97:
   - Sajjad Chats: ayesha has a normal photo + amber "Old LinkUp", and there is no "You blocked" chip.
   - In the chat with ayesha: the header says "Old LinkUp" and the footer card says "ayesha has an old LinkUp".
2. Ayesha (stopped): the Chats banner says "Stopped by admin" + Update, and the chat footer says "Your LinkUp is old"
   + Update. Sajjad must NOT show as "Blocked".
3. Ayesha taps Update: the sheet shows "X of Y MB · N%", and the download should finish from Sajjad nearby.
   - If it fails: "Could not get it now" with OK + Try again. Send logs with `VERSION_PEERS_DROPPED`,
     `LINK_AUTH contact link closed` and `APP_UPDATE_SILENT download_fail`.
4. Block kiran yourself: red "Blocked", "You blocked kiran.", and Unblock still work.
5. Light and dark mode both match the mock.
