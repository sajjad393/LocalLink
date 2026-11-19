# 328 — the safety number (`3.0.122+193`)

**What it does:** People → tap a contact → **Safety number**. Both phones show the same **60 digits in 12 groups of 5**. Read them to each other in person — if they match, the keys really are each other's and nobody is in the middle. **No server, no internet, no timer.** Nothing to set up, nothing expires.

**All commands in one block** (download `locallink_app_328_2026-11-18.zip` first):

```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"; Expand-Archive -Path "$env:USERPROFILE\Downloads\locallink_app_328_2026-11-18.zip" -DestinationPath "C:\Users\sajjad Ahmed\Downloads\LocalLink" -Force; Select-String -Path lib\core\config\app_build.dart -Pattern "kAppBuild = "; flutter pub get; flutter test test/bundle328_test.dart; flutter test test/bundle196_test.dart; flutter test test/bundle327_test.dart; flutter test test/bundle325_test.dart; flutter test test/bundle326_test.dart; flutter test test/bundle223_logs_test.dart; git add -A; git commit -m "328: 3.0.122+193 - the safety number (read it in person, works offline)"; git push origin main; git log --oneline -1
```

Expected: `kAppBuild = 193` → **15 passed** → **32 passed** → **11 passed** → **19 passed** → **14 passed** → **7 passed** → push.

---

## The number, exactly

- Made from **both signing keys**, sorted first → **A sees the same number as B**.
- 60 digits, 12 groups of 5, shown as **3 rows of 4 groups** (easy to read aloud).
- Same two keys → always the same number. A changed key → **a different number** (that is the whole point).
- Fixed domain string `locallink-safety-328` — if that ever changed, every number people had already compared would change with it, so it must not change.
- Missing keys (the common offline case) → **no number at all**, and the screen says why instead of inventing one.

## What is in it

| File | Change |
|---|---|
| **new** `lib/features/directory/data/safety_number_328.dart` | the pure rules: `of`, `groups`, `rows`, `matchPercent`, `looksValid`, `canCompare` |
| **new** `lib/features/directory/presentation/safety_number_328_screen.dart` | the screen: 12 groups, "read these in person", honest card when the keys are not here |
| `admin_action_service.dart` | `safetyNumber328(deviceId)` + `canShowSafety328` (my signing key vs theirs, computed on the phone) |
| `contact_sheets.dart` | one new row: **Safety number** (`contact_sheet_safety328`) |
| `contacts_screen.dart` | opens the screen for that person |
| `lib/l10n` en + ur (+ gen) | 5 new lines, Urdu included |
| `app_build.dart`, `pubspec.yaml`, `bundle223_logs_test.dart` | `3.0.122` / `193` |
| **new** `test/bundle328_test.dart` | 15 tests (14 pure + 1 widget) |

## Verified here

| Check | Result |
|---|---|
| `bundle328_test.dart` | **15 passed** — 60 digits/12 groups · same number both ways round · different person, different number · changed key, changed number · no keys, no number · 3 rows of 4 · match % · signing key on both sides · honest screen · no `http`, no timer · reachable row + handler · words in both languages · widget: the screen opens and shows the honest card · pins |
| `bundle196_test.dart` | **32 passed** (the contact sheet still works after the new row) |
| `bundle327_test.dart` | **11 passed** |
| `bundle325_test.dart` | **19 passed** |
| `bundle326_test.dart` | **14 passed** |
| `bundle223_logs_test.dart` | **7 passed** (pins at `122/193`) |
| Patch applies clean on your `7f69ab5` (327) | ✅ fresh clone |

**Not run here:** full `flutter analyze` (the analyzer dies on this 1.9 GB box — `Bad state: The analysis server crashed unexpectedly`) and the heaviest widget suites. The screen itself is compiled and pumped by the widget test, so it is not untested code.

## One honest limit

The number compares **identity signing keys**. If a person has two phones, each phone has its own key, so each phone shows its own number for them — that is correct and is what Signal does: you verify the phone you are actually talking to. If you want one number per *person* instead of per phone, that is a different design (families of keys), and I'd write it as its own issue.
