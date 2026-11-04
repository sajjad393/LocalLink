# APPLY 209 - group members pass group files on (no internet)

Version **3.0.50+121**, database **v34** (adds one column `group_copies.sig3`; nothing else changes).
No Kotlin change. No backend change. Plan: `TODO_209.md`.

## What changed (simple)

Ali sends a photo in a Nearby group. Bilal gets it. Alex was away. Later Alex meets **Bilal**
(Ali is not there): Alex's phone asks Bilal, Bilal's phone sends the photo, Alex's phone checks
the photo's fingerprint against the one Ali signed. Wrong fingerprint = the file is thrown away.
Then Alex's phone tells Ali "I have it", so Ali doesn't send it again and gets ✓✓.

Rules (your choice): any member who has the file; files up to 50 MB from the last 7 days;
a phone at battery 10% or less passes nothing; only files sent after this update.

| Phase | What |
|---|---|
| A | Sender makes the file's sha256 (background, Nearby groups only) and signs it with the message (`llgm3` / `sig3`); old phones still check `sig2` |
| B | Receiver keeps the signed sha; takes a file from **any** member only if the sha matches (`GROUP_FILE_BAD_HASH` otherwise); early files checked too |
| C | Writer away -> ask one member who is near (`group_file_ask`), same member at most every 10 min; AutoFetch + Tap to download |
| D | Helper checks message / own copy / sha / 50 MB / 7 days / battery / 5 asks per 10 min, max 2 passes at once, 2 tries (memory only) |
| E | `group_ack` carries `fh` (files I have) -> the writer marks them done, no resend, ✓✓ |
| F | Version, tests, this file |

## Logs to look for

- Asker (C): `AUTO_DL_ASK ... way=group via=member`, `GROUP_FILE_ASK to=...`
- Helper (D): `GROUP_FILE_RELAY_SEND to=... writer=...` or `GROUP_FILE_RELAY_SKIP why=battery|no_copy|no_sha|old|big|rate|busy|no_msg|writer`
- Asker got it (B): `GROUP_FILE_RX msg=... from=relay`, then `GROUP_FILE_HAVE to=<writer>`
- Bad file (B): `GROUP_FILE_BAD_HASH`, `GROUP_FILE_RX_REFUSED why=not_writer|early_unchecked`
- Writer (E): `GROUP_FILE_HAS member=... files=...`

## Phone tests 209 (3 phones: A = sender, B = helper, C = late member)

All 3 in one Nearby group; mobile data + Wi-Fi internet OFF. All 3 phones on 3.0.50.

| # | Steps | Expected | Result |
|---|---|---|---|
| 209-1 | A sends a photo; B near gets it; C far. A goes away, C comes near B | C gets the photo from B in ~1-2 min (logs above) | |
| 209-2 | After 209-1, A meets C | A does NOT send it again; A's bubble ✓✓; log A `GROUP_FILE_HAS` | |
| 209-3 | Same as 209-1 with a 20-40 MB video | Arrives, ring moves, plays | |
| 209-4 | B battery 10% or less | B passes nothing (`why=battery`); C keeps "Waiting for A" | |
| 209-5 | A file sent before updating to 209 | Not passed on (`why=no_sha`); comes only from A (like 208) | |
| 209-6 | Message older than 7 days | Not passed on (`why=old`) | |
| 209-7 | B deleted its copy | `why=no_copy`; C waits for A | |
| 209-8 | A and B both near C at the same time | C gets it once; no crash | |
| 209-9 | C taps "Tap to download" while A away, B near | B sends it | |
| 209-10 | B still on 208 | C asks, B silent; C gets it from A later | |
| 209-11 | Restart C in the middle of a pass | C asks again after restart and gets it | |
| 209-12 | 1:1 photo + normal group send with A near | Same as 208 | |

Honest limits: passing only while the app runs; two phones never split one file (one waits);
a 50 MB fingerprint takes ~1-3 s on the ZTE when sending (background, screen does not freeze);
battery rule is literal (10% or less = no passing, even while charging).

## Tests here (no phone)

RESULT: full `flutter test` **1706/1706 pass** (208: 1654; +52 new in `bundle209a..e_test.dart`).
`flutter analyze`: **166** (same as 208). Updated scans: DB version 34 (`db_v27_197b`, `read_receipt_store_198`,
`message_delete_197`), early file test row has `sender_id` (`groups_g7`), version scan (`nearby_190`).
New test helper: `test/support/g209_fakes.dart`.
