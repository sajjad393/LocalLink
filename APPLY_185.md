# Bundle 185 - ZTE: killed in the background, slow open, SEAL not_ready (3.0.16+87)

Plan: TODO_185.md. Phone: ZTE Blade A35 (Z2453), Android 14, 2 GB RAM.
**Apply 184 first** if you have not pushed it yet (185 is built on top of 184).

## What changed
A. **Measure (new log lines)**
- `APP_LAST_EXIT` on every start: why LinkUp stopped last time
  (low_memory / force_stop / permission_change / crash ...), was Keep running on, ZTE's own text.
- `KEEP_ALIVE_STATE` on open and when the app goes behind another app
  (battery unrestricted, background restricted, bucket, notifications, service).
- `MAIN_STALL` when the screen is frozen 700 ms or more (first 2 min after open + during calls).
- `APP_OPEN since_process_start_ms`, `STARTUP_STEP` per step, `STARTUP_DONE total_ms=... slowest=...`.

B. **ZTE background kill**
- Low memory while hidden: video thumbnails and pictures are dropped (`MEMORY_PRESSURE`, `MEMORY_TRIM`).
- "Keep LinkUp running" on ZTE: the shortcut also opens ZTE's power manager app; 3 simple steps under it.

C. **SEAL not_ready**: a locked message that comes before the keys are ready is held
(max 50, max 30 s) and opened in order when the keys are ready. Before, it was thrown away.

D. **Slow open**
- Chat list shows as soon as database, settings and keys are ready; the rest starts after the first frame
  (max 1.5 s wait). Notification taps wait until the services run.
- Voice self-test: 20 s after start (or at the first call), and its answer is remembered per build.
- Keys start: no more 4 secure-storage writes on every start (only when something changed).
- WorkManager health schedule moved off the main thread.

## Files (22)
New:
- android/app/src/main/kotlin/com/sajjad/locallink/AppHealth.kt
- android/app/src/main/kotlin/com/sajjad/locallink/AppHealthPolicy.kt
- android/app/src/main/kotlin/com/sajjad/locallink/OpusSelfTestMemory.kt
- android/app/src/test/kotlin/com/sajjad/locallink/App185Test.kt
- lib/core/diagnostics/startup_timer.dart
- lib/core/services/memory_trim.dart
- test/bundle185_test.dart

Changed:
- android/app/src/main/AndroidManifest.xml (queries for 2 ZTE packages)
- android/app/src/main/kotlin/com/sajjad/locallink/CallOpusCodec.kt
- android/app/src/main/kotlin/com/sajjad/locallink/CallVoiceUdp.kt
- android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt
- android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt
- android/app/src/main/kotlin/com/sajjad/locallink/VendorBackgroundIntents.kt
- lib/app/app_dependencies.dart
- lib/app/local_link_app.dart (stamp: bundles 104-185)
- lib/core/services/identity_crypto_service.dart
- lib/features/connectivity/data/services/sealing_peer_transport.dart
- lib/features/files/presentation/widgets/chat_video_controller.dart
- lib/features/home/domain/background_brand_guide.dart
- pubspec.yaml (3.0.16+87)
- test/bundle184_test.dart (version check moved to 185)

## Apply (PowerShell)
```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes185_2026-11-01.zip" .
git add -A
git add -f APPLY_185.md
git reset -q -- android/local.properties
git commit -m "v3 185: ZTE - why it stopped (exit reason log), freeze watcher, held locked messages, faster start, ZTE settings help - 3.0.16+87"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter pub get
flutter build apk --release
```

## Phone checks (ZTE)
1. Open the app from cold, then send the log. Look for `STARTUP_DONE total_ms=` (goal: under 3000) and `MAIN_STALL`.
2. Open Share logs, wait 1 minute, come back. If LinkUp restarted, the log shows `APP_LAST_EXIT reason=...`.
3. Do the 3 ZTE steps in Keep LinkUp running, then repeat test 2. Did it survive?
4. 3-min call: no "Skipped 60+ frames" lines during the call.
5. Turn Realme Wi-Fi off and on while the ZTE opens: no `SEAL_OPEN_FAILED reason=not_ready` (maybe `SEAL_HELD`).

## Tested here (not on a phone)
- Kotlin: clean compile, 281 tests pass (14 new).
- Flutter: analyze no errors (150 info, same as before); all 827 tests pass (15 new).
- The first-screen order, ZTE screens and memory events can only be proven on the phone.
