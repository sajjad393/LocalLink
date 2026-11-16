# TODO 319 - Owner phone stuck loading (database jam) (16 Nov, 3.0.109+180 logs)

Freeze ON: fix after "Build". Code read on GitHub `e6473ed` (app 318).

## What the user saw (C71 / RMX5303, 18:55-19:04)
- Conversations: grey shimmer forever (Chats 0 / Requests 0), with server and without.
- Viewer "ayesha & kiran · Full chat": spinner forever.
- Block or unblock a user: spinner forever.
- TECNO (kiran): logs can't be taken.

## Proof in the logs
| Proof | File / time |
|---|---|
| `database has been locked for 0:00:10` **26,100 times**, every minute 18:29 -> 19:01 (never stops) | RMX5303-1901 l.8700... |
| A simple outbox read takes 10 s, then **95 s**, then **192 s** (`STORE_SUMMARY max_ms=192149`) | RMX5303-1901 18:41, 18:54 |
| Jam starts 10 s after a flood: 18:29:05-18:29:11 hundreds of `admin_act_parts` in; ayesha `ADMIN_ANSWER_PARTS_SENT parts=400` 18:29:11 | RMX5303 + RMX3938 |
| ayesha sends the Owner **400 parts again and again**: 12 x 400 + 15 x 40 between 18:28 and 18:53 (about 5,400 parts); the Owner parsed 2,084 | RMX3938-1901 |
| No slow transaction (`STORE_TX_SLOW` none): the queue is full of MANY small reads, not one long write | RMX5303-1901 |
| Same pattern, smaller, on 3.0.107: 515 lock warnings at 11:42 during the first 400-part flood | RMX5303-1155 |

## Cause (code)
1. **Every incoming part re-counts ALL requests ever** - `ChatAnswerCarrier._changed()` -> `refreshProgress()`
   (`chat_answer_carrier.dart` l.433-450): reads all acks + all parts, then for EACH action id calls
   `progressOf()`, which reads all acks + all parts again. Not throttled; runs overlap. 400 parts x hundreds of
   action ids = hundreds of thousands of SQLCipher reads on the ONE queue every screen uses.
2. **Acks and stops are never deleted** - tables `answer_acks`, `answer_stops` (`hidden_store_221.dart`) only grow
   (one per chat request and, since 317, one per file). So (1) gets slower every day = "again the same issue".
3. **New acks never reach the carrier** - `haveFrame()` sends `acks.values.take(100)` = the OLDEST 100. Once the
   Owner has >100 acks, ayesha never hears "I have them / stop" -> she sends the same 400 parts every meeting.
4. **Each part reads all acks + all stops** - `takePart()` (l.506-510) does 2 full table reads per part.
5. **A closed answer comes back** - `takePart()` skips the stop check for the Owner's own answers (`&& !_isMine(p)`),
   so parts of an answer the Owner closed are stored again.
6. **Screens reload on every part** - viewer `_changed` -> `_load()` -> `open()` (reads + decrypts all 400 parts
   each time); Conversations `_reload` -> `_load()` on every progress change. No "one at a time".

TECNO (kiran, in the same chat, holds the same big answer): most likely the same jam / memory, so the logs screen
never finishes. NOT VERIFIED (no TECNO log).

## Fix (smallest)
| # | Fix | File |
|---|---|---|
| F1 | `refreshProgress`: ONE acks read + ONE parts read, all counts in memory; max once per 1 s, one run at a time (late calls merged) | `chat_answer_carrier.dart` |
| F2 | Acks + stops kept in memory (loaded once, updated on save) - `takePart` / `_sendMissing` / `progressOf` read no table | `chat_answer_carrier.dart` |
| F3 | Sweep (start + every 6 h): acks / stops older than 7 days go, and those of answers no longer held | `hidden_store_221.dart`, `app_dependencies.dart` |
| F4 | Have frame sends the NEWEST 100 acks; on a peer's `have`, reply with the acks of the answers it lists (so the sender stops at once) | `chat_answer_carrier.dart` |
| F5 | Owner: a part of an answer it stopped is not stored; the stop is sent back (max once per 30 s per answer) | `chat_answer_carrier.dart` |
| F6 | Sender: the same part is not sent to the same phone again within 3 min | `chat_answer_carrier.dart` |
| F7 | Viewer: a complete answer is not re-read on progress; reloads merged (max once per 2 s, one at a time). Conversations the same | `admin_chat_viewer_screen.dart`, `admin_conversations_screen.dart` |
| F8 | Logs: `ADMIN_ANSWER_PARTS_SENT` + answer id (6) + to; `ADMIN_PROGRESS_SLOW ms=` over 500 ms | `chat_answer_carrier.dart` |

## Not changing
Sealing / SecurityPolicy, 8 MB carrier cap, 318 kept copy, 317 file trips, mesh voice, video (stopped).

## Tests
- F1: 300 acks + 400 parts -> one refresh = 2 store reads (counting fake store); 50 quick changes -> max 2 runs.
- F2: 400 parts in -> acks/stops table read once.
- F3: ack 8 days old goes, 6 days stays; ack of an answer still held stays.
- F4: 150 acks -> have frame carries the newest; a peer listing answer X gets ack X back.
- F5: closed answer part comes -> not stored, stop sent once.
- F6: second have within 3 min -> 0 parts sent again.
- F7: viewer with a complete answer + 20 progress ticks -> open() once.
- Regression: 221 / 316 / 317 / 318 carrier + viewer tests, full suite, Kotlin, analyze.

## Limits
- Parts already held stay until their own sweep; the first start after the update cleans old acks once (a few s).
- TECNO cause NOT VERIFIED until a TECNO log exists.

## As built (16 Nov, 3.0.110+181)
- **F1** `refreshProgress` = `MergedRun319` (1 s gap, one run, calls merged): ONE `acks()` + ONE `metas()` read, counted by the pure `ChatAnswerCarrier.countProgress` (same 317 rules: a stop is not "all here"; my held parts count). `progressOf` uses the same count. `ADMIN_PROGRESS_SLOW ms=` over 500 ms.
- **F2** `SqlAnswerPartStore`: acks + stops loaded once into memory, every save/stop updates the memory copy (still written to SQL). A load that raced a write is not kept (`_gen319`). Copies handed out (`Map.of` / `Set.of`).
- **F3** `AnswerPartStore.forgetOld(before, keep)` (SQL + memory) + `ChatAnswerCarrier.forgetOld()`: acks / stops older than 7 days go, EXCEPT answers whose parts are still held here. Runs in the start sweep + every 6 h (`sweepEvery318`). Log `ADMIN_ANSWER_ACKS_SWEPT rows=`.
  - Changed from the plan: stops of answers "no longer held" are NOT dropped early - that would let a closed answer flow in again (the 16 Nov flood).
- **F4** Have frame: newest 100 acks (`newestAcks`). On a peer's `have`: one `acks` frame back with the acks of its listed answers that tell it something (a stop/all, or parts it holds that are here).
- **F5** Owner: a part of an answer with MY stop (ack all + not every part) is not stored; the stop goes back to the sender (max once per 30 s per phone+answer; never to `server`). Log `ADMIN_ANSWER_STOP_BACK`. A server "all" ack (every part) does not block.
- **F6** `_sendMissing`: the same part to the same phone waits 3 min (`resendGap`); map pruned in the sweep / over 20,000.
- **F7** Viewer: progress ticks ignored once the view is complete; loads (first, ticks, 20 s poll) through `MergedRun319` (2 s). Conversations: `_reload` the same. Both `close()` in dispose. Direct `await _load()` calls (after a request) unchanged.
- **F8** `ADMIN_ANSWER_PARTS_SENT parts=N answer=<6>+<6> to=<6>`.
- Files: `chat_answer_carrier.dart`, `hidden_store_221.dart`, `admin_chat_viewer_screen.dart`, `admin_conversations_screen.dart`, `app_dependencies.dart` (1 line), `test/bundle319_test.dart` (14 tests). Backend unchanged.
