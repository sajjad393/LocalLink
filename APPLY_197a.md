# Bundle 197a - message options (3.0.30+101)

Scope: TODO_197 section 2 + mock v8 only. 197b (thumbnails, clean-up, storage) is NOT in this bundle.

**Both phones must have 3.0.30.** An old phone shows a reply / forward as plain text and ignores Delete for everyone.

## What is new

1. **Hold a message** -> emoji row + Reply / Copy / Forward / Message info (own only) / Select / Delete (red).
   - The held bubble stays bright; the rest of the chat dims.
   - Only the bubble turns grey with a ring, never the full row.
2. **Delete**
   - Own message 5 minutes old or less: Delete for everyone + Delete for me.
   - Older, or a friend's message: Delete for me only, with the hint "Ali still has it".
   - Delete for everyone: the message just disappears on both phones. No "deleted" line.
   - A quote of a deleted message shows "Message not available".
3. **Reply** -> reply bar above the box; the quote sits in the bubble; tapping the quote jumps to the old message and flashes it grey.
4. **Forward** -> "Forward to" screen (search, pick many, no limit), with the "Forwarded" label.
   - 1 chat picked -> that chat opens.
   - Several -> "Sent to N chats".
5. **Select** -> top bar with X, count, Reply / Info (1 picked), Copy, Forward, Delete. Back key closes Select first.
6. **Message info** (own messages)
   - 1-to-1: Sent + Delivered, or "Waiting. Ali gets it ...".
   - Group: Sent, or "Not sent yet".
7. **Chat ⋮** = tidy pop-up: Search, Conversation info, divider, Clear chat.
8. **Chats list hold**
   - 1-to-1: Clear chat / Delete chat.
   - Group: Clear chat only.
9. Groups get the same hold / reply / select / info / delete / clear.
10. The failed-message sheet (162) is unchanged.

## How it works (differences from TODO_197)

- **No database change** (stays v26). Nothing to migrate.
- Reply and forward ride inside the message text as `llmsg:v1:{...}`. Plain messages are sent exactly as before.
- Delete for everyone is sent as `lldel:v1:{id,by,at}` through the normal message path, so it works over Nearby and Online.
  - The receiver accepts it only from the sender of that message, and only within 5 min + 2 min slack.
  - A delete that arrives before its message is kept for 7 days, and the late message is dropped.
- Deleted ids and chat clears are stored in two settings keys (`deleted_messages_197`, `chat_clears_197`).
  - Save paths refuse those messages, so Online history or a late Nearby copy can't bring them back.
- **Clear chat keeps my unsent messages**:
  - 1-to-1: queued / sending / pending;
  - group: not yet sent to the server.
- Deleting a message also deletes its own file copy on this phone.

## Known limits (accepted)

- Clear chat uses this phone's clock. If the clock is wrong, a message near that time may stay or go.
- Group history sync skips read-receipt bodies (as before).
- Received `-thumb` files are not deleted yet (197b L1).
- A photo in a quote shows "📷 Photo" (no small picture).
- The jump to a quoted message first scrolls to an estimated place, then fine-tunes. On a very long chat it may need a second tap.
- The mock's "new" / "changed" tags are mock-only.

## New logs

MESSAGE_DELETE_ME, MESSAGE_DELETE_ALL_SENT, MESSAGE_DELETE_ALL_RECEIVED, MESSAGE_DELETE_ALL_REJECTED, MESSAGE_DELETE_EARLY, MESSAGE_REPLY_SENT, MESSAGE_FORWARD, CHAT_CLEARED, CHAT_DELETED, MESSAGE_ENVELOPE_BAD

## Phone tests (Realme = you, ZTE = Ali)

| # | Do this | Expected |
|---|---------|----------|
| Q1 | Hold Ali's message | Emoji row + Reply, Copy, Forward, Select, Delete. No Message info. Only that bubble is bright and grey-ringed. |
| Q2 | Hold your own message | Same + Message info |
| Q3 | Message info on a delivered message | Sent + Delivered times. With ZTE off: "Waiting. Ali gets it ..." |
| Q4 | Send "test", within 5 min Delete -> Delete for everyone | Gone on both phones, no "deleted" line |
| Q5 | Wait over 5 min, Delete your message | Only "Delete for me"; Ali still has it |
| Q6 | Delete Ali's message | Only "Delete for me"; gone only on your phone, stays gone after reopening the chat |
| Q7 | Reply to Ali's message | Reply bar, then a quote in the bubble on both phones; tap quote -> jumps + grey flash |
| Q8 | Delete the quoted message for everyone | The quote shows "Message not available" |
| Q9 | Forward one message to 2 chats | "Sent to 2 chats"; both show "Forwarded" |
| Q10 | Forward a photo to 1 chat | That chat opens; photo arrives with "Forwarded" |
| Q11 | Select 3 messages -> Delete | "Delete 3 messages?"; back key closes Select first |
| Q12 | ⋮ -> Clear chat | Pop-up under ⋮ with icons; chat empty, row stays in Chats |
| Q13 | Chats list: hold Ali -> Delete chat | Row gone; Ali's next message brings it back with only the new message |
| Q14 | Group: hold Bilal's message, then Reply, Info on own, Clear chat | Same as 1-to-1; group info shows Sent only |
| Q15 | Turn ZTE off, send a message, Clear chat | Your unsent message stays and is sent later |

## Checks here

- flutter analyze: 0 errors (155 issues, all old warnings/infos)
- full suite -j 1: 1017 passed (962 before + 55 new)
- kcheck: clean (168 classes), no Kotlin change
