# TODO 204 - Profile picture with no internet (Wi-Fi Direct / mesh) + friends see your picture

Status: **PLAN ONLY - FREEZE ON.** No code changed. Starts only after you say "go ahead 204".
Asked: "Can we update [profile picture] when user is on Wi-Fi Direct or mesh as well?" -> yes.
Code checked at app commit `94274a6`. Mock first (Phase 0) because screens change.
Phone database: **no change**. Backend: only if you say yes to Q1 (separate backend zip).

---

## 1. What happens today (checked in code)

1. **Saving a picture with no internet**
   * `account_repository.dart` lines 81-90: the picture is copied to `profile_avatar_pending.jpg` and shown on your
     own Profile. Then `syncPendingProfile` (`locallink_api.dart` line 400) tries the server, fails, and you see
     "Saved on this phone; it will sync when available".
   * When the internet comes back, the picture uploads (`POST /api/v1/profile/avatar`, line 495).
2. **Friends never get it over Nearby**
   * Your profile card goes to other phones as `DIRECTORY_PROFILE` (`directory_repository.dart` line 148,
     `publishOwnProfile`).
   * Its picture field is **always empty** (`avatarUrl: ''`, line 232). So the card carries name, username and
     phone only.
3. **Friends never see a picture anywhere, even online**
   * The app only downloads **your own** picture (`GET /api/v1/profile/avatar`, line 512). There is no way to get a
     friend's picture.
   * Chats list, chat top bar, People, Nearby, Calls, Forward and groups all show **only the first letter**
     (`AccountAvatar(name: ...)` with no picture: `chat_screen.dart` lines 736 + 916, `home_screen.dart` line 896,
     `forward_screen.dart` line 282, group widgets, ...).
4. **Your own picture is missing in 2 places**
   * The Settings card shows your letter (`messenger_settings_screen.dart` line 131, no picture passed).
   * My QR screen tries to use the card's picture field as a file (`my_qr_screen.dart` line 64). That field is always
     empty, so it never shows.
5. **Changing the picture twice with no internet can show the old one**
   * The waiting picture always has the same file name (`local_store.dart` line 1526). Flutter keeps showing the
     first picture from memory for the same file name.
6. **Notifications**: the code already looks for a friend's picture (`notification_identity_resolver.dart` line 37),
   but none is ever stored and nothing uses it. So notifications show no picture.

Good news found in the code:
* The card's picture field (`avatar_url`) is **already inside the signed part** of the card
  (`directory_models.dart` line 74). We can put a short picture code there. **Old phones (3.0.4x) still accept the
  card** (they sign/check the same field) and just keep showing the letter.
* Group photos (G6) already use a small picture (512 px, quality 78, `group_info_sheets.dart` line 157) and a
  picture book (`GroupPhotoBook`). The same ideas can be reused.
* Phones in the middle of a mesh already carry locked files between friends (bundles 156/195). The picture can use
  the same road.

---

## 2. How it will work (my advice)

**Short version:** your card says "my picture is number 3, code ab12...". A friend whose phone doesn't have that
picture asks you for it. Your phone sends a small locked copy only to friends. Phones in the middle carry it.

1. **Small picture:** the profile picker makes a 512 px picture, quality 78 (about 30-80 KB, same as group photos).
   The same file is used for the server and for Nearby. A picture over 200 KB is not sent over Nearby (log).
2. **Picture code in the signed card:** `avatar_url = "llav1:<16 hex of sha256>:<picture number>"`.
   * New picture = new number (+1). An old picture can never replace a newer one.
   * Picture removed = empty code. Friends go back to the letter.
   * Signed with your key, so no other phone can change your picture.
3. **Asking for it (pull):** when a friend's phone gets your card and does not have that picture:
   * it sends `PROFILE_PHOTO_NEED {user, code}` to you, over Wi-Fi, Wi-Fi Direct or mesh (the same routed road as
     messages);
   * max 3 asks per friend per 10 minutes, and again when you come near.
4. **Sending it:** your phone checks the asker is **your friend** (contacts table) and **not blocked**. Then it sends
   the picture with the normal file engine:
   * id `av<code>`, message id `avatar-<your user id>`;
   * locked between the 2 phones, like a photo in chat; phones in the middle carry it but can't open it.
5. **Pushing it straight away:** when you save a new picture, your phone also sends it to friends who are near right
   now. Everyone else asks later, when they see your new card.
6. **Receiving:** the friend's phone checks the sha256 matches the code in your signed card. Then it saves the file as
   `avatars/<code>.jpg` and deletes your older picture. A wrong picture is thrown away (log
   `PROFILE_PHOTO_REFUSED`).
7. **Who gets it:** **friends only**. People who are not your friends (Nearby people list, name search) see your
   letter. Private profile: the same (friends only anyway).
8. **When the internet comes back:** the picture also uploads to the server, as today.
9. **No database change:** the code lives in the existing signed card. The file name comes from the code.

---

## 3. Phases

### Phase 0 - Mock (before any code)
* Friends' pictures in: Chats list, chat top bar, People, Nearby, Calls, Forward, group members, group bubbles,
  call screen, notification.
* The way badge (Wi-Fi / Wi-Fi Direct / Mesh / Online) stays at the top right of the picture (bundle 201).
* Your own picture on the Settings card + My QR (+ the lock ring from 203 if that is in).
* What a friend sees while the picture is coming: the letter, then the picture (no spinner).

### Phase 1 - My picture: small, unique file name, Settings + QR
* `profile_screen.dart` `_pickImage` (line 169): 512 px, quality 78 (today 1024 / 82). Camera option is not in scope.
* `local_store.dart` `pendingProfileAvatarFilePath`: a new name each time (`profile_avatar_<time>.jpg`), old one
  deleted. Clear Flutter's picture memory for the old file.
* After the upload, keep a copy for Nearby (`my_avatar_<code>.jpg`). Today the pending file is deleted after the
  upload (line 424).
* Settings card (`messenger_settings_screen.dart` line 131) and My QR (`my_qr_screen.dart` line 64) show my picture
  (`localAvatarPath`).

### Phase 2 - Picture code in my signed card
* `directory_repository.dart` `_buildOwnProfile` (line 232): `avatarUrl` = `llav1:<code>:<number>` when I have a
  picture, '' when not.
* Picture number saved in settings (`my_avatar_v`), +1 on every change or removal.
* Saving a new picture bumps `profileVersion` (already done by `saveProfile`) and calls `publishOwnProfile`
  (already called by the Profile screen, line 151). So the new card goes out at once.
* Helper `ProfilePhotoCode.parse/format` (accepts only `llav1:` + 16 hex + number; anything else = no picture).

### Phase 3 - Friend side: ask, receive, check, keep
* New `PeerPhotoBook` (like `GroupPhotoBook`): user id -> picture file. Listens to card updates (`_updates`).
* On a card (`DIRECTORY_PROFILE`, `..._RESULT`, `SYNC_RESPONSE`) from a **friend** with a new code and no file:
  send `PROFILE_PHOTO_NEED`. Limit 3 per 10 min per friend; retry when that friend comes near (`PresenceHub`).
* `reliable_messaging_service.dart` file-received path: ids starting with `avatar-` go to `PeerPhotoBook`
  (same kind of routing as G7 group files). The 1:1 chat path stays as it is.
* Check: sha256 == code, size <= 200 KB, sender = the card's device. Save `avatars/<code>.jpg`, delete the old one.
* Card with an empty code = picture removed: delete the file, show the letter.
* Unfriend or block: delete that person's picture.
* Logs: `PROFILE_PHOTO_NEED_SENT`, `PROFILE_PHOTO_RX`, `PROFILE_PHOTO_REFUSED why=`, `PROFILE_PHOTO_REMOVED`.

### Phase 4 - Owner side: send only to friends
* Handle `PROFILE_PHOTO_NEED`: must be a friend, not blocked, the code = my current picture. Else ignore (log
  `PROFILE_PHOTO_NEED_REFUSED`).
* Max 1 send per friend per picture per 10 minutes. If it's still sending, don't start again (uses the 203 rule if
  203 is in).
* Push to friends near right now when I save a new picture.
* Logs: `PROFILE_PHOTO_SENT to=`, `PROFILE_PHOTO_PUSH n=`.

### Phase 5 - Show friends' pictures everywhere
* `AccountAvatar` gets an optional `userId` / `deviceId`. When given, it shows the picture from `PeerPhotoBook`, or
  the letter if none. All callers stay the same unless changed.
* Places (from the code): `home_screen.dart` (chat rows), `chat_screen.dart` 736 + 916 (top bar), `PresenceAvatar`
  (keeps its way badge), `contacts_screen.dart`, `nearby_people_section.dart` (friends only), `contact_sheets.dart`,
  `forward_screen.dart`, calls (`call_history_tile.dart`, `call_header.dart`, `incoming_voice_call_body.dart`),
  groups (`group_member_tile.dart`, `group_message_bubble.dart`, `group_sheets.dart`,
  `group_message_info_sheet.dart`, `group_mention_widgets.dart`).
* Notifications: set the friend's picture as the large icon (the resolver already reads it, line 37). It's a native
  notification part, so compile-checked only.

### Phase 6 - Online (only if Q1 = yes)
* Backend: `GET /api/v1/directory/user/{id}/avatar`, which works only if you are friends. Separate backend zip, deployed
  first.
* App: when online and a friend's code changed but no Nearby copy came in 30 s, download from the server instead.
  Same check (sha256 = code).

### Phase 7 - Tests
* New `test/profile_photo_204_test.dart`:
  * code format/parse; a wrong code = letter;
  * the card with a picture code is still signed and verified (and an **old-style check** of the same card passes);
  * a friend asks -> picture sent; a non-friend or blocked person asks -> nothing;
  * receive: good sha256 saved, wrong sha256 refused, too big refused, older number ignored;
  * removed picture -> file deleted, letter shown;
  * unique pending file name; Settings card + QR show my picture;
  * `AccountAvatar` with a user id shows the picture, else the letter; the way badge stays.
* Full suite + analyze (+ Kotlin compile check if the notification part touches native).

### Phase 8 - Zip + APPLY_204.md + phone tests (internet OFF unless said)
1. **204-1 Wi-Fi Direct:** Sajjad sets a new picture. Sumaira (friend, near) sees it within about 10 s in Chats, the
   chat top bar and People.
2. **204-2 Mesh:** Ali (friend) is 2 rooms away, reachable only through Sumaira's phone. Ali gets the picture.
3. **204-3 Later:** Ali's phone is off. Sajjad changes the picture. Ali turns on near Sajjad and gets it.
4. **204-4 Not a friend:** Zara (Nearby people, not a friend) still sees the letter.
5. **204-5 Change twice:** change the picture twice with no internet. The newest shows on every phone (and on
   Sajjad's own Profile).
6. **204-6 Remove:** (if a remove option exists, see Q3) friends go back to the letter.
7. **204-7 Internet back:** the picture uploads to the server. Nothing breaks.
8. **204-8 Old app:** a phone on 3.0.42 still adds and sees Sajjad (letter only), with no errors.
9. **204-9 Notification:** a message from Sajjad shows his picture in the notification.

---

## 4. Files that change
* `lib/features/account/presentation/screens/profile_screen.dart` - picker size
* `lib/features/account/data/repositories/account_repository.dart`, `lib/core/services/local_store.dart`
  (file name only), `lib/core/services/locallink_api.dart` - keep the Nearby copy
* `lib/features/directory/data/repositories/directory_repository.dart` - code in the card, NEED / send
* New `lib/features/directory/data/peer_photo_book.dart`, `lib/features/directory/domain/profile_photo_code.dart`
* `lib/features/messaging/data/services/reliable_messaging_service.dart` - route `avatar-` files
* `lib/core/widgets/account_avatar.dart` + the screens in Phase 5
* `lib/features/home/presentation/screens/messenger_settings_screen.dart`, `lib/features/directory/presentation/my_qr_screen.dart`
* Notifications (Phase 5) - check which file builds the large icon
* `pubspec.yaml`, `lib/app/local_link_app.dart`, `test/nearby_190_test.dart` - version
* New `test/profile_photo_204_test.dart`, `APPLY_204.md`, mock pages `mock_204_page*.png`

Version: one step after whatever goes before it (G7 = 3.0.43, 203 = 3.0.44, so 204 = 3.0.45 in that order).

---

## 5. Questions before I start
* **Q1 - Online too?** Friends who are far away and online can't get your picture today (no server way).
  * (my advice) Yes, add the small backend part (Phase 6). Separate backend zip, deploy first.
  * Or Nearby only for now.
* **Q2 - Who gets my picture:** (my advice) friends only. Or anyone near you.
* **Q3 - "Remove picture" button on Profile:** today there is none (only change).
  * (my advice) Add "Remove photo" to the camera button (like group photo: Camera / Gallery / Remove).
  * Or leave it out.
* **Q4 - Order:** (my advice) G7 -> 203 -> 204, each its own zip and commit.

## 6. Not in 204
* Group photos (already done in G6/G7).
* Pictures for people who are not friends.
* Video or animated pictures.

---

## 7. Progress (204 approved: "Follow your advise Go ahead 204")
Answers = my advice: Q1 online too (separate backend zip) - Q2 friends only - Q3 add "Remove photo" - Q4 G7 -> 203 -> 204.
203 is not approved yet, so 204 is built on G7 (local `7de1136`). Version 3.0.44+115 if 203 is still not in, else 3.0.45.

**Done (no screen changes yet):**
* Backend (in `/tmp/be`, backup `/home/user/be204_wip/`):
  * `GET /api/v1/directory/user/{id}/avatar` - friends only (account_contacts, either way), else 404; own id OK.
    Sends `X-Avatar-SHA256`.
  * `DELETE /api/v1/profile/avatar` - "Remove photo" (clears the columns, deletes the file).
  * Test `avatar_204_test.go`; full `go test ./...` passes; vet + gofmt clean.
* App (in `/tmp/g7`, backup `/home/user/p204_wip/`):
  * `peer_photo_book.dart`: `ProfilePhotoCode` (`llav1:<16 hex>:<size>`), `ProfilePhotoLimiter` (3 / 10 min),
    `PeerPhotoBook` (`avatars/<hash>.jpg`, user + device lookup, sweep, dropPicture).
    Change from the plan: the number is the **size in bytes**, not a counter. The code comes from the picture
    itself, so the same picture = the same code on every phone (online copy too). No `my_avatar_v` setting needed.
  * Card: `_buildOwnProfile` puts my code in `avatar_url` (signed); '' = no picture.
  * Friend side: checked card -> remember code -> if friend and missing: `DIRECTORY_PHOTO_NEED` to the owner's
    phone (sealed, one step), then the server after 20 s if still missing. Retry when that friend comes near
    (`peer_connected`) and at start-up (codes reloaded from the saved cards).
  * Owner side: friend + not blocked + same code + <= 200 KB -> `transport.sendFile` (id `av<hash>`, message
    `avatar-<my user id>`). Max 3 per friend per 10 min.
  * Receive: `reliable_messaging_service` routes `av*` / `avatar-*` files BEFORE the chat file code (never a chat
    file). Checks: card code, sender = card's phone, friend, sha256 + size. File deleted after.
  * Unfriend / block: the picture file is deleted (4 places in `directory_repository.dart`).
  * Remove photo: `saveProfile(removeAvatar: true)` -> pending mark `remove` -> `DELETE` when online.
  * Own picture files: new names (`profile_avatar_pending_<ms>`, `profile_avatar_<hash>`), old ones swept.
  * Picker 512 px / quality 78.
  * Logs: `PEER_PHOTO_ASK`, `PEER_PHOTO_SENT`, `PEER_PHOTO_GOT way=nearby|online`, `PEER_PHOTO_REFUSED why=`,
    `PEER_PHOTO_CODE`.
  * Tests: `test/profile_photo_204_test.dart` 23 pass; 32 related test files (501 tests) pass; analyze 0 errors.

**Phase 5-8 DONE (mock OK'd: "Yes, build it like the mock"):** AccountAvatar `peerId` + all friend places,
Profile photo sheet (Camera / Gallery / Remove photo), Settings card, My QR (picture in the QR centre, layout
kept), own picture in "You" rows, notification large icon (round, friends only - reverses bundle 141, flagged).
Version 3.0.44+115. Suite 1479 passed; analyze 0 errors; kcheck clean. Zips: `locallink_app_204_2026-11-04.zip`,
`LocalLinkBackend_204_2026-11-04.zip`; `APPLY_204.md`.

**Old next list (done):**
1. User OK on the mock (`mock_204_page1.png`, `mock_204_page2.png`).
2. Phase 5 screens: `AccountAvatar` + places, profile sheet Camera / Gallery / Remove photo, Settings card, My QR,
   notification large icon.
3. Phase 7: full suite in chunks of 8 + analyze + kcheck. Phase 8: app zip + backend zip (separate) + APPLY_204.md.

**Limits (say in APPLY):** friends on the old app send no code -> letter only. A picture > 200 KB (old uploads)
comes from the server only.
