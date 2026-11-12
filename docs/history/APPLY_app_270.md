# APPLY app 270: App CI Kotlin tests green (CI/test setup only, no version change)

Zip: `locallink_app_270_2026-11-14.zip`, on top of 3.0.84+155 (`d4bfe39`).

## Why
The first App CI run after the push had one red step, "Kotlin unit tests" (`./gradlew testDebugUnitTest`): 35 of 488 app tests and 2 tests of the image_picker plugin failed. The app itself was fine. Details: `docs/history/TODO_270.md`.

## What changed (4 files + 2 notes; nothing in lib/ or android main code)
- `android/app/build.gradle`: unit tests start in `android/app/src`, so the source-check tests find `main/kotlin/...`.
- `MeshRoutingTest.kt`, `MeshFinalRecipientDeliveryTest.kt`: `removeFirst()` → `removeAt(0)` (works on Java 17; same checks).
- `.github/workflows/app_ci.yml`: runs `./gradlew :app:testDebugUnitTest` (our tests only) and uploads the report from `build/app/reports/tests/`.
- `docs/history/TODO_270.md`, `docs/history/APPLY_app_270.md`.

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_270_2026-11-14.zip" .
git add -A
git add -f docs/history/TODO_270.md docs/history/APPLY_app_270.md
git commit -m "v3 3.0.84 bundle 270: App CI Kotlin tests green - unit tests start in android/app/src so the source checks find main/kotlin (33 failed only in Gradle), two mesh tests use removeAt(0) instead of the Java 21 removeFirst (CI runs Java 17), CI runs only the app's own tests (:app:testDebugUnitTest) and uploads the report from build/app/reports/tests; no app code change"
git push
```
Then check GitHub > LocalLink > Actions > App CI: every step should be green.
