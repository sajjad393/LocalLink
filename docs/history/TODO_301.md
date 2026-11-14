# TODO 301 - smaller APK (app only, 3.0.97+168)

Status: BUILT (14 Nov) - real release APK built here: 112.0 MB -> 36.3 MB.
Base: app `16464ac` (3.0.96+167).

## User choices (14 Nov)
- Keep ARM 32 + ARM 64 only. One APK for every phone; drop x86 / x86_64.
- Compress the native code inside the APK.
- NOT doing: WAV to OGG sounds, Roboto subset, QR scanner from Play services, removing Dart debug names,
  one APK per phone type.

## Why the APK is big (from the code + real library files)
- `android/app/build.gradle` has no `abiFilters`. So the release APK carries native code for arm64, armeabi-v7a and
  x86_64, plus the plugins' x86 copies, which are useless because Flutter has no x86 engine.
- Native libraries in the APK (MB, uncompressed):

  | Library | arm64 | armv7 | x86_64 | x86 | Source |
  |---|---|---|---|---|---|
  | `libflutter.so` (engine 3.47.7) | ~11 | ~8 | 13.0 | - | x86_64 measured after strip |
  | `libapp.so` (our Dart, 147k lines) | ~15-20 | ~12-16 | ~15-20 | - | estimate |
  | `libbarhopper_v3.so` (ML Kit barcode 17.2.0) | 4.4 | 2.8 | 5.5 | 5.5 | measured |
  | `libsqlcipher.so` (sqlcipher-android 4.10.0) | 5.2 | 3.6 | 5.7 | 4.9 | measured |

- Flutter 3.47 `minSdk` 24, so AGP stores `.so` files UNCOMPRESSED in the APK (`useLegacyPackaging` defaults to false).
  The download/share size is the full raw size.
- Assets are small (fonts 630 KB, sounds 1.9 MB) and are left as they are, per the user.

## Change (`android/app/build.gradle` only)
1. `defaultConfig { ndk { abiFilters.clear(); abiFilters.addAll(['armeabi-v7a', 'arm64-v8a']) } }`
   - BUILD NOTE: the Flutter Gradle plugin (3.47.7, `FlutterPlugin.kt` `configureAbiWithoutSplits`) already puts
     armeabi-v7a, arm64-v8a AND x86_64 into `defaultConfig.ndk.abiFilters` when it is applied (plugins block). So a
     release-only filter could be merged with it. Clearing the list in `defaultConfig` overrides it.
   - This applies to debug too (no emulator is used). Realme / Tecno = arm64; ZTE Z2453 Android Go = arm (32- or
     64-bit userspace both covered).
2. `packaging { jniLibs { useLegacyPackaging true } }` (AGP 8.11 name)
   - `.so` files are compressed in the APK; Android extracts them at install (AGP sets `extractNativeLibs=true` itself).
   - Also removes the 16 KB page-alignment worry for uncompressed libs.
3. CI release command: `--target-platform android-arm,android-arm64`. The x64 Dart code is no longer compiled at all,
   which makes the CI build faster. The debug step is unchanged.

## Measured result (real release APKs built here, same command as CI, Flutter 3.47.7, AGP 8.11.1)
| | 3.0.96 (16464ac) | 3.0.97 (301) |
|---|---|---|
| APK file | **112.0 MB** | **36.3 MB** (-68 %) |
| native libs | 100.9 MB stored raw, arm64 + armv7 + x86_64 | 28.8 MB deflated, arm64 + armv7 |
| dex / res / assets | 2.03 / 2.00 / 1.35 MB | same |
- `libapp.so` arm64 is 14,222,216 bytes in both builds. Its strings are identical except the version text, so no
  app code is lost.

## Earlier estimate (kept for history)
- Native code: ~125 MB raw (4 ABIs) -> ~64 MB raw (2 ABIs) -> ~28-32 MB compressed.
- APK: roughly 1/3 of today's size. The user compares the release APK file sizes of 3.0.96 and 3.0.97.
- Space used on the phone: about the same as now (smaller APK + extracted libs).
- Install: a few seconds longer (the phone unpacks the libs once).

## Safety checks
- Phone-to-phone share sends `ApplicationInfo.sourceDir` (`AppShareNative.kt:105`), the installed APK, so it stays
  2-ABI and installs on every phone.
- Server upload limit 300 MB (`apk299.go:34`), with no minimum size. The app download checks size + sha256 only
  (`silent_update_275.dart:401-406`). Nothing depends on the APK size.
- `System.loadLibrary` (Flutter, sqlcipher, ML Kit) works the same with extracted libs.
- Signing unchanged (same debug key), so it installs over 3.0.96.

## Tests
- New `test/apk_size_301_test.dart` (source check, like `bundle178_test`):
  - The release block has `abiFilters 'armeabi-v7a', 'arm64-v8a'` and no x86.
  - `useLegacyPackaging true`.
  - The manifest has no `extractNativeLibs="false"`.
  - The CI release line has `--target-platform android-arm,android-arm64`.
- Version lines in `bundle223_logs_test` + `nearby_190_test` (bump).
- Full Flutter suite + analyze. Kotlin/CI builds the real APK (cannot here).

## Files
- `android/app/build.gradle`
- `.github/workflows/app_ci.yml` (release line only)
- `pubspec.yaml`, `lib/core/config/app_build.dart` (version 3.0.97+168)
- `test/apk_size_301_test.dart` (new); version lines in `test/bundle223_logs_test.dart`, `test/nearby_190_test.dart`
- `docs/history/TODO_301.md`, `docs/history/APPLY_app_301.md`

## Phone checks after the build
1. APK file size (`build/app/outputs/flutter-apk/app-release.apk`): 3.0.97 vs 3.0.96. The gradle filter works with a plain
   `flutter build apk --release`; adding `--target-platform android-arm,android-arm64` only makes the build faster.
2. Install over 3.0.96 on Realme, Tecno and the ZTE: opens, chats, a call, a QR scan (ML Kit lib) and the encrypted DB
   (sqlcipher lib) all work.
3. Share the app phone to phone, and upload it on web App download: installs on the ZTE.
