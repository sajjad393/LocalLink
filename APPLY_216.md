# APPLY 216 – app (216a–g + 216j)

App **3.0.57+128** · DB v34 (no change) · no new permissions.
Built on top of 215 (app `c8af499`).
**Deploy the backend zip (`locallink_backend_216_2026-11-05.zip`) first, then install this app.**
The app also works with the old server: the new fields are optional, and an old server ignores `neighbors`.

## What changed

**216a – Crown style A**
- A gold ring around the admin's photo, with a small painted crown on top. It shows on Profile, chats, the map and the admin lists.
- The "Admin · Owner" tag now uses the painted crown instead of the emoji.

**216b – Settings card tap zones**
- Admin: tapping the card (photo, name or tag) opens the switch sheet. Only the round › button opens Account.
- Not an admin: the whole card opens Account, as before.

**216c – Map**
- Each phone shows a round photo with the name under it.
- The same phone never shows twice:
  - removed phones are dropped;
  - an old account on the same phone is dropped;
  - this phone is shown once.
- Log: `MAP_NODES shown=… hidden=…`.

**216d – Admin home and live lock**
- The home page has:
  - a hero card (photo + crown, level, live status, 3 numbers);
  - a small live map;
  - the offline tools;
  - App version;
  - the tool menus People / Network / Safety / System;
  - the Testers section.
- When the server is lost, the server tools lock at once and the yellow banner "No server right now" shows. Offline tools keep working.
- When the server comes back, the tools unlock by themselves and "Server is back. Tools unlocked." shows for 3 s. Log: `ADMIN_LOCK on|off way=… page=…`.

**216e – All admin tool pages in the new style (spec pages 8–25)**
- People:
  - Users: chips, search, and a person sheet with status cards, Wi-Fi rule and "Sign out all phones".
  - Devices: phone sheet with Wi-Fi rule chips, Rename and Remove phone.
  - Sessions: "This phone" / "This one" tags and Sign out pills.
- Network:
  - Network & mesh: 4 tiles and the "Phones right now" list.
  - Calls: chips plus "A → B".
  - File transfers: space-used bar, file kinds and Done / Waiting tags. **File names are never shown.**
- Safety:
  - Recovery: the request card with "Approve and give code", a code card with Copy / New code, a Reject reason, and an Earlier list.
  - Security: Serious / Small / Locked, and "This week" in plain words. Wrong passwords are grouped per person per day.
- System:
  - Dashboard.
  - Audit log: a timeline with Today / Yesterday / Earlier, written as sentences.
  - Diagnostics: 6 tiles and 4 health bars.
  - Privacy & access: Never shown / Owner only / Always.
  - Admin settings (Owner only): − / + steppers, Save, backup card and a limits note.
- Blocking pages:
  - "Block or unblock a user" and "Blocked by admin" use the new look, with Block / Unblock pills, the third line "Reached N phones · On server", and an info banner.
  - Keys, words and the confirm dialog are unchanged.

**216f – Offline account upload: logs + background step**
- Every step is logged, with no password or key in the logs:
  - `OFFLINE_ACCOUNT_CHECK pending=…`
  - `PROBE ok|fail ms=…`
  - `PUBLISH try=n user=@x`
  - `PUBLISH ok`, `CONFLICT renamed=@x2`, `FAIL code=… reason=…`, `DONE`, `GIVE_UP after=6`, `NEXT_TRY in=…`
  - `BUSY` and `SKIP` also appear.
- New background step `offline_account` (runs after `identity` while the app is closed):
  - It uploads a phone-only account when the server answers.
  - Only one upload runs at a time (a lock shared by the app and the background engine).
  - There is a 2 min gap between tries. After a miss it tries again after 2, 4, 8 … 30 min.

**216g – Phones report who they reach**
- `presence_update` now carries `neighbors: [{device_id, link: wifi_direct|lan|mesh}]`:
  - at most 32 phones;
  - only live links;
  - never a blocked phone, never itself.
- The web map draws lines from this list.

**216j – UI check**
- The Testers switch **"UI check data"** (off by default) fills the admin pages with the mock people, so you can compare a phone screenshot with `mock_216_appNN.png`. A yellow banner "UI check data – not real" shows while it is on. Turn it off after the check.
- `ui_check_216.jpg` (sent next to this zip, not inside it, so it is not committed) shows 19 admin pages: the mock on the left and the real widgets rendered in the sandbox on the right. Known sandbox-only difference: the first letter of "Link paths" draws with a cut top in the sandbox render (the same font draws fine in a separate check); please look at it on the phone in 216-10.

## Files
New:
- `lib/features/admin/presentation/theme/admin_ui216.dart`
- `lib/features/admin/presentation/widgets/admin_kit216.dart`, `admin_format216.dart`, `admin_people216.dart`, `admin_tool_page216.dart`
- `lib/features/admin/presentation/ui_check/admin_ui_check216.dart`
- `lib/features/admin/presentation/screens/admin_dashboard216_screen.dart`, `admin_local_blocked_screen.dart`
- `assets/fonts/Roboto-Regular.ttf`, `Roboto-Medium.ttf`, `Roboto-SemiBold.ttf`, `Roboto-Bold.ttf`, `OFL.txt` (family `Roboto216` in `pubspec.yaml`)
- Tests: `test/bundle216a_test.dart` … `test/bundle216g_test.dart`, `test/bundle216ui_kit_test.dart`, `test/bundle216ui_pages_test.dart`, `test/support/b216_fonts.dart`

Changed:
- Admin screens in `lib/features/admin/presentation/screens/`:
  - `admin_panel_screen.dart`
  - `admin_users_screen.dart`, `admin_devices_screen.dart`, `admin_sessions_screen.dart`
  - `admin_network_screen.dart`, `admin_calls_screen.dart`, `admin_transfers_screen.dart`
  - `admin_recovery_screen.dart`, `admin_security_screen.dart`, `admin_audit_screen.dart`
  - `admin_privacy_screen.dart`, `admin_diagnostics_screen.dart`, `admin_settings_screen.dart`
  - `admin_block_users_screen.dart`, `admin_blocked_list_screen.dart`, `link_paths_full_screen.dart`
- Admin widgets in `lib/features/admin/presentation/widgets/`: `link_paths_map.dart`, `admin_version_card.dart`, `account_switch_sheet.dart`, `admin_block_confirm.dart` (radius only)
- Admin data: `lib/features/admin/bloc/admin_bloc.dart`, `data/services/admin_service.dart`, `data/repositories/admin_repository.dart`, `domain/admin_repository_contract.dart` (link map + avatar reads)
- `lib/core/widgets/admin_crown.dart`
- `lib/features/home/presentation/screens/messenger_settings_screen.dart`
- `lib/features/authentication/data/services/offline_account_sync_service.dart`, `lib/app/background_runner.dart`, `lib/app/app_dependencies.dart` (one line)
- `lib/features/connectivity/data/services/presence_service.dart`
- Version: `pubspec.yaml`, `lib/core/config/app_build.dart`

## Old tests changed (approved / version line)
- `test/bundle214d_test.dart:122` → expects 'Admin · Security' (the crown is now painted, not an emoji).
- `test/bundle214e_test.dart:74` → expects 'Admin · Owner' (same reason).
- `test/nearby_190_test.dart:291` → version line `3.0.57+128`.

## Phone tests
See `TODO_216.md` (216-1 … 216-10). For 216-10, turn on Admin → Testers → "UI check data" and compare with the mock.

## PowerShell (app, after the backend)
```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_216_2026-11-05.zip" .
git add -A
git add -f APPLY_216.md TODO_216.md assets/fonts/OFL.txt
git reset -q -- android/local.properties
git commit -m "v3 3.0.57+128 bundle 216: crown style A, settings card tap zones, map one node per phone with photos, admin home with live lock, all admin pages redesigned, offline account upload logs and background step, phones report neighbours, UI check data switch"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter pub get
flutter test
flutter build apk --release
```
