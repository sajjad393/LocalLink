# TODO 216 – Admin redesign (app + web), crown A, map photos, live lock, offline upload logs

Status: PLAN ONLY. Freeze ON. No code until the user says "go ahead".
Base: app `c8af499` (3.0.56+127), backend `1fd6e6b`.
New version: 3.0.57+128. `nearby_190` version line bump (only old-test change that is always needed).
Mock: `mock_216_all.jpg` (**v4**: app pages 1-26, web W1-W15). **Exact look, sizes, colours, texts, keys, data and states per page: `UI_SPEC_216.md` (the target; the UI must match it 100 %).** Words: `WORDS_216.md` (+ "v4 changes").

User choices (2026-11-05):
- Crown style **A**: thin gold ring round the photo + small painted crown sitting on the ring, top centre.
- Settings card: admin → tap photo / name / tag = Switch account sheet; only the round › = Account. Not admin → whole card = Account.
- Map: round profile photo + profile name below, one circle per phone, on the app AND a new web Map page.
- Web map lines between phones: YES (small backend step, phones report who they can reach).
- Words: keep the app's words, change only hard ones (list in `WORDS_216.md`).
- Wi-Fi Direct / mesh: server tools shown locked ("Needs the server"); lock / unlock live.
- Web panel: same redesign.
- Offline account upload: a log line for every step + a background step (uploads with the app closed).
- Recovery: empty state instead of a blank page.

Delivery: ONE backend zip (deploy first, it is backward compatible) + ONE app zip, one commit each.

---

## 216a – Crown A (app)

File: `lib/core/widgets/admin_crown.dart` (+ new painter in the same file).
- `AdminCrown`: replace the emoji with:
  - gold ring (`#E7B416`, width = max(2, radius*0.09)) painted round the child (Stack, no layout change, `Clip.none`), and
  - a painted crown (`CustomPaint`, `_CrownPainter`: 3 points with round tips, band, red dot, white halo) centred on the ring at the top. Width = clamp(radius*0.78, 11, 30).
  - keep `ValueKey('admin_crown')` on the crown and `ValueKey('admin_crown_stack')` on the Stack, so the 214d position tests (top centre, does not overlap the lock badge) still hold.
- `AdminCrown.mark(size)`: returns the painted crown (used on map nodes and titles), key unchanged.
- `AdminRoleLine` and Settings tag `SettingsAdminTag`: painted crown icon + text `Admin · Owner` (no emoji).
  - **Old tests:** `bundle214d_test.dart:122` and `bundle214e_test.dart:74` look for the text `'\u{1F451} Admin · …'`. They get the expectation changed to `'Admin · …'` (text only, nothing else). **User OK given 2026-11-05.**
- Account switch sheet "Admin" row: painted crown in the gold circle (`account_switch_sheet.dart`).
- Tests `bundle216a_test.dart`: ring painted only when admin; crown hidden when blocked by admin; crown above the photo centre; mark() has no Text emoji.

## 216b – Settings card tap zones

File: `lib/features/home/presentation/screens/messenger_settings_screen.dart`.
- Card `settings_profile_card` onTap: `_openAccount(context)` → `_photoTap(context)` (admin → switch sheet; not admin → `_openAccount(ctx)` inside `_photoTap`, as today).
- Avatar `settings_avatar_switch` keeps `_photoTap(context)`.
- Chevron (`Icons.chevron_right`, L197) becomes a 36 dp round grey button `settings_account_arrow` with its own onTap `_openAccount(context)`.
  - `bundle183` L780 needs the literal `'_openAccount(context)'` exactly once: it moves from the card to the arrow, still once (code-checked; `_photoTap` uses `_openAccount(ctx)`).
- Tests `bundle216b_test.dart`: admin: tap name → sheet; tap arrow → Account. Non-admin: tap name → Account; tap arrow → Account.

## 216c – Map: photo + name, one per phone (app)

Files: `lib/features/admin/presentation/widgets/link_paths_map.dart`, `link_paths_full_screen.dart`, `admin_panel_screen.dart`.
- `LinkNode` gets `userId`, `name` (profile display name → @username → phone name as last fallback), `admin` (AdminCrown.showFor).
- Node drawing: round photo (same source as chat avatars: `PresenceAvatar` / `AccountAvatar` with `peerId: userId`), initials when no photo; name label in a white pill under the photo; crown A on admins; blocked = grey photo + red ring + "Blocked" tag; me = "You".
- `_openFullMap` and the map card use `_profiles[d.id]` for name/userId (today `label: d.name` = phone model → the bug).
- **One per phone (duplicate fix):** new `dedupeNodes()` in `link_paths_map.dart`:
  1. revoked devices are dropped;
  2. two records with the same `userId` → keep the one with the newest `presenceLocalAt`;
  3. two records with the same phone name where one is live (presence < 4 min) and the other is stale → drop the stale one (old account on the same phone);
  4. this phone's own old device ids (from the saved last-account record, 214 offline re-login) are never shown as another phone.
  - Phone test 216-3 confirms; if a duplicate still shows, I need the two device ids from the log (`MAP_NODES` line, below).
- Log line `MAP_NODES shown=N hidden_dupes=M` once per open.
- Tests `bundle216c_test.dart`: label = profile name; dedupe rules 1-4; crown on admin node; blocked styling.

## 216d – Admin home redesign + live lock (app)

Files: `admin_panel_screen.dart`, new `lib/features/admin/presentation/widgets/admin_home_sections.dart`, new `theme/admin_ui216.dart` (tokens, UI_SPEC §1), new `widgets/admin_kit216.dart` (shared widgets, UI_SPEC §2), new `widgets/admin_format216.dart` (§1.8), `pubspec.yaml` (font `Roboto216`), new `assets/fonts/Roboto-{Regular,Medium,SemiBold,Bold}.ttf` + `OFL.txt`. `admin_components.dart` / `admin_theme.dart` NOT changed (old tests check them).
- Layout = UI_SPEC pages 3, 4, 26, 5, 6: hero card, minimap + legend, "Block users (all phones)", App version card, People / Network / Safety / System, Testers card (Nearby tests (testers only) → page with `const NearbyTestSwitches()`, `const PretendOldBuildSwitch()`, `const StorageTestButton()`).
- Source scans that must stay true in `admin_panel_screen.dart`: `_moderationCard(scheme),` before `const AdminVersionCard(),`; `const PretendOldBuildSwitch(),` after `const NearbyTestSwitches(),`; `const StorageTestButton()`; `'Nearby tests (testers only)'`; keys `admin_switch_button`, `admin_block_card/list/pick/status`, `admin_not_available`, `admin_no_longer`.
- Module **keys stay** (`'Network & Mesh'`, `'Audit Log'` … used by `_screenFor` and `admin_dashboard_screen_test` navigation); only the shown label changes (WORDS_216).
- Status chip shows the real way: Online · Server / Offline · Wi-Fi Direct / Offline · Mesh / Offline · Local Wi-Fi / Offline · No link (from `_onLink`: any wifiDirect → Wi-Fi Direct, else mesh, else lan, else No link).
- **Live lock:**
  - Home: already rebuilt by `BlocBuilder<AppViewModeCubit>`; locked rows = grey, lock icon, "Needs the server", tap → short note.
  - When `serverConnected` goes false → true: green note "Server is back. Tools unlocked." (3 s, no tap).
  - New `ServerLockGate` wraps the body in `_openModule`: listens to `viewMode`; when the server is lost the page greys (last data stays) with the card "Server lost. This page is locked. It opens again by itself when the server is back."; when it is back the gate lifts and the page refreshes once.
  - Owner-only tools show "Owner only" for other levels.
- Log lines: `ADMIN_LOCK on|off way=<x>`.
- Tests `bundle216d_test.dart`: chip text per way; rows lock/unlock on cubit change without rebuild of the route; gate shows/hides; module keys unchanged; testers page contains the old header.

## 216e – Server tool screens (app)

Files (each screen keeps its bloc/repository calls, only UI + words change):
`admin_users_screen.dart`, `admin_devices_screen.dart`, `admin_sessions_screen.dart`, `admin_network_screen.dart`, `admin_network_policy_dialog.dart`, `admin_calls_screen.dart`, `admin_transfers_screen.dart`, `admin_security_screen.dart`, `admin_audit_screen.dart`, `admin_recovery_screen.dart`, `admin_diagnostics_screen.dart`, `admin_settings_screen.dart`, `admin_privacy_screen.dart`, new `admin_dashboard216_screen.dart` (page 25; the old `admin_dashboard_screen.dart` is NOT touched – its test checks ~30 old texts), new `admin_local_blocked_screen.dart` (page 10), `admin_block_users_screen.dart`, `admin_blocked_list_screen.dart`, `admin_block_confirm.dart` (look only, texts kept for 212e), `admin_list_page.dart`, `admin_version_card.dart` (look only, texts/keys kept for 213f), `link_paths_full_screen.dart` (texts/keys kept for 212f), `admin_service.dart` / `admin_repository*.dart` (only the new avatar + link-map calls).
- Every screen exactly as UI_SPEC §3 (order, texts, keys, data, empty / offline / locked states).
- Rows with photo + name instead of ids (names from directory profiles; id only when no name).
- Status / severity / link as coloured tags; filters as chips; one-line explanation under every choice.
- Duplicate in-body titles removed (AppBar has the title).
- Empty states everywhere (Recovery: "No one is asking"; Blocked lists; Calls; Transfers; Audit; Security; Sessions).
- Wi-Fi rule (was Network policy): Default / Allowed / Always on / Always off = server values null / allowed / forced_on / forced_off (unchanged).
- Admin settings: − / + steppers (5-120 s; alert 1-20), backup card.
- "Blocked devices" bottom sheet → page "Blocked on this phone".
- Block confirm text (WORDS_216).
- Tests `bundle216e_test.dart` (one widget test per screen: renders names, empty state, words) — uses `FakeAdminRepository`; plus `bundle216ui_kit_test.dart` and `bundle216ui_pages_test.dart` (UI_SPEC §6: texts, order, keys, sizes, colours at 360×760).
- `admin_shell_screen.dart` is not used by the app → NOT touched (its old tests stay as they are).

## 216f – Offline account upload: logs + background step

Files: `lib/features/authentication/data/services/offline_account_sync_service.dart`, `lib/app/background_runner.dart`, `lib/app/app_dependencies.dart`.
- Log every step (tag `OFFLINE_ACCOUNT_*`, no passwords / keys in logs):
  `CHECK pending=<bool>` → `PROBE ok|fail ms=` → `PUBLISH try=n user=@x` → `PUBLISH ok` / `CONFLICT renamed=@x2` / `FAIL code=… reason=…` → `DONE` / `GIVE_UP after=6` → `NEXT_TRY in=…`.
- Background: new step `offline_account` in `background_runner.dart` (after `identity`, before `messages`): if a not-yet-uploaded offline account exists and the server is reachable → `autoPublish()`; guarded by a lock so the foreground burst and the background step never run together; 2 min minimum gap.
- Tests `bundle216f_test.dart`: log lines in order (fake http); step skipped when nothing pending; lock prevents double publish; rename on conflict logged.

## 216g – Phones report who they can reach (app side of the web map)

File: `lib/features/connectivity/data/services/presence_service.dart` (+ reads the nearby / mesh peer lists already kept by the nearby services).
- `presence_update` gets `neighbors: [{device_id, link: wifi_direct|mesh|lan}]`, max 32, only phones seen < 4 min, never blocked ones.
- Old servers ignore the field (Go json ignores unknown fields) → safe before the backend deploy.
- Tests in `bundle216g_test.dart`.

## 216h – Backend: link map

Files: `internal/httpapi/websocket.go`, new `internal/httpapi/link_map.go`, route in `api.go`, tests `link_map_test.go`.
- `WSMessage.Neighbors []Neighbor` (`device_id`, `link`).
- In-memory store per device (no migration, no DB): last report + time; entries older than 4 min ignored; max 32 per device.
- `GET /api/v1/admin/link-map` (any admin role, read): nodes (device id, phone name, user id, display name, @username, avatar_url, admin role, blocked, online, link now) + edges (from reports; server edges for online devices). Only devices of active accounts; revoked dropped; one node per device id.
- Tests: report → edge; stale report dropped; non-admin 403; revoked hidden.
- **Extra fields for the mock (UI_SPEC §5, additive JSON, no migration):** users `display_name/has_avatar/last_seen_at`; devices `display_name/app_build`; sessions `display_name`; calls `caller_name/callee_name/(user ids)`; security events `username/display_name/device_name`; logs `admin_name/target_name`; transfers `owner_user_id/owner_name/kind` (never `original_name`); recovery `user_id/display_name`; settings `last_backup_at/last_backup_bytes/max_file_bytes/device_quota_bytes/tls_required`.
- New `GET /api/v1/admin/users/{id}/avatar` (admin read) and static `/admin/fonts/*` (Roboto for the web). Routes in `cmd/server/main.go`. Files: `admin.go`, `admin_panel.go`, `recovery.go`, `calls.go` (admin list only), new `admin_avatar.go`, `adminweb/fonts/*`, tests `admin_216_fields_test.go`.

## 216i – Web panel redesign + Map page

Files: `internal/httpapi/adminweb/index.html`, `styles.css`, `app.js`, `views.js`, `components.js`, `charts.js` (labels).
- Exactly UI_SPEC §4 (web tokens, W1-W15). Menu groups People / Network / Safety / System; "Owner" hint on owner-only items.
- New view `map` (W3): SVG map, photo circles (avatar_url, initials fallback), names under, crown A on admins, blocked grey + red ring, line colour per link, filter chips, side list "Phones (N)", drag + wheel zoom, refresh every "Refresh every" seconds.
- Dashboard: tiles, small map, "Needs a look", one chart.
- Users: chips instead of selects, photo + crown + level in the row, "Manage" side panel with Status and Admin level cards (descriptions from the real rights: Owner = everything; Operator = phones, Wi-Fi rules, recovery; Security = recovery requests, can look at the rest; Auditor = can only look).
- Devices / Sessions / Network / Calls / Files / Recovery / Security / Audit / Conversations / App version / Diagnostics / Settings / Privacy as in the mock, words from WORDS_216.
- Sign-in page short words.
- Web rules already checked by `admin_web_test.go` (kept, no change): no external URLs (no CDN / Google fonts → photos and icons are inline SVG / same-server avatar_url), every value through `ui.esc(`, `emptyText` stays in views.js, `ESCAPE_MAP` stays in components.js, every `/api/v1/admin/...` path the console calls must be registered (the new `link-map` route is registered in 216h), no "sample/dummy data" words.

## 216j – UI match proof (app)

Files: `lib/features/admin/presentation/ui_check/admin_ui_check216.dart` (fixture repo with the mock people + testers switch "UI check data", off by default, yellow banner "UI check data – not real" while on), Testers card row.
- Sandbox: render every page with the real widgets at 360×760 (Roboto loaded) → `ui_check_216.jpg` side by side with the mock; every difference fixed before the zip; the JPG comes with the zip.
- No golden files committed (Windows/Linux font difference).

---

## Tests and checks
- New: bundle216a…216g, bundle216ui_kit, bundle216ui_pages (Flutter); link_map_test.go, admin_216_fields_test.go (Go).
- Full Flutter suite (≈198 files + new) in chunks; `flutter analyze` must stay at 166.
- Go: `go test ./...`.
- Old tests changed: `nearby_190` version line; and the 2 crown text expectations (214d:122, 214e:74), approved.

## Phone tests (after backend deploy + APK install)
- 216-1 Crown A on Settings, chat list, profile, map; no crown when blocked.
- 216-2 Settings: admin tap name → switch sheet; tap › → Account; non-admin both → Account.
- 216-3 Map: photos + profile names; Sumaira's phone shows once (also after she made a new account).
- 216-4 Turn router off, Wi-Fi Direct on: chip "Offline · Wi-Fi Direct", server tools locked; router back → unlock note within a few seconds without leaving the page.
- 216-5 Open Users, turn router off → page locks; back → opens again.
- 216-6 Recovery with no requests → "No one is asking".
- 216-7 Create an account offline, close the app, turn internet on → account appears on the server; send logs (`OFFLINE_ACCOUNT_*`).
- 216-8 Web: Map shows both phones with photos; Wi-Fi Direct line between them while both are online.
- 216-9 Web: every page opens, words as the list, Users side panel works.
- 216-10 UI check: Testers → "UI check data" ON → open every admin page, screenshot, compare with `mock_216_appNN.png` (checklist in UI_SPEC §6) → OFF.
