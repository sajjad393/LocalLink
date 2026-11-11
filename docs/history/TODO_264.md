# TODO 264 - run-time test on GitHub (Android emulator + real server) that makes logs for me

Status: BUILT as test kit on top of 3.0.83+154 (14 Nov), no version change.
Base: app 3.0.80+151 (bundle 263, built, waiting for your push). Backend `ca4f41c` (259), no backend change.

## Goal (your words)
"Maybe copilot can do run time test and make logs for you?"
- A GitHub job starts an Android emulator and our Go server, installs the app, then runs real flows: server off, server on, admin actions.
- At the end it gives one download (zip) with:
  - the same `LinkUp-logs-...txt` file you send me from the phones;
  - logcat;
  - the server log;
  - a screenshot after each step;
  - a PASS/FAIL summary.
- You upload that zip here and I read it, like the phone logs.

## What it can test / what it cannot

Can test (emulator + server on the same GitHub machine):
- Sign-up with the server off, the account upload by itself later, and the 3.0.80 auto-tries.
- Profile save offline, sign-in again, blocked by admin, update needed.
- The 3.0.80 "security code changed" note in the chat (2 emulators, phase F8).

Cannot test (no radio in an emulator, so only your 4 phones can):
- Wi-Fi Direct, Bluetooth, mesh, 2.4 GHz groups, the Nearby list.
- Calls / audio.
- ZTE / TECNO / Realme killing the app in the background.

## Decisions (my advice marked)

- **D1. How the emulator finds the server.** The app finds the server by UDP broadcast on port 45454 (`DiscoveryService.discover()` in `lib/features/connectivity/data/services/discovery_service.dart`). An emulator's broadcast never reaches the machine it runs on. Only a direct packet to `10.0.2.2` (the machine, as the emulator sees it) does.
  - **(my advice)** Add ONE test-only switch: `--dart-define=LINKUP_TEST_SERVER_IP=10.0.2.2`. When set, `discover()` also sends its normal ask straight to that address.
    - It is empty in every build you make, so your phones behave exactly as today.
    - No other app code changes.
  - Other choice: no app change, and the test types the address. That is not possible today, because sign-up has no server address box (only the QR transfer screen has one).
- **D2. Version.** **(my advice)** No version change: the app stays 3.0.80+151, because nothing changes for users. It goes in its own commit `v3 3.0.80 test kit 264: ...` on top of 3.0.80, after you push 3.0.80. Old tests stay unchanged; no version lines move.
- **D3. Who runs it.** **(my advice)** You press **Actions → "Runtime test 264" → Run workflow** on GitHub. It is one click, it does the same every time, and you don't need Copilot.
  - The repo is public, so these GitHub machines cost no minutes (NOT VERIFIED on your account page; check Settings → Billing if unsure).
  - Copilot is optional (phase E): only to repair the workflow if GitHub changes something. It must never touch `lib/`.
- **D4. When it runs.** **(my advice)** Only when you press the button (`workflow_dispatch`). It never runs on every push, so there are no surprise runs and no red marks on your commits.

---

## A. App: test-only server address (D1)

File: `lib/features/connectivity/data/services/discovery_service.dart`
- A1. New constant in `DiscoveryService`:
  `static const String testServerIp264 = String.fromEnvironment('LINKUP_TEST_SERVER_IP');`
- A2. New static method `static Set<String> targets264(List<String> addresses, {String testIp = testServerIp264})`. It returns:
  - `255.255.255.255`,
  - `subnetBroadcast(a)` for each address,
  - `testIp` only when it is not empty and `isPrivateIpv4(testIp)` is true.
- A3. In `discover()` (~line 158), the `targets` set becomes `targets264(addresses)`. The send loop, timeouts and the `SERVER_SEARCH` log stay as they are.
  - The log line `SERVER_SEARCH start ... targets=N` now shows N+1 when the switch is set. That makes the hint easy to spot in the log.
- A4. Nothing else in `lib/`. The server's reply already carries its address (`DiscoveredServer.fromJson`). The CI server sets `LOCALLINK_ADVERTISE_HOST=10.0.2.2`, so the reply says `10.0.2.2:8080`.

## B. Flutter run-time test (new folder `integration_test/`)

- B1. `pubspec.yaml`, under dev_dependencies:
  `integration_test: sdk: flutter`
  This is part of the Flutter SDK; nothing is downloaded from pub.dev. `pubspec.lock` gets the matching update.
- B2. `integration_test/rt264_helpers.dart`:
  - `Ctl264`: a small HTTP client to the control script on the machine (`http://10.0.2.2:8099`). It has `start()`, `stop()`, `admin(action, args)`, `shot(name)` and `mark(name)` / `waitMark(name)` for the 2-emulator job.
  - `waitLog(tag, {contains, timeout})`: waits until the app log has the line. It reads `AppLogFile.instance` and the log files, the same way as `LogShareService.prepare()`.
  - `dumpLogs()`:
    - calls `LogShareService.prepare()` (the same file the Send logs button makes);
    - prints it line by line between `RT264_LOG_BEGIN` / `RT264_LOG_END`;
    - asks the control script to pull the file with `adb run-as` as well.
  - `expectNoText(list)`: the 3.0.80 "must not show" texts.
- B3. `integration_test/rt264_server_flows_test.dart`: the scenarios in F, one `testWidgets` each, picked by `--dart-define=RT264_CASE=...` (one case per GitHub job).
  - It starts the real app (`app.main()`), so the real services, background work, timers and native code all run.
  - Timers are real time (the 60 s upload try is really 60 s).

## C. The machine side (new folder `tool/rt264/`)

- C1. `tool/rt264/server_ctl.py` (Python 3, standard library only), listening on `0.0.0.0:8099`:
  - `/start`, `/stop`: run or stop the Go server with the test settings (see C3). The database is kept between stop and start.
  - `/admin/<action>`: signs in to the admin API and calls the same paths the web admin uses:
    - `users`
    - `user/status` (block)
    - `version-rule` (update needed)
    - `session/revoke` (sign out)
    - `duplicates`
  - `/shot/<name>`: runs `adb exec-out screencap -p` to `out/shots/NN_<name>.png`.
  - `/mark/<name>`, `/wait/<name>`: barrier for the 2-emulator case.
  - `/pull-logs`: runs `adb exec-out run-as com.sajjad.linkup sh -c 'cat cache/LinkUp-logs-*.txt'` to `out/`.
- C2. `tool/rt264/run_case.sh <case> [serial]`:
  1. Starts `adb logcat` to `out/logcat_<case>.txt` (in the background).
  2. Runs a background loop that grants the permissions once the app is installed, so Android pop-ups don't hang the run:
     - `pm grant com.sajjad.linkup` for POST_NOTIFICATIONS, NEARBY_WIFI_DEVICES, ACCESS_FINE_LOCATION, BLUETOOTH_SCAN, BLUETOOTH_CONNECT, BLUETOOTH_ADVERTISE.
     - The same Allow you would tap. This only runs on the emulator.
  3. Runs `flutter test integration_test/rt264_server_flows_test.dart -d <serial> --dart-define=LINKUP_TEST_SERVER_IP=10.0.2.2 --dart-define=RT264_CASE=<case>`.
  4. Writes `out/summary_<case>.txt` with PASS/FAIL per step, the wall times, and the first failing step.
- C3. Server settings in CI (only on the GitHub machine; never your PC):
  - `LOCALLINK_ENV=development`, so no pairing code is needed. Pairing is tested separately in F7 by setting `LOCALLINK_PAIRING_CODE`.
  - `LOCALLINK_ADDR=0.0.0.0:8080`
  - `LOCALLINK_ADVERTISE_HOST=10.0.2.2`
  - `LOCALLINK_DB=out/server/locallink.db`
  - `LOCALLINK_ADMIN_BOOTSTRAP_USERNAME=rtadmin`, `LOCALLINK_ADMIN_BOOTSTRAP_PASSWORD` = a random 24-character value made in the job. It is not a secret and is never printed.
  - HTTP only (your rule "keep http not https"), no TLS settings.

## D. GitHub workflow (new file `.github/workflows/runtime_test_264.yml`)

- D1. Trigger: `workflow_dispatch` only, with an input `cases` (default `all`).
- D2. Job `server-flows`, matrix over the cases in F1–F7, runs-on `ubuntu-latest`, `timeout-minutes: 45`:
  1. `actions/checkout` (app) + `actions/checkout` of `sajjad393/localLinkBackend` at `ca4f41c` into `backend/`.
  2. `actions/setup-go` (`go-version-file: backend/go.mod`), then `go build -o out/server/locallink ./cmd/server`.
  3. `actions/setup-java` 17 + `subosito/flutter-action` pinned to Flutter **3.47.7** (the version my tests use).
  4. Enable KVM (the udev rule from the android-emulator-runner README).
  5. `reactivecircus/android-emulator-runner@v2` with:
     - `api-level: 34`, `target: google_apis`, `arch: x86_64` (Android 14, like the ZTE);
     - `disable-animations: true`;
     - `emulator-options: -no-window -gpu swiftshader_indirect -noaudio -no-boot-anim -camera-back none`;
     - `script: python3 tool/rt264/server_ctl.py & bash tool/rt264/run_case.sh ${{ matrix.case }}`.
  6. `actions/upload-artifact`: `rt264-<case>`, holding `out/` (logs, shots, summary, server log). Kept 14 days.
- D3. Job `key-note` (F8, 2 emulators). Same steps, but it starts 2 emulators (`emulator-5554` / `5556`), one server, and runs the A and B sides at the same time.
  - Allowed to fail without failing the run (`continue-on-error`). It is the slowest and the most likely to be flaky on GitHub machines.
- D4. Final job `pack`: downloads all artifacts and makes ONE zip `rt264_all_<run>.zip` with a top `SUMMARY.txt`. This is the only file you download and send me.

## E. Copilot (optional, only if you want it)

- E1. `.github/workflows/copilot-setup-steps.yml`, job `copilot-setup-steps`. It installs the same Go, Java and Flutter 3.47.7 and enables KVM, so Copilot's machine can run the same script. GitHub limits this job to 59 minutes.
- E2. `.github/copilot-instructions.md` (added with `git add -f`, because `*.md` is ignored):
  - "Never change files in `lib/`, `android/`, `test/` or `pubspec.yaml`."
  - "Only fix `.github/workflows/runtime_test_264.yml` and `tool/rt264/*` on a new branch, and open a PR."
  - "Do not push to `main`."
- E3. How you would use it: open an issue, "Runtime test 264 failed at <step>, see run <link>. Fix only the workflow", and assign it to Copilot. You check the PR before merging.

## F. Cases (what each job does, and what makes it PASS)

Each case starts on a fresh emulator with a fresh server database. "Log:" means the line must appear in the app log within the time given.

- **F1. signup_offline** (3.0.80 sign-up, 236):
  1. Server OFF. Open the app, then Create account with `rt_a` and a test password.
  2. PASS:
     - the Chats tab shows within 20 s;
     - no "Saved on this phone" text;
     - none of the 3.0.80 removed texts (list in G);
     - Log: `UI_HIDDEN_263|card=signup_saved`, `SERVER_SEARCH none` (or `start` with no `found`).
  3. Screenshots: `01_welcome`, `02_creating`, `03_chats`.
- **F2. upload_timer** (256 timer, by itself):
  1. After F1, start the server and touch nothing.
  2. PASS:
     - Log: `OFFLINE_ACCOUNT_CHECK ... from=timer`, then `OFFLINE_ACCOUNT_DONE` within 6 min (first tries 60 s apart);
     - the server user list has `rt_a`;
     - no card on Chats except "@x was taken, so you are @y" (only if renamed).
- **F3. upload_add_open / upload_account_open / upload_refresh** (3.0.80 auto-tries; 3 jobs):
  1. After F1, start the server, then within 5 s open Add friend (or Account, or pull down Chats).
  2. PASS:
     - Log: `OFFLINE_ACCOUNT_CHECK ... from=add_open` (or `account_open` / `refresh`), then `OFFLINE_ACCOUNT_DONE` within 30 s. That is before the 60 s timer, so it proves the new trigger did it.
     - No "Server connected / No server" line on Add friend; no "Find server now" on Account.
- **F4. profile_offline** (3.0.80 B1):
  1. Signed in, server OFF. Change the display name, then Save.
  2. PASS:
     - the snack "Profile saved" (exact);
     - Log: `PROFILE_SAVED_263|synced=n`.
  3. Then server ON. PASS: the server shows the new name within 6 min, and there is no message on the phone.
- **F5. signed_out** (262 D):
  1. Signed in, server ON. The admin calls `session/revoke` (sign out all phones of `rt_a`).
  2. PASS:
     - Log: `SESSION_DEAD_262 n=3`;
     - the card text "Sign in again" shows;
     - the app stops calling every 30 s: no more 401 lines in the server log for 10 min (check 3 min of it).
- **F6. blocked_and_update** (212, 3.0.80 kept messages):
  1. Admin `user/status` → blocked. PASS: the banner "Your account is blocked by admin..." shows.
  2. Unblock.
  3. Admin `version-rule` → minimum build 152. PASS: "Update needed in ..." shows.
- **F7. pairing_needed** (kept message):
  1. Server with `LOCALLINK_PAIRING_CODE` set; new sign-up.
  2. PASS: "The server needs a pairing code" card shows, and no other server cards.
- **F8. key_note** (3.0.80 C, 2 emulators, may fail without failing the run):
  1. A = `rt_a`, B = `rt_b`, both via the server. A adds B by @username, B accepts, and each sends one message.
  2. B: `pm clear` (new key), then logs in again as `rt_b`.
  3. PASS on A:
     - Log: `KEY_EVENT_263|user=..`;
     - in B's chat, the pill "rt_b's security code changed. Tap to learn more." (or "Tap to check.") is between the messages and there is NO bar on top;
     - tapping it opens "Security code";
     - after reopening the chat, the pill is still there.
  4. Also checks 237: still ONE chat for B, with the old and new messages.

## G. The 3.0.80 "must NOT show" list (checked on every screen the test opens)
- "carried by", "Account saved", "Publish", "Waiting for the server to be updated", "on the server now", "Couldn't sync right now"
- "Account published to the server.", "will update when online", "Find server now", "Can't reach LinkUp"
- "Server connected", "No server", "Copy device id", "Saved on this phone", "Could not check your account history"

## H. Tests and checks before the zip (in my sandbox)
- H1. New `test/bundle264_test.dart` (unit tests):
  - `targets264(['10.0.2.16'])` has no extra address when the switch is empty;
  - with `testIp: '10.0.2.2'` it adds it;
  - a public IP such as `8.8.8.8` is never added;
  - `testServerIp264` is empty in normal test runs;
  - a source check that the switch name appears only in `discovery_service.dart` and `tool/rt264/` + the workflow.
- H2. Full Flutter suite (≈ 2650 + new) and `flutter analyze`: 0 errors.
- H3. `python3 -m py_compile tool/rt264/server_ctl.py`; `bash -n tool/rt264/run_case.sh`; the workflow YAML parses (`python3 -c "import yaml..."`).
- H4. The Go server builds from `ca4f41c` and `server_ctl.py` really starts and stops it here, and the admin calls answer. I CAN do this part in my sandbox (no emulator needed).
- H5. NOT possible here: the emulator part. My sandbox has no KVM and 1 GB of RAM. The first real run happens on GitHub; if it breaks I fix the scripts (not the app) from its log.
- Old tests: none change.

## I. Delivery
- ONE app zip `locallink_app_3.0.80_testkit264_<date>.zip` + ONE commit `v3 3.0.80 test kit 264: ...`, on top of your pushed 3.0.80.
- `APPLY_app_testkit264.md` has the PowerShell block plus "how to run it on GitHub and send me the zip" with screenshots-in-words:
  1. Actions
  2. Runtime test 264
  3. Run workflow
  4. wait ≈ 30–40 min
  5. open the run
  6. Artifacts: `rt264_all_...zip`
  7. upload it here
- TODO + APPLY go to `docs/history/` (`git add -f`).

## J. Risks
- R1. The first GitHub run may fail on machine setup (emulator boot, Gradle download). That is fixed in `tool/rt264` + the workflow only, never the app.
- R2. Emulator timing is slower than phones. Waits are generous (F2: 6 min), and FAIL means "not seen in time", with the log attached.
- R3. Android permission pop-ups: they are handled by the grant loop (C2). Flutter test taps go straight into the app, so a pop-up can't block them.
- R4. `flutter test` on a device may remove the app at the end. That is why logs are printed into the run log AND pulled by `run-as` before the test returns.
- R5. GitHub can change its machines. Pinned versions: Flutter 3.47.7, emulator action v2, API 34, backend `ca4f41c`.

## Not in this TODO
- No change to how the app works for users. No backend change. No Kotlin change.
- Wi-Fi Direct, Bluetooth, mesh, calls and video (video is stopped).
