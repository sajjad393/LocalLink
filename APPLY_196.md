# Bundle 196 - contact sheets, Private profile, Blocked everywhere, Nearby requests

Version **3.0.29+100**, stamp `v3 · 3.0.29 · bundles 104-196 (2026-11-02)`.
Base: pushed `59728d3` (3.0.28+99). Mock: `mock_196_contact_sheets.html` (v6).

## What changed (simple words)
1. **People ⋮** opens a bottom sheet: Message / Voice call / Remove contact / **Block <name>** (red).
   Long press on a row opens it too. The old pop-up and "Contact privacy…" box are gone.
2. **Block** and **Remove** ask first (sheet with short points). Block = remove + block + tell their phone.
3. **Unblock** sheet: "Unblock and add back" / "Unblock only" / Cancel.
4. **People**: red **BLOCKED** part at the bottom (All filter only, follows search);
   **REQUESTS** part at the top (people near you who asked to add you); grey **🔒 Private** label
   when that person made their own profile private.
5. **Settings › PRIVACY** (new group between THIS PHONE and ADMIN):
   - **Private profile** switch (asks first when turning ON, no question when turning OFF).
   - **Blocked people** + count → new screen with Unblock buttons. Empty: "You haven't blocked anyone."
6. **Blocked label everywhere**: Chats row, chat top bar, Calls row, Profile page, Add Contact search.
   No call buttons for a blocked person. A Calls row of a blocked person does NOT call; it opens Unblock.
7. **Chat**: the message box is replaced on BOTH phones.
   - Mine: "You blocked Ali." + **Unblock**, small chip "You blocked Ali · 8:49 PM".
   - Ali's phone: "You can't message Sajjad." (no call icon, never the word "blocked").
   - Chat ⋮ › **Conversation info** is a bottom sheet now (Voice call / Search messages / Block or Unblock / Close).
8. **Block state**: a signed "I blocked / unblocked you" goes **locked** to the other phone through
   any phone (like the 195c friend link), resent every 2 min (max 50 tries, 7 days) until their phone
   sends a signed "got it". From a blocked phone ONLY that "got it" can open.
9. **Private profile → Nearby adds need approval**:
   - Ali taps Add friend → your phone answers "wait" → Ali sees **"Requested"** (24 h) and
     "Request sent. sumaira needs to accept."
   - You get a notification **Accept / Decline** + a row under REQUESTS on People.
   - Accept → friends (works later too, through any phone). Decline = silent.
   - **QR code still adds at once.**
10. Old per-contact private marks are ignored (only the person controls their own privacy).
11. Profile save keeps your Private choice (no longer forced to public).

## Android (Kotlin) - small changes
- Pair kind `wait` (new `PairKind.kt`), 2 new notifications (friend request with Accept / Decline,
  "accepted your request"), receiver + channel entries. Kotlin unit test `Pair196Test.kt`.
- **Old app versions** ignore `wait` and the block state silently (no crash). Install 3.0.29 on all phones.

## Checks done here
- `flutter analyze`: **0 errors** (150 infos/warnings, same as before).
- Full test suite: **962 passed** (was 916).
- Kotlin compile check + Kotlin unit tests: OK.
- No apk build here; notifications / pairing on real phones = phone tests below.

## Note
- With only **2 phones**, after a block the direct link is cut, so the block state reaches the other phone
  only through a **third phone** or the **server** path. With 2 phones the other side may keep its
  message box until a third phone is near (their messages are still dropped as before).

## Phone tests (P1-P14 from TODO_196 Part 15)
- P1 People ⋮ → sheet with 4 rows; long press same.
- P2 Phone B: Settings › Private profile ON (asks first). Phone A: B shows "Private" on People.
- P3 Phone A taps Add friend on B in Nearby → "Requested" + note; B gets notification + REQUESTS row.
- P4 B taps Accept (notification or People) → both friends, A's chat opens if Nearby is open.
- P5 B taps Decline → nothing on A; A sees "Add friend" again after 24 h.
- P6 QR add with B private → added at once.
- P7 Block from People → sheet → Block → Ali in BLOCKED (People + Settings), pill on Chats / Calls / chat.
- P8 Chat with Ali: "You blocked Ali." + Unblock; no call icon; Conversation info sheet.
- P9 Settings › PRIVACY › Blocked people: same list; empty text after unblocking.
- P10 Ali's phone (third phone near): "You can't message Sajjad.", no call buttons.
- P11 Unblock only → Ali's box comes back; Unblock and add back → friends again (Hello only if chat empty).
- P12 Calls row of Ali: no call button, tap opens Unblock.
- P13 Add Contact search "Ali" → blocked card first with Unblock.
- P14 Check logs: `CONTACT_BLOCK`, `BLOCK_STATE_SENT/RECEIVED/CONFIRMED`, `FRIEND_REQUEST_IN/SENT_WAIT/ACCEPT`,
  `PRIVATE_PROFILE`, `APP_BUILD_STAMP ... bundles 104-196`.
