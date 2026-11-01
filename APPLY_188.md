# Bundle 188 - "Why it stopped" also says what was running (3.0.19+90)

Item B3 from the 185 plan.
**Apply 184, 185, 186 and 187 first** if you have not pushed them yet (188 is built on top of 187).

## What changed
- The `APP_LAST_EXIT` line (185) now has `doing=` before `text=`:
  `APP_LAST_EXIT reason=force_stop code=10 was=service ago_s=65 mem_mb=146 rss_mb=205 doing=call+file_out text=...`
  - `call`: a voice call was running.
  - `file_in` / `file_out`: a photo, video or file was coming in / going out (it moved in the last 60 s before the kill).
  - `none`: nothing was running. `-`: no note (older Android or a very early death).
- How: Android keeps a tiny note (under 128 bytes) with each LinkUp process and gives it back after a kill
  (Android 11+, both of your phones).
  - The note is updated only when a call starts or ends, when file counts change, or every 10 s while a file moves.
  - No disk writes, no timers.

## Files (8)
New:
- android/app/src/test/kotlin/com/sajjad/locallink/Exit188Test.kt
- test/bundle188_test.dart

Changed:
- android/app/src/main/kotlin/com/sajjad/locallink/AppHealth.kt
- android/app/src/main/kotlin/com/sajjad/locallink/AppHealthPolicy.kt
- android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt
- lib/app/local_link_app.dart (stamp: bundles 104-188)
- pubspec.yaml (3.0.19+90)
- test/bundle187_test.dart (version check moved to 188)

## Apply (PowerShell)
```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes188_2026-11-01.zip" .
git add -A
git add -f APPLY_188.md
git reset -q -- android/local.properties
git commit -m "v3 188: why it stopped also says what was running (call / file in / file out) - 3.0.19+90"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter pub get
flutter build apk --release
```

## Phone check (ZTE)
1. Start a call or send a big video. Then go Home and wait until ZTE closes LinkUp (or swipe it away from recent apps).
2. Open LinkUp again and send the log. Look for `APP_LAST_EXIT ... doing=call` (or `doing=file_out`).
3. Kill it while doing nothing: expect `doing=none`.

## Tested here (not on a phone)
- Kotlin: clean compile, 299 tests pass (7 new).
- Flutter: analyze no errors (150 issues, same as before); all 845 tests pass.
