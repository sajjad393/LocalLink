# APPLY app test kit 264 (no version change, stays 3.0.83+154)

Zip: `locallink_app_testkit264_2026-11-14.zip`, on top of 3.0.83+154.
No backend change. Nothing changes for users.

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_testkit264_2026-11-14.zip" .
flutter pub get
flutter test
git add -A
git add -f docs/history/TODO_264.md docs/history/APPLY_app_testkit264.md .github/copilot-instructions.md
git commit -m "v3 3.0.83 test kit 264: GitHub run-time test - Actions > Runtime test 264 starts an Android emulator and the real server, runs sign-up, upload, profile, signed out, blocked, update and pairing flows and gives one zip with the app log, logcat, server log, screenshots and a PASS/FAIL summary; the app gets one test-only switch LINKUP_TEST_SERVER_IP that is empty in every normal build; App CI checks analyze, tests, the debug APK and Kotlin tests after each push to main and only warns"
git push
```

## Run it on GitHub
1. Open github.com/sajjad393/LocalLink > Actions.
2. Click "Runtime test 264" > "Run workflow" (keep `all`, backend `main`) > Run.
3. Wait about 30-40 min.
4. Open the run. At the bottom, under Artifacts, download `rt264_all_<number>`.
5. Upload that zip here.

## What is in it
- `integration_test/`: the app flows (sign-up with the server off, upload by itself, opening Add friend / Account / pull down, profile offline, signed out, blocked, update needed, pairing code, and the security code note with 2 emulators).
- `tool/rt264/`: the control script (starts the Go server over HTTP, admin actions, screenshots, logs).
- `.github/workflows/runtime_test_264.yml`: runs only when you press the button.
- `.github/workflows/app_ci.yml` (App CI): after each push to main GitHub runs analyze, all Flutter tests with coverage, the debug APK and the Kotlin tests. A red mark only warns you; it never stops a push. Results are under the run's Artifacts. Phones, radios and calls can't be tested there.
- `.github/workflows/copilot-setup-steps.yml` + `.github/copilot-instructions.md`: only if you want Copilot to repair the workflow; it may not touch `lib/`.
- App: `discovery_service.dart` also asks `LINKUP_TEST_SERVER_IP` when it is set. It is empty in your builds.
- `pubspec.yaml`: `integration_test` (part of Flutter, nothing new downloaded).

## Checked here
- New `test/bundle264_test.dart`: 7 tests, pass. `flutter analyze integration_test`: no issues.
- Live check here with the real Go server (backend 267): `server_ctl.py` start/stop, admin users/block/unblock/revoke/version/duplicates/count401, mark/wait. Block and revoke turn the next app call into 401, unblock gives 200 again.
- Fixed in the kit: in development mode the server does not make the admin account by itself, so `server_ctl.py` now runs `locallink --reset-admin` before each start (test 7 checks it). Without it every admin step got 401.
- Full Flutter suite with this kit: 2696 tests (2695 + test 7).
- `server_ctl.py` really started and stopped the Go server here and the admin calls answered (see report).
- NOT checked here: the emulator part (no emulator in my sandbox). The first real run is on GitHub; if it breaks, I fix only `tool/rt264` and the workflow.
- The backend is taken from `main` (so 267 is included). Wi-Fi Direct, Bluetooth, mesh and calls can't run on an emulator.
