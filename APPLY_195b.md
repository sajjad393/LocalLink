# Bundle 195b - friend link sent again + "got it" + profile inside the link
Version 3.0.27+98. Stamp: v3 · 3.0.27 · bundles 104-195b (2026-11-02)

## What changed (simple)
1. Friend link sent again (Part 1)
   - When you add someone (search / profile / QR / Nearby), your phone keeps the
     friend link in a saved list ("friend_links_waiting").
   - It is sent again when a friend phone is linked: at app start, when a
     friend comes near, and on the 2-min cycle.
   - Max 1 send per 2 min per person, max 50 sends. No friend near = wait
     (no send used up).
   - Stops when: their phone says "got it"; your Hello 👋 shows delivered;
     you remove them; you block them; 7 days passed; 50 sends.
   - Survives app restarts and swipes.
2. "Got it" (Part 2)
   - The added phone sends a small signed "got it" back (new message
     CONTACT_EDGE_ACK, passed on by friends the same way).
   - Copies of the link: no second notice; "got it" again at most once per 2 min.
   - Older app versions ignore it; then the delivered Hello or 7 days stops it.
3. Profile inside the link (Part 3)
   - Every friend link (and "got it") carries the sender's signed profile
     (phone number only if it is public). The other phone can check the link
     even if it never saw the sender's profile.
   - Links from older phones (no profile inside) are parked and SAVED
     (max 32, 7 days), so a restart doesn't lose them. Applied when the
     profile arrives (profile message, profile answer or friend sync).
   - Small extra: my own link / "got it" coming back through friends is
     not handled again.

## New logs
- CONTACT_EDGE_SENT to= op= try=<n> friends=<n|?> server=y|n profile=y|n
- CONTACT_EDGE_ACK_SENT to=   ;  CONTACT_EDGE_PROFILE_USED from=
- CONTACT_EDGE_PARKED saved=<n> [restored=y]
- FRIEND_LINK_CONFIRMED to= by=ack|delivered|removed|blocked|timeout|max_tries tries=<n>
- warnings: FRIEND_LINK_RESEND_FAILED, CONTACT_EDGE_ACK_FAILED,
  CONTACT_EDGE_ACK_UNCHECKED, CONTACT_EDGE_ACK_BAD_SIGNATURE

## Files
- NEW lib/features/directory/data/friend_link_resend.dart
- NEW test/friend_of_friend_195b_test.dart (2 fake phones)
- lib/features/directory/data/repositories/directory_repository.dart
- lib/features/directory/data/contact_edge.dart (ack text)
- lib/core/services/local_store.dart (sentMessageDeliveredSince)
- lib/app/local_link_app.dart (stamp), pubspec.yaml, test/nearby_190_test.dart
- No Kotlin change.

## Not in 195b
- Name question for non-friend phones -> 195c (needs its own go-ahead)

## Phone tests: TODO_195 Part 9 T1-T8 (3 phones).
