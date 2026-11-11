# APPLY app R268-1 - release HTTP build rule (no version change, no app code change)

Zip: `locallink_app_r268-1_2026-11-14.zip`, on top of test kit 264 (after 3.0.83).

## Why
A release APK refuses plain HTTP unless it is built with `--dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true` (`lib/core/security/security_policy.dart`). Since 3.0.79 the app never uses HTTPS ("keep http not https"). So a release APK built without the flag cannot reach the server; the log shows "Plain HTTP is disabled in release builds". Up to 3.0.78 the saved HTTPS certificate hid this.

The security rule is NOT changed. Debug builds and release builds with the flag can use HTTP; release builds without it cannot.

## The one release build command
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
flutter build apk --release --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true
```
or: `powershell -ExecutionPolicy Bypass -File tool\build_release_apk.ps1` (same command).
Risk: with plain HTTP anyone on the same Wi-Fi can read and change passwords, sign-in tokens, messages and files sent to the server.

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_r268-1_2026-11-14.zip" .
git add -A
git add -f docs/history/APPLY_app_r268-1.md
git commit -m "v3 3.0.83 R268-1: release APK HTTP rule - one build command flutter build apk --release --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true (tool/build_release_apk.ps1), a test that runs the security rule with real release constants (without the flag plain HTTP is refused, with it the LAN server works, a saved pin never moves http to https), App CI runs it in release mode and builds the release APK; SecurityPolicy unchanged"
git push
```

## What changed (4 files)
- New `test/security_release_268_test.dart`. RT268_MODE says which build it is; test 0 proves the constants really are that mode:
  - debug: 5 tests;
  - release without the flag: 6 tests;
  - release with the flag: 5 tests.
- New `tool/build_release_apk.ps1`: the one release build command.
- `.github/workflows/app_ci.yml`: + 2 release-mode runs of the new test, + release APK build. Old steps unchanged. Only warns, never blocks.
- `docs/history/APPLY_app_r268-1.md` (this file).

## Checked here (14 Nov)
- The new test in 3 modes: 5/5, 6/6, 5/5 pass.
- The new test fails when it should:
  - mode asked without the release constant: 3 failures;
  - policy weakened to always allow: 4 failures;
  - pin ignores HTTP-only: 1 failure.
- 11 related old test files: pass. `flutter analyze`: 0 errors, the same 9 old warnings.
- Real release APK with the command above: built (exit 0), 3.0.83 (154), not debuggable. The compiled code has no "Plain HTTP is disabled" branch any more (the flag is in); the private-host and resource checks are still there.
- NOT checked: install on a phone. The APK built here is signed with this machine's debug key, not yours. Build your own with the command above.

## Phone check
After installing your own release build, open the app with the server on. The log must NOT show "Plain HTTP is disabled in release builds", and Chats / Add Contact must load from the server.
