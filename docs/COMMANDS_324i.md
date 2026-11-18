# 324i — the red run will give me the test name by itself (`3.0.119+190`)

**Your 324h landed:** commit `41c264d`, pushed. Android ✅, Flutter ❌ again (run #37, 11 m 11 s) — so the failing test is **not** `nearby_190` (that one is fixed and green on your PC). It is something else in the suite.

**And I found out why the run page still didn't help me:** the step summary sits behind the same sign-in wall as the log. What *is* readable without signing in is the **Annotations** box — I can see "Tests + coverage: exit code 1" right now, but not the names.

**So 324i writes the names into an annotation.** One new block in the test step:

```
::error title=Failing test::test/xyz_test.dart: the test name
```

That appears in the Annotations box, which I can read anonymously — so the next red run tells me the name itself, with no pasting from you. I tested the extraction on a fake CI log; it prints exactly that for each failing test (up to 5).

---

## Run in PowerShell, one line at a time

Download and extract **`locallink_app_324i_2026-11-18.zip`** into your repo folder (replace = Yes), then:

```powershell
git status --short
```
*Must show 4 modified files: `app_ci.yml`, `app_build.dart`, `pubspec.yaml`, `bundle223_logs_test.dart`.*

```powershell
Select-String -Path lib\core\config\app_build.dart -Pattern "kAppBuild = "
```
*Must print `const int kAppBuild = 190;`*

```powershell
git add .github/workflows/app_ci.yml lib/core/config/app_build.dart pubspec.yaml test/bundle223_logs_test.dart
```
```powershell
git commit -m "324i: 3.0.119+190 - a red run names the failing test in an annotation (readable without sign-in)"
```
```powershell
git push origin main
```

Then build the APK as usual — **3.0.119+190**.

---

## What is in it

| File | Change |
|---|---|
| `.github/workflows/app_ci.yml` | after the tests, up to 5 `::error title=Failing test::<file>: <test>` annotations (+ `fails.txt` in the artifact) |
| `lib/core/config/app_build.dart` | `3.0.119` / `190` |
| `pubspec.yaml` | `3.0.119+190` |
| `test/bundle223_logs_test.dart` | pins follow |

No app code changes. No screen changes. Nothing to test on a phone.

**Checked here:** YAML parses, `bundle223_logs_test.dart` 7/7 passed with the new numbers, `nearby_190_test.dart` 12/12, and the annotation extraction verified against a fake log with your exact failure line format.

---

## One thing worth knowing

`324h` fixed `nearby_190` — that failure was real on your PC (Windows, Flutter 3.47.5). The CI red is a **different** test. After 324i, its name will be sitting in the Annotations box of the run page, and I will read it there.

**325 is unaffected**, but its version moves to **`3.0.120+191`** because 324i takes `119+190`. `ISSUE_325_waiting.md` is updated to say so — still waiting on your four answers (or "your way") before I build it.
