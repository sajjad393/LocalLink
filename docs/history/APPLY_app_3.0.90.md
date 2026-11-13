# APPLY app 3.0.90+161: bundles 282-289 (one zip, one commit)

Zip: `locallink_app_3.0.90_2026-11-14.zip`, on top of the **3.0.89+160** commit (bundle 280).
**Order:** backend 279, then 3.0.87, then 3.0.88, then 3.0.89, then this zip. No backend change in 282-289.
Plan: `PLAN_3.0.90.md`. Mocks: `mocks/*_283/284_285/286/287/288*.html` (all approved).
Side by side mock vs build: `compare_3.0.90.html` (not in the zip).

## What changed
- **282 Tones:** the owner's picks from Android (AOSP) under the same file names: ringtone Triton, message
  Salacia, in-chat arrived NFC Start, in-chat sent Volume blip. Outgoing ringback unchanged. The message
  notification channel moves `locallink_messages_v4` -> `_v5` (Android keeps the old sound in an old channel);
  the old channel is deleted. `NOTICE` (new) carries the AOSP Apache 2.0 line.
- **283 Add Contact:** new search screen like mock v2 (search box, RESULTS cards with the green Contact pill
  or the Add button, "No one called X" card, PEOPLE NEARBY with the live Searching pill and the radar,
  Wi-Fi off / Allow cards only when needed, empty state "You've added everyone").
  - No Bluetooth / Wi-Fi Direct words or chips on the screen any more. BLE still works in the background;
    the Bluetooth permission is asked together with Nearby devices (once, then rests 7 days if refused).
  - QR: Scan QR code = camera at once; "My QR code" on the scanner really shows my code; "From photo"
    reads a QR from a picture (image_picker, already in the app); "Paste code" stays.
  - Same look on every phone: Roboto in the whole app, text size capped at 1.3x, fixed colours,
    light mode = light version of the same design.
- **284 Profile photo:** the Save spinner stops when the save ends; a ring on the photo while saving,
  then "Profile saved".
- **285 Calls:** one row per person per day, newest call + "(N)"; missed calls inside the row
  (red, "· N missed"); tap the row = list of that day's calls.
- **286 Recovery code:**
  - Chats: "Save your recovery code" card at the top (new account: hidden code, Show / Copy, Save on
    WhatsApp, I saved it / Later; old account: Show my code / Later; no code: Make my code / Later).
    No x button; Later = hide 1 day; "I saved it" = card goes away + toast "Recovery code saved".
  - Settings > Account > Backup and safety: first row "Recovery code" with Not saved / Saved tag (replaces
    the old grey note). Profile row opens the same screen.
  - Password first (checked on the phone, works offline; wrong password = red line), then the code screen
    (Hide / Copy, WhatsApp, 2 tips, Make a new code with "Your old code stops working").
  - The code is never written to the logs.
- **287 Forgot password:** new look like the mock, same logic (I have a code / I don't have it).
- **288 Welcome / Log in / Create account:** new look like the mock; ONE loading inside the button
  (the second spinner row is gone); red error card; password rules with ticks + strength bar.
- **289 Toasts:** one toast look everywhere (all 102 old SnackBars + the error toast + admin):
  `LinkToast` (done = green tick, error = red, info = blue). Same words as before. The round button moves up
  while a toast shows. Back-to-exit toast 2 s, app helper 4 s, all others 3 s.
- Buttons: 16 places where a button text had no font now use Roboto (they showed the phone's own font).

## Old tests changed (listed, nothing deleted or weakened)
- 282: `bundle178` (channel v5 + old v4 deleted).
- 283: `bundle173` (Contact pill keys), `bundle267` (small capital titles), `nearby_154`, `nearby_190`
  (new words + version line), `ble_cards_226` group 3 (BT chips -> 283 group).
- 284/289: `bundle263:93` (Profile saved via LinkToast, same words).
- 285: `calls_group_171` :44 / :66 + new tests; `bundle255_ui` `[3,1]` -> `[4]` (missed inside the row).
- 286: `bundle183` row order (Recovery code first, old note gone). 289: `bundle183:407` (back toast = LinkToast).
- 287: `forgot_password_222` (4 short words from the mock).
- 288: `welcome_152` (logo = mock badge).
- Version lines: `bundle223_logs`, `nearby_190`.

## New tests
`add_contact_283_test` (15), `auth_288_test` (5), `forgot_287_test` (3), `link_toast_289_test` (11),
`profile_save_284_test` (4), `recovery_286_test` (12), Kotlin `Tone282Test` (3),
`test_golden/golden_290_test.dart` (screens vs mocks; manual, not in CI: `flutter test --update-goldens test_golden/golden_290_test.dart`).

## Checks here
- `flutter test` all 291 files in 12 chunks (run again after the last edit): 2817 passed, 0 failed (2762 + 55 new).
- Kotlin unit tests: 491 passed, 0 failed (488 + 3 new). Compiled by Gradle `:app:compileDebugUnitTestKotlin`;
  run with plain JUnit in `android/app/src` (the Gradle test step ran out of memory in this 2 GB sandbox).
- Goldens: 18 screens x 12 modes (320/360/412 dp, dark/light, text 1.0/1.3) = 216 passed, no overflow.
- `flutter analyze`: 173 issues, 0 errors (was 175).
- Release APK: NOT built here. The Dart part compiled (ASSEMBLE_EXIT=0, app.so for arm, arm64, x64), but Gradle
  was killed for lack of memory at the R8 step after 23 min (2 GB sandbox). The CI build is the check.

## Not verified
- On phones: all new screens, the new tones and the v5 channel sound, From photo QR, BLE permission asked
  with Nearby, Recovery code card on a fresh sign-up and on an old account.

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_3.0.90_2026-11-14.zip" .
git add -A
git add -f docs/history/TODO_282.md docs/history/TODO_283.md docs/history/TODO_284.md docs/history/TODO_285.md docs/history/TODO_286.md docs/history/TODO_287.md docs/history/TODO_288.md docs/history/TODO_289.md docs/history/PLAN_3.0.90.md docs/history/APPLY_app_3.0.90.md
git commit -m "v3 3.0.90 bundles 282-289: new AOSP tones (message channel v5), Add Contact redesign without Bluetooth/Wi-Fi Direct words + QR scan/my QR/from photo, Roboto app-wide + text cap 1.3x, profile photo save ring, calls one row per person per day, recovery code card + Settings row + password screen, forgot password and welcome/login/create redesign with one loading, one toast look everywhere"
git push
```
Then GitHub > LocalLink > Actions > App CI should be green. Install the new APK over the old app on all phones.
