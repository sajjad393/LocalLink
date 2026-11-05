# APPLY 211: photo lock + tap to change, admin stays signed in, Gmail-style switch

App 3.0.52+123 · DB v34 (no change) · no new permissions.
Backend: separate zip `locallink_backend_211_2026-11-05.zip`. **Deploy the backend first.**

## Your 3 open questions: what I picked (my advice)
- Q1: a picked photo **saves at once**. The Save button is still there for name and phone. First-time setup still uses Save.
- Q2: the web panel **stays signed in** (localStorage) until you press Sign out.
- Q3: the Settings Admin section **hides 5 s after the server drops**. It comes back as soon as the server returns.
- Q4 is still open: if the app sign-in still fails, send the exact message, the "Server: …" line under the button, and the web panel URL.

## What changed
**A. Photo and lock**
- Account now shows the Private ring + lock (it was already on Settings and Profile).
- Profile: the camera button is gone (it covered the lock).
- Tap the photo → a camera shows in the middle for 3 s → tap it → Take photo / Gallery / Remove photo.
- Under the name: "Tap photo to change" (or "Tap photo to add one").

**B. Admin sign-in stays until Sign out**
- The sign-in has no 30-minute limit. It survives closing the app and restarting the phone.
- It ends only on:
  - Sign out,
  - a revoke in web Sessions,
  - an admin password reset.
- The phone clock is no longer checked.
- When the server says the sign-in is gone (only while online): "Admin sign-in ended. Sign in again." Offline never signs you out.
- Sign out while offline: the phone forgets it at once, and the server is told on the next connect.

**C. Switch (Gmail style)**
- Settings → tap **your photo** → sheet: you / Admin / Sign out of Admin.
- Admin opens with no password once you have signed in.
- In Admin: the shield button (top right) → you (back to chats) or Sign out.
- The rest of the Settings card still opens Account.

**D. Settings Admin section** shows only while the server is connected. When offline, use the photo (if already signed in).

**E. Sign-in errors in plain words**
- Wrong username or password / Too many tries / Can't reach the server at host:port / server problem (code) / no admin sign-in on this server.
- The keyboard no longer auto-capitalises or auto-corrects the username and password.
- The line "Server: host:port" is under the Sign in button.
- The log has an `ADMIN_LOGIN result=… status=… host=…` line, with no username or password.

**Backend (F)**
- The admin sign-in lasts until logout, a revoke or a password reset (TTL 10 years).
- The web panel keeps you signed in (localStorage). It shows "· signed in until you sign out".
- New Go test.

## Old test touched (setup only)
`test/bundle183_test.dart` 'F Settings' test: added `_viewMode.setServerConnected(true)` (+ teardown back to false), because the Admin section now needs the server. No expectation changed.
Version stamp in `test/nearby_190_test.dart` → 3.0.52+123 (done every bundle).

## Files
App:
- New:
  - `lib/features/account/presentation/widgets/photo_tap_overlay.dart`
  - `lib/features/admin/presentation/widgets/account_switch_sheet.dart`
  - `lib/features/admin/domain/admin_login_error.dart`
- Changed:
  - `profile_screen.dart`, `account_center_screen.dart`
  - `admin_session.dart`, `admin_session_store.dart`, `admin_capability_service.dart`
  - `admin_login_screen.dart`, `admin_panel_screen.dart`
  - `messenger_settings_screen.dart`, `app_dependencies.dart`
  - `pubspec.yaml`
- Tests:
  - `bundle211a..f_*_test.dart`, `support/g211_fakes.dart`
  - `bundle183_test.dart` (setup), `nearby_190_test.dart` (version)

Backend: `internal/httpapi/admin_auth.go`, `internal/httpapi/adminweb/app.js`, `internal/httpapi/admin_session_211_test.go`.

## Phone tests
- [ ] 211-1 Private ON: Settings, Account and Profile all show ring + lock. Public: none.
- [ ] 211-2 Profile: no camera button. Tap photo → camera for 3 s → it goes away by itself.
- [ ] 211-3 Tap photo → tap camera → Gallery → "Profile saved" at once; the new photo shows on Settings + Account.
- [ ] 211-4 No photo: tap the letter circle → camera → add a photo.
- [ ] 211-5 Admin sign-in with the **same** username/password as the web → opens. If it fails: write the exact message + the "Server:" line.
- [ ] 211-6 Wrong password → "Wrong username or password." Wi-Fi off → "Can't reach the server at …".
- [ ] 211-7 Settings → tap photo → Admin → opens with no password. Admin → shield → sajjad → back to Settings.
- [ ] 211-8 Close the app, restart the phone, wait 1 hour+ → photo → Admin → still no password.
- [ ] 211-9 Server off (or Wi-Fi + data off) → after ~5 s Settings has no Admin section. Photo → Admin → offline panel with the test switches.
- [ ] 211-10 Server back → the Admin section returns by itself.
- [ ] 211-11 Photo → Sign out of Admin → Sign out → next time it asks for the password. Chats untouched.
- [ ] 211-12 Web → Sessions → revoke the phone's admin session → on the phone open Admin (online) → "Admin sign-in ended. Sign in again."
- [ ] 211-13 Sign out while offline → reconnect → web Sessions: that session is gone.
- [ ] 211-14 Send logs (`ADMIN_LOGIN`, `ADMIN_SIGN_OUT` lines).
