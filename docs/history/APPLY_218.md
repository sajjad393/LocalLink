# APPLY 218 – app 3.0.59+130 (offline account joins the server)

Built on app `64d103e` (3.0.58+129). **Order: backend 218 zip → commit → deploy → then this app zip.**
The app also works with an old server (no error codes): it falls back to today's behaviour (rename on a taken name, red mark when the server does not know someone).

## What she sees
- **Chats, once, after joining** (mock U-1 / U-2): card "You're on the server now" with one of 3 texts:
  - name free → "Your account is on the server now. Your chats stay on this phone."
  - name used by someone else → "@sumaira was taken, so you are @sumaira37. …" (her friends get her new card)
  - same name + same password → "This phone joined your account @sumaira. …" (no rename; her server profile wins)
  - orange line "Your phone number stays on this phone only." when the number belongs to another account.
  - **Account** opens Profile, **OK** hides it for good.
- **Recovery card** only when an old server made a new code (Copy / I saved it). With the 218 server her offline code keeps working, so no card and no dialog.
- **Stuck card** (mock U-3) instead of silent retries: "This phone is already linked to @ali on the server…" (the @name only when the server proves it is the same phone, else "another account"), or "The server needs a pairing code" with a code field. **Try again** joins at once.
- **Profile** (mock U-4): orange phone field + "Used by another account. Saved on this phone only." Typing another number hides it.
- **Chat** (mock U-5): a message to someone who is not on the server keeps the clock (never red). Message info shows "Not sent yet" + "Zeeshan is not on the server yet. It goes when Zeeshan is nearby or joins the server."
- **Admin app → Users → person** (mock A-5): "Joined from offline · 5 Nov 2026".

## What happens inside
- **Join** (`offline_account_sync_service.dart`): after register/login the profile row gets the real id, the waiting profile is sent with the final name (and her offline photo), the offline login copy is updated, the old→new id is remembered (`id_moves_218`), then the join hook (`app_dependencies.dart`) pulls/pushes the profile, publishes her card, syncs contacts and flushes waiting messages.
  - Name taken → one sign-in try with the same password first (also fixes "the answer was lost" so no orphan rename); otherwise today's rename.
  - The 216 log steps are unchanged (`CHECK, PROBE, PUBLISH, PUBLISH, DONE`); new lines: `OFFLINE_ACCOUNT_LINK_NO`, `OFFLINE_ACCOUNT_STUCK`, `OFFLINE_ACCOUNT_BLOCKED_BY`, `OFFLINE_ACCOUNT_PHONE_LOCAL_ONLY`, `OFFLINE_ACCOUNT_PROFILE_PUSHED`.
- **API** (`locallink_api.dart`): register sends `offline_user_id` + `recovery_code`, login sends `offline_user_id` (only while the account is waiting). Server errors come as `ApiError218(code, owner)`; the shown text is unchanged. `PHONE_TAKEN` → saved again without the number (kept on this phone). `POST /api/v1/users/resolve`.
- **Friends' phones** (`directory_repository.dart`, `local_store.dart`, `peer_photo_book.dart`): a card with her server id, from the same phone **and the same signing key**, moves contact / custom name / private mark / block / picture from her offline id to the new id (`ID_MOVED`). Chats are kept by phone id, so nothing moves there. A block by phone id also covers her new id. Every 30 min (and right after joining) offline ids are asked from the server; offline ids are never pushed to the server contacts list (`CONTACT_PUSH_SKIP_OFFLINE` once).
- **Messages** (`reliable_messaging_service.dart`, new `not_on_server_218.dart`): "recipient device not found" → the message waits (`MESSAGE_WAIT_NOT_ON_SERVER`), no upload / no server copy for 30 min, it goes by nearby, and at once when the server learns her phone (resolve, her new card, reconnect). Once after the update, red messages of the last 60 days go back to the clock (`MESSAGE_REQUEUE_218`). Other errors stay red as before.

## Small changes from TODO_218 (on purpose)
1. Error codes travel as `ApiError218` (code + owner), not a `[code=X]` text suffix, so no error text shown to users changes.
2. Friend links she signed with the old id are checked while her old card is still there, then they move with the contact (rewriting the id would break the signature). A waiting add from this phone is signed again for her new id.
3. The old "Account published / New recovery code" dialog after the manual publish is replaced by the recovery card (it only shows when the code really changed).
4. `updateProfile` also keeps the local-only number on this phone (otherwise the saved copy would lose it).
5. `joinedOffline218()` (date text) sits in `admin_users_screen.dart`, so `admin_format216.dart` is untouched.
6. The join card's left padding is 14 and the icon gap 10 (TODO said 16 / 12) so the text sits exactly where the mock has it and the orange line fits on one line.
7. 218c tests use fakes (the project has no sqflite ffi); the SQL of `moveUserId218` was checked against the real table layout with sqlite3 here.

## Files
- `lib/features/authentication/data/services/offline_account_sync_service.dart`
- `lib/core/services/locallink_api.dart`, `lib/core/services/local_store.dart` (new methods only)
- `lib/features/account/data/repositories/account_repository.dart`
- `lib/features/directory/data/repositories/directory_repository.dart`, `lib/features/directory/data/peer_photo_book.dart`
- `lib/features/messaging/data/services/reliable_messaging_service.dart`, new `lib/features/messaging/data/services/not_on_server_218.dart`
- `lib/features/messaging/presentation/widgets/message_options.dart`, `lib/features/messaging/presentation/screens/chat_screen.dart`
- new `lib/features/home/presentation/widgets/join_cards218.dart`, `lib/features/home/presentation/screens/home_screen.dart`
- `lib/features/account/presentation/screens/profile_screen.dart`
- `lib/features/admin/presentation/screens/admin_users_screen.dart`
- `lib/app/app_dependencies.dart`
- `pubspec.yaml`, `lib/core/config/app_build.dart` (3.0.59+130)
- new tests `test/bundle218b_test.dart`, `bundle218b_api_test.dart`, `bundle218c_test.dart`, `bundle218d_test.dart`, `bundle218e_test.dart`
- **Old test changed:** `test/nearby_190_test.dart` – the version line only (3.0.58+129 → 3.0.59+130).
- `APPLY_218.md`, `TODO_218.md`

## Checked here
- `flutter analyze` = 159 (same as before, nothing new).
- New tests: 218b 12 + 218b_api 8 + 218c 10 + 218d 10 + 218e 15 = 55, all pass; 216f passes unchanged.
- Full suite in chunks: 2088 tests, all pass.
- `ui_check_218.jpg` (in the chat): U-1…U-5 and A-5 built next to the mocks.
- Not checked here: a real phone (no APK build in this sandbox) – see the phone tests in `TODO_218.md` §8.
