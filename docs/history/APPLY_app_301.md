# APPLY app 301 - smaller APK (3.0.97+168)

**Real result, built here: release APK 112.0 MB -> 36.3 MB (-68 %).**

Zip: `locallink_app_301_2026-11-14.zip`, on top of GitHub `16464ac` (3.0.96+167).
Plan: `docs/history/TODO_301.md`.

## What changes
- **ARM 32 + ARM 64 only.** It is still ONE APK for every phone (Realme, Tecno, ZTE Go). The x86_64 code (PC emulators /
  Chromebooks) is gone.
  - Flutter's Gradle plugin had put x86_64 into the list itself when it loaded, so `build.gradle` clears that list and
    sets the two ARM types. A plain `flutter build apk --release` also gets this.
- **Native code is compressed inside the APK.** Since minSdk 24, Android Gradle stored it raw. The phone now unpacks it
  once at install, which takes a few seconds longer. Space used on the phone stays about the same.
- `tool\build_release_apk.ps1` and CI build ARM only (faster) and print the APK size.
- Not changed (your choice): sounds, fonts, the QR scanner, debug names. No Dart/Kotlin code changed; only the version
  number.

## Files (10)
- `android/app/build.gradle`
- `.github/workflows/app_ci.yml` (release line + "APK size" report step)
- `tool/build_release_apk.ps1`
- `pubspec.yaml`, `lib/core/config/app_build.dart` (3.0.97+168)
- new `test/apk_size_301_test.dart`
- `test/bundle223_logs_test.dart`, `test/nearby_190_test.dart` (version lines only)
- `docs/history/TODO_301.md`, `docs/history/APPLY_app_301.md` (git add -f)

## Tests
- `flutter analyze`: 0 errors; no issues in the new test.
- Full Flutter suite: 308 files, 13 chunks, **2973 tests, all passed** (2969 + 4 new).
- **Real release APKs built here** with the same command as CI (Flutter 3.47.7, AGP 8.11.1, NDK 28.2, JDK 17):

  | | 3.0.96 (16464ac) | 3.0.97 (this) |
  |---|---|---|
  | APK | **112.0 MB** | **36.3 MB** |
  | native code | 100.9 MB raw, arm64 + armv7 + x86_64 | 28.8 MB compressed, arm64 + armv7 |
  | dex / res / assets | 2.03 / 2.00 / 1.35 MB | same |

  - `libapp.so` (our Dart code) is the same size in both builds, 14,222,216 bytes. Its strings are identical except the
    version text.
  - The built manifest has `extractNativeLibs=true`, minSdk 24, versionCode 168, and a v2 signature (verified with
    apksigner).
  - The backend 299 upload check (`readAPK299` + `checkAPK299`) reads 3.0.97 correctly (com.sajjad.linkup, build 168)
    and accepts it after 3.0.96.
  - The APKs built here are signed with this sandbox's own debug key, so they are NOT for phones. Build yours on your
    PC as usual.
- **NOT checked here:** real phones (install over 3.0.96, sqlcipher DB, QR scan, calls) and CI.

## Phone checks
1. Install 3.0.97 over 3.0.96 on Realme, Tecno and the ZTE (no uninstall). Check that each one:
   - opens and logs in by itself;
   - shows old chats (the encrypted DB uses the sqlcipher native lib);
   - can make a voice call;
   - can scan a QR code (the ML Kit native lib).
2. Settings > Apps > LinkUp > Storage: app size is about the same as before (fine).
3. Upload the 3.0.97 APK on web System > App download, then update the ZTE from the server or from another phone. It
   installs.
