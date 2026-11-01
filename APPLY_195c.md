# APPLY 195c - v3 3.0.28+99 (bundles 104-195c, 2026-11-02)

Nearby name question + friend link through ANY phone.
Builds on 195b (same zip has 191-195c).

## What changes (simple words)
1. **Nearby name question (Q5 = yes).**
   Sajjad searches "Safeer", finds nothing, and there is no internet.
   His phone then asks the nearby LinkUp phones that are NOT his friends:
   "anyone know Safeer?"
   - One step only: just the phones linked right now. Never passed on.
   - The answer has only the matching profiles, max 10.
   - Never: the full list, private contacts, people with "find me by name"
     off, unsigned profiles, blocked people, or private phone numbers.
   - Needs at least 3 letters. Max 1 question per 10 s per phone, on
     both sides (the asking phone and the answering phone).
   - Waits up to 4 s for answers.
2. **The first "X added you" travels locked through ANY phone (option B).**
   Before: the link went only through friends' phones. If Sajjad and
   Safeer had no friend in common nearby, it waited.
   Now one extra copy is locked with Safeer's own key and sent to his
   phone. Any LinkUp phone can carry it (and keep it in its queue while
   there is no path); nobody but Safeer can read it.
   - Safeer's phone opens this kind of message from a not-yet-friend
     ONLY when it is a friend link or its "got it", and the key matches
     the signed profile inside it, and it came from that profile's phone.
     It never opens anything else from a stranger: chat, calls and files
     still need a friend.
   - Blocked phones: dropped.
   - Safeer gets the usual "Sajjad added you" notice with Remove / Block.
   - Safeer's "got it" goes back to Sajjad the same locked way.
   - Each resend (195b) sends the locked copy again. Resends now also
     happen when only stranger phones are linked (before: friends only).
3. **A friend's phone is trusted right away.**
   Added by search, link or name question: the friend's phone is saved
   as a known phone (as Nearby pairing does). So locked messages and
   calls can go through other phones at once, without waiting for the
   server's device list.

## New logs
- FRIEND_SEARCH ... nearby=<n|off>   (rows found by the name question)
- FRIEND_SEARCH_ASK len=<n> peers=<n> kind=nearby
- FRIEND_SEARCH_ANSWER to=<id6> rows=<n> kind=nearby|friend
- FRIEND_LINK_LOCKED_SENT type=CONTACT_EDGE|CONTACT_EDGE_ACK to= try= ok=y|n
- FRIEND_LINK_LOCKED_OPENED type= from=
- FRIEND_DEVICE_TRUSTED device=<id6> peers=<n>
- CONTACT_EDGE_SENT ... friends=<n> now counts ALL linked phones
- warnings: FRIEND_LINK_LOCKED_SEND_FAILED, CONTACT_EDGE_LOCKED_MISMATCH,
  FRIEND_DEVICE_TRUST_FAILED, FRIEND_SEARCH_ANSWER_FAILED,
  SEAL_OPEN_FAILED reason=stranger_type
- native: mesh_dropped reason=name_not_one_step

## Files
- NEW lib/features/directory/data/name_question_policy.dart
- NEW test/friend_of_friend_195c_test.dart (rules, lock, 2 phones, end to end)
- NEW android/app/src/test/kotlin/com/sajjad/locallink/Name195Test.kt
- lib/features/directory/data/repositories/directory_repository.dart
- lib/features/directory/data/directory_search_merge.dart (log field)
- lib/features/connectivity/data/services/sealing_peer_transport.dart
- android/.../mesh/MeshRelayPolicy.kt (name question one step)
- android/.../LocalLinkTransportService.kt (name question one step)
- lib/app/local_link_app.dart (stamp), pubspec.yaml, test/nearby_190_test.dart

## Checks here
- flutter analyze: 0 errors (no new issues)
- flutter test -j 1: see the delivery message
- Kotlin compile check + Kotlin tests: see the delivery message
- Not checked here: real phones (needs your 3-phone test)

## Phone test changes (TODO_195 Part 9)
- T5: Sajjad NOT a friend of Bilal, everyone offline, Bilal near Sajjad.
  Sajjad searches "Safeer" -> Safeer IS found (if "find me by name" is
  on and Bilal didn't mark him private). Log: FRIEND_SEARCH_ASK on
  Sajjad, FRIEND_SEARCH_ANSWER on Bilal.
- T9 (new): Sajjad adds Safeer; Bilal (not a friend of either) is the
  only phone between them; no internet. Safeer gets "Sajjad added you".
  Logs: FRIEND_LINK_LOCKED_SENT on Sajjad, FRIEND_LINK_LOCKED_OPENED on
  Safeer, then FRIEND_LINK_CONFIRMED by=ack on Sajjad.
