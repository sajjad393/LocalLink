# TODO 211 (built 2026-11-05: app 1808/1808 tests, analyze 166; backend go test ok): Private lock everywhere, tap-photo camera, Admin switch (no re-login), clear admin login errors, Admin hidden offline

Status: **BUILT** (bundle 211 zip). Planned Code-checked at app HEAD `30109f9` (210, 3.0.51+122) and backend HEAD `b17f935`.
Nothing is built. Needs your **"go ahead"** (freeze).
Mocks: `mock_lock_all.jpg` (7 pages, lock + camera) and `mock_switch_account.html` (10 phones, switch + offline).
Target: app **3.0.52+123**, DB stays **v34**, no new permission, no new package.
Backend: **one small change** (admin sign-in no longer ends after 30 min) → separate backend zip, **deploy backend first**.

---

## 0. Your decisions (2026-11-05)
| # | Topic | Decision |
|---|---|---|
| 1 | Private lock | Ring + lock on **Settings, Account, Profile** only (not "You" chat, not My QR, never on friends). Public = no ring, no lock. |
| 2 | Profile camera | **Camera button removed.** Tap the photo (or letter circle) → dark circle + camera in the middle for **3 s** → tap camera → photo choice. Nothing shows until you tap. |
| 3 | Switch | **Tap your photo on Settings** → "Switch account" list: **sajjad** / **Admin** (Gmail-style). No password when switching. |
| 4 | Admin sign-in ends | **Only on "Sign out of Admin"** (also when removed from Admin → Sessions, or admin password reset on the server). Survives app close + phone restart. |
| 5 | Admin section in Settings | Shown **only while the server is connected**. Offline: reach Admin through the photo list if already signed in (existing offline panel, bundles 134/162). |
| 6 | Server drops while in Admin | Stay in Admin, server parts locked (as today, bundle 162). |
| 7 | Login error | Show the **real reason**, never "Something went wrong". |

## 0b. Questions to confirm before building (my advice first)
- **Q1 Photo save:** after you pick a photo, save it **at once** (my advice, you said "then upload") or keep the "Save changes" button as today?
- **Q2 Web panel:** the web panel also stays signed in after closing the browser tab (my advice, same rule as the app), or keep "closing the tab signs out"?
- **Q3 Flicker:** hide the Admin section **after 5 s** without the server (my advice, so it doesn't blink on a short drop), or at once?
- **Q4 Admin login cause:** still need from you: screenshot of the error, the app's server address, the web panel URL, logs right after the failed try. The fixes below help in every case; the logs tell which case it was.

---

## 1. What the code does today (checked)

### 1a. Private lock
- `lib/core/widgets/account_avatar.dart` L21 `locked` → ring + lock badge (bundle 207 option B), keys `avatar_private_lock/ring/badge`.
- Settings card: `messenger_settings_screen.dart` `SettingsOwnAvatar` (L346-398) passes `locked: own == true` from `ProfilePrivacyRule.ownPrivate`. ✅
- **Account:** `account_center_screen.dart` **L189-192** `AccountAvatar(name, localPath, radius: 28)` → **no `locked`** ❌.
- **Profile:** `profile_screen.dart` **L362-377**: `Stack(alignment: bottomRight)` with `AccountAvatar(radius: 52, locked: …)` **and** `IconButton.filled(camera)` at L375 → both bottom-right, the button **covers the lock** ❌.
- Photo choice: `_pickImage()` L180 → `showProfilePhotoSheet` (Take photo / Gallery / Remove photo, `profile_photo_sheet.dart`). The picked file is only sent on **Save changes** (`save()` L161 `avatarFile`).

### 1b. Admin sign-in / session
- App login: `admin_login_screen.dart` `_login()` **L74-100** → `AdminService.login` (`admin_service.dart` L74-87, `POST {baseUrl}/api/v1/admin/login`, same JSON as web).
- **Hidden reason:** `AdminRequestException.toString()` (L13) returns only the server text ("invalid admin credentials"), so `friendlyErrorMessage` (`core/widgets/error_toast.dart` L14-50) finds no "401" → **"Something went wrong. Please try again."**
- **Phone clock:** L88 rejects the login if `session.expired` (`admin_session.dart` L29-32 compares `expires_at` with the **phone** clock). Clock 30+ min ahead → good login thrown away.
- **Keyboard:** username + password `TextField`s (L212-237) have default autocorrect / suggestions / capitals.
- **Server address:** app uses `store.serverAddress` (`locallink_api.dart` L213); web uses the browser URL. Your Account screen showed "Can't reach LinkUp" → may be a different/unreachable address.
- **30 min:** backend `admin_auth.go` **L16 `adminSessionTTL = 30 * time.Minute`**, set once at login (L199), never extended (`authorizeAdminSession` L243-257 only updates `last_seen_at`).
- App throws the saved session away when expired: `admin_session_store.dart` `read()` L22-44 (`if (session.expired) clear()`); `profile_screen.dart` L117-122 also checks `expired`.
- Settings → "Admin panel" row (`messenger_settings_screen.dart` **L283-303**) → `AdminLoginScreen` → `_restore()` L64-72 opens `AdminPanelScreen` directly **if** a saved session is still valid → that's why it works for 30 min, then asks again.
- `AdminPanelScreen` (the panel really used, `admin_panel_screen.dart`): AppBar "Admin" + status chip (L300-317), offline banner, local tools (Nearby test switches, blocklist, storage test), server module grid locked offline. **No Sign out, no 401 handling.**
- `AdminShellScreen` (old shell with "View as User" / "Sign out", L163-190, L691-760) is **not opened anywhere** in the app now (only its tests use it) → leave it alone.
- Server reachability: `AppViewModeCubit.serverConnected` (`core/state/app_view_mode.dart`), set in `app_dependencies.dart` L151 / L686 / L755.
- Backend password reset already revokes all admin sessions (`ResetAdminCredentials`, L143-150). Admin → Sessions list + revoke exist (`admin_panel.go` L195, L327).
- Web panel: `adminweb/app.js` L14 token in **sessionStorage** (tab close = signed out), L262-267 shows "expires in …", L714-721 login.

---

## 2. New and changed files

**New (Dart):**
- `lib/features/admin/presentation/widgets/account_switch_sheet.dart`: the "Switch account" bottom sheet + "Sign out of Admin?" dialog.
- `lib/features/admin/domain/admin_login_error.dart`: turns a login failure into one plain sentence (pure, testable).
- `lib/features/account/presentation/widgets/photo_tap_overlay.dart`: the 3 s dark circle + camera on top of an avatar.

**Changed (Dart):**
| File | Change |
|---|---|
| `account_center_screen.dart` | L189 avatar gets `locked` (same `ownPrivate` listener as Settings) |
| `profile_screen.dart` | remove camera `IconButton` (L375); avatar wrapped in `PhotoTapOverlay`; "Tap photo to change" line; `_refreshAdminCapability` uses the new "usable" check |
| `messenger_settings_screen.dart` | own avatar tap → switch sheet (rest of card still → Account); Admin section only while `serverConnected` |
| `admin_login_screen.dart` | real error text, keyboard settings, no phone-clock check, `ADMIN_LOGIN` log, intro text |
| `admin_session.dart` | add `usable` (token + ids present); keep `expired` as is (old test unchanged) |
| `admin_session_store.dart` | `read()` no longer deletes on expiry; pending server sign-out token |
| `admin_capability_service.dart` | `readValidSession()` = saved + usable |
| `admin_panel_screen.dart` | AppBar Admin icon → switch sheet; 401 from server → signed out with a message; sign-out sends pending revoke |
| `pubspec.yaml`, `test/nearby_190_test.dart` | version 3.0.52+123 |

**Changed (backend, separate zip):** `internal/httpapi/admin_auth.go` (TTL), `internal/httpapi/adminweb/app.js` (label; storage per Q2), new `admin_session_ttl_test.go`.

---

## 3. Phases

### Phase A: Private lock + tap-photo camera (app)
- [x] **A1 Account lock.** `account_center_screen.dart` L189: wrap in `ValueListenableBuilder(ProfilePrivacyRule.ownPrivate)`; `locked: own ?? ProfilePrivacyRule.isPrivate(profile)`. Same 28 dp size, so it matches Settings exactly (badge 18 dp, ring 2 dp).
- [x] **A2 Remove camera button.** `profile_screen.dart` L375 `IconButton.filled` removed; `Stack` keeps only the avatar → lock badge visible bottom-right.
- [x] **A3 `PhotoTapOverlay` widget** (new): `child` = avatar, `radius`, `onCamera`.
  - Tap the photo → overlay on (key `profile_photo_overlay`): dark circle 45% black over the **inner photo only** (ring + lock stay clear), white camera icon in the middle (key `profile_photo_camera`, size = radius × 0.5).
  - Hides after **3 s** (Timer, cancelled in `dispose`), on a second tap outside the camera, or when the screen loses focus.
  - Tap camera → overlay off → `onCamera()` = existing `_pickImage()` (Take photo / Gallery / Remove photo sheet, unchanged).
  - Works the same with a photo or the letter circle. Semantics label "Change profile photo" kept (TalkBack).
- [x] **A4 Hint line** under `@username`: "Tap photo to change" (no photo: "Tap photo to add one"); while the overlay shows: "Tap the camera to choose a photo". Key `profile_photo_hint`. Small, primary colour.
- [x] **A5 Photo save (per Q1).** If "at once": after a pick/remove, call the existing `save()` path (same validation; if name/phone invalid, the usual error shows and the photo stays pending for Save changes).
- [x] **A6** No change on friends' photos, "You" chat, My QR (decision 1).

### Phase B: Admin sign-in stays until Sign out (app)
- [x] **B1 `AdminSession.usable`** = token, adminId, username, role not empty. `expired` getter unchanged (test `admin_session_model_test.dart` stays green).
- [x] **B2 `AdminSessionStore.read()`**: returns the saved session if `usable`; **no delete on expiry** (the server decides).
- [x] **B3 `AdminCapabilityService.readValidSession()`** → saved + usable. `profile_screen.dart` L120 uses `session != null` only.
- [x] **B4 Login** (`admin_login_screen.dart` L88): only `token.isEmpty` is an error (phone clock ignored).
- [x] **B5 Server says "not signed in" (401) while online** → the only automatic end (removed from Sessions / password reset):
  - `AdminPanelScreen` listens to `AdminBloc.sessionExpired` → clear store, `viewMode.setAdminCapability(false)`, pop back to your chats, snack: "Admin was signed out on the server. Sign in again."
  - Offline errors never sign out (no 401 offline).
- [x] **B6 Sign out of Admin** (from the switch sheet, B/C): confirm dialog → `POST /admin/logout` → clear store → back to chats.
  - Offline: clear on the phone at once and save the token as `pending_revoke`; sent to the server on the next connect (`serverConnected` → true), then deleted. So a phone signed out offline can't stay signed in on the server.
- [x] **B7** Intro text on the sign-in screen: "Sign in once on this phone. You stay signed in until you tap Sign out." (replaces "Admin sessions expire automatically…", L206-209).

### Phase C: Switch account sheet (app)
- [x] **C1 `AccountSwitchSheet`** (new widget, keys `switch_sheet`, `switch_user`, `switch_admin`, `switch_admin_signin`, `switch_admin_signout`):
  - Row **sajjad**: own avatar (with ring + lock if Private), "@sajjad · Chats, calls, people", tick when in your chats.
  - Row **Admin** (session saved): shield avatar, "<admin username> · <role> · signed in" (offline: "offline: test tools only"), tick when in Admin.
  - **No session + server connected:** "Sign in to Admin" → `AdminLoginScreen`.
  - **No session + offline:** no Admin row (sign-in needs the server).
  - "Sign out of Admin" at the bottom (only with a session).
  - Note line: "No password when you switch. Admin stays signed in until you tap Sign out."
- [x] **C2 Settings:** `SettingsOwnAvatar` gets its own `GestureDetector` (key `settings_avatar_switch`) → opens the sheet; the rest of the card keeps `_openAccount` (bundle 183 A1 rule "card = only way into Account" stays true).
- [x] **C3 Admin panel:** AppBar action = small shield avatar (key `admin_switch_button`) before the status chip → same sheet (current = Admin).
- [x] **C4 Switching:** Admin opens as today (`AdminPanelScreen` pushed over Settings, `setAdminCapability(true)`); "sajjad" from inside Admin pops it (`enterUserView`). Back button from Admin = back to Settings (as today). The app always starts in your chats (view mode not saved, as today).

### Phase D: Admin section only with the server (app)
- [x] **D1** `messenger_settings_screen.dart` L283-303: wrap the `ADMIN` label + "Admin panel" row in `BlocBuilder<AppViewModeCubit>` → shown only when `serverConnected` (per Q3: hidden after 5 s offline; shown at once when connected).
- [x] **D2** Row tap unchanged: saved session → panel opens straight away; else sign-in.
- [x] **D3** Offline + signed in → Admin only via the photo list → existing offline panel (local tools work, server modules locked). No change inside the panel.

### Phase E: Clear admin login errors (app)
- [x] **E1 `adminLoginErrorText(error, serverAddress)`** (new, pure):
  | Case | Text |
  |---|---|
  | 401, or 400 "invalid admin credentials" | "Wrong username or password." |
  | 429 | "Too many tries. Wait 1 minute and try again." |
  | SocketException / connect timeout | "Can't reach the server at <host:port>. Check Wi-Fi or the server address in Settings." |
  | no server address saved | "No server address on this phone. Set it in Settings first." |
  | 404 | "This server has no admin sign-in. Check the server address." |
  | 5xx | "The server has a problem (code N). Try again later." |
  | not JSON (HTML / proxy page) | "The server answered in a wrong way. Check the server address." |
  | other | "Sign-in failed (code N)." (never "Something went wrong") |
- [x] **E2 Keyboard:** both boxes `autocorrect: false`, `enableSuggestions: false`, `textCapitalization: none`; username `keyboardType: visiblePassword` (stops Gboard word guesses); password not trimmed (same as web).
- [x] **E3 Log** `ADMIN_LOGIN result=ok|wrong|rate|unreachable|no_server|not_found|server|format status=N host=<host:port>` (never username or password). HTTP lines already log the code.
- [x] **E4** Show the server address under the Sign in button in small grey: "Server: 192.168.1.5:8080" → you can compare with the web URL.

### Phase F: Backend (separate zip, deploy first)
- [x] **F1** `admin_auth.go` L16: `adminSessionTTL = 10 * 365 * 24 * time.Hour` with comment "ends only on logout, revoke, or password reset". Column and checks unchanged (no DB migration).
- [x] **F2** Old 30-min sessions already in the DB just end once → sign in one more time after the update.
- [x] **F3** `adminweb/app.js` L262-267: show "signed in until you sign out" instead of "expires in 10 years". Q2: `sessionStorage` → `localStorage` if you want the web to stay signed in too.
- [x] **F4** Test `admin_session_ttl_test.go`: login → `expires_at` > now + 365 days; logout → next call 401; revoke → 401; password reset → 401.
- [x] **F5** `go test ./...` all green.

### Phase G: Tests (app), full run, zip
- [x] `bundle211a_lock_test.dart`: Account shows `avatar_private_lock` when Private, none when Public; Profile has no camera button; lock badge visible (not covered).
- [x] `bundle211b_photo_overlay_test.dart`: tap → overlay + camera; 3 s → gone; tap camera → photo sheet; works with letter circle; timer cancelled on dispose.
- [x] `bundle211c_session_test.dart`: store keeps a session past `expires_at`; login OK with phone clock 2 h ahead; 401 → cleared + back to chats; sign-out online → logout call; sign-out offline → `pending_revoke` sent on connect.
- [x] `bundle211d_switch_sheet_test.dart`: rows by state (signed in / not, online / offline); ticks; tap Admin opens panel with no sign-in; tap sajjad pops; settings avatar opens sheet, card text still opens Account.
- [x] `bundle211e_admin_offline_test.dart`: Admin section hidden offline, shows when `serverConnected`; 5 s rule.
- [x] `bundle211f_login_error_test.dart`: every row of the E1 table; keyboard flags; log has no username/password.
- [x] Full `flutter test` (old tests unchanged, see §5), analyze ≤ 166, version scan.

---

## 4. Phone tests (go into `APPLY_211.md`)
- [ ] 211-1 Private ON: Settings, Account, Profile all show ring + lock; Public: none.
- [ ] 211-2 Profile: no camera button; tap photo → camera 3 s → disappears by itself.
- [ ] 211-3 Tap photo → tap camera → Gallery → photo saved (Q1) and shows on Settings + Account.
- [ ] 211-4 No photo: tap letter circle → camera → add photo.
- [ ] 211-5 Admin sign-in with the **same** username/password as web → opens. If it fails: write the exact message.
- [ ] 211-6 Wrong password → "Wrong username or password."; Wi-Fi off → "Can't reach the server at …".
- [ ] 211-7 Settings → tap photo → Admin → opens with no password; Admin → shield icon → sajjad → back to chats.
- [ ] 211-8 Close the app, restart the phone, wait 1 hour+ → switch to Admin → still no password.
- [ ] 211-9 Server off / mobile data + Wi-Fi off → Settings has no Admin section; photo → Admin → offline panel with test switches.
- [ ] 211-10 Server back → Admin section returns by itself within a few seconds.
- [ ] 211-11 Sign out of Admin → next time asks for the password; chats untouched.
- [ ] 211-12 Web panel → Admin → Sessions → revoke the phone's session → phone shows "Admin was signed out on the server".
- [ ] 211-13 Sign out while offline → reconnect → web Sessions list shows that session gone.
- [ ] 211-14 Logs from the phone (`ADMIN_LOGIN` lines).

## 5. Safety: no effect on the rest of the app
- All new work in 3 new files + small listed edits; no DB change, no Kotlin change, no permission.
- Old tests:
  - `admin_session_model_test.dart`: unchanged (the `expired` getter is kept).
  - `admin_shell_screen_test.dart`: unchanged (`AdminShellScreen` not touched).
  - `direct_send_203_test.dart`, `bundle207m_test.dart` (lock size/badge): unchanged (`AccountAvatar` not touched).
  - **`bundle183_test.dart` F "sections in order"** expects "ADMIN / Admin panel" in Settings while its test cubit has `serverConnected = false` → after D1 it would fail. **Only fix: add one setup line** `_viewMode.setServerConnected(true)` in that test (no expectation removed). I'll list it in APPLY.
- Nearby / mesh / calls / chats code untouched.
- Security: a lost phone keeps Admin until revoked → revoke it from web Admin → Sessions (211-12) or reset the admin password.

## 6. Not in 211
- Video issue, block fix, other PENDING items.
- Saving the view mode across app restarts (app always starts in your chats).
- Changes to the old `AdminShellScreen`.

## 7. Delivery
- **Backend zip first** (`v3 bundle 211 backend: admin sign-in stays until sign out`) → deploy → then app zip.
- App: one zip, one commit `v3 3.0.52+123 bundle 211: …`, `APPLY_211.md`, `PENDING.md` updated.
