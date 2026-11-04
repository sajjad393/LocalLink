# APPLY G7 - group photos, videos, voice notes and files with NO internet (+ typing + group photo)

App only. **No backend change.** Version **3.0.43+114**, phone DB **v33**.
Base: app `94274a6` (groups G1-G6). Zip: `locallink_app_G7_2026-11-04.zip` (app repo only).

## 1. What changed (simple words)

* **Groups now work like 1:1 chat with no internet** (router Wi-Fi, Wi-Fi Direct, mesh):
  photos, videos, voice notes and documents, with the same grid, rings, "Tap to download" and ticks.
* **The sender sends each file to each member, one by one** (like 1:1). Each member gets its own copy id,
  so two members never share one transfer. Max 6 group files at once (1:1 keeps room).
* **Members who are not friends** (joined by QR / link) also get files: a lock key per pair of phones is made
  from the group card keys and given to the phone's file engine. Only those two phones can open the file;
  any LinkUp phone in the middle can carry it.
* **50 MB per file** over Nearby (same as 1:1). Bigger files go by the server when there is internet.
* **Battery 10% or less:** voice notes under 1 MB still go; bigger files wait.
* **When the internet comes back:** if every member already got the file Nearby, the sender does **not**
  upload it (log `GROUP_FILE_UPLOAD_SKIPPED`). A member who already has a file never downloads it again.
* **Old app (3.0.42) members:** still see the words; they get files from the server only.
* **Sender:** now sees their own group photo at once (before the server takes it) - also in Online groups.
* **Tap to download:** if nothing moves for 3 minutes (sender went away), the square shows
  "Tap to download". Tap = ask the sender again (max 5 asks per 10 minutes).
* **Typing:** "Sumaira is typing…" also with no internet (live lock, never stored).
* **Group photo** in a group made with no internet: admins can set / remove it; members get it Nearby
  (signed by the admin, checked by hash). The server gets it after the group goes online.
* Group call stays dropped; the invite link stays server only.

## 2. Files

New:
* `lib/features/groups/data/group_nearby_files.dart` - file list, per-member ids, send queue, watch, pair keys
* `test/groups_g7_test.dart` - 39 tests

Changed:
* `lib/features/groups/data/services/group_nearby_service.dart` - files in the message (`att` + `llgm2`
  signature), `fv:2` in "got it", catch-up with files, `group_file_need`, `group_typing`, `group_photo`
* `lib/features/groups/data/services/group_messaging_service.dart` - keep my copy, files before queue,
  receive files, upload rule, typing Nearby, group photo Nearby
* `lib/features/groups/data/services/group_nearby_store.dart` - copies with files; file rows store
* `lib/features/groups/data/repositories/group_repository.dart` - group photo with no internet
* `lib/features/messaging/data/services/reliable_messaging_service.dart` - hands group files to the group code;
  Tap to download / X for groups (1:1 unchanged)
* `lib/features/files/presentation/widgets/attachment_tile.dart` - receiving ring / Tap to download in groups
* `lib/features/connectivity/data/services/sealing_peer_transport.dart` - live lock for typing; push file keys
* `lib/features/connectivity/data/services/wifi_direct_transport_service.dart` - `updatePeerFileKeys`
* `lib/core/services/local_store.dart`, `lib/core/storage/database_config.dart` - DB v33
* `lib/app/app_dependencies.dart` - wiring
* `android/.../LocalLinkTransportService.kt`, `MainActivity.kt`, `BackgroundChannels.kt` - group file keys
  (used only for file locks; the link check is untouched)
* `pubspec.yaml`, `lib/app/local_link_app.dart`, tests (version / DB checks)

## 3. Checks done here

* Full test suite: 146 files, **1451 passed** (1412 old + 39 new G7).
* `flutter analyze`: 0 errors.
* Kotlin compile check: clean.
* **Compile-checked only (real check = phone tests):** native file lock with group keys, Wi-Fi Direct /
  mesh file sending, notifications.

## 4. Commands (PowerShell)

```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_G7_2026-11-04.zip" .
git add -A
git add -f APPLY_G7.md TODO_G7.md
git reset -q -- android/local.properties
git commit -m "v3 3.0.43 groups G7: group photos videos voice notes files with no internet, typing and group photo Nearby"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter pub get
flutter build apk --release
```

**All 3 test phones must have 3.0.43.**

## 5. Phone tests (internet OFF unless said)

Phones: Sajjad (Realme), Sumaira (ZTE), Ali (3rd phone). Group "Family".

1. **G7-1 Photos, Wi-Fi Direct:** Sajjad sends 5 photos + caption. Sumaira and Ali see the grid with rings,
   then the photos. Sajjad's ticks turn grey ✓✓ after both have them.
2. **G7-2 Video + voice note + PDF, router Wi-Fi (no internet):** same as G7-1.
3. **G7-3 Mesh:** Ali two rooms away (only through Sumaira's phone). Ali gets the photo through mesh.
4. **G7-4 Not friends:** Ali is not Sajjad's friend (joined by QR). Ali still gets photos.
   App log on Sajjad (5 taps on "Chats"): `GROUP_FILE_KEYS peers=` (1 or more).
5. **G7-5 Late member:** Ali's phone off. Send a photo. Turn Ali on near Sumaira only: the words come by
   catch-up. Then near Sajjad: the photo comes from Sajjad.
6. **G7-6 Tap to download:** Sajjad walks away during a video. After 3 min Ali sees "Tap to download".
   When Sajjad is back, tap: it comes.
7. **G7-7 Big file:** a 60 MB video with no internet does not go Nearby; turn internet on: it arrives.
8. **G7-8 Internet back:** after G7-1 turn internet on. Photos are **not** downloaded again; Sajjad's log
   shows `GROUP_FILE_UPLOAD_SKIPPED`.
9. **G7-9 Typing:** Sumaira types; Sajjad sees "Sumaira is typing…" with no internet.
10. **G7-10 Group photo:** in a group made with no internet, Sajjad (admin) sets a photo; Sumaira and Ali see it.
    Sumaira (not admin) can't change it.
11. **G7-11 1:1 still fine:** send a photo 1:1 on Wi-Fi Direct while a group video is sending: both arrive.

Logs to send if something fails: `GROUP_FILE_QUEUED`, `GROUP_FILE_READY`, `GROUP_FILE_SENT`,
`GROUP_FILE_FAILED`, `GROUP_FILE_WAIT`, `GROUP_FILE_RX`, `GROUP_FILE_RX_REFUSED`, `GROUP_FILE_NEED`,
`GROUP_FILE_UPLOAD_SKIPPED`, `GROUP_FILE_KEYS`, `GROUP_TYPING_NEARBY`, `GROUP_PHOTO_NEARBY`,
`GROUP_PHOTO_REFUSED`.
