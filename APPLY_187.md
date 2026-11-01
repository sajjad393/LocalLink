# Bundle 187 - ZTE slow storage (4.12): measuring only (3.0.18+89)

Plan: TODO_187.md. Your choice: Option A.
**Apply 184, 185 and 186 first** if you have not pushed them yet (187 is built on top of 186).

## Why only measuring
- The newest ZTE log (about 1 hour) has **0** slow storage lines.
- The only slow line (Realme, `call_save ms=1918`) came while the screen was frozen after Accept. 186 fixes that freeze.
- So 4.12 is closed. Nothing changes in how messages and data are saved.

## What changed
A1. **`STORE_SUMMARY` every 10 min, only when something was slow**:
`STORE_SUMMARY window_min=10 ops= slow_500= max_ms= max_op= tx= max_tx_ms= max_tx= during_stall=`
- Counts the timed storage steps and transactions. Steps over 500 ms count as slow (before: only over 1500 ms showed).
- No timer: the line is written by the first storage step after the 10 minutes.

A2. **Frozen screen or slow disk?**
- A slow step asks Android whether the main thread was frozen at the same moment.
- The old lines stay, with a note at the end: `STORE_OP_SLOW op=… ms=… during_stall=y|n|-`.
  - `y` = the screen was frozen, not the disk.
  - `n` = the disk was really slow.
  - `-` = not watched (the freeze watcher runs only in the first 2 min after opening and during calls).

## Files (10)
New:
- lib/core/diagnostics/store_health.dart
- test/bundle187_test.dart
- android/app/src/test/kotlin/com/sajjad/locallink/Store187Test.kt

Changed:
- android/app/src/main/kotlin/com/sajjad/locallink/AppHealth.kt (remembers the last 300 ms+ freeze)
- android/app/src/main/kotlin/com/sajjad/locallink/AppHealthPolicy.kt (overlap rule)
- android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt ("stallOverlap" on the device channel)
- lib/core/services/local_store.dart (timing goes to StoreHealth; saving unchanged)
- lib/app/local_link_app.dart (stamp: bundles 104-187)
- pubspec.yaml (3.0.18+89)
- test/bundle186_test.dart (version check moved to 187)

## Apply (PowerShell)
```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes187_2026-11-01.zip" .
git add -A
git add -f APPLY_187.md
git reset -q -- android/local.properties
git commit -m "v3 187: storage check - STORE_SUMMARY every 10 min, slow step says if the screen was frozen, 4.12 closed - 3.0.18+89"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter pub get
flutter build apk --release
```

## Phone check (ZTE)
- Use the ZTE normally for 30 min (chats, a photo, a call), then send the log.
- Good: no `STORE_SUMMARY`, or small numbers.
- If `STORE_OP_SLOW … during_stall=n` shows up many times, the disk really is slow and we reopen 4.12.

## Tested here (not on a phone)
- Kotlin: clean compile, 292 tests pass (4 new).
- Flutter: analyze no errors (150 issues, same as before); all 844 tests pass (9 new).
