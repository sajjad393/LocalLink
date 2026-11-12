# TODO 270: App CI "Kotlin unit tests" red (CI/test setup only, no app change)

First App CI run after the push (`d4bfe39`, run 43168256041):
- `flutter` job: green (analyze, all Flutter tests, both R268-1 release checks).
- `android` job: debug APK OK, release APK OK, **Kotlin unit tests FAILED**.
- Backend CI (`86aa525`): green.

## Reproduced here with the same command (`./gradlew testDebugUnitTest`)
- App: 488 tests, 35 failed.
  - 33: the source-check tests read `main/kotlin/...`, relative to `android/app/src` (that's how the local runner starts them). Gradle starts tests in `android/app`, so the file isn't found (`FileNotFoundException`, or an empty list in `Perm223Test`).
  - 2: `MeshRoutingTest:392` and `MeshFinalRecipientDeliveryTest:57` call `mutableListOf().removeFirst()`. Kotlin compiles it to the Java 21 `List.removeFirst`, and CI runs Java 17, so `NoSuchMethodError`.
    - App code checked: every `removeFirst()` in `main/` is on an `ArrayDeque`, so it's safe on all phones.
- Plugin `image_picker_android` (not our code): 2 of its own Robolectric tests fail on Java 17.

Not a regression: it's the first time Gradle unit tests ever ran in CI (CI came with kit 264). Before that they ran only with the local runner.

## Fix (4 files, nothing under lib/ or main/)
1. `android/app/build.gradle`: `testOptions { unitTests.all { workingDir = file("src") } }`. Affects unit tests only.
2. `MeshRoutingTest.kt` and `MeshFinalRecipientDeliveryTest.kt`: `removeFirst()` → `removeAt(0)` (same meaning, assertions unchanged).
3. `.github/workflows/app_ci.yml`:
   - run `./gradlew :app:testDebugUnitTest` (the app's own tests only);
   - upload path `build/app/reports/tests/` (Flutter writes app output there; the old path never existed).

## Checked here
- `./gradlew :app:testDebugUnitTest`: **488 tests, 0 failed, 0 skipped, EXIT=0**.
- `security_release_268_test.dart` (reads app_ci.yml): +5, EXIT=0.
- Patch: `/home/user/wip_270_app.patch`. No version change.
