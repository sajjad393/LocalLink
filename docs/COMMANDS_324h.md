# 324h — the red build, named and fixed (`3.0.118+189`)

**Your paste found it.** The failing test is:

```
test/nearby_190_test.dart:216
"no contacts + a stranger with a relay link: card, not "everyone added""
Expected: exactly one matching candidate
  Actual: Found 0 widgets with text "Add friend"
```

**Why it failed:** that test pumped the screen for a fixed length of time and then looked for the card. Building the first card takes a while for real reasons (the pairing/crypto work runs on the real clock), so the fixed pump can finish *before* the card exists — on your PC it did (Flutter 3.47.5), on a fast runner it just barely didn't.

**The fix:** the test now **waits for the card itself** (up to 90 s) and then makes the *same* assertion. Nothing is loosened, no app code is touched — it is the timing guess that went away, not the check. Same file, updated in place.

---

## Run these in PowerShell (one line at a time — `&&` does not work in PowerShell 5)

```powershell
git pull
```

```powershell
git apply --check ..\fix324h.patch
```
*(silence = good; if it complains, copy the 5 files from `pkg324h` over your repo instead)*

```powershell
git apply ..\fix324h.patch
```

**Before pushing — each file on its own line:**

```powershell
flutter pub get
```
```powershell
flutter test test/nearby_190_test.dart
```
```powershell
flutter test test/bundle223_logs_test.dart
```
```powershell
flutter test test/bundle324_test.dart
```

All three must say **All tests passed!** Then:

```powershell
git add -A
```
```powershell
git commit -m "324h: 3.0.118+189 - a red build now says which test failed; nearby_190 waits for its card"
```
```powershell
git push origin main
```

---

## What is in this build (5 files)

| File | Change |
|---|---|
| `.github/workflows/app_ci.yml` | a red run now writes **which test failed** and **the file count** to the run page (readable without signing in) |
| `test/nearby_190_test.dart` | **the fix** — waits for the card instead of guessing a pump length (+20 lines) |
| `lib/core/config/app_build.dart` | `3.0.118` / `189` |
| `pubspec.yaml` | `3.0.118+189` |
| `test/bundle223_logs_test.dart` | the pins follow (`118`, `189`, `v3 · 3.0.118+189`) |

No app behaviour changes. No screen changes. The only user-visible difference is the version number.

---

## What I checked here (Flutter 3.47.7, clean clone of your `8311c00`, patch applied)

| File | Result |
|---|---|
| `nearby_190_test.dart` | **12 passed** — and the whole file now takes **6 s** instead of 77 s, because it stops guessing how long to wait |
| `bundle223_logs_test.dart` | 7 passed (the version pins) |
| `bundle324_test.dart` | 18 passed |
| `bundle323_test.dart` | 18 passed |

The patch **applies clean** on `8311c00` (checked with `git apply --check` on a fresh clone).

---

## Two notes

1. **Your Flutter is 3.47.5, CI is 3.47.7.** Worth knowing: a test can behave differently between them. If you ever see a test pass locally and fail in CI (or the reverse), that is the first thing I will check.
2. **PowerShell:** use `;` or separate lines. In PowerShell 5.1, `a && b` is a syntax error; in PowerShell 7 it works. Everything above is written so it works in both.

After you push, the run page will say, in plain text, which test failed if anything still fails — so the next red build names itself without you sending me anything.
