# APPLY 204: friends see your profile picture (no internet too) + Remove photo

Version **3.0.44+115** (203 is not approved yet, so 204 takes 3.0.44. If 203 comes later, it will be 3.0.45).
Built on **G7** (`locallink_app_G7_2026-11-04.zip`). No DB change.

| Zip | What | Order |
|---|---|---|
| `LocalLinkBackend_204_2026-11-04.zip` | server: friend picture download (friends only) + Remove photo (4 files) | **1st: deploy the server** |
| `locallink_app_G7_2026-11-04.zip` | groups G7 (skip it if you already pushed G7) | 2nd |
| `locallink_app_204_2026-11-04.zip` | bundle 204 (app) | 3rd |

The 204 app zip **needs G7 first**. Some files are in both zips, and the 204 copy already has the G7 changes inside.

---

## What changes for the user (mock 204, approved)
* **Friends' pictures:** they show in Chats, the chat top bar, People, Calls, the incoming call screen, group
  bubbles, Group info, the member sheets, Forward, New group, reactions, polls, Message info and notifications.
  The way badge (Wi-Fi / Wi-Fi Direct / Mesh / Online) stays at the top right.
* **Not a friend** (e.g. Zara in Nearby people): the letter only.
* **No picture set** (e.g. Bilal): the letter, as today.
* **While a picture is coming:** the letter, then the picture. No spinner and no new message.
* **Profile:** tap the camera button to get Camera / Gallery / **Remove photo** (Remove only shows when you have a
  picture). The new picture shows at once and is saved with **Save**.
* **Settings card** and **My QR**: your picture (before, a letter or nothing).
* **Notification:** the friend's picture on the right. The LinkUp icon stays on the left.
  ⚠️ This changes bundle 141 ("no picture on the right"). Mock A8 showed it and you approved it. If you want it
  off again, it's one line.

## How the picture travels
1. You save a picture (512 px, about 30 to 80 KB). Your signed card now carries a short picture code.
2. A friend's phone sees the new code and asks your phone for it (Wi-Fi, Wi-Fi Direct or mesh). Your phone
   checks: friend? not blocked? Then it sends the picture.
3. Not near now: it asks again when you come near, and when the app starts.
4. Online and far away: from the server after 20 s (the new endpoint, friends only).
5. Every copy is checked against the code (sha256 + size). A wrong or changed picture is dropped.
6. Remove photo: the card has no code, so friends go back to the letter. The server copy is deleted when online.
7. Unfriend or block: that person's picture is deleted from your phone.

---

## Apply: backend (FIRST)
```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLinkBackend"
git pull
Expand-Archive -Force "$HOME\Downloads\LocalLinkBackend_204_2026-11-04.zip" .
git add -A
git commit -m "v3 bundle 204 backend: friend picture download (friends only) and remove photo"
if ($LASTEXITCODE -eq 0) { git push }
```
Then deploy the server the same way as before.

New routes:
* `GET /api/v1/directory/user/{id}/avatar`: friends only (either side added), otherwise 404. Your own id also works.
* `DELETE /api/v1/profile/avatar`: Remove photo.

## Apply: app
(Skip the G7 line if G7 is already pushed.)
```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_G7_2026-11-04.zip" .
Expand-Archive -Force "$HOME\Downloads\locallink_app_204_2026-11-04.zip" .
git add -A
git add -f APPLY_*.md TODO_*.md
git reset -q -- android/local.properties
git commit -m "v3 3.0.44 bundle 204: friends see your profile picture with no internet and online, Remove photo"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter pub get
flutter build apk --release
```
If G7 was not pushed yet, this ONE commit has G7 + 204. If you want them as two commits, extract G7, commit it with
the commit line from `APPLY_G7.md`, then extract 204 and commit.

---

## Phone tests (internet OFF unless said)
1. **204-1 Wi-Fi Direct:** Sajjad sets a new picture and taps Save. Sumaira (friend, near) sees it within about
   10 s in Chats, the chat top bar and People.
2. **204-2 Mesh:** Ali (friend), reachable only through Sumaira's phone, gets the picture.
3. **204-3 Later:** Ali's phone is off. Sajjad changes the picture. Ali turns on near Sajjad and gets it.
4. **204-4 Not a friend:** Zara (Nearby people, not a friend) still sees the letter.
5. **204-5 Change twice:** change the picture twice. The newest shows on every phone and on Sajjad's Profile,
   Settings card and My QR.
6. **204-6 Remove:** Profile > camera > Remove photo > Save. Friends go back to the letter.
7. **204-7 Internet ON:** Sumaira far away and online. She gets the picture from the server. Remove photo also
   clears it on the server.
8. **204-8 Old app:** a phone on 3.0.43 or older still adds and sees Sajjad (letter only), with no errors.
9. **204-9 Notification:** a message from Sajjad shows his picture on the right of the notification.

Logs to look for: `PEER_PHOTO_ASK`, `PEER_PHOTO_SENT`, `PEER_PHOTO_GOT way=nearby|online`,
`PEER_PHOTO_REFUSED why=...`.

## Limits
* Friends still on the old app send no picture code, so they show the letter until they update.
* A picture over 200 KB (an old upload made before 204) goes by the server only, not phone to phone. Setting the
  picture again makes it small.
* The notification picture, the camera and real Wi-Fi Direct / mesh sending are compile-checked only. Test them on
  the phones.
* My QR keeps today's layout (your picture in the middle of the QR, where the letter was). In the mock the
  picture was drawn above the QR. Tell me if you want it moved.

## Checks done here
* Backend: `go vet` clean, `go test ./...` all ok (new `avatar_204_test.go`).
* App: new `test/profile_photo_204_test.dart` (28 tests). Full suite **1479 passed, 0 failed** (147 test files,
  in parts of 8; the known flaky `seal_relay_156` failed once and passed twice alone). `flutter analyze`: 0 errors.
  Kotlin compile check: clean.
