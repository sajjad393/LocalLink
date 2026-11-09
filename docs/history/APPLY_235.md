# APPLY 235 - one phone = one account (app 3.0.72+143)

App + backend. **Deploy the backend first.**

- Backend zip: `locallink_backend_230-231-235_2026-11-09.zip` (230 + 231 + 235). It replaces the 230-231 zip.
- App zip: `locallink_app_235_2026-11-09.zip` (one commit, on top of `e5f7494`).
- App DB stays 34. The backend makes one new table (`duplicate_waits`) by itself.

## PowerShell (backend, first)
```
cd "C:\Users\sajjad Ahmed\Downloads\localLinkBackend"
Expand-Archive -Force -Path "C:\Users\sajjad Ahmed\Downloads\locallink_backend_230-231-235_2026-11-09.zip" -DestinationPath .
go test ./...
git add -A
git add -f APPLY_230.md APPLY_231.md APPLY_235.md TODO_230.md TODO_231.md TODO_235.md
git commit -m "v3 bundles 230-231-235 backend: admin sign-in ends after 180 unused days, no-account devices off by default (LOCALLINK_ALLOW_DEVICE_ONLY), constant-time pairing code checks, PBKDF2 600000 rounds with re-hash on login (230); pairing info proves the server signing key (231); one phone = one account - a new account on a known phone waits for proof, admin Waiting for proof list with New owner and Dismiss, server-signed return note (235)"
git push
```
Before you restart the server, run this check (from 230):
```
sqlite3 data\locallink.db "SELECT COUNT(*) FROM devices WHERE COALESCE(user_id,'')='' AND COALESCE(status,'active')='active';"
```
If the result is above 0, set `LOCALLINK_ALLOW_DEVICE_ONLY=true`.

## PowerShell (app)
```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force -Path "C:\Users\sajjad Ahmed\Downloads\locallink_app_235_2026-11-09.zip" -DestinationPath .
flutter pub get
flutter test -j 1
git add -A
git add -f APPLY_235.md TODO_235.md
git commit -m "v3 3.0.72+143 bundle 235: one phone = one account - a new account on a phone friends know as another account is blocked at once (offline too) and shows Confirm your account; the recovery code (offline, checked with the recovery key a friend holds) or the old password (server) brings the old account back; friends take the new keys from a signed return card; only the web admin can give the phone to a new owner; a new recovery code is hidden (Show / Hide) and saved with Save on WhatsApp (235 screen, Forgot password, home card, Profile)"
git push
```
Then build the APK as usual.

## What users see
- **The phone with the second account** (example: the Note had @ali, now @ali2 is made on it):
  - As soon as it meets a friend of @ali (Wi-Fi Direct, mesh, same Wi-Fi) or the server, the whole app is covered by **"Confirm your account"** (no back button).
  - **Use recovery code**: recovery code + new password twice -> "Confirm it's me". Works with no server if a friend nearby holds @ali's recovery key.
  - **Use old password**: only when the chip says "Server connected".
  - Wrong code -> "That code is not right."
  - With the server, the new recovery code is shown once, hidden (Show / Copy), with **Save on WhatsApp** (see below).
  - "Check again" asks the server again (for when the admin gave the phone away).
- **Friends' phones:** nothing new on screen. @ali2 never shows up; @ali's chat goes on after the proof.
- **Web admin:** chip "Waiting for proof N" (only when N>0) and the panel "Waiting for proof" with **New owner...** and **Dismiss**.

## Save on WhatsApp + hidden code (235 addition, mock `mock_235_whatsapp.png` v3)
- In all 4 places a NEW recovery code shows up (235 done screen, Forgot password done screen, the home card "Your recovery code changed", Profile -> Recovery code -> new code):
  - The code is hidden (dots). **Show** / **Hide** next to **Copy** (+ **Share** on Forgot password). Hidden again every time it opens.
  - Copy (and WhatsApp) use the real code even while hidden.
  - Green **Save on WhatsApp** replaces "I saved it". It opens WhatsApp (or WhatsApp Business) with: `My LinkUp recovery code (@ali): XXXXX-... - keep it private.` -> pick "Message yourself" -> send.
  - Back in LinkUp, the screen / card / box closes by itself.
  - No WhatsApp on the phone -> the code is copied, message "Copied. WhatsApp is not on this phone.", nothing closes.
  - Forgot password with no server (no new code) keeps "OK".
- Profile dialog: button "Done" is now "Close".
- No new permission, no manifest change.

## Who needs the update
- **Everyone.** Friends' phones do the offline check (they hold the recovery key and refuse the new account). A friend with the old app still lets @ali2 in.
- Each phone sends its own recovery key to friends when they meet (only if the phone has its recovery code saved).

## Different from the plan (tell me if you want it changed)
1. The server answer stays `409 DEVICE_TAKEN`, with `duplicate:true` added (old apps keep working).
2. A refused sign-up keeps no new display name on the server (only the username).
3. The web shows "Tried to join <when>" (+ tries), not "Seen by <phone>".
4. The admin chip shows only when there is at least 1 waiting.
5. The app screen adds "Check again".
6. No server and no friend's recovery key yet -> the code path says "No friend's phone could check the code yet..." (it can't check the code alone).
7. A login (not only a sign-up) of a different existing account on a known phone also waits for proof.
8. (Addition) The WhatsApp code lives in the shared widget file (`recovery_code_save_235.dart`), not a separate service file.
9. (Addition) The home card button has no hint line under it (small card); the full screens and the Profile box have it.

## Limits (known)
- The recovery key needs a saved recovery code on the old phone (made at sign-up / reset).
- A fake "owner" note can lock a new account on a phone; the admin frees it ("New owner").
- Owner / return messages go one step only (direct link, no mesh relay).
- Background service, calls and the native link-key cache were not changed; the native link keys refresh on their normal schedule.
- After "New owner", friends that stay offline keep refusing the new account until they reach the server once.
- The password path leaves the recovery code unknown until the next reset.
- A phone-only return goes up to the server when the phone has an offline publish secret, or at the next silent re-sync burst.
- (Addition) Going back from WhatsApp WITHOUT sending still closes the screen (the app can't know if you sent it). If that happens: Profile -> Recovery code -> Replace code makes a new one.
- (Addition) The native WhatsApp part (MainActivity.kt) was not compiled here (no APK build in my workspace) - `flutter build apk` checks it.

## Phone tests (after building 3.0.72)
1. Note has @ali, C71 is @ali's friend. Reinstall the Note, make @ali2 offline. Connect to C71 (Wi-Fi Direct). -> The Note shows "Confirm your account" within seconds. C71 log: `DUP_ACCOUNT_BLOCKED`.
2. On the Note: @ali's recovery code + a new password -> the app opens as @ali. C71: the chat with @ali goes on, a call works.
3. Reinstall again, make @ali3 with the server on. -> Sign-up refused, the screen shows, chip "Server connected". Use the old password of @ali -> opens as @ali.
4. Wrong code -> "That code is not right."
5. Web admin -> "Waiting for proof" shows the line. "New owner..." -> type the name -> the Note taps "Check again" -> opens as the new account.

6. (Addition) Profile -> Recovery code -> Replace code: the code shows as dots. Show -> the code, Hide -> dots. Copy -> paste somewhere -> the real code.
7. (Addition) Tap **Save on WhatsApp** -> WhatsApp opens with the message -> "Message yourself" -> send -> back: the box closes. Close and open again -> hidden again.
8. (Addition) On a phone without WhatsApp (or WhatsApp disabled): Save on WhatsApp -> "Copied. WhatsApp is not on this phone." and the box stays.
9. (Addition) Forgot password with the code + server -> done screen: green tick, hidden code, Share works, Save on WhatsApp closes it after coming back.

Logs to look for: `DUP_ACCOUNT_BLOCKED`, `DUP_ACCOUNT_NEW_OWNER`, `DUP_PROOF_OK` / `DUP_PROOF_FAIL`, `DUP_RETURN_SYNC_SENT` / `OK` / `FAIL`, `DUP_RETURN_NOTE_FAIL`. Server: `DUP_ACCOUNT_BLOCKED`; audits `duplicate_refused`, `duplicate_new_owner`, `duplicate_dismiss`, `account_return_note`.

## Old tests changed
- `test/bundle223_logs_test.dart`, `test/nearby_190_test.dart`: only the version pin (3.0.71+142 -> 3.0.72+143).
- (Addition) `test/forgot_password_222_test.dart` R-4: taps Show before checking the code; "I saved it" -> "Save on WhatsApp" (fake WhatsApp + coming back).
- (Addition) `test/bundle218e_test.dart` "recovery card": the code is hidden (no text field any more), Show, Copy as before, `join218_saved` = Save on WhatsApp (fake WhatsApp + coming back).

## Files
App:
- new `lib/core/identity/dup_account_235.dart`
- new `lib/features/directory/data/services/duplicate_guard_235.dart`
- new `lib/features/authentication/data/services/account_return_235.dart`
- new `lib/features/authentication/presentation/screens/confirm_account_235_screen.dart`
- new `test/bundle235_test.dart`
- new `lib/features/recovery/presentation/widgets/recovery_code_save_235.dart` (addition)
- (addition) `android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt`, `lib/features/recovery/presentation/screens/account_recovery_screen.dart`, `lib/features/home/presentation/widgets/join_cards218.dart`, `lib/features/home/presentation/screens/home_screen.dart`, `lib/features/account/presentation/screens/profile_screen.dart`, `test/forgot_password_222_test.dart`, `test/bundle218e_test.dart`
- `lib/app/app_dependencies.dart`, `lib/app/local_link_app.dart`, `lib/core/config/app_build.dart`, `pubspec.yaml`
- `lib/core/services/local_store.dart`, `lib/core/services/locallink_api.dart`
- `lib/features/authentication/data/services/offline_account_sync_service.dart`
- `lib/features/connectivity/data/services/sealing_peer_transport.dart`
- `lib/features/directory/data/repositories/directory_repository.dart`, `lib/features/directory/data/services/pairing_service.dart`

Backend:
- new `internal/httpapi/duplicate_235.go`, `internal/httpapi/duplicate_235_test.go`
- `cmd/server/main.go`, `internal/httpapi/auth.go`, `internal/httpapi/join_relay_222.go`, `internal/httpapi/adminweb/views.js`
