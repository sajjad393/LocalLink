# TODO 229 (= audit S1) - size limits on nearby socket lines

- **Version:** 3.0.68+139.
- **Scope:** app only, **Kotlin only** (+ version pins). No backend, no database, no UI, no new permission.
- **Source:** `AUDIT_REPORT.md` F6, `TODO_AUDIT.md` S1. The user gave the go ahead on 2026-11-09.

## Problem (confirmed in code)
- `LocalLinkTransportService.kt` read every nearby socket line (LAN, Wi-Fi Direct, hotspot / local net) with `BufferedReader.readLine()`. That keeps one line in memory however long it is.
- The read loop already threw away lines over 256 KB, but only **after** the whole line was in memory.
- Anyone on the same router, or in the Wi-Fi Direct group (its password is in the tag on purpose), could send one endless line and run a small phone (ZTE 2 GB) out of memory.
- Each incoming connection got its own thread and could hang in the handshake for 15 s. There was no limit on how many could do that at once.

## Changes
1. **NEW `mesh/LineLimits.kt`**
   - `LineLimits`:
     - `HANDSHAKE_MAX_CHARS = 64K` (real handshake lines are <2 KB);
     - `DATA_KEEP_MAX_CHARS = 256K` (the same number the loop already used);
     - `DATA_HARD_MAX_CHARS = 8M`;
     - `MAX_PENDING_HANDSHAKES = 24`;
     - `handshakeAllowed(n)`.
   - `BoundedLineReader`:
     - reads lines exactly like `BufferedReader.readLine()` (`\n`, `\r`, `\r\n`; the last line without an end is returned; `null` = end);
     - lines longer than keepMax are **skipped without being kept** (returns "" + `droppedLast`);
     - past hardMax it throws `LineTooLongException`;
     - a read timeout keeps the part already read.
2. **`LocalLinkTransportService.kt`**
   - Both handshake readers → `BoundedLineReader`. The 4 handshake reads use `readLine(LineLimits.HANDSHAKE_MAX_CHARS)`.
   - Read loop:
     - uses `readLine(DATA_KEEP_MAX_CHARS, DATA_HARD_MAX_CHARS)`;
     - a skipped line → `noteVideoDrop("wire_line_over_256k"); continue` (**same as before**);
     - the old `line.length > 256 * 1024` check stays.
   - New `catch (LineTooLongException)` in the read loop: `exitCause = "line_too_long"` + log `LINE_TOO_LONG peer=<8> side=data max=…`.
   - `PeerConnection.reader` type → `BoundedLineReader`.
   - `handleIncomingTransportSafe`:
     - a counter of handshakes in progress; above 24 the new socket is closed at once;
     - log `HANDSHAKES_FULL transport=… max=24` (at most once a minute);
     - a too-long handshake line → log `LINE_TOO_LONG peer=? side=hs`.
     - **Working links are not counted.**
3. **Version** 3.0.68+139: `pubspec.yaml`, `lib/core/config/app_build.dart`, plus the version pins in `test/bundle223_logs_test.dart` and `test/nearby_190_test.dart` (as every bump).

## Not changed (on purpose)
- Real traffic: video packets ≤200 KB, file chunks 48 KB and admin parts <64 KB are all kept as before. Lines over 256 KB were dropped before too.
- The outgoing side (this phone dialling) is not limited by the counter.
- Strict link mode, relay budgets, the UDP discovery: unchanged.

## Tests
- NEW `android/app/src/test/kotlin/com/sajjad/locallink/mesh/Line229Test.kt` (16 tests):
  - line endings with buffers of 1/2/3/8192;
  - `\r\n` split across chunks;
  - exactly max kept; max+1 skipped and the next line still read;
  - a skipped line at the end of the stream; past hardMax throws; the handshake limit;
  - an endless line stopped; a 200 KB video line kept; over 256 KB dropped like before;
  - Urdu UTF-8 arriving one byte at a time;
  - a timeout in the middle of a line keeps it;
  - the handshake gate; the limits; a source check that the service uses the limits everywhere.
- Old tests unchanged (only the version pins, as every bump).
- **Checks run:**
  - all Kotlin unit tests: **447 OK** (431 old + 16 new);
  - the 18 Dart test files that read the Kotlin service or the version: **219 OK**;
  - full Flutter suite (10 chunks): **2355 passed, 0 failed**.
  - All 106 strings that the Dart source-scan tests look for in the service are still present.
