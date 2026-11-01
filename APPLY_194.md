# Bundle 194 - "Hello 👋" after Add friend - 3.0.25+96

## What changes (your answers Q1-Q7)
1. **First add (any way: Nearby, Wi-Fi Direct, online search, profile, QR):**
   - The phone that tapped Add **opens the chat** right away (no "X added" toast).
   - About 3 s later it sends one normal message: **"Hello 👋"** (outbox, so it
     also waits for offline phones; same ticks as any message).
   - The other phone gets **one** notice "X added you as a friend" (Remove /
     Block). The Hello arrives **silently** (stays unread in the chat).
2. **Already friends + Add tapped again:** no add, no Hello, no toast, no
   notice. The chat just opens.
3. **Removed and added again:** a new Hello only if the chat is empty.
4. **Both phones tap Add at the same time:** only one Hello (the phone with
   the smaller account id sends; the other skips).
5. No Hello for silent adds: message from someone new, restore, sync.
6. Fixed order risk: if a Hello lands before the online friend link, the
   "X added you" notice still shows.

## New log lines
- `FRIEND_ADD_TAP source=nearby|online|profile already=y|n`
- `FRIEND_ADD_OPEN_CHAT to=<id6> reason=already_friend|new_friend opened=y|n`
- `FRIEND_HELLO action=sent|skip reason=sent|chat_has_messages|already_sent|mutual_other_sends|blocked|self|no_device to= source= mutual=y|n`
- `FRIEND_HELLO_RECEIVED from=<id6> silent=y|n`
- `FRIEND_ADD_MUTUAL node=…`  `PAIR_COMPLETE toast=no`

## Files
- NEW `lib/features/directory/data/services/friend_hello_service.dart`
- NEW `test/friend_hello_194_test.dart`
- `lib/features/directory/data/services/pairing_service.dart`
- `lib/features/directory/data/repositories/directory_repository.dart`
- `lib/features/directory/presentation/nearby_people_section.dart`
- `lib/features/directory/presentation/add_contact_screen.dart`
- `lib/features/messaging/data/services/reliable_messaging_service.dart`
- `lib/core/notifications/local_link_notification_service.dart`
- `lib/core/services/local_store.dart` (hasDirectMessages only)
- `lib/app/app_dependencies.dart`, `lib/app/local_link_app.dart`
- `pubspec.yaml`, `test/nearby_190_test.dart`
- No Kotlin change in 194.

## Phone tests (TODO_194.md part 8)
T1 first Nearby add, T2 tap Add again, T3 other phone adds (already friends),
T4 online add, T5 other phone off, T6 swipe after Add, T7 both tap at once,
T8 re-add with old chat (no Hello), T8b re-add with empty chat (Hello),
T9 blocked. Send both logs after.
