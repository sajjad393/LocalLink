# Bundle 190 - Nearby list stops flashing, no false "Everyone nearby is already in your contacts" (3.0.21+92)

## Why
2026-11-02 logs (before the two phones were paired):
- ZTE 02:24:56 `relay link up peer=...da19f3`, Realme 02:24:57 `relay link up peer=...a834`.
  Since bundle 156 a stranger's phone can hold a relay (helper) link.
- The Nearby list still used the old rule "a linked phone = a contact", so it
  hid the stranger's card and said "Everyone nearby is already in your
  contacts." with no contacts at all.
- Every ~4 s the "I'm here" beacon marked the phone "seen" (card back), then
  the link update marked it "linked" (card gone) -> flashing.
- With real contacts, a short link drop made the phone vanish for ~4 s
  ("Everyone nearby..." <-> "Looking for LinkUp phones...").

## What changed (Nearby list in Add Contact only)
A. A linked phone counts as a contact only if it is paired (your contact
   list). Until the paired list is read (a moment at open) the old rule stays.
B. A phone seen in the last 15 s stays on the list during a short link drop.

Nothing else changes: relay links, pairing, contacts, People, Chats, the
search animation and the "found" moment are as before.

## Files
- lib/features/directory/presentation/nearby_list_plan.dart
- lib/features/directory/presentation/nearby_people_section.dart
- test/nearby_190_test.dart (new), test/bundle189_test.dart (version moved)
- lib/app/local_link_app.dart, pubspec.yaml (3.0.21+92)

## Phone test
1. Fresh phone or no contacts: open Add Contact near the other phone.
   Pass: the other phone shows as a card with "Add friend", it does NOT flash,
   and "Everyone nearby is already in your contacts." never shows.
2. With the other phone as a contact: open Add Contact.
   Pass: "Everyone nearby is already in your contacts." stays steady (no
   switching to "Looking for LinkUp phones...").
