# G7 - Group photos, videos, voice notes and files with NO internet (+ typing + group photo)

Status: **DONE in code (2026-11-04) - all phases 1-11 finished.** Zip `locallink_app_G7_2026-11-04.zip`, apply steps + phone tests G7-1..G7-11 in `APPLY_G7.md`. Version 3.0.43+114, DB v33, no backend change. Full suite 1451 passed, analyze 0 errors, Kotlin compile clean. **Waiting: your push + phone tests.**
Base: app `94274a6` (3.0.42+113, groups G1-G6), backend `510c99b`.
Target version: **3.0.43+114**, phone DB **v33**. **No backend change.**

---

## 0. Your answers (2026-11-04)

| Question | Answer |
|---|---|
| What must work with no internet | Photos, videos, voice notes, documents **+ typing + group photo**, same as 1:1 chat |
| How the file goes | **The sender sends to each member** (like 1:1). On mesh it goes through other phones |
| Big files | **Same rules as 1:1 chat** |
| Group call | **Stays dropped** for now |

**One correction from me:** I said 1:1 has a "big file question". It does not (checked in code). The 1:1 rule is:
a file up to **50 MB** goes Nearby; a bigger one can't go Nearby (`MAX_DIRECT_FILE_SIZE = 50 MB` in
`DirectFileTransferPolicy.kt`) and goes when there is internet. Groups will use exactly this rule.

---

## 1. Why it does not work today (code-checked)

1. **Group Nearby packets carry words only.** `GroupNearbyService.fanOut(gid, id, body, createdAt)` sends only
   `body`. `GroupMessagingService._queue()` returns early when the body is empty, so a photo with no caption
   never goes Nearby at all; a photo with a caption sends only the caption.
2. **Group outbox waits for the server for files.** `flush()` uploads `pendingGroupAttachments` to the server;
   in a Nearby-only group it skips everything ("waits for the bridge").
3. **The file pipe is only connected for 1:1.** 1:1 uses `files.sendDirectFile(recipientId, messageId, fileId)`
   -> native `sendFileTransportInternal` (48 KB chunks, resume, sha256, goes over router / Wi-Fi Direct and
   through mesh). When a file arrives (`file_received`), `ReliableMessagingService` saves it and looks for the
   message only in **1:1** chats (`store.messagesFor(senderId)`), never in groups.
4. **Native keeps one transfer per file id** (`outgoingTransfers[fileId]`). Sending the same photo to a second
   member with the same id would **replace** the first transfer. Max **8** outgoing transfers at once,
   256 MB active bytes.
5. **Members who are not friends.** Through a phone that is not a friend (relay link) native only carries
   **locked** file packets (`sealed_f`). The file lock uses the **friend link key** (`linkKeys[target]`), which
   only friends have. So a non-friend group member can't get files this way today. Group words already work
   for non-friends because G3 locks them in Dart with the keys from the group card.
6. **Catch-up copies (mesh, G4) keep words only** (`group_copies` has `body`, signature `llgm1` covers body only).
7. **Typing** goes only through the server (`sendTyping`: `if (!socket.isConnected) return`).
   (1:1 has no typing line at all; groups got it in G5 for Online.)
8. **Group photo** in a Nearby-only group is refused on purpose: `setPhoto()` throws
   "The group photo can be set when Online." and the group card has no photo field.

---

## 2. What the user will see (no new screens)

Same look as the 1:1 chat and the 202 bubbles:

* **Sender:** the bubble shows at once (grid / voice / doc row) with the upload ring. The ring = how much of the
  file has reached the members that can be reached now. Ticks per member as today (✓, grey ✓✓ when **all**
  members got the message **and** its files, blue ✓✓ when all read).
* **Member:** the bubble shows at once with the **receiving ring per square** (202 key `chat_media_receiving`)
  and the size chip. When the file is in, the picture / voice / doc opens like 1:1.
* **File did not come** (sender went away, cancelled, 7 days passed): the square shows **"Tap to download"**
  (same as 1:1 bundle 174). Tap = ask the sender again (Nearby) or download from the server (if it is there).
* **Over 50 MB, no internet:** same as 1:1 - it does not go Nearby; the member sees the square with the size and
  it arrives when the sender has internet.
* **Typing:** "Sumaira is typing…" in the top bar and the blue line in Chats, also on Wi-Fi Direct / router / mesh.
* **Group photo:** an admin can set / remove it in a group made with no internet; members get it Nearby.

Mock: none (P4) - all states already exist in 202 / 174 / G5.

---

## 3. Design (how it works)

### 3.1 Message with files over Nearby
* The group Nearby message (`group_msg`) gets a new field **`att`**: list of
  `{id, name, type, size, sha256, img, w, h}` (same fields as the 1:1 `direct_message` attachments + sha256).
* Media-only messages (empty body) now go Nearby too (remove the "body empty -> return" rule for messages with files).
* Signature: messages with files use **`llgm2`** = `llgm1` text + a hash of the `att` list, so a phone in the middle
  can't change the file list. Messages without files keep `llgm1` (old phones still check them).

### 3.2 The file itself: one copy per member
* For every member that can be reached, the sender calls the native file send with a **per-member file id**:
  `wireId = <attachmentId>.<first 8 of member id>` (dot is allowed in native ids). This stops the "one transfer
  per id" clash (1.4). The member removes the `.xxxxxxxx` part to find its attachment.
* `messageId` = the group message id. Progress events (`file_progress`, `file_received`) already carry it.
* **Send queue** (new `GroupFileSender`, saved in DB table `group_file_sends`):
  one row per (message, file, member): status `waiting / sending / done / failed / too_big`, tries, last try.
  * Max **6** group transfers at once (leaves 2 of native's 8 for 1:1 chat).
  * Next one starts on `file_sent` / `file_failed` / `file_received`-ack, or when a member comes near
    (`peer_connected`, `route_recovered`, `relay_connected`).
  * Keep trying for **7 days** (same as the G3 member queue), then `failed` -> member sees "Tap to download".
  * Over 50 MB -> `too_big` (never tried Nearby; server path only, like 1:1).
  * Battery <= 10%: no new big sends (same rule as G4 catch-up); small voice notes (< 1 MB) still go.

### 3.3 Members who are not friends (native change)
* Each pair of phones already has keys in the group card (`seal` X25519 key per member).
* Dart works out a **pair file key** = HKDF(X25519(my seal key, their seal key), "llgfk1|<smaller id>|<bigger id>")
  plus a short key id, and gives it to native: new channel method **`setPeerFileKeys([{peer, kid, key}])`**
  (only for group members that are **not** friends; friends keep the link key).
* Native (`LocalLinkTransportService.kt` + `mesh/FileSeal.kt`):
  * `sealFilePayload()`: use `linkKeys[target]` first, else `peerFileKeys[target]`.
  * `handleIncomingSealedFile()`: match the key id against link keys, else peer file keys.
  * Keys kept in app-private storage like the link keys; cleared when the person leaves all shared groups or is blocked.
  * Blocked phones: nothing in, nothing out (same as today).
* Result: files to non-friend members are always **locked end to end** (also on a direct link), and relay
  phones can carry them (`sealed_f` is already allowed on relay links).

### 3.4 Member side (receiving)
* `group_msg` with `att` -> saved with attachments (no `local_path` yet) -> receiving ring.
* `file_received` -> new hook in `ReliableMessagingService` hands group files to `GroupMessagingService`
  (1:1 stays exactly as today): if the message id is a group message -> `setGroupAttachmentLocalPath()`
  -> bubble updates. If the file came **before** the message: keep it in `direct_files` (already used by 1:1)
  and attach it when the message comes.
* sha256 checked against the `att` list; wrong file = dropped + "Tap to download".
* Blocked sender: dropped (same as 1:1).

### 3.5 Mesh catch-up (G4) with files
* `group_copies` gets a new column `att` (JSON). Catch-up (`group_give`) sends the file list with the words.
* The member who got the words by catch-up but not the file asks the **sender** for it: new packet
  **`group_file_need {gid, id, file}`** (locked to the sender, max 5 asks per 10 min - same limit as 1:1
  `media_resend_request`). Only the sender sends files (your answer: no passing on by other members).

### 3.6 When the internet comes back (no double download)
* The server keeps the phone's own file id (checked: backend uses `X-Client-File-ID` as `files.id`), so the
  server copy of the message has the **same** attachment id. `saveGroupMessage` keeps an existing `local_path`
  (`COALESCE`) - a member who already has the file never downloads it again.
* **Upload rule (P1 = yes):** like 1:1 ("direct delivered" = no upload), the sender uploads a file to the
  server **only if at least one member still does not have it** (no `done` row for that member). Nearby-only
  groups upload nothing until the bridge; after the bridge the same rule applies.

### 3.7 Typing on Nearby
* `sendTyping()`: when the server is not reachable (or the group is Nearby-only), send `group_typing {gid, on}`
  to members with a live route, locked with the **live** lock (`sealed_x`: never queued, never stored), max one
  per 3 s (same as Online). Receiver uses the same `GroupTypingBook` (6 s timeout).

### 3.8 Group photo with no internet
* Group card gets `ph` = sha256 of the photo + photo version, signed by the admin (new card version).
* Photo bytes (<= 256 KB JPEG, the current limit) go to each member with the same file pipe:
  `wireId = gp.<photoHash first 12>.<member 8>`; member checks the hash against the card, then
  `GroupPhotoBook.put()`.
* Remove photo = card with empty `ph`.
* `setPhoto()` no longer refuses card groups: card first, server too when Online.
* Bridge: when the group goes on the server, the admin phone uploads the photo once.

### 3.9 Old phones (3.0.42)
* An old phone can't read `att` (it would show an empty bubble). So members get files Nearby **only after their
  phone says it can** (`fv: 2` in its `group_ack`; new phones send it). Old phones get files from the server as
  today. **All 3 test phones must have 3.0.43.**

---

## 4. Files to change (paths checked)

| File | Change |
|---|---|
| `lib/features/groups/data/services/group_nearby_service.dart` | `fanOut` with `att`; `llgm2` sign/check; copies with `att`; `group_file_need`; `group_typing`; card `ph`; `fv` in `group_ack` |
| `lib/features/groups/data/services/group_messaging_service.dart` | `_queue` passes attachments (no early return for media); start `GroupFileSender`; receive files; upload rule (3.6); `sendTyping` Nearby |
| **new** `lib/features/groups/data/group_file_sender.dart` | per-member send queue (3.2) |
| **new** `lib/features/groups/data/group_file_keys.dart` | pair file keys (3.3), push to native |
| `lib/features/messaging/data/services/reliable_messaging_service.dart` | `file_received` / `file_progress`: hand group files to the group hook; strip `.member` from wire ids; 1:1 path unchanged |
| `lib/features/connectivity/data/services/wifi_direct_transport_service.dart` + `peer_transport_contract.dart` | `setPeerFileKeys()` |
| `lib/features/connectivity/data/services/sealing_peer_transport.dart` | live lock option for `sendGroupLocked` (typing) |
| `lib/core/services/local_store.dart` + `lib/core/storage/database_config.dart` | DB v33: table `group_file_sends`, column `group_copies.att`, queries |
| `lib/core/models/group_card.dart` | `ph` field in card + signature |
| `lib/features/groups/data/repositories/group_repository.dart` | `setPhoto` for card groups |
| `lib/features/groups/data/group_photo_book.dart` | photo from Nearby (hash check) |
| `lib/features/groups/presentation/widgets/group_message_bubble.dart` | "Tap to download" for Nearby files that did not come; ring from Nearby progress |
| `android/.../LocalLinkTransportService.kt`, `mesh/FileSeal.kt`, `MainActivity.kt`, `BackgroundChannels.kt` | peer file keys (3.3) |
| `lib/app/local_link_app.dart`, `pubspec.yaml`, `test/nearby_190_test.dart` | version 3.0.43+114 |

Not touched: the 1:1 send path, `ChatComposer`, server code, the 202 widgets (only used).

---

## 5. Logs (for your phone logs)

`GROUP_FILE_QUEUED id= file= members=N`, `GROUP_FILE_SEND to=a1b2c3 size=`, `GROUP_FILE_DONE to=`,
`GROUP_FILE_FAILED to= reason=`, `GROUP_FILE_TOO_BIG size=`, `GROUP_FILE_RX from= id=`, `GROUP_FILE_BAD_HASH`,
`GROUP_FILE_NEED from= id=`, `GROUP_FILE_UPLOAD_SKIPPED all_have=y`, `GROUP_FILE_KEYS n=`,
`RELAY file open ... key=peer` (native), `GROUP_TYPING_NEARBY`, `GROUP_PHOTO_NEARBY v=`.

---

## 6. Tests (app)

1. `att` list in `group_msg`; media-only message goes Nearby; caption + photos together.
2. `llgm2`: changed file list -> refused; `llgm1` still accepted.
3. Per-member wire id: 3 members -> 3 sends with different ids; member strips the suffix correctly.
4. Queue: max 6 at once; next starts on `file_sent`; member comes near -> its rows start; 7 days -> failed.
5. Over 50 MB -> `too_big`, never sent Nearby; under 1 MB voice note still sent at 9% battery.
6. File before message / message before file -> both end with the picture.
7. Wrong sha256 -> dropped, "Tap to download".
8. Blocked sender's file dropped; blocked member gets no file.
9. Catch-up copy carries `att`; `group_file_need` -> sender re-sends; 6th ask in 10 min ignored.
10. Server copy later: same id, `local_path` kept, no second download.
11. Upload rule: all members `done` -> no upload (`GROUP_FILE_UPLOAD_SKIPPED`); one missing -> upload.
12. Old phone (no `fv:2`) -> no Nearby files for it.
13. Pair file key: both phones get the same key; friend members keep link keys.
14. Typing Nearby: live lock, max 1 per 3 s, gone after 6 s.
15. Group photo: card `ph` signed; wrong hash refused; remove works; non-admin can't.
16. 202 look unchanged: grid, rings per square, time on picture (existing 202 tests keep passing).
17. Kotlin: peer file key seal/open round trip (compile check + Dart-side tests; native is compile-checked only).

Full suite in parts + `flutter analyze` 0 errors + Kotlin compile check.

---

## 7. Phone tests (3 phones, all on 3.0.43, internet OFF unless said)

1. **G7-1 Photos Wi-Fi Direct:** Sajjad sends 5 photos + caption in "Family". Sumaira and Ali (Wi-Fi Direct)
   see the grid with rings, then the photos. Ticks grey ✓✓ after both have them.
2. **G7-2 Video + voice note + PDF:** same, router Wi-Fi without internet.
3. **G7-3 Mesh:** Ali two rooms away (only through Sumaira's phone). Ali gets the photo through mesh.
4. **G7-4 Not friends:** Ali is not Sajjad's friend (joined by QR). Ali still gets photos (locked).
5. **G7-5 Late member:** Ali's phone off. Send a photo. Turn Ali on 10 min later near Sumaira only, then near
   Sajjad: words come by catch-up, the photo comes from Sajjad.
6. **G7-6 Tap to download:** Sajjad leaves before the video finishes. Ali sees "Tap to download"; when Sajjad is
   back, tap -> it comes.
7. **G7-7 Big file:** send a 60 MB video with no internet: it does not go Nearby; turn internet on -> it arrives.
8. **G7-8 Internet back:** after G7-1 turn internet on: photos are **not** downloaded again; the log on Sajjad
   shows `GROUP_FILE_UPLOAD_SKIPPED`.
9. **G7-9 Typing:** Sumaira types; Sajjad sees "Sumaira is typing…" with no internet.
10. **G7-10 Group photo:** in a group made with no internet, Sajjad (admin) sets a photo; Sumaira and Ali see it.
11. **G7-11 1:1 still fine:** send a photo 1:1 on Wi-Fi Direct while a group video is sending - both arrive.

---

## 8. Risks

* **Data / battery on the sender:** a 20 MB video in a group of 6 = 100 MB out from one phone (your choice:
  sender sends to each). The 6-at-once cap and the battery rule keep the phone usable.
* **Wi-Fi Direct is slow with many transfers** - 1:1 media may wait a little while a big group send runs
  (2 slots kept for 1:1).
* **Native change (3.3)** can only be compile-checked here; real check = phone test G7-4.
* Old phones in a group get files only from the server (3.9).

---

## 9. Decisions (answered 2026-11-04: "follow your advice")

* **P1 = Yes.** No server upload when every member already got the file Nearby (same as 1:1, saves data).
  If at least one member is still missing it, the file is uploaded.
* **P2 = Yes.** Members on the old app (3.0.42) get files only from the server.
* **P3 = Yes.** Sender ring = progress to the members that can be reached now; ticks show the rest.
* **P4 = No mock.** No new screens; all looks already exist (202 rings / grid, 174 "Tap to download", G5 typing).

---

## 10. Order of work (one bundle G7, no stops)

1. DB v33 + `GroupFileSender` + wire ids + receive hook (friend members first - link keys already work).
2. Native peer file keys + Dart key push (non-friend members).
3. `llgm2` + catch-up `att` + `group_file_need`.
4. Upload rule + server-copy merge.
5. Typing Nearby.
6. Group photo Nearby.
7. Tests, analyze, Kotlin check, full suite, zip + `APPLY_G7.md`.

---

## 11. Progress and remaining work (updated 2026-11-04 - ALL DONE)

### 11.0 Final result
* Phases 1-11 all done (the plan in 11.3 below is kept as a record).
* Tests: `test/groups_g7_test.dart` = 39 new tests (file list + signatures, per-member ids, send queue, old-app
  member, P1 upload skip, battery rule, Tap to download watch, pair keys, receive path, file before message,
  wrong member / sender refused, sender keeps own copy, X / Tap to download hooks).
  Old test `message_delete_197_test` now allows v33 (group tables only, no message table change).
* Full suite: 146 files, **1451 passed** (1412 + 39). `flutter analyze`: 0 errors (only the old calls warnings).
  Kotlin compile check: clean (177 classes).
* **Known limits (by design):**
  * no sha256 in the file list - the native file engine checks the file itself; the group photo IS checked by hash;
  * the sender's copy is kept after the server takes the message (same as 1:1);
  * old-app (3.0.42) members get files from the server only (P2); a photo with no caption shows on an old phone
    only after the server copy comes.
* **Compile-checked only (real check = phone tests G7-1..G7-11):** native file lock with group keys, Wi-Fi Direct /
  mesh file sending, typing over mesh, group photo note.


### 11.1 Done so far
* **Code reading (all of it):** group send / outbox / server accept, Nearby service (send, receive, catch-up),
  1:1 file pipe (send, receive, Tap to download, X), native file sending + file lock, DB tables, group photo, wiring.
* **1 new file written (not compiled, not tested yet):** `lib/features/groups/data/group_nearby_files.dart` (658 lines)
  * file list format + checks (max 10 files, 50 MB each);
  * per-member file ids;
  * `GroupFileSender`: per-member queue, 6 at once, retry 15 s ... 15 min, 7 days, Tap to download limit 5 per 10 min,
    "everyone has it" check for P1;
  * `GroupFileWatch`: shows "Tap to download" when nothing moved for 3 min;
  * `GroupPairFileKeys`: lock keys for non-friend members.
  * Safe copy: `/home/user/g7_wip/lib/features/groups/data/group_nearby_files.dart`
* **No other file changed.** Nothing zipped, nothing in git.

### 11.2 Things found in the code that change the plan a little
1. **The sender can't see their own group photo until the server takes it.** Today group send keeps no copy and saves
   the message without its files. G7 must copy the file to app storage at send time (`stageOutgoingFile`, same as 1:1)
   and save the message **with** its files, so the sender sees the photo + ring at once (also fixes Online groups).
2. **When the server accepts the message, today's code deletes the sender's copy.** G7 must keep it (Nearby sends may
   still be running, and 1:1 keeps it too).
3. **`send()` queues the message before it adds the files.** It must add the files first, then queue.
4. **The bubble never shows the receiving ring / Tap to download in groups** (`_arrivingDirect` says "no" for every
   group message). One line to change.
5. **Tap to download and X work only for 1:1.** Two small group hooks are needed in `ReliableMessagingService`.
6. **Old phones (3.0.42):** the message gets **two signatures**: the old one over the text, the new one over text + files.
   So an old phone still shows the caption (files come from the server, P2). A photo with no caption is not shown on
   an old phone until the server copy comes.
7. **Group photo (section 3.8 changed):** a separate **signed photo note** from the admin (`group_photo`) instead of
   a new field in the group card. Same result for you, but the group card and its signature stay untouched (less risk
   for G3-G6).
8. **Native change is smaller than planned:** the existing key check already accepts a key that has the same id on both
   phones, so native only needs a second key list used **only for file locks** (link checks stay untouched).
9. **Typing on stranger phones:** checked - relay links already carry the live lock (`sealed_x`), so typing can go
   through mesh too.

### 11.3 Remaining work in phases

**Phase 1 - Database (DB v33)**
* `database_config.dart`: version 33.
* `local_store.dart`: `_upgradeTo33`:
  * `group_copies` gets columns `att` + `sig2`;
  * new table `group_file_sends` (message, file, member, group, status, tries, next try, created);
  * call it from the new-install path too.
* Store functions for `group_file_sends` (add, list, update, clean after 7 days) behind a small seam (tests use the
  memory version that is already written).
* `GroupCopy`: add `att` + `sig2`.
* Update the 2 old tests that check "version 32".

**Phase 2 - Sending a group message with files**
* `group_messaging_service.send()`:
  * copy each file to app storage;
  * add the files first, then queue;
  * save the message with its files (sender sees the photo + ring at once).
* `_queue()`: no early return for photo-only messages; pass the file list to Nearby (only files up to 50 MB).
* Server accept: keep the sender's copy (no delete).
* Add sha256 to the file list (TODO test 7).
* Battery 10% or less: no new big sends; voice notes under 1 MB still go (section 3.2).

**Phase 3 - Nearby service (`group_nearby_service.dart`)**
* `fanOut` sends the file list + old signature (text) + new signature (`llgm2`, text + files).
* `_onMessage` / `_onGive`: accept photo-only messages with a valid new signature; refuse a changed file list.
* Catch-up copies keep the file list and pass it on.
* Every "got it" says `fv: 2`. A "got it" starts that member's files; no `fv` = old phone = server only.
* Native file events go to the sender queue; a member coming near starts its waiting files.
* New packet `group_file_need` (Tap to download -> ask the sender).

**Phase 4 - Receiving files**
* `reliable_messaging_service.dart`: after the file is saved and locked, a group file goes to the group code
  (1:1 path stays as it is).
* Group code:
  * removes the member part of the id and checks the file is for me;
  * sets the file on the message and refreshes the bubble;
  * file before message: picked up when the message comes;
  * message without that file yet: adds it;
  * wrong hash: dropped, then Tap to download.
* Bubble (`attachment_tile.dart`): receiving ring + Tap to download also in groups.
* Group hooks for Tap to download and X.
* `GroupFileWatch`: 3 min with no movement = Tap to download.

**Phase 5 - Members who are not friends (native + Dart)**
* Kotlin `LocalLinkTransportService.kt`:
  * a second key list (`peerFileKeys`), kept in the locked app storage;
  * used for file lock / unlock only when there is no friend key;
  * cleared on block.
* `MainActivity.kt` + `BackgroundChannels.kt`: new method `updatePeerFileKeys`.
* Dart:
  * `WifiDirectTransportService.updatePeerFileKeys`;
  * `SealingPeerTransport.pushPeerFileKeys`;
  * `GroupPairFileKeys` pushes the keys when groups change and before sending.

**Phase 6 - Internet comes back (P1)**
* `flush()`: if every other member already has every file -> no upload (`GROUP_FILE_UPLOAD_SKIPPED`):
  * photo only: the message is not posted;
  * with words: words only.
* Otherwise upload as today. Same file id on the server, so members who already have the file don't download it again.

**Phase 7 - Typing with no internet**
* `sendTyping()`:
  * server when connected and the group is on the server;
  * otherwise `group_typing` to each member with the live lock (never stored).
* Receiver uses the same typing line (6 s).
* `sealing_peer_transport.sendGroupLocked`: live lock for `group_typing`.

**Phase 8 - Group photo with no internet**
* `group_repository.setPhoto()`:
  * a group made with no internet: admins (or everyone if "Edit info = all") can set / remove;
  * saved on the phone, signed photo note to each member, picture through the same file pipe.
* Member:
  * checks signature, admin and hash;
  * only a newer version wins;
  * then `GroupPhotoBook.put` + refresh.
* When the group goes on the server: the admin phone uploads the photo once.

**Phase 9 - Wiring + version**
* `app_dependencies.dart`: create the file sender, watch and pair keys; connect them to the Nearby service, group
  messaging and the 1:1 file hook.
* Version **3.0.43+114** (`pubspec.yaml`, `local_link_app.dart`, `test/nearby_190_test.dart`).

**Phase 10 - Checks**
* New `test/groups_g7_test.dart` (the 17 tests in section 6).
* Full suite in parts of 8 (about 1430 tests); fix anything broken.
* `flutter analyze` 0 errors; Kotlin compile check (`kcheck.sh`).
* Audio / Wi-Fi Direct / native file lock: compile-checked only; the real check is the phone tests.

**Phase 11 - Delivery**
* App zip `locallink_app_G7_<date>.zip` (separate from everything else, no backend zip).
* `APPLY_G7.md` with phone tests G7-1 ... G7-11, commit message and PowerShell commands.

### 11.4 Size
About **14 files changed + 2 new + 1 test file**; Phases 2-4 are the biggest. Native change: about 40 lines.

### 11.5 Still waiting from you
* Freeze: say **"go ahead G7"** to continue from Phase 1.
* Points 11.2-6 (old phones, two signatures) and 11.2-7 (group photo as a note, not in the card) are my advice;
  say if you want them different.
* Earlier phone tests still open: 202, groups (`APPLY_groups.md`), 201, 200, 199b.
