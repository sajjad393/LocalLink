# Bundle 198 + X1 - Read receipts (blue ticks), voice "played", mic slide-up, sounds, hidden-note acks (3.0.32+103)

Scope: TODO_198 + mock v5 + your answers Q1-Q11 + X1 (your "Yes X1").

**Both phones need 3.0.32.** An older phone ignores read notes, so your ticks stay grey for that friend.

## What is new

1. **Blue ticks (1-to-1 chats only)**
   - Grey ✓✓ = delivered. Blue ✓✓ = Ali read it.
   - "Read" means Ali's chat with you is open, LinkUp is on screen and the screen is on. Replying from the notification or tapping "Mark as read" also counts.
   - Only looking at the notification does **not** count (stays grey).
   - Ali's phone collects what he read and sends **one** hidden note per chat after 2 s (at most 200 messages per note). The note goes the normal way (Nearby, Online, relays, outbox), so it still arrives if Ali reads while offline.
   - Groups don't change: still "Sent", no "Read by", no played.
   - The Chats list doesn't change.
2. **Settings › PRIVACY › Read receipts** (switch, ON by default), between Private profile and Blocked people.
   - OFF (WhatsApp rule): Ali gets no read notes from you, and **your** messages show grey ticks even when Ali read them. Message info then hides "Read" and shows "Read receipts are off. Turn on in Settings › Privacy."
   - Turning it back ON shows the blue ticks again at once.
3. **Voice notes "played"**
   - When Ali plays your voice note (or audio file) for the first time: the small mic next to "0:14" on your bubble turns blue (grey until then). Message info shows a "Played" row.
   - Played also counts as read. Replays send nothing.
   - Played is still sent when the switch is OFF (WhatsApp rule).
4. **Message info** (your message): Sent / Delivered / **Read** / **Played** times.
5. **Hold the mic: slide-up movement**
   - While you hold, the arrow in the lock box bobs up and down (1 s loop).
   - The big mic follows your finger up (0 to 60 px). The lock box rises a little and the arrow fades.
   - Lock is still at 60 px. Sliding back down undoes it. With the phone's "Remove animations" setting on, nothing bobs.
6. **Sounds** (our own short files in `res/raw`)

   | Moment | Sound |
   |---|---|
   | Hold the mic → recording starts | "tik" (the mic opens 90 ms later, so the tik is not in the recording; the timer starts when the mic opens) |
   | Let go / locked Send | "swoosh" |
   | Slide left / bin / too short | "tok" |
   | Send a text, photo, group message, forward | one soft tick (forward to 3 chats = one tick) |
   | A message arrives in the chat that is open on screen | one "pop" (at most once every 1.5 s) |

   - Silent or Vibrate mode, or during a call: no sound (vibration as today).
   - Pause / Continue / Lock / quick tap: no sound. Notification sounds are unchanged.

## Extra safety guards (small, no behaviour change you can see)
- When the server confirms a hidden note (read / reaction / delete), it is never shown as a bubble on your phone. Before, a reaction or delete note confirmed by the server could show as an empty bubble.
- The chat screen also drops any hidden note, in case one ever reaches it.
- A message whose photo you cancelled keeps "Not sent - tap to retry" even if Ali read the text part.
- Coming back to an open chat (Home → LinkUp again) now marks what arrived meanwhile as read (blue for the friend, and the chat's notification is cleared) - same as opening the chat.

## X1 - hidden notes are now confirmed
Before: reaction (`llrx`) and Delete-for-everyone (`lldel`) notes were never confirmed, so over **Nearby** the sender's outbox resent them about every 64 s (no end) while the phones were near. The other phone ignored the copies, so you saw nothing, but it was extra traffic and repeating `MESSAGE_FLUSH_ITEM` log lines.

Now every hidden note sent **to me** (read, reaction, delete) is confirmed the same way as a normal message:
- Nearby: `direct_delivery_ack` -> the friend's outbox drops it.
- Online (live): `ack_delivery`.
- Online (sync after being away): the same server confirm a normal message gets.

Nothing changes on screen. Old notes already waiting in an outbox stop after the other phone gets 3.0.32 and confirms them once.

## How it works
- Hidden note `llread:v1:{"r":[ids],"p":[played ids],"at":"..."}`. Only your own messages sent to that friend can change.
- Database v28 = one new column `messages.played_at` (guarded ALTER). Status order: played > read > failed > delivered > sent.
- Times from a phone clock more than 2 min in the future are cut to "now".
- Kotlin: new `UiSounds.kt` (SoundPool, `USAGE_ASSISTANCE_SONIFICATION`), new `"tone"` method on the existing `locallink/voice_notes` channel. 5 new WAV files. No new permission. The Kotlin service is unchanged.
- No server change.

## Logs
`READ_RECEIPT_SENT chat= read= played=`, `READ_RECEIPT_GOT chat= read= played= applied= ignored=` (or `blocked=y`), `CONTROL_ACK kind=read|reaction|delete path=online|nearby|sync`, `READ_RECEIPTS on|off`, `VOICE_PLAYED_NOTED id=`, `VOICE_TONE_FAIL name=` (errors only), `READ_RECEIPT_SEND_FAILED`, `READ_RECEIPT_APPLY_FAILED`, `MESSAGE_ENVELOPE_BAD kind=read`. No log for each sound or finger move.

## Checks done here
- `flutter analyze`: 0 errors (same 156 old infos/warnings as 197b).
- Full test suite `-j 1`: **1123 passed** (48 new). `bundle183_test`: 2 Settings tests use a taller test screen, because the new Read receipts row pushes ADMIN lower.
- 9 new test files: `read_receipt_envelope_198`, `read_receipt_service_198`, `read_receipt_store_198`, `read_receipt_apply_198`, `message_info_198`, `settings_read_receipts_198`, `bubble_ticks_198`, `voice_slide_198`, `ui_sounds_198`.
- Old tests updated: `message_delete_197_test` (v28 may only add `played_at`), `db_v27_197b_test` (version 28), `nearby_190_test` (version strings).
- Kotlin compile check (kcheck): clean (171 classes).
- Not tested here (needs the phones): the sounds, Silent / call muting, real database upgrade, read notes between two phones.

## Phone tests - Sajjad (Realme) + Ali (ZTE), both on 3.0.32

| # | Do this | Expected |
|---|---------|----------|
| RR1 | Send Ali 3 messages, Ali's chat closed | grey ✓✓ |
| RR2 | Ali opens the chat (Nearby) | your 3 ✓✓ turn blue in ~2-3 s |
| RR3 | Same, but only Online | blue when the note arrives |
| RR4 | Ali keeps the chat open, you send 1 more | blue in ~2 s |
| RR5 | Ali replies from the notification / taps Mark as read | that message blue |
| RR6 | Ali only looks at the notification | stays grey |
| RR7 | Ali reads while his phone is offline, comes back later | blue when he is back |
| RR8 | Your Message info on a read message | Sent / Delivered / Read times |
| RR9 | Ali turns Read receipts OFF, opens chat | your ticks stay grey; Ali's own sent messages show grey too |
| RR10 | Group message info | unchanged ("Sent") |
| RR11 | Ali plays your voice note | your small mic turns blue; Message info shows Played |
| RR12 | Ali OFF + plays your voice note | mic still blue, ticks grey |
| RR13 | Hold the mic | arrow in the lock box moves up and down |
| RR14 | Hold + slide up slowly | big mic follows your finger, locks at the top; slide back down = no lock |
| RR15 | Hold, speak, let go (sound ON) | tik → recording → swoosh; play it back: no tik inside |
| RR16 | Slide left / bin / very short hold | low tok |
| RR17 | Send a text, a photo, a group message, a forward to 3 chats | one tick each (forward: one tick) |
| RR18 | Ali's chat open, Ali sends 1, then 5 fast | one pop, then one pop for the 5 |
| RR19 | You are on the Chats list, Ali sends | normal notification sound, as today |
| RR20 | Phone on Silent or Vibrate, repeat RR15-RR18 | no sounds, vibration only |
| RR21 | Logs | `READ_RECEIPT_SENT` / `READ_RECEIPT_GOT` lines; no "llread..." bubble anywhere; no repeating flush lines |
| RR22 | Ali's chat open on his phone, he presses Home, you send 2, he opens LinkUp again | blue in ~2 s |
| X1a | Phones Nearby (no internet): react 👍 to a message, wait 3 min | Ali sees 👍 once; your log: one `MESSAGE_FLUSH_ITEM` for it, then no repeats; Ali's log: `CONTROL_ACK kind=reaction path=nearby` |
| X1b | Same, Delete for everyone | message gone on Ali's phone; Ali's log `CONTROL_ACK kind=delete path=nearby`; no repeats |
| X1c | Ali offline, you react, Ali comes back Online | 👍 shows; Ali's log `CONTROL_ACK kind=reaction path=sync` (or `online`) |
