# TODO 214: Admin = an app user made admin on the web (crown, no admin login)

- Status: **PLAN only. Freeze ON.** Nothing is built until you say "go ahead" for 214.
- Built AFTER 213 (uses 212's server key, signed records, offline key and one-step frames, plus 213's build header). **Push 211 → 212 → 213 first.**
- Target: app **3.0.55+126**, app DB stays **v34** (settings keys), backend **migration 57**.
- Repos: https://github.com/sajjad393/LocalLink (app), https://github.com/sajjad393/LocalLinkBackend (backend).
- Mock: made, `mock_214_page1..11.png` + `mock_214_all.jpg` (app 1-8, web 9-11).

---

## 0. Your words and choices (2026-11-05)
- "If web admin marked any user as an admin they can act as an admin, no need separate login for admin."
- "Also save in app for offline; this sync also works when the user is in background."
- "If any user made admin show crown 👑 on his/her profile everywhere."
- "Just need to switch profile like Gmail."
- "Remove admin panel section login from app completely from settings."
- "No need separate logout for admin as well in app."
- Admin level: **the web picks the level for each user**: Owner / Operator / Security / Auditor. **Default Owner.** Only Owner can block users (212) and set the minimum version (213) offline.
- Crown: **on the photo, top centre**, on every photo of that person.
- Who sees it: **everyone** (chats list, chat top bar, profile, people, calls, groups, map, switch sheet).
- Made admin while offline: the **server-signed admin card travels phone to phone**, so the crown shows offline. The admin tools turn on once his own phone reaches the server.
- Added later: "Make sure if a user created an account when online and logs out, when they want to login when offline it also works, same account." Choices:
  - **Same phone only** (the phone where the account was used online).
  - An admin who signs out and signs in again offline **keeps admin and the crown** at once.
  - **Only the last account** that signed in online can reopen offline on a phone (as today).
  - **Part of 214** (tests + fix only what the tests show is broken).

## 1. Code facts (checked in w213 / wb213 today)
**Backend**
- App users are in table `users` (`internal/store/store.go` L183). Admins are a separate table `admin_accounts` (L343) with their own password, `role` (owner / operator / security / auditor) and `admin_sessions` (L355).
- Admin permissions come from `adminPermission(role, permission)` and `requireAdminPermission(...)` (`internal/httpapi/admin_auth.go` L266 / L283). Admin calls use `Authorization: Bearer <admin token>`, checked by `authorizeAdminSession` (L252).
- **No endpoint creates or changes admins.** The only admin comes from `LOCALLINK_ADMIN_BOOTSTRAP_*` at startup (`ensureBootstrapAdmin`, admin_auth.go L56-140).
- The web Users page has Suspend / Unsuspend / Disable only (`AdminSetUserStatus`, `admin_panel.go` L166). Suspend makes a 212 signed block.
- The 212 offline key: `POST /api/v1/admin/offline-cert` (`trust.go` L146) needs an admin session (`manage_users`). The cert holds `admin_id, username, role, device_id, signing_key, session_id`. It ends with the admin session (`endCertsForSessionID`, `endCertsForAdmin`, `certEndedNotes`).
- Phone calls are checked by `authorizeDevice` (`api.go` L990): device token + active `auth_sessions` + user `active`.
- Web socket hub: `ws.Hub.SendTo(deviceID, payload)` (`internal/ws/hub.go` L65). It can push "your admin role changed" to the user's phones.
- The 213 version gate exempts `/api/v1/admin/*`.
- Last migration: v56 (213 `app-version-rule`).

**App**
- Settings has the Admin section: `ServerOnlySection` → `settings_admin_section` → `MessengerGroupLabel('Admin')` → "Admin panel" → `AdminLoginScreen` (`messenger_settings_screen.dart` L301-333).
- `AdminLoginScreen` (`admin_login_screen.dart`, 442 lines) signs in with the web username and password (`AdminService.login`) and saves `AdminSession` in secure storage (`AdminSessionStore`: token, expires, admin id, username, role, pending-revoke key).
- `AdminCapabilityService`: `readValidSession`, `isAdminCapable`, `clear`, `signOut`, `sendPendingRevoke`. `sendPendingRevoke` runs on every server connect (`app_dependencies.dart` ~L165).
- Switch sheet (`account_switch_sheet.dart`): choices `user / admin / signIn / signOut`, "Sign out of Admin?" dialog, `openAdminPanel(nav, deps, session)`. It is opened from the Settings photo (`settings_avatar_switch`) and from the Admin panel top bar (`admin_switch_button`).
- The Admin panel ends the sign-in on a server "session expired" with the snackbar "Admin sign-in ended. Sign in again." (`admin_panel_screen.dart` L122-138).
- `profile_screen.dart` L121-127 reads the saved session and sets `viewMode.setAdminCapability`.
- 212 `AdminBlockService` gets the admin sign-in through the `adminSignIn` hook (`readValidSession`). `_usableCert()` drops the offline key when there is no sign-in. 213 `VersionRuleService` uses the same hooks.
- Profiles are signed by **each phone's own key** (`directory_profiles.signature`), so a crown flag inside a profile could be faked. **The crown must be a server-signed record.**
- Photos: almost every person photo is `AccountAvatar` (42 calls). 36 of them already pass `peerId` (user id or phone id). Six calls pass no id:
  - `group_info_sheets.dart:594`, `group_qr_screens.dart:626`, `group_link_screens.dart:474`, `contacts_screen.dart:545`;
  - own photo: `account_center_screen.dart:194`, `profile_screen.dart:396`.
  - Also `SettingsOwnAvatar` (Settings card) and `PresenceAvatar` (wraps `AccountAvatar`; online dot is top-right).
  - The map draws its own nodes (`link_paths_map.dart`, `link_paths_full_screen.dart`).
- Background: `background_runner.dart` steps (`admin_blocks`, `version_rule`, ...) run with the app closed.
- Kotlin `mesh/MeshBlockPolicy.kt` `MeshOneStep`: one-step frame names (212 + 213). New frames must be added here.

## 2. Files
**Backend (new / changed)**
- `internal/store/store.go`: migration **57 `app-user-admins`**.
- `internal/httpapi/user_admins.go` (new): make / remove admin, device admin session, admin cards.
- `internal/httpapi/admin_auth.go`: web password login refused for app-linked admins; session lookup unchanged.
- `internal/httpapi/admin_panel.go`: users list gets `admin_role`; Disable also removes admin.
- `internal/httpapi/trust.go`: offline cert works with a device admin session (no code change expected; test it).
- `internal/httpapi/api.go` or the auth file: device sign-out / revoke ends that phone's admin session.
- `cmd/server/main.go`: routes.
- `internal/httpapi/adminweb/views.js`, `app.js`: Users page Admin column + Make admin / Remove admin.
- `internal/httpapi/user_admins_214_test.go` (new).

**App (new)**
- `lib/features/admin/data/models/admin_badge.dart`: signed admin card model + checks.
- `lib/features/admin/data/services/admin_badge_book.dart`: who has a crown (ChangeNotifier).
- `lib/features/admin/data/services/admin_badge_service.dart`: keep, spread phone to phone, server sync.
- `lib/features/admin/data/services/admin_role_service.dart`: my own admin role, automatic admin session, background refresh.
- `lib/features/admin/data/services/admin_role_server.dart`: HTTP calls.
- `lib/core/widgets/admin_crown.dart`: the crown on a photo.
- Tests `test/bundle214a..g_test.dart`, `test/support/b214_fakes.dart`.
- Kotlin test `Admin214Test.kt`.

**App (changed)**
- `lib/core/widgets/account_avatar.dart`: crown.
- `lib/features/home/presentation/screens/messenger_settings_screen.dart`: remove the Admin section; the photo opens the switch only for admins; crown on my photo.
- `lib/features/admin/presentation/widgets/account_switch_sheet.dart`: me / Admin 👑 only; no Sign in / Sign out.
- `lib/features/admin/presentation/screens/admin_panel_screen.dart`: session expired → automatic refresh (no "sign in again").
- `lib/features/admin/data/services/admin_capability_service.dart`: remove `signOut` / `sendPendingRevoke`.
- `lib/features/admin/data/services/admin_session_store.dart`: remove the pending-revoke key use.
- `lib/features/account/presentation/screens/profile_screen.dart`, `account_center_screen.dart`: crown on my photo; role from the new service.
- Group / contacts files listed in §1 (add the id so the crown can show).
- `lib/features/admin/presentation/widgets/link_paths_map.dart`, `link_paths_full_screen.dart`: crown above admin nodes.
- `lib/app/app_dependencies.dart`, `lib/app/background_runner.dart`, `lib/app/local_link_app.dart`.
- `android/.../mesh/MeshBlockPolicy.kt`: 2 new one-step frames.
- Phase G: `lib/app/local_link_app.dart` (`_signedOut` keeps admin; after sign-in → role check), `lib/features/admin/data/services/admin_role_service.dart` (account id check), `lib/features/authentication/bloc/authentication_bloc.dart` (log lines only, no behaviour change).
- **Deleted:** `lib/features/admin/presentation/screens/admin_login_screen.dart`, `lib/features/admin/domain/admin_login_error.dart` (only used by the login).
- `pubspec.yaml` + `lib/core/config/app_build.dart` → 3.0.55+126; `test/nearby_190_test.dart` version line.

## 3. Phases

### A. Backend: link an app user to an admin role
- [ ] A1. Migration 57 `app-user-admins`:
  - `ALTER TABLE admin_accounts ADD COLUMN user_id TEXT` + `CREATE UNIQUE INDEX ... ON admin_accounts(user_id) WHERE user_id IS NOT NULL`.
  - `ALTER TABLE admin_sessions ADD COLUMN device_id TEXT NOT NULL DEFAULT ''`.
  - New table `admin_badges(user_id TEXT PRIMARY KEY, record_id, role, on_flag INTEGER, seq INTEGER, at TEXT, body TEXT, sig TEXT, updated_at TEXT)`.
- [ ] A2. Linked admin account:
  - username `app:<user id>` (no clash with web admin names). The shown name is the app username.
  - Random unusable password, so the web login refuses it.
  - `role` from the web; `status` active / disabled.
- [ ] A3. `POST /api/v1/admin/user-admin` (**web Owner only**). Body `{user_id, role, remove}`.
  - Make: create or update the linked admin, status active, role (default `owner`).
  - Remove: status disabled; revoke its `admin_sessions`; `endCertsForAdmin` (the "key ended" notes reach offline phones like 212).
  - Both: write a **server-signed admin card** (A5) with seq+1, add an audit row, and push `{"type":"admin_role_changed"}` to every phone of that user (`Hub.SendTo`).
  - Refuse: unknown user, disabled user, role not in the 4, removing the last Owner.
- [ ] A4. `POST /api/v1/admin/device-session` (phone, device auth):
  - The user has an active linked admin → reuse this phone's live admin session (same `device_id`) or make a new one.
  - Expiry 30 days, pushed forward on each call (the phone refreshes every 10 min, so it never runs out in use).
  - Answer = same shape as admin login: `{token, expires_at, admin:{id, username, role}}` + `card` (the signed admin card).
  - Not admin → `403 {"error":"not_admin"}`. Bad device token → 401 (the phone keeps what it has, see B3).
- [ ] A5. Admin card body (signed with the 212 server key):
  `{v:1, kind:"admin_badge", id, user_id, username, role, on, seq, at, by, signer:"server"}`. `on:false` = crown removed. Newest wins: seq → at → id (same as 212).
- [ ] A6. `GET /api/v1/admin-badges` (device auth) → `{badges:[signed cards], ended:[key ended notes]}`. Admins are few, so it sends the whole list.
- [ ] A7. Web password login (`AdminLogin`) refuses accounts with `user_id` ("This admin uses the LinkUp app"). Web admins (like the bootstrap owner) work as before **on the web only**.
- [ ] A8. Ends with the account:
  - User Disabled, or the phone signed out / revoked → that phone's admin session ends + its key ends.
  - Disabled → the admin is removed (card `on:false`).
  - Suspended (212 block) → the admin role stays, but the blocked phone can't use admin tools (C6).
- [ ] A9. `GET /api/v1/admin/users` gets `admin_role` ("" or the role). Admin sessions page shows "App · <phone name>" for device sessions.
- [ ] A10. Web console Users page:
  - "Admin" column with 👑 + role.
  - Button **Make admin…** → dialog with a role picker (Owner default) → Save.
  - Button **Remove admin** → red confirm (what happens on his phone; "Can't remove the last Owner").
  - Button **Level** → same dialog to change the level (new signed card).
  - New filter **Admins: All / Admins only / Not admins**, badge "N app admins".
  - Owner only. Uses only registered routes (`TestAdminWebOnlyCallsRegisteredEndpoints`).
- [ ] A11. Go tests:
  - make / remove / role change;
  - device-session 200 / 403;
  - web login refused for linked admins;
  - offline cert works with a device session;
  - remove ends the cert;
  - badges list + newest wins;
  - not the last Owner;
  - Disable removes admin;
  - push sent;
  - web page calls only registered routes.

### B. App: my own admin role, automatic (no login)
- [ ] B1. `AdminRoleService` (singleton, also in the background engine) `refresh()`:
  - Calls `POST /api/v1/admin/device-session`.
  - **200** → save `AdminSession` with the **same `AdminSessionStore`** (so 212 / 213 / the panel work unchanged); `viewMode.setAdminCapability(true)`; save my card; then 212 `pinTrust()` + `ensureCert()` (offline key).
  - **403 not_admin** → `adminCapability.clear()` (the 212 key drops by itself, `_usableCert`), `setAdminCapability(false)`, crown off.
  - **Network error / server off / 401** → keep everything (offline stays admin, your 211 rule).
- [ ] B2. When it runs:
  - 6 s after start;
  - on every server connect (replaces `sendPendingRevoke` in `app_dependencies`);
  - every 10 min;
  - at once on the socket push `admin_role_changed`;
  - and as a **background step `admin_role` right after `admin_blocks`** (app closed too).
- [ ] B3. One notification each time it changes (also with the app closed):
  - "You are now an admin 👑 · Tap your photo in Settings to switch."
  - "You are no longer an admin."
  - Settings key `admin_role_noted` (role or "") so it shows once.
- [ ] B4. Admin panel: when the server says the admin session expired → call `refresh()` quietly.
  - New session → keep going.
  - `not_admin` → close the panel + snackbar "You are no longer an admin". No "Sign in again" any more.
- [ ] B5. Remove:
  - `AdminCapabilityService.signOut` / `sendPendingRevoke`;
  - the pending-revoke key use;
  - `AdminLoginScreen`;
  - `admin_login_error.dart`;
  - every "Sign in to Admin" / "Sign out of Admin" text.

### C. App: crown cards for everyone (offline too)
- [ ] C1. `AdminBadge` model + check (only `signer:"server"`, verified with the saved 212 server key; no key yet → ignore, like 212).
- [ ] C2. `AdminBadgeBook` (ChangeNotifier):
  - `isAdmin(id)` for a user id **or** a phone id (phones from `directory_profiles`, same way as 212 `_adminBlockedIds`);
  - `roleOf(id)`;
  - `selfAdmin`.
  - Saved in settings `admin_badges_v1`.
- [ ] C3. `AdminBadgeService`, spread like 213:
  - One-step frames `admin_badge_digest` `{type, h}` and `admin_badge_records` `{type, records:[cards]}`.
  - Digest when a phone links + every 60 s, max once per phone per 30 s.
  - The phone with newer cards pushes them; each phone passes new cards one step on.
  - Max 200 cards, 20 per frame.
- [ ] C4. Server sync: `GET /api/v1/admin-badges` at start (+8 s), on connect and every 10 min. Takes cards + key-ended notes.
- [ ] C5. Kotlin: add `ADMIN_BADGE_DIGEST` / `ADMIN_BADGE_RECORDS` to `MeshOneStep` (`isOneStep`) + Kotlin test.
- [ ] C6. Admin tools are refused while my own account is blocked by admin (212 `selfBlocked`). The crown stays until the web removes admin.

### D. App: the crown 👑 (on the photo, top centre)
- [ ] D1. `AdminCrown`:
  - a 👑 centred above the top edge of the photo; size about 0.75 × radius (min 12 px);
  - a thin white shadow so it shows on any photo;
  - does not change the photo's size or layout (Stack, no clip);
  - listens to `AdminBadgeBook`.
- [ ] D2. `AccountAvatar` shows the crown when `peerId` (or the new `userId`) is an admin. New `crown` param (default true) for places that must not show it. This covers chats list, chat top bar, calls, people, groups (members, sender photos, info), forward, call screen and the switch sheet.
- [ ] D3. Add the id to the 6 calls with no id (§1): 4 group / contacts calls; my own photo in Account center + Profile (`selfAdmin`). Plus `SettingsOwnAvatar`.
- [ ] D4. `PresenceAvatar` (online dot **top-right**, `messenger_conversation_tile.dart` `right:-2, top:-2`) + crown top centre: check they don't overlap at radius 20-28; if they touch, the crown gets smaller (min 12 px) and stays at the top centre. (The mock drew the dot bottom-right; the real dot stays top-right.)
- [ ] D5. No crown on group photos or blocked (grey) photos. The Private lock stays where it is (**bottom-right**, `avatar_private_badge`); the crown never covers it.
- [ ] D6. Map: 👑 drawn above admin nodes (small map and full-screen map), also in the node sheet title.
- [ ] D7. Profile page of an admin: crown on the big photo + a small line "Admin · Owner" under the name.

### E. App: Gmail-style switch only
- [ ] E1. Switch sheet rows:
  - **me** (photo, name, tick when in chats);
  - **Admin 👑** (role, "offline tools only" when offline; tick when in the panel).
  - No "Sign in to Admin", no "Sign out of Admin", no dialog.
- [ ] E2. Settings photo tap:
  - admin → the switch sheet;
  - not admin → opens Account (same as the rest of the card), no sheet.
- [ ] E3. Admin panel top bar switch button stays (back to my chats).
- [ ] E4. **Remove the Settings "Admin" section completely** (`ServerOnlySection` + label + row).

### G. Same account offline after Sign out (added)
Today (code checked at `30109f9` + 211-213 zips):
- Online register/login saves a scrambled password copy (`AuthenticationBloc._mirror` → `mirrorOfflineLogin`, secure storage, bundle 110).
- Profile **Sign out** only sets the `signed_out` flag (`AuthenticationRepository.signOut`); `local_link_app.dart` `_signedOut()` wipes nothing. Chats, friends, keys and the device token stay.
- Offline login: server not reachable → `_offlineFallback` → `verifyOfflineLogin` (username + password) or `verifyOfflineRecovery` (recovery code in the password box) → `completeOfflineLogin`. Wrong password → "That username and password do not match."
- **Reset account** (`_resetAccount`) wipes everything, including the admin session (`adminCapability.clear()`, 211) and the offline login.
- One account slot per phone: a new online login replaces the mirror.

Tasks:
- [ ] G1. Sign out keeps the saved admin session + my admin card (no clear in `_signedOut`). Reset account still clears them (as today).
- [ ] G2. Owner check: the saved admin session remembers the account id. At start and after any sign-in, if it is not the current account → clear it and the role notes, then refresh from the server. (So after A signs out and B signs in, B never gets A's admin.)
- [ ] G3. After an offline sign-in, `AdminRoleService` reads the saved session at once (no server): the Admin row in the switch sheet and my crown are back immediately. Refresh runs when the server is reachable.
- [ ] G4. After an online sign-in: refresh the role at once (not only after 6 s).
- [ ] G5. While signed out: no admin refresh, no role notifications (the background runner already stops on `signedOut`).
- [ ] G6. Log lines `AUTH_OFFLINE_LOGIN ok/bad`, `ADMIN_ROLE_KEPT_AFTER_SIGNIN`, `ADMIN_ROLE_OTHER_ACCOUNT_CLEARED`.
- No change to the login screen, password rules or the server.

### F. Tests + delivery
- [ ] F1. `bundle214a` card model + checks + newest wins.
- [ ] F2. `bundle214b` badge spread over a 3-phone line, late link, fake card refused, `on:false` removes.
- [ ] F3. `bundle214c` role service: 200 saves session + key, 403 clears, offline keeps, push → refresh, notifications once, background step order.
- [ ] F4. `bundle214d` crown widget: shows / hides live, top centre, size unchanged, with presence dot, own photo.
- [ ] F5. `bundle214e` switch sheet (me / Admin only), Settings with no Admin section, non-admin photo tap → Account.
- [ ] F6. `bundle214f` panel session expired → refresh / close; source scans (no `AdminLoginScreen`, Kotlin frames, routes).
- [ ] F6b. `bundle214g` offline sign-in: account created online (fake server) → Sign out → server gone → same username + password opens the **same account** (same account id, chats and friends still there); recovery code works; wrong password refused; an admin keeps the Admin row + crown after offline sign-in; another account's online sign-in clears the old admin; Reset account clears everything.
- [ ] F7. Full suite, `flutter analyze` 166, Kotlin compile check, `go vet` + `go test ./...`.
- [ ] F8. `APPLY_214.md`, `PENDING.md`, app zip (one commit) + backend zip (deploy first).

## 4. Old tests that must change (you asked to be told)
| Test | Why | Change |
|---|---|---|
| `test/bundle196_test.dart` (L551-552) | checks Settings group order up to `MessengerGroupLabel('Admin')`, which is removed | drop that one order line only |
| `test/bundle211c_switch_test.dart` | checks Sign in / Sign out rows and the sign-out dialog | rewrite to the new rows (me / Admin) |
| `test/bundle211e_login_error_test.dart` | tests `AdminLoginScreen` errors; the screen is deleted | delete the file |
| `test/bundle211b_session_test.dart` | uses `signOut` / `sendPendingRevoke` (removed) | drop those cases, keep the session-store cases |
| `test/bundle211f_panel_test.dart` | expects "Admin sign-in ended. Sign in again." | expect the automatic refresh / "You are no longer an admin" |

All other old tests stay as they are.

## 5. Phone tests (APPLY_214.md)
- [ ] 214-1 Web (Owner): Users → Sajjad → Make admin (Owner). Realme online gets the notification within seconds; Settings has no Admin section; tap photo → me / Admin 👑 → panel opens with no password.
- [ ] 214-2 Realme offline (airplane + Wi-Fi Direct to ZTE): panel still opens; 212 block and 213 minimum version still work offline.
- [ ] 214-3 ZTE sees the 👑 on Sajjad's photo (chats, chat top bar, profile, people, groups, map), first from the server, then also over Wi-Fi Direct / mesh with ZTE never online.
- [ ] 214-4 Web makes Sumaira (ZTE) an admin while ZTE is offline: Realme passes the card on, so the crown shows on both; ZTE's admin tools turn on when it reaches the server.
- [ ] 214-5 Web role → Operator: block / minimum version say "Only the owner admin…"; crown stays.
- [ ] 214-6 Web Remove admin: notification "You are no longer an admin", the panel closes, the crown goes on all phones (offline phones when the card reaches them). Blocks he made before stay (an Owner can undo them); NEW blocks from his old key are refused after the "key ended" note (212 `cert_ended`).
- [ ] 214-7 App closed on Realme during 214-1 / 214-6: the change arrives in the background (notification).
- [ ] 214-8 A non-admin taps the Settings photo → Account opens, no switch.
- [ ] 214-9 Logs: `ADMIN_ROLE_*`, `ADMIN_BADGE_*`.
- [ ] 214-10 Same account offline: on ZTE, create a new account online (or sign in) → send a few messages → Profile → Sign out → turn off Wi-Fi and data → sign in with the same username + password → the same account opens with the old chats. Also try the recovery code in the password box, and a wrong password ("That username and password do not match.").
- [ ] 214-11 Admin offline sign-in: on Realme (admin) → Sign out → airplane mode → sign in again → crown on my photo and Admin 👑 in the switch sheet at once; the panel opens with the offline tools.
- [ ] 214-12 Other account on the same phone: Realme Sign out → sign in online as a normal test user → no crown, no Admin row. (The old account can't open offline any more, by your choice: only the last account.)

## 6. Safety
- Crown and admin power come only from the server key. A phone can't make itself admin, and a fake card is refused (log `ADMIN_BADGE_REJECT`).
- Admin tokens stay in secure storage. Admin cards hold no secrets (user id, name, role).
- Offline the admin keeps the tools (your 211 rule). Removing admin reaches offline phones only through the cards and "key ended" notes, like 212.
- Web admins (bootstrap owner) keep working on the web. They can't open the app panel (no app login any more).
- Offline sign-in checks the scrambled password copy on this phone only. If the password is changed elsewhere, this phone keeps the old one until its next online sign-in.
- A saved admin session belongs to one account (G2); it never moves to another account on the same phone.
- The testers' switches (Nearby tests, Pretend old build) live in the Admin panel, so testers must be made admin on the web.

## 7. Mock (made: `mock_214_all.jpg`, pages `mock_214_page1..11.png`)
App:
1. Settings as admin: crown on my photo, "Admin · Owner" tag, no Admin section.
2. Switch sheet: me / Admin · Owner (offline: "Offline tools only · block, app version").
3. Chats list: crown on admins' photos, online dot + unread unchanged.
4. Chat top bar: crown on the small photo.
5. Admin's profile: big photo with crown + "Admin · Owner".
6. Group members + map with crowns ("Group admin" tag unchanged).
7. Notifications: "You are now an admin 👑" / "You are no longer an admin".
8. Settings for a normal user: no crown, photo tap → Account.
Web:
9. Users page: Admin column, Admins filter, Make admin… / Remove admin / Level.
10. Make admin dialog: level picker, Owner default.
11. Remove admin confirm + "last Owner" refusal.

## 8. Points to confirm before build
- Linked (app) admins can't use the web password login; the web-only admin (bootstrap, e.g. `test-admin`) can't open the app panel.
- Only a web Owner can make / remove admins (web only, never from the app).
- Level rights in the app = the same rights as that level on the web; only Owner gets the offline block (212) and minimum version (213).
- After Remove admin, blocks he made before stay (an Owner can undo them).
- Testers must be made admin to reach "Nearby tests" and "Pretend old build".

## 9. Delivery
- Backend zip first (migration 57), then the app zip (one commit), each with `APPLY_214.md`.
- App commit (planned): `v3 3.0.55+126 bundle 214: web makes any user an admin (no admin login or logout in the app), admin saved for offline and refreshed in the background, crown on admin photos for everyone (also over mesh), Gmail-style switch only, Settings Admin section removed, same account and admin after Sign out and offline sign in`.
- Backend commit (planned): `v3 bundle 214 backend: app users as admins (make/remove admin with role, device admin session, signed admin cards, web Users page)`.
