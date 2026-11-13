# APPLY app 3.0.91+162 (TODO 290: crown colour per admin level + crown C + crown tip)

Zip: `locallink_app_3.0.91_2026-11-14.zip`, on top of GitHub `b1a4bbe` (3.0.90+161).
Deploy the backend web zip `locallink_backend_290_2026-11-14.zip` first (web only, any order works).

## What changes
- Every admin level has its own crown + photo ring colour: Owner gold (as before), Operator blue,
  Security red, Auditor silver. Unknown level = gold. Normal users: no change.
- New lower crown C ("round soft crown"): height 50 % of width (was 88 %), rounded points, no pearls.
- "Admin · level" tag (profile, Settings card) in the level colours.
- Account switch circle, admin top bar crown, Admin actions slot: my level's colours.
  Admin conversations "Owner only" slot stays gold.
- Tap a crown (chat list, chat top bar, profile, contacts, admin lists, map nodes) or the
  "Admin · level" tag -> small bubble: level name in the crown colour + what this admin can do for you.
  Closes after 3 s / any tap / scroll / screen change. Rest of the row still opens the chat; a drag
  on the crown still scrolls.

## Tests (here)
- `flutter analyze`: 0 errors, nothing new in the changed files.
- Full suite (292 files): 10 of 12 chunks green on the first run. Chunk 02 was cut by the sandbox
  out of memory (a second job I ran) and chunk 08 hit the `link_paths_zoom_222` sha256 lock -> I put
  `link_paths_map.dart` below the lock line back exactly (hash matches). Then chunk 02 + chunk 08 + all
  map/crown files (58 files, 599 tests) rerun: all green.
- New `test/crown_tip_290_test.dart`: 13 tests; the 4 tap tests FAIL with the tap scope switched off.
- Old test changed (shape C only): `bundle217d_test.dart` crown height 0.88 -> 0.50
  (`heightFor(50)` 44 -> 25, `mark(20)` 17.6 -> 10.0). Version lines in `bundle223_logs_test` /
  `nearby_190_test`. Nothing removed.
- Kotlin not touched (not run). Release APK: CI builds it (sandbox has 2 GB).

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_3.0.91_2026-11-14.zip" .
git add -A
git add -f docs/history/TODO_290.md docs/history/APPLY_app_3.0.91.md
git commit -m "v3 3.0.91 bundle 290: crown colour per admin level (owner gold, operator blue, security red, auditor silver) with matching photo ring and tag, lower round crown C, tap a crown or the admin tag for a small tip on what that admin can do"
git push
```
