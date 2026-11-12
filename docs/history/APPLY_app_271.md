# APPLY app 271: D-271-1 startup guard + Cycle 3 report (no version change)

Zip: `locallink_app_271_2026-11-14.zip`, on top of `390de01` (3.0.84+155 + bundle 270).

## Why
Cycle 3 (3 phones) passed all 8 checks. One red log line on RMX3938, first open after the update:
`LateInitializationError: Field '_db' has not been initialized` from the group file pump.
The pump runs from an 8 s timer; the database took 8.2 s to open that time. No user effect.

## What changed (1 code file + 1 test + 4 notes)
- `lib/core/services/local_store.dart`: `purgeGroupFileSends` and `groupFileSends` do nothing /
  return an empty list until the database is open (same guard as `touchDevicePresence`).
- `test/bundle271_store_guard_test.dart` (new, 4 tests; without the fix 3 fail with the same
  LateInitializationError as the phone).
- `docs/history/TODO_271.md`, `docs/history/APPLY_app_271.md`, `docs/history/CYCLE3_REPORT.md`,
  `docs/history/RUN_CYCLE3.md`.

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_271_2026-11-14.zip" .
git add -A
git add -f docs/history/TODO_271.md docs/history/APPLY_app_271.md docs/history/CYCLE3_REPORT.md docs/history/RUN_CYCLE3.md
git commit -m "v3 3.0.84 bundle 271: group file pump waits for the database (D-271-1, one LateInitializationError on the first open after an update when the 8 s timer beat an 8.2 s DB open; no user effect) + Cycle 3 report (3 phones, 8 checks OK, READY WITH KNOWN LIMITATIONS); no version change"
git push
```
Then check GitHub > LocalLink > Actions > App CI: every step should be green.
No new APK is needed (no user-visible change).
