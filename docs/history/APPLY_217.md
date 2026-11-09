# APPLY 217 – app (217c, 217d, 217f, 217g) – includes 216

App **3.0.58+129** · DB v34 (no change) · no new permissions.
**This zip also contains all of 216** (216 was not pushed yet; GitHub is at `c8af499`). One commit pushes 216 + 217 together.
If you push the 216 zip first, this zip still works: it just overwrites the same files again.
**Deploy the backend zip `locallink_backend_217_2026-11-05.zip` first** (web panel only), then install this app.

For what 216 changed, read `APPLY_216.md` (in this zip).

## What changed in 217

**217c – Aerial moving lines on the map (small card + full map)**
- Every line is a curved flight path that bows away from the middle of the map (small card: lower curve so it fits in 104 dp).
- Layers: soft glow, the line, moving dashes (one loop every 2 s, from the sender side) and a glowing dot with a short tail (one trip every 3 s; dots are not in step).
- Colour = link type (server green, Wi-Fi Direct amber, mesh purple, local Wi-Fi teal). Blocked = grey dashed, never moves. Server offline = red / grey dashes, no motion.
- Motion stops when: Android "Remove animations" is on, battery saver is on, the map is not on screen, or the app is in the background. When you come back it checks battery saver again.
- Dark mode: dark server circle with a blue border; light dashes. Light mode: darker dashes.
- Only the drawing repaints (not the page), so it stays light on slow phones.
- Log: `LINK_MOTION on` / `LINK_MOTION off why=anim|saver|paused` (only when it changes).
- Native: one new branch `powerSave` on the `locallink/device` channel in `MainActivity.kt`.

- Full map, found in the UI check against mock A-2: the name pill under each photo is now as wide as the name (it was always 110 dp), and the map opens with the group in view (Server, You and the others) instead of the top-left corner. Zoom 1x–4x, drag and double tap are unchanged.

**217d – New crown everywhere**
- Gradient gold body, 3 pearls, red + blue jewels, shine and a soft shadow. Same drawing on the web.
- Size 1.1 × photo radius (never under 13). It sits on the gold ring and touches the photo edge.
- Everywhere at once: photos with a ring (chats, profile, lists, map nodes, hero card, sheet), the top crown button, the "Admin · Owner" tag, and the old map crown (no more 👑 emoji).

**217f – Tests**
- New: `test/bundle217c_test.dart` (line shape, motion on / off by Remove animations / battery saver / paused, blocked = no dot, dark server, repaint rules), `test/bundle217d_test.dart` (sizes, position on the ring, drawing at 13 / 26 / 40 px, colours), `test/bundle217ui_test.dart` (UI check pages).
- Under `flutter test` the map does not move unless a test asks for it, so old tests that wait for the screen to settle are not affected.

**217g – UI check**
- `ui_check_217.jpg` (sent next to this zip, not inside it): mock on the left, real widgets on the right.

## Old tests changed
- `test/bundle214d_test.dart:60-61` → `closeTo(30.8, 0.01)` and `13` (approved: crown 1.1 × radius, min 13).
- `test/bundle216a_test.dart:28` → `13` instead of `12` (same reason; this is a 216 test that was never pushed – it was missing from the 217 plan, so I am telling you here).
- `test/nearby_190_test.dart:291` → version line `3.0.58+129`.

## Files (217 part)
- `lib/features/admin/presentation/widgets/link_paths_map.dart`
- `lib/features/admin/presentation/screens/link_paths_full_screen.dart` (first view + name pill; also a 216 file)
- `lib/core/widgets/admin_crown.dart`
- `android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt` (1 branch)
- `pubspec.yaml`, `lib/core/config/app_build.dart` (version)
- new `test/bundle217c_test.dart`, `test/bundle217d_test.dart`, `test/bundle217ui_test.dart`
- old tests above; `TODO_217.md`, `APPLY_217.md`
- plus every 216 file (see `APPLY_216.md`).

## Phone tests
See `TODO_217.md` → 217-8, 217-9, 217-10 (app) and 217-1 … 217-7 (web).

## PowerShell (app, after the backend)
```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_217_2026-11-05.zip" .
git add -A
git add -f APPLY_216.md TODO_216.md APPLY_217.md TODO_217.md
git reset -q -- android/local.properties
git commit -m "v3 3.0.58+129 bundles 216+217: crown style A then new crown everywhere, settings card tap zones, map one node per phone with photos and aerial moving lines, admin home with live lock, admin pages redesigned, offline account upload logs and background step, phones report neighbours, UI check data"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter pub get
flutter test
flutter build apk --release
```
