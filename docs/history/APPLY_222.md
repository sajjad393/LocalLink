# APPLY 222 - forgot password, offline accounts in Users, nearby phones carry her account, map zoom, crown room (app 3.0.62+133 + backend)

**Order (after 221):**
1. **Backend 222 zip**: commit, run `go test ./...`, deploy (migration 61). Migration 61 checks the columns first, so running it twice is safe.
2. **App 222 zip**: commit, then build the APK.

Phones older than build 133 keep working. They don't carry join boxes, and their Users page has no offline rows.

## PowerShell

Backend:
```
cd "C:\Users\sajjad Ahmed\Downloads\localLinkBackend"
Expand-Archive -Force -Path "C:\Users\sajjad Ahmed\Downloads\locallink_backend_222_2026-11-06.zip" -DestinationPath .
go test ./...
git add -A
git commit -m "v3 bundle 222 backend: reset with recovery code, no-code request to admin, carried join for offline accounts, offline accounts in web Users"
git push
```

App:
```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force -Path "C:\Users\sajjad Ahmed\Downloads\locallink_app_222_2026-11-06.zip" -DestinationPath .
flutter pub get
flutter test
git add -A
git commit -m "v3 3.0.62+133 bundle 222: forgot password (code / no code / offline), offline accounts in Users, nearby phones carry her account, map zoom to whole map, crown room"
git push
```

## What users see
- **Sign in -> "Forgot password?"** (this replaces "Account recovery", which never worked). Mocks R-1..R-5:
  - Pill: "Server connected" or "No server · works on this phone only".
  - **I have my recovery code**: Username, Recovery code, New password (twice), then "Set new password". You are signed in at once and get a new code. Your other phones stay signed in.
  - **I don't have it**: a request goes to the admin and stays "Waiting" with no time limit. The admin approves, you type the 12-digit one-time code (valid 24 h) plus a new password, and you are signed in.
  - **No server**: works only on the same phone, for the last account, with the code saved on it. The new password goes to the server later.
- **Her phone (account made offline, never online)**, mock U-3:
  - Card "Waiting for the server": "Your account was sent with a nearby phone (Ali)…", plus a blue line "Sent 2 h ago · carried by 2 phones". The card has a clock and is never red.
  - When the answer comes back, the 218 card "You're on the server now" shows. If her name was taken, it says "@sumaira was taken, so you are @sumaira37".

## What the admin sees
- **Admin -> Users** (mock U-1):
  - Offline accounts seen by Wi-Fi Direct / mesh / router have a grey "Offline account" tag and the line "Not on server yet · Wi-Fi Direct · 2 h".
  - New chip "Not on server". The subtitle reads "3 people · 1 admin · 2 not on server".
  - **With no server, Users now opens.** You see the orange bar "No server · showing people seen nearby" instead of the "needs the server" page.
  - A server row that came from an offline account shows "· Joined from offline" for 7 days.
- **Tap an offline row** (mock U-2): Status / Phone / Seen / Server ("Waiting to join the server", or "Waiting · carried by this phone"). **Block** and **Sign out** go as 220 cards (Pending until done). Nothing else is possible until she joins.
- **Web -> Users**: chip "Not on server N", grey tag, Seen by / Last seen, and "Join box carried by N phones". **Web -> Recovery**: "No code" tag, **Approve shows the one-time code in a dialog**, and Reject works.
- **Admin map** (mocks M-1, M-2):
  - "−" and pinch now zoom out to the whole map. At that point "−" turns grey and a dark "Whole map" tag shows for 1.5 s.
  - Double tap switches between the whole map and 2x.
  - The small map always shows You + Server. With no other phones it says "No other phones linked".
  - **The lines are unchanged** (same 217 moving curved dashes).
- **Crown** (mock C-1): fully visible on Profile, Users, Settings and Account. The extra space appears only while the crown shows. Admin rows in Users are 12 px taller, with the photo lower.

## How it works (short)
- **Reset with code:** `POST /api/v1/account/recovery/reset`. 5 tries per minute per name, 10 per minute per IP. The server normalizes the code. The response is a normal sign-in plus a new code.
- **No code:** `no_code:true` makes a request. Approve creates a 12-digit code valid for 24 h ("New code" makes another one). An unknown name gets 404 `NO_ACCOUNT` ("No account with this username").
- **Offline reset:** the same phone checks its saved code. The new password hash waits in secure storage (`pwd_reset_pending_222`) and goes up on the next connect. For an account that was never on the server, the waiting registration simply gets the new password.
- **Carried join (section 9):**
  - Her phone makes ONE box with her name, the PBKDF2 hash + salt it already keeps, the **hash** of her recovery code, and her phone id and keys. **The password never travels.**
  - The box is signed by her phone and locked for the server (llaa1 box to the server's join key), so carriers can't read or change it.
  - It travels over every link (Kotlin one-step frame `account_join`). Any phone with internet uploads it: `POST /api/v1/auth/join-relay`.
  - The server applies the 218 rules: same name + same code = join that account, name taken = auto rename, phone already used = refused.
  - The server-signed answer comes back the same way. Her session token inside is locked to her phone's key.
  - Carriers drop the box when they see the answer. Same box twice = same answer.
  - Limits: 200 boxes per phone, kept 60 days, no other time limit.
- **Join key on a phone that was never online:** taken only when **2 different phones** hand the same server-signed note. A phone that already knows the server checks it at once. It is used only for the join box; admin trust is unchanged.
- **Offline rows rule:** a person whose id still starts with `offline_` (a join moves the id, as in 218). The signed profile card is not changed. Phones also report these people to the server (`offline_seen` in presence, max 20, seen in the last 15 min).

## Files

**Backend (new):**
- `internal/httpapi/recovery_reset_222.go`
- `internal/httpapi/join_relay_222.go`
- Tests: `recovery_222_test.go` (6), `join_relay_222_test.go` (7), `admin_web_222_test.go` (1)
- `TODO_222.md`

**Backend (changed):**
- `cmd/server/main.go`
- `internal/store/store.go` (migration 61)
- `internal/httpapi/recovery.go`, `trust.go`, `websocket.go`, `admin_panel.go`
- `internal/httpapi/adminweb/views.js`, `app.js`, `styles.css`

**App (new):**
- `lib/features/authentication/data/services/join_carrier_222.dart`
- `lib/features/admin/data/services/admin_offline_users_222.dart`
- Tests:
  - `forgot_password_222_test.dart` (13), `offline_reset_222_test.dart` (9);
  - `link_paths_zoom_222_test.dart` (4), `link_paths_small_222_test.dart` (2);
  - `crown_room_222_test.dart` (4);
  - `admin_users_offline_222_test.dart` (9), `join_carrier_222_test.dart` (10);
  - Kotlin `android/app/src/test/.../Join222Test.kt` (3).
- `TODO_222.md`, `APPLY_222.md`

**App (changed, in the TODO list):**
- `setup_screen.dart`, `account_recovery_screen.dart`, `account_recovery_bloc.dart`, `recovery_repository.dart`
- `locallink_api.dart`, `offline_account_sync_service.dart`
- `local_store.dart` (join box table, made with CREATE IF NOT EXISTS; the DB version stays 34)
- `link_paths_full_screen.dart`, `link_paths_map.dart`
- `admin_crown.dart`, `profile_screen.dart`, `account_center_screen.dart`, `messenger_settings_screen.dart`, `admin_users_screen.dart`
- `admin_bloc.dart`, `admin_tool_page216.dart`, `presence_service.dart`
- `MeshBlockPolicy.kt`
- `pubspec.yaml`, `app_build.dart`

**Outside the TODO file list (needed):**
- `app_dependencies.dart`: wiring (join carrier, offline-users book, presence hook, reset sync on reconnect).
- `home_screen.dart` + `join_cards218.dart`: her "Waiting for the server · carried by N phones" card (U-3) and the "password only on this phone" card.
- `recovery_repository_contract.dart`: shared reset types (the bloc may only import the domain layer).
- New `admin_offline_users_222.dart`: the Users offline rows, kept in their own file.
- Backend `adminweb/app.js` + `styles.css`: the Recovery Approve/Reject fix and the code dialog.

**Old tests changed (expectation only):**
- `test/nearby_190_test.dart`: version line -> `3.0.62+133` (as in every bundle).
- `test/bundle221b_test.dart`: the build check is now "at least 132". It was exactly 132, which broke on every new version (my mistake in 221).
- `test/bundle212f_test.dart`: 2 expectations (marked "Bundle 222"). The smallest zoom is now the whole map (below 1), because that is exactly the change you asked for.

**Windows test fixes (your 2026-11-06 run; setup only, no rule changed):**
- `test/profile_photo_204_test.dart` (204-6): waits for the picture file before checking it. It waited a fixed 150 ms, and the PC needed longer.
- Backend `internal/httpapi/admin_conversations_test.go` (TestNoteDeviceFrame...): the test's "old time" is now made in UTC. It was made in Pakistan time (+05:00) and compared as text with the server's UTC time, so it failed on your PC only.
- Backend `internal/httpapi/main_test.go`: turns on `LOCALLINK_TEST_FAST_DB=1` for the httpapi tests only.
- Backend `internal/store/store.go`: when BOTH `LOCALLINK_ENV=test` and `LOCALLINK_TEST_FAST_DB=1` are set, the database skips the forced disk flush (`synchronous(OFF)`). This is what made httpapi pass 10 minutes on Windows. The real server and the store tests still use `synchronous(FULL)`.

## Differences from TODO_222
- The app has no Urdu system, so the new screens are English only (no new translation system was made).
- The recovery code hint uses the real 20-character format (ABCDE-FGHIJ-KLMNO-PQRST).
- The join box carries the **recovery code hash**, not "same password": the server can't compare passwords for a box. Same name + same code = her own account.
- Join key from the 210 app share: not used. The share does not carry the server record, so only the "2 phones" rule (or an online phone) applies.
- Offline sightings come in `presence_update` (`offline_seen`), not in the 216 neighbour list (that struct must not change).
- After an online sign-in on a new phone, the saved code may be an old local one. The offline reset still works there, but the server refuses the sync and the "password only on this phone" card shows.
- Profile -> new recovery code now also updates the code saved on the phone (it did not before).

## Phone tests
- **222-1** Logout -> Forgot password -> username + code + new password (online) -> signed in, new code shown once. The old password fails; the new one works on another phone; your other phone is still signed in.
- **222-2** "I don't have it" -> request -> web Recovery shows "No code" -> Approve (code in a dialog) -> type the 12-digit code + new password -> signed in.
- **222-3** Server off -> Forgot password on the same phone with the code -> signed in. Later online -> the new password works on the server, and a new code shows once.
- **222-4** Wrong code 5 times -> "Too many tries. Try again in 1 minute".
- **222-5** Admin map: "−" and pinch go down to the whole map, then "−" turns grey; double tap goes to 2x. **Lines look and move exactly as before.**
- **222-6** Small map with nobody else linked: You + Server with the moving green line + "No other phones linked".
- **222-7** Crown fully visible on Profile, Users, Settings and Account (light + dark).
- **222-8** Sumaira makes an account offline and meets the admin phone with no server -> Admin -> Users shows "Offline account · Not on server yet" + the orange bar.
- **222-9** Sumaira stays offline; Ali's phone meets her (her card: "carried by 1 phone"), then Ali gets internet -> web Users shows her joined -> Ali meets her again -> she is on the server without ever being online.
- **222-10** Name taken -> she becomes sumaira37 by the carried join; her friends see the new name.
- **222-11** Search Ali's log file for her password: it is not there.

Logs to send if something fails:
- Reset: `RESET_OFFLINE_OK`, `RESET_SYNC_*`, `RESET_CODE_*`, `RECOVERY_NOCODE_*`.
- Carried join: `JOIN_KEY_SAVED`, `JOIN_KEY_FROM_PHONES`, `JOIN_BOX_MADE`, `JOIN_BOX_GOT`, `JOIN_BOX_CARRIED`, `JOIN_RELAY_UPLOADED`, `JOIN_RELAY_DONE`, `JOIN_RELAY_FAIL`, `JOIN_ANSWER_TAKEN`, `JOIN_RELAY_JOINED`.
- Users: `USERS_LOCAL_ROWS`.
