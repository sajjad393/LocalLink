# TODO 316 - crash loop on ayesha (RMX3938) and kiran (TECNO): out of memory while reading held Get chat / Get file parts

Status: TODO (freeze ON, user 16 Nov: more points coming, build only on "Build"). Picks: build together with 315 (3.0.108+179); F3 cap = 8 MB. Base: app `5bad575` (3.0.107+178). Backend: no change.
Logs: `uploads/LinkUp-logs-RMX3938-2026-11-16-1152.txt` (ayesha), `uploads/LinkUp-logs-RMX5303-2026-11-16-1155.txt` (C71).
TECNO: no log (it crashes before Share logs) - same cause is LIKELY (same chat, same carrier role), NOT VERIFIED.

## What the logs show (facts)
- RMX3938 crashed **~30 times between 11:42:55 and 11:50:55**: `APP_LAST_EXIT reason=crash code=4 was=open ago_s=3`
  (the app dies about 3 s after every start).
- 5 crashes have the full Android stack, all the same:
  `java.lang.OutOfMemoryError: Failed to allocate a 36949008 byte allocation ... growth limit 201326592`
  `ByteArrayOutputStream.grow <- p4.s.k(189) <- p4.s.k(334) <- p4.s.k(334) <- p4.s.k(387) <- p4.t.a <- o4.o.a <- A.h.run` on the main thread.
  = Flutter `StandardMessageCodec` packing a plugin reply of Map -> List -> List -> text (the sqflite query reply
  shape `{columns, rows:[[...]]}`) that is already **over 18 MB**. Java heap went 79 MB -> 169 MB of 192 MB in 1 s.
- Just before: 11:42:18 ayesha `ADMIN_ANSWER_PARTS_SENT parts=400` (the per-meeting maximum for the admin phone).
  C71 received **355 `admin_act_parts` frames in 11:42 + 48 in 11:41**, but logged no `ADMIN_ANSWER_STOP` for them.
- 11:37-11:46 the C71 made many requests on the kiran + ayesha chat (`phones=2`): 13 Get file (videos 2-3 MB),
  2 Get chat, 5 Delete completely.
- C71 itself: no crash, no OOM (bigger heap).

## Cause (code, 5bad575)
- `SqlAnswerPartStore.parts()` (`lib/core/services/hidden_store_221.dart` ~l.739) = `SELECT * FROM answer_parts`
  **with every `body` (up to 64 KB each)**, in ONE sqflite reply.
- A carrier may hold up to `capOthers = 20 MB` of other people's parts + all its own parts
  (`chat_answer_carrier.dart` l.302) -> one reply of 20-30 MB -> Java strings (2 bytes/char) + codec buffer doubling
  -> over the 192 MB Java heap of a Realme / TECNO -> crash.
- `parts()` runs all the time: every received part (`takePart` cap check l.451), every change (`refreshProgress` l.382),
  every have frame (`haveFrame` l.557, every 60 s per linked phone), `_sendMissing` l.632, `syncWithServer` l.673,
  `_fetchMine`, `progressOf`, `carrying`. Right after a start the carrier meets the C71 -> `parts()` -> crash again = loop.
- Why the 400 parts never go away: NOT VERIFIED. Likely: the C71 already has them, `store.put` ignores a repeat
  (`ConflictAlgorithm.ignore` -> false) so `takePart` returns before `_ackMine` = no new ack/stop for ayesha, and she
  sends the same 400 again at every meeting.

## Fix plan
- **F1 (main):** never read `body`/`sig` in bulk.
  - New light read: `answer_id, part, of, action_id, device, reply_to, is_file, own, at, length(body)+length(sig) AS size`.
  - Used by every place that only needs ids / counts / sizes (cap check -> one `SUM(...)` query; progress, have frame,
    carrying, fetchMine, choosing what to send/upload).
  - The blob is read **one part at a time** just before it is sent or put in the upload batch (6 MB batch stays).
- **F2:** the admin phone answers a repeated part of its own answer with its signed ack (have list / `all:true` when
  complete), so carriers drop what it already has (`takeAck` already removes them). Code-check first; regression test.
- **F3 (USER PICK 8 MB):** a carrier keeps at most 8 MB of other people's parts (now 20 MB).
- No change: part size 64 KB, 40 / 400 per meeting, file parts only to the admin phone, server path.

## Tests
- New: a store with 500 parts x 60 KB -> the light read returns no body; the cap check, have frame and progress never
  read bodies (fake store counts body reads); sending reads one blob per sent part.
- New: C71 gets a part it already has -> sends its ack; ayesha drops those parts.
- Regression: old answer tests (`chat_answer_*`, `bundle221*`, 307/310 Get chat tests) unchanged; full suite.
- Phone check: install on ayesha + kiran (over the old app, chats stay) -> no crash; Get file on a video completes;
  log `ADMIN_ANSWER_STOP` appears and `ADMIN_ANSWER_PARTS_SENT parts=400` does not repeat.

## Files (expected)
`hidden_store_221.dart`, `chat_answer_carrier.dart`, maybe `chat_answer_reader.dart` (l.271/345 use `parts()`),
version 3.0.108+179 (+ the 2 version tests), 1 new test, docs. TODO_315 (clock banner) can go in the same build.
