# APPLY app 3.0.96+167 (TODO 299 app part: C + Q + R)

Zip: `locallink_app_299_2026-11-14.zip`, on top of app 298 (3.0.95+166). Apply + push app 298 FIRST.
Backend 299 goes before both (the update check uses `/api/v1/app/latest`; an old server answers 404 and the
app simply uses nearby phones as today).

## What changes
- **C. Update from the server first, nearby phones second.**
  - The phone asks the server "which LinkUp is on you?" at most every 6 hours, and once each time it gets back on the server.
  - Server has a newer LinkUp -> the same update popup opens by itself, with the words "New LinkUp on the server" /
    "Getting it from the server...". The file comes inside LinkUp, then 3 checks: size, sha256 = the server's, and
    it is LinkUp. Then Install (Android's own screen).
  - Server off, no APK there, or a bad file -> the file is deleted and nearby phones are tried, exactly as before.
  - Same rules as 275: once per new build per day (Cancel = not again today), never during a call, the Update button
    always works, the file is deleted after the update / on cancel.
- **Q. QR codes shared as a picture card** (the recovery-card look): My QR code ("ADD ME ON LINKUP", photo or first
  letter, name, @username, date) and group Invite with QR ("JOIN MY GROUP", group photo, name, members, "Expires in 24
  hours"). The caption is only the code. The temp picture is deleted after the share sheet.
- **R. Phone share page redesign** (the page a phone shows when it shares LinkUp): the same look as the server page:
  navy top with the LinkUp rings, one card with "Shared by ..." + Download + Urdu, step cards; light and dark.
  Same words, same 4 steps, same `/LinkUp.apk` link.

## Files
New `share_app/data/app_latest_server_299.dart`, `share_app/presentation/qr_share_card_299.dart`,
`share_app/presentation/qr_card_share_299.dart`; changed `silent_update_275.dart`, `update_sheet.dart`,
`apk_share_page.dart`, `my_qr_screen.dart`, `group_qr_screens.dart`, `app_dependencies.dart`, version files.
New tests `update_server_c_299_test` (11), `update_server_299_test` (4), `qr_card_299_test` (3), `qr_share_299_test` (3).
Old tests changed: only the version lines (`bundle223_logs_test`, `nearby_190_test`). Nothing removed.

## Tests (here)
- `flutter analyze`: 0 errors; no warnings or infos in the changed / new files.
- Full Flutter suite: 307 files, 13 chunks, **2969 tests, all passed**. After a last import clean-up the 299 tests and every
  test that opens My QR / group QR were run again: 90/90 passed.
- QR card pictures decoded by a real QR reader (zxing) at 30-100 % size and after JPEG compression.
- Backend 299 + app tests together: the app reads the real server answer format (`version, build, size, sha256, path`).
- NOT checked here: real phones, WhatsApp, a real 60-100 MB APK download over Wi-Fi, the Kotlin build (CI builds the APK).

## Phone check
1. Server 299 running; web App download: add the 3.0.96 APK (from this build's GitHub run).
2. A phone on 3.0.95 (on the server): within a minute of opening LinkUp (or after reconnecting) the popup says
   "New LinkUp on the server" -> Install -> 3.0.96. (If you cancelled today: tap Update in Settings.)
3. Server off + a nearby 3.0.96 phone: the old nearby popup still works.
4. My QR code > Share -> WhatsApp: the card picture, caption = only the code. The other phone scans it from the picture.
5. Group > Invite with QR > Share code: group card; scan works.
6. Share LinkUp from a phone: the new page on the other phone's browser (light and dark).

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_299_2026-11-14.zip" .
git add -A
git add -f docs/history/TODO_299.md docs/history/APPLY_app_299.md
git commit -m "v3.0.96+167: update from the LinkUp server first (every 6 h + on reconnect, sha256 checked, nearby phones as fallback), My QR and group invite shared as picture cards with code-only caption, phone share page redesign"
git push
```
