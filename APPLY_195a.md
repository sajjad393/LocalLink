# Bundle 195a - friend of friend: Hello notice, search merge, offline hint, logs
Version 3.0.26+97. Stamp: v3 · 3.0.26 · bundles 104-195a (2026-11-02)

## What changed (simple)
1. Hello from someone new (Part 4)
   - If "Hello 👋" comes from someone who is not your friend yet (their friend
     link has not arrived), you now see "X added you as a friend" (Remove / Block)
     instead of a plain message notification. The Hello itself stays in the chat.
   - Only one notice: the old 24 h notice rule still stops a second notice when
     the friend link arrives later.
2. Search shows everyone (Part 5)
   - Name search now shows saved people AND online (server) people together,
     saved first, no doubles. Server wait max 4 s when saved people were found.
   - Offline: same as before (saved people, then asks friends nearby).
3. Offline hint (Part 6)
   - Nothing found and no internet -> extra line:
     "Not found. Try again when you're online or near friends."
4. New logs (Part 7)
   - FRIEND_SEARCH len= saved= server=<n|off> friends_asked=y|n shown=   (no names)
   - CONTACT_EDGE_SENT to=<id6> op= try=1
   - CONTACT_EDGE_FORWARDED from=<id6> to=<id6> ttl=   (phone in the middle)
   - CONTACT_EDGE_APPLIED from=<id6> new=y|n notice=y|n
   - FRIEND_HELLO_RECEIVED ... notice=y|n ; FRIEND_ADDED_NOTICE source=hello

## Files
- NEW lib/features/directory/data/directory_search_merge.dart
- NEW test/friend_of_friend_195a_test.dart
- lib/features/directory/data/repositories/directory_repository.dart
- lib/features/directory/data/services/friend_hello_service.dart
- lib/features/directory/presentation/add_contact_screen.dart
- lib/features/messaging/data/services/reliable_messaging_service.dart
- lib/core/notifications/local_link_notification_service.dart
- lib/app/local_link_app.dart (stamp), pubspec.yaml, test/nearby_190_test.dart

## Not in 195a
- Resend of the friend link, confirm, profile with the link -> 195b
- Name question for non-friend phones -> 195c

## Phone tests (TODO_195 Part 9): T1-T8. Send logs after.
