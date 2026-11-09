# TODO 209: group members pass group files to each other

**Status: PLAN ONLY. Nothing is built yet. To build it, reply "go ahead 209".**
Base: bundle 208 code (3.0.49+120). Bundle 208 must be pushed first.
Target: **3.0.50+121**, database **v34**.

---

## 0. What it does (example)

Ali sends a photo in the group "Family" with no internet. Bilal is near Ali and gets it.
Alex was away. Later Alex meets **Bilal**, but Ali isn't there.

- **Now (208):** Alex sees "Waiting for Ali" until Ali comes back.
- **After 209:** Alex's phone asks Bilal. Bilal's phone sends the photo. Alex's phone checks its
  fingerprint (sha256) against the one Ali signed. If it matches, the photo opens. If not, it is deleted.
- Later, when Ali meets Alex, Ali's phone learns that Alex already has the photo. Ali doesn't send it
  again and gets ✓✓.

**Your rules (2026-11-05):**
| Rule | Value |
|---|---|
| Who passes | Any member who has the file |
| Which files | ≤ 50 MB, sent in the last 7 days |
| Battery | A phone at ≤ 10 % never passes a file on |
| Old files | Only files sent **after** 209 (they have the signed fingerprint) |
| Replaces | "Only the sender sends a group file" |

No new screens or buttons. The ring and "Waiting for {name}" stay as they are now.

---

## 1. What the code does today (checked in the 208 code)

| # | Place | Today | 209 change |
|---|---|---|---|
| 1 | `group_nearby_files.dart` `GroupNearbyFile` | id / name / type / size only; `toAttachment` sets `sha256: ''` | add `sha` (64 hex) and pass it to `Attachment.sha256` |
| 2 | `GroupFileWire.messageText2` (`llgm2`) | signs words + `[id,name,type,size]` | keep for old phones; add `llgm3` = words + `[id,name,type,size,sha]` |
| 3 | `group_nearby_service.dart` `fanOut` (~521) | signs `sig` + `sig2` | also signs `sig3`; payload gets `'sig3'`, `att` entries get `sha` |
| 4 | `group_messaging_service.dart` `sendMessage` (~850) | no fingerprint | compute sha256 of the plain file once, before staging (in a background isolate, streaming, ≤ 50 MB) |
| 5 | `_onMessage` (~1004) | checks `sig2` | checks `sig3` when present → saves the sha; if `sig3` is bad → no sha (still shows the message by `sig2`) |
| 6 | Catch-up give `'s2'` (~1767) / apply (~1801) | `att` + `s2` | add `'s3'`; apply checks it the same way |
| 7 | `group_copies` table (DB v33: att, sig2) | no sig3 | **DB v34:** `ALTER TABLE group_copies ADD COLUMN sig3` |
| 8 | `receiveNearbyFile` (~158) | **refuses any file whose sender is not the writer (`not_writer`)** | accept from any card member **only if** the native sha256 == the signed sha; otherwise delete it + `GROUP_FILE_BAD_HASH` |
| 9 | `_withEarlyFiles` (~125) | attaches an early file with **no check** | attach only if the early file's sender == writer OR its sha == the signed sha |
| 10 | `requestFileAgain` (~229) + AutoFetch `_nearby` (~370) | ask **only the writer**, only when the writer is near | writer first; if the writer isn't near → ask one near member (new `group_file_ask`) |
| 11 | `handlePacket` switch (~800) | no ask type | add `group_file_ask` → `_onFileAsk` |
| 12 | `GroupFileSender` | sender rows only (DB table) | a 2nd sender ("relay") with **memory-only** rows, max 2 at a time |
| 13 | `_onAck` / `memberGot` | "got it" → row `ready` → the writer sends | new `fh` (files I have) in the ack → those rows go `done` (no resend, ✓✓) |

**Checked and OK, no change needed:**
- **Native file keys:** `GroupPairFileKeys` makes a key for **every member of my Nearby groups**, so a Bilal → Alex file can be locked and opened even when they are not friends.
- **Native sha check:** the receiver checks the whole file against the sha256 in the header, and `file_received` gives `sha256` to Dart (`reliable_messaging_service.dart` ~2496 → `onGroupFile`).
- **Two phones send the same file:** the native transfer id = the wire id (`<fileId>.g<tag of the receiver>`), the same from Ali and from Bilal. While one is sending, the other phone's pieces are ignored (`senderId` check). When it is done, a `.done_<id>_<sha>` marker on disk makes the native layer answer "all received" to the other sender. Nothing breaks; at most a few pieces are wasted.
- **Source of the bytes:** `fileSource(msgId, fileId)` already opens a **received** copy too (the attachment's `localPath` → plain copy), so Bilal can send what he got.
- **Mesh:** the relay uses the same `sendFile` road, so it works over a live mesh chain too (same limits as now).
- **Old phones:** a 208 phone never sends `group_file_ask` and ignores it (the switch has no default). A 208 sender adds no sha, so its files are not passed on. Mixed groups keep working as in 208.

**No Kotlin change. No backend change.**

---

## 2. Phases

Delivery rule (same as 207 / 208): one zip after each phase, then the next phase starts by itself.

### Phase A: fingerprint in the signed file list
1. `GroupNearbyFile`: add `final String sha` (default `''`).
   - `toJson` adds `'sha'` only when it isn't empty, so old phones' `fromJson` ignores it.
   - `fromJson` takes it only if it is 64 lowercase hex.
   - `fromAttachment` copies `a.sha256` when it is 64 hex.
   - `toAttachment` sets `sha256: sha`.
2. `GroupFileWire`: add `canonical3(files)` = JSON `[id,name,type,size,sha]` and `messageText3(...)` = `'llgm3\n…'`. Keep `messageText2` unchanged.
3. `sendMessage`: before staging each file, run `GroupFileHash.ofFile(path)` (new, `lib/features/groups/data/group_file_hash.dart`).
   - `Isolate.run` + `sha256.bind(File.openRead())`.
   - Skip files > 50 MB.
   - If it fails → `''`, so that file won't be passed on (no crash).
4. `fanOut`: sign `sig3` when every file has a sha; payload `'sig3'`; `_keepCopy(..., sig3:)`.
5. `GroupCopy` + `group_nearby_store.dart` + `local_store.dart`: add the `sig3` field / column.
   - `DatabaseConfig.version = 34`.
   - `_upgradeTo34` only adds the `group_copies.sig3` column (no table changes).
6. Tests (`test/bundle209a_test.dart`):
   - toJson / fromJson round trip;
   - the old parser ignores `sha`;
   - `llgm3` text;
   - the hash of a file equals `sha256` of its bytes;
   - `fanOut` payload has `sig2` + `sig3`;
   - DB v34 scan.
   - **Update scans:**
     - `db_v27_197b_test.dart:14`, `read_receipt_store_198_test.dart:18` → 34;
     - `message_delete_197_test.dart` ~355 `isNot(contains('_upgradeTo34'))` → v34 adds only a `group_copies` column, no `messages`;
     - `groups_g7_test.dart:952` stays.

### Phase B: receiver keeps the signed fingerprint and checks it
1. `_onMessage` and catch-up apply: if `sig3` / `s3` is valid for the same writer → save the attachments with `sha256 = sha` (the `group_message_attachments.sha256` column already exists). Otherwise use the 208 path (no sha).
2. Catch-up give: send `'s3'` from the copy row.
3. `receiveNearbyFile`:
   - `sender == writer` → as today. If the signed sha exists and the native sha differs → refuse (`bad_hash`).
   - `sender != writer`: the sender must be in the card, the signed sha must not be empty, and the native sha must equal it → accept (`GROUP_FILE_RX from=relay`).
     Otherwise delete the file, clear the `direct_files` row, log `GROUP_FILE_BAD_HASH` / `why=not_writer`, return true.
   - "Add an unknown file from an old copy": **only when sender == writer** (a relay can't add files).
4. `_withEarlyFiles`: attach an early file only if `direct_files.sender_id == writer` or `direct_files.sha256 == a.sha256` (not empty). Otherwise delete it + log.
5. Tests (`test/bundle209b_test.dart`):
   - a relay file with a good sha is accepted;
   - a bad sha is refused and deleted;
   - a relay without a signed sha is refused (the existing test "a file … from someone else is refused" must still pass);
   - an early relay file is checked;
   - a relay can't add an unknown file;
   - a bad `s3` → no sha.

### Phase C: asking a member (receiver side)
1. New packet `group_file_ask {gid, id, file, sha}` (`GroupNearbyService.sendFileAsk`, not kept, best effort).
2. `GroupMessagingService.requestFileFrom(messageId, fileId, peer)`.
   - Checks: peer in the card, peer != me, peer != writer, the attachment has a sha, ≤ 50 MB, message ≤ 7 days old.
   - Then: `allowIncomingFile(wireId)`, send the ask, `fileWatch.expect`.
3. `requestFileAgain` (tap / auto):
   - writer near → ask the writer (as today);
   - else → `pickHelper(gid, writer, fileKey)`: the first member who is near (PresenceHub) and not yet asked for this file in the last 10 min → `requestFileFrom`.
4. AutoFetch `_nearby` (208):
   - a group file where the writer is not near but `seen` is a near group member → call the new `askOther(f, seen)` callback. It uses the same 2 min `askGap` and the same `AUTO_DL_ASK` log, plus `via=member`.
   - Wire `askOther` in `app_dependencies.dart`.
5. Tests (`test/bundle209c_test.dart`):
   - the writer away + a member near → the ask goes to the member;
   - the writer near → the writer is asked;
   - each member is asked at most once per 10 min;
   - no sha / > 50 MB / > 7 days → no ask;
   - the AutoFetch source-scan string.

### Phase D: passing the file (helper side)
1. `_onFileAsk(from, gid, p)` checks, in order. The skip reason is logged as `GROUP_FILE_RELAY_SKIP why=…`:
   - the card has me + them, and the key is OK;
   - `battery` → my battery ≤ 10 % (same helper as `lowBattery`: `wifiDirectFallback.batteryLevel` 0–10);
   - `no_msg` → I don't have the message;
   - `writer` → the asker is the writer;
   - `no_copy` → the attachment has no `localPath`;
   - `no_sha` → it has no sha, or the sha differs from the ask;
   - `big` → > 50 MB;
   - `old` → > 7 days;
   - `rate` → more than 5 asks per asker per 10 min;
   - `busy` → 2 passes are already running.
   - If I am the writer → the 208 `files.need(...)` path.
2. New `relayFiles = GroupFileSender(store: MemoryGroupFileSendStore(), …)`.
   - Same `source` / `sendFile` / `beforeSend`.
   - **Max 2 active, at most 2 tries.** Rows live in memory only; after a restart Alex asks again.
   - Add `maxActive` / `maxTries` constructor options (the defaults stay 6 / unlimited for the writer).
3. `GroupNearbyService.handleEvent` (~755): `mine = await files?.handleEvent(e) ?? false; if (!mine) mine = await relayFiles?.handleEvent(e) ?? false;`
4. Logs: `GROUP_FILE_RELAY_SEND to=… file=…`, `GROUP_FILE_RELAY_DONE`, `GROUP_FILE_RELAY_FAILED`.
5. Tests (`test/bundle209d_test.dart`):
   - each skip reason;
   - a good ask → the relay row is sent with wire `wireId(file, asker)`;
   - file_sent → done;
   - at most 2 at once;
   - battery 10 % → nothing.

### Phase E: the writer learns "Alex already has it" (✓✓, no resend)
1. When a file is saved from a relay, Alex sends `group_ack {gid, ref: msgId, fv: 3, fh: [fileId…]}` to the writer (best effort).
   Every later ack for that message also carries `fh` (the catch-up / message receive acks), so a lost ack is fixed the next time.
2. `_onAck` → `files.memberGot(from, ref, fv, have: fh)`: rows for those files in `wait` / `ready` (and `sending` older than 10 min) → `done` + `onChanged` (✓✓ refresh).
3. If the note never arrives: Ali sends one piece, Alex's native layer answers "all received" (`.done_` marker), and the row is done. Nothing extra is needed.
4. Tests (`test/bundle209e_test.dart`):
   - `fh` marks rows done;
   - `allDelivered` turns true;
   - an old ack without `fh` works as in 208;
   - `fh` with an unknown file id is ignored.

### Phase F: finish
1. Version 3.0.50+121 (+ the `nearby_190` version scan).
2. Full `flutter test` in chunks; analyze must stay at 166.
3. `APPLY_209.md` (phone tests below), PENDING.md update, final zip.

---

## 3. Files that will change

| File | Phases |
|---|---|
| `lib/features/groups/data/group_nearby_files.dart` | A, D, E |
| `lib/features/groups/data/group_file_hash.dart` (new) | A |
| `lib/features/groups/data/services/group_nearby_service.dart` | A, B, C, D, E |
| `lib/features/groups/data/services/group_messaging_service.dart` | A, B, C |
| `lib/features/groups/data/services/group_nearby_store.dart` | A |
| `lib/core/services/local_store.dart` | A (v34) |
| `lib/core/storage/database_config.dart` | A |
| `lib/features/files/data/services/auto_fetch_service.dart` | C |
| `lib/app/app_dependencies.dart` | C, D |
| `pubspec.yaml` | F |
| `test/bundle209a..e_test.dart` (new) + 3 scan updates | A–E |

---

## 4. Phone tests (209-x) — 3 phones (A = sender, B = helper, C = late member)

Before each test: all 3 in one Nearby group, mobile data + Wi-Fi internet OFF.

| # | Steps | Expected |
|---|---|---|
| 209-1 | A sends a photo; B is near and gets it; C is far away. Then A goes away, and C comes near B | C gets the photo from B in ~1–2 min. Log C: `AUTO_DL_ASK … via=member`, `GROUP_FILE_RX from=relay`. Log B: `GROUP_FILE_RELAY_SEND` |
| 209-2 | After 209-1, A meets C | A doesn't send it again; A's bubble shows ✓✓. Log A: `GROUP_FILE_READY`/done with `fh` |
| 209-3 | Same as 209-1 with a 20–40 MB video | It arrives; the ring moves; it plays |
| 209-4 | B's battery ≤ 10 % | B doesn't pass it on. Log B: `GROUP_FILE_RELAY_SKIP why=battery`. C keeps "Waiting for A" |
| 209-5 | A file sent before updating to 209 | Not passed on (`why=no_sha`); it comes only from A, as in 208 |
| 209-6 | A message older than 7 days | Not passed on (`why=old`) |
| 209-7 | B deleted its copy of the photo | `why=no_copy`; C waits for A |
| 209-8 | A and B both near C at the same time | C gets it once; nothing crashes; the second sender ends with "done" |
| 209-9 | C taps "Tap to download" while A is away and B is near | B sends it |
| 209-10 | Mixed: B still on 208 | C asks, B stays silent; C gets it from A later (as in 208) |
| 209-11 | Restart C in the middle of a pass | After the restart, C asks again and gets the file |
| 209-12 | 1:1 photo + normal group send with A near | Works exactly as in 208 |

---

## 5. Risks and limits (honest)

- **Two senders at the same moment:** one of them waits (pieces ignored). It finishes with "all received". A file isn't **split** between two phones; that would need a Kotlin change, which isn't planned.
- **CPU on old phones:** the fingerprint of a 50 MB file takes ~1–3 s on ZTE when sending (background isolate, the UI doesn't freeze).
- **Pass-only-while-the-app-runs:** like 208 auto-download.
- **Battery ≤ 10 %:** follows your rule literally, even while charging (same as the current `lowBattery`). Say so if charging phones should still pass.
- **Server sha:** a message that came only from the server may have a server sha that isn't the plain-file sha. Then a pass fails the check and is deleted safely, and the file comes from the server or the writer as now.
- **Privacy:** B can only send what B already has and can open. C checks Ali's signature, so B can't swap the file.

---

## 6. Order to run

1. You push 208 and run phone tests 207 / 208.
2. You reply **"go ahead 209"**.
3. I build phases A → F (one zip each, then the final zip).
