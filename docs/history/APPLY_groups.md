# Groups G1-G6 on top of bundle 202 - 3.0.42+113

All group phases in one app zip + one backend zip. Built on **201 (`b8edf97`) + the 202 zip**.
Group voice call is not included (you dropped it).

| Zip | What | Order |
|---|---|---|
| `LocalLinkBackend_groupsG2-G6_2026-11-04.zip` | server: G2 admin/info, G3 phone-made ids + bridge, G5 receipts, G6 link + sender-key notes (12 files) | **1st - deploy the server** |
| `locallink_app_fixes202_2026-11-04.zip` | bundle 202 (no group code) | 2nd |
| `locallink_app_groups_2026-11-04.zip` | groups G1-G6 merged with 202 | 3rd |

Phone database: v32. The server must be deployed first: the old server does not know the new group calls
(info, roles, photo, receipts, invite link).

## What is in it

* **G1** look + basics: New group (3 steps, friends only), group chat like the mock (names, photo column,
  "Admin"/"Owner", same message box as 1:1, voice notes, reactions, reply, swipe, zoom, delete for everyone).
* **G2** admin + info: Group info screen, member sheet, make admin, remove, Exit group (owner hand-over),
  name / description / photo, system lines, "You're no longer a participant" + Delete group.
* **G3** Nearby group (router + Wi-Fi Direct): phone-made group id, signed group card, locked per-member
  packets, 7-day per-member queue, the maker bridges to the server.
* **G4** mesh catch-up + **Join with QR** (+ "Approve new members").
* **G5** ticks per member (✓ / grey ✓✓ all got it / blue ✓✓ all read), Message info, typing,
  @mentions (@all = admins), media strip + page.
* **G5b** pin (admins only; 24 h / 7 d / 30 d) and polls (everyone, 2-12 options, "Allow more than one answer").
* **G6** sender keys (end-to-end lock for group messages through the server, no UI) and **Invite with link**
  (Online groups only; Nearby-only groups say "use Invite with QR").

## Fitted to 202 (checked in code)

* Group bubbles use the 202 picture grid: 4 squares + "+N", swipe viewer, 3 px edge, time on the picture,
  caption under the grid, docs as rows. Ticks on a picture are white (light blue when all read).
* Group reply: mini grid + words ("📷 5 photos"), the same as 1:1.
* Group forward: the 202 forward card.
* Group review strip before send: the 202 strip with "+" to add more.
* Invite link card shows in both 1:1 and group bubbles; it sits above the photos and keeps the 202 layout.
* No status icon in group screens (only words, the same as 202).

## Changes made during the merge

* `group_message_bubble.dart`: the G1 bubble + the 202 grid (merged by hand).
* `message_bubble.dart`: the G6 invite card + the 202 grid.
* `home_screen.dart`: both the 202 phone-number align and the G2 people hub run at start.
* `local_link_app.dart`: the open-group hook is cleared when the app closes.
* Version 3.0.42+113 (202 = 3.0.41).

## Apply - backend (FIRST)

Unzip `LocalLinkBackend_groupsG2-G6_2026-11-04.zip` into the LocalLinkBackend folder, then commit and deploy
the same way as before:

```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLinkBackend"
git pull
Expand-Archive -Force "$HOME\Downloads\LocalLinkBackend_groupsG2-G6_2026-11-04.zip" .
git add -A
git commit -m "groups G2-G6: admin/info, phone-made ids + bridge, receipts, invite link, sender keys"
if ($LASTEXITCODE -eq 0) { git push }
```

## Apply - app (after the 202 zip)

```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes202_2026-11-04.zip" .
Expand-Archive -Force "$HOME\Downloads\locallink_app_groups_2026-11-04.zip" .
git add -A
git add -f APPLY_*.md TODO_*.md
git reset -q -- android/local.properties
git commit -m "v3 3.0.42 bundle 202 + groups G1-G6: media grid, viewer, privacy + groups (admin, nearby, mesh, QR, ticks, pin, polls, sender keys, invite link)"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter pub get
flutter build apk --release
```

## Phone tests

Older phone tests are still valid: `APPLY_G1.md` (G1-1..14), `APPLY_G2.md` (G2-1..12), `APPLY_G3.md`,
`APPLY_G4.md`, `APPLY_G5.md` (G5-1..8). New ones:

**202 inside groups**
1. **GM-1 Grid:** in a group send 5 photos + 1 PDF. One bubble: 4 squares, "+1" on the last, PDF row under it,
   time + ticks on the picture. Tap a square: viewer, swipe works.
2. **GM-2 Reply:** swipe right on that bubble. The bar shows the mini grid + "📷 5 photos". Send: the quote shows the same.
3. **GM-3 Forward:** hold the bubble > Forward > the forward card shows the photos; send to a friend.
4. **GM-4 Review strip:** + > pick 3 photos: the strip shows them; "+" adds one more; X removes one.

**G5b**
5. **G5b-1 Pin:** admin holds a message > Pin > 7 days. Everyone sees the pin bar. A member (not admin) has no Pin.
6. **G5b-2 Poll:** a member makes a poll with 3 options and "Allow more than one answer". Others vote; counts change on every phone.

**G6 - sender keys (no UI)**
7. **G6-1 Lock:** 3 phones Online. Send "s1". All read it. The log of the sender shows `GROUP_SK_KEYS_SENT`, the others `GROUP_SK_KEYS_GOT`.
8. **G6-2 New member:** add D. D reads new messages but not messages from before the add. The log shows a new key (`GROUP_SK_KEYS_SENT` again).
9. **G6-3 Removed member:** remove C. C gets nothing new.
10. **G6-4 Late key:** turn B off, send "s2", turn B on. B reads "s2" (log `GROUP_SK_ASK` then `GROUP_SK_REOPENED`).

**G6 - invite link**
11. **G6-5 Link page:** admin: Group info > Invite with link: link, Copy, Share, Reset link. A member who is not admin has no row.
12. **G6-6 Join now:** server-only group. Share the link on WhatsApp to E. E taps the web link > "Open in LinkUp" > Join group > the chat opens.
13. **G6-7 Ask to join:** in a group that also works Nearby (or with Approve new members ON): E taps the link > "Ask to join" >
    "Requested ✓". The admin sees E in Group info > requests > Add. E's chat opens in Chats.
14. **G6-8 Reset:** admin taps Reset link. The old link says "This invite link doesn't work any more. Ask for a new one."
15. **G6-9 Nearby only:** in a Nearby-only group, Invite with link says "use Invite with QR".
16. **G6-10 Link in chat:** paste the link in a 1:1 chat: a card "Family · Group invite · 4 members · Join". Tap: Join group screen.

Logs to look for: `GROUP_LINK`, `GROUP_LINK_OPENED`, `GROUP_LINK_JOIN`, `GROUP_LINK_REQUEST`, `GROUP_LINK_APPROVED`,
`GROUP_SK_KEYS_SENT`, `GROUP_SK_KEYS_GOT`, `GROUP_SK_ASK`, `GROUP_SK_REOPENED`, `GROUP_SK_PLAIN` (should not appear),
`GROUP_PIN`, `GROUP_POLL_SENT`, `GROUP_VOTE`.

## Checks done here

* `flutter analyze`: 0 errors.
* Kotlin compile check (MainActivity link channel): clean.
* Backend: `go vet` clean, `go test ./...` all ok (G6 link: 4 tests).
* App suite: **1412 passed, 0 failed** (145 test files, run in parts). New: `groups_g6_link_test.dart` (16).
* Found and fixed while testing: the G6 Android log line used the old "LocalLink" name -> now the shared log tag.
