# Everything unpushed — 329 + 330 + 331 in one (`3.0.125+196`)

One zip, one block, one commit. These three are the only builds not yet on your `main` (your main is at `0eb170b` = 328).

**What you get after this push:** your phone keeps its own chained record (**329**), an ask can travel by QR/link when two phones aren't on the same Wi-Fi (**330**), and a screen that says honestly where an ask can go right now, with dates in real words (**331**).

**All commands in one block** (download `locallink_app_329_331_2026-11-18.zip` first):

```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"; Expand-Archive -Path "$env:USERPROFILE\Downloads\locallink_app_329_331_2026-11-18.zip" -DestinationPath "C:\Users\sajjad Ahmed\Downloads\LocalLink" -Force; Select-String -Path lib\core\config\app_build.dart -Pattern "kAppBuild = "; flutter pub get; flutter test test/bundle329_test.dart; flutter test test/bundle330_test.dart; flutter test test/bundle331_test.dart; flutter test test/bundle196_test.dart; flutter test test/bundle223_logs_test.dart; git add -A; git commit -m "329 + 330 + 331: 3.0.125+196 - export evidence, ask by QR/link, honest dates and what this phone can do"; git push origin main; git log --oneline -1
```

Expected: `kAppBuild = 196` → **15 passed** → **14 passed** → **16 passed** → **32 passed** → **7 passed** → push.

---

## What is in the zip (21 files)

| File | Build | Change |
|---|---|---|
| `lib/features/admin/data/evidence_329.dart` | **new** 329 | the chained record: `add`, `export`, `verify`, keeps newest 500 |
| `lib/features/admin/presentation/screens/evidence_329_screen.dart` | **new** 329 | count, check result, Copy, the file itself |
| `lib/features/admin/data/actions/chat_answer_reader.dart` | 329 | one line: every Get chat ask is recorded (a failed record never breaks the ask) |
| `lib/features/directory/data/ask_link_330.dart` | **new** 330 | `of`, `parse`, `chatOf`, `codeOf` (the 6 letters) |
| `lib/features/directory/presentation/ask_qr_330_screen.dart` | **new** 330 | QR + 6 letters + Copy link + Scan their ask (camera) |
| `lib/features/directory/presentation/contact_sheets.dart` | 330 | row **Ask by QR or link** |
| `lib/features/directory/presentation/contacts_screen.dart` | 330 | builds your ask for that person and opens it |
| `lib/features/admin/data/honest_331.dart` | **new** 331 | `Honest331.ago`, `CanDo331`, `CanDoFacts331.read` |
| `lib/features/admin/presentation/screens/can_do_331_screen.dart` | **new** 331 | the three true cards |
| `lib/features/admin/presentation/screens/admin_security_screen.dart` | 329 + 331 | two rows in Security: **Export evidence** and **What this phone can do** |
| `lib/l10n/app_en.arb`, `app_ur.arb` + 3 gen files | all three | 29 new lines, Urdu included |
| `lib/core/config/app_build.dart`, `pubspec.yaml` | all three | `3.0.125` / `196` |
| `test/bundle223_logs_test.dart` | all three | the single literal pin, now `125/196` |
| `test/bundle329_test.dart`, `bundle330_test.dart`, `bundle331_test.dart` | **new** | 15 + 14 + 16 tests |

`fix329_331.patch` (2058 lines) does exactly the same as the zip — use it if you prefer `git apply`.

## Verified here

| Check | Result |
|---|---|
| `bundle329_test.dart` | **15 passed** — chained lines · **one changed word → "line 2 was changed"** · deleted line, reorder, junk all fail · newest 500 kept |
| `bundle330_test.dart` | **14 passed** — QR/link round trip · junk refused · same 6 letters both phones · a 2020 link still works · scanning a good ask files it here |
| `bundle331_test.dart` | **16 passed** — every date form · **never "0 days ago"** · clock behind says "time is off" · phone → server → **waiting** · no spinner when nothing can travel |
| `bundle196_test.dart` | **32 passed** (the extra contact-sheet row did not break People) |
| `bundle223_logs_test.dart` | **7 passed** (single pin at `125/196`) |
| One patch on a fresh clone of your `0eb170b` | ✅ applies clean |

**Not run here:** full `flutter analyze` (the analyzer dies on this 1.9 GB sandbox). Every new screen is compiled and pumped by a widget test, so none of it is untested code.

## If something goes red

Tell me the build number and the failing test name and I'll fix that one, no guessing. Nothing here expires and nothing needs a server — if you want to sit on this build for a week, it behaves the same.
