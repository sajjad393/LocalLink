# APPLY app 3.0.87 -> 3.0.90+161 in ONE zip (bundles 278, 279 app part, 280, 282-289)

Zip: `locallink_app_3.0.87-3.0.90_2026-11-14.zip`, on top of the last pushed app commit **`de70ef7` (3.0.86+157)**.
It replaces the four separate zips 3.0.87, 3.0.88, 3.0.89 and 3.0.90: apply only this one.
The zip holds the final version of every changed file (3.0.87, then 3.0.88, 3.0.89 and 3.0.90 laid on top).
No file is deleted.

**Order:** backend 279 zip first (separate repo, `locallink_backend_279_2026-11-14.zip`), restart the server,
then this app zip.

## What is inside (details in each APPLY doc in docs/history)
- 3.0.87 (278): offline sign-in says why it failed. `APPLY_app_3.0.87.md`
- 3.0.88 (279 app part): the phone no longer reports old offline cards. `APPLY_app_3.0.88.md`
- 3.0.89 (280): friend links work from and to a phone-only account before the server is back. `APPLY_app_3.0.89.md`
- 3.0.90 (282-289): new AOSP tones (message channel v5), Add Contact redesign without Bluetooth / Wi-Fi Direct
  words + QR fixes, Roboto app-wide + text cap 1.3x, profile photo save ring, calls one row per person per day,
  recovery code card + Settings row + password screen, forgot password and welcome / login / create redesign
  with one loading, one toast look everywhere. `APPLY_app_3.0.90.md`

## Checks (done on the 3.0.90 tree = this zip on de70ef7)
- `flutter test` 291 files: 2817 passed, 0 failed.
- Kotlin unit tests: 491 passed, 0 failed (plain JUnit on Gradle-compiled classes).
- `flutter analyze`: 173 issues, 0 errors.
- Screen checks vs the mocks: 216 passed, no overflow.
- Release APK: 3.0.87 / 3.0.88 / 3.0.89 built here before (BUILD_EXIT=0). 3.0.90 was NOT built here
  (sandbox out of memory at R8), so the GitHub App CI build is the check.

## Not verified
- Nothing has been tested on a phone yet (278, 279, 280, 282-289). Web Users check after backend 279.
