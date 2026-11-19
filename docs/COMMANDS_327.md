# 327 — your own phones help each other (`3.0.121+192`)

**What changed:** your other phone was invisible to a Get chat — `_resolve()` removes your own phones from the list of phones a card can go to. Now they are **kept and put first**, so a chat your home phone already has comes from it, phone-to-phone, **0 MB** — and the request row says so: `Get chat · Full chat · phone to phone · 0 MB`.

Nothing else changes: if no own phone has it, the ask goes on to the other phones exactly as before. No server, no new timer, nothing expires.

**All commands in one block** (download `locallink_app_327_2026-11-18.zip` first):

```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"; Expand-Archive -Path "$env:USERPROFILE\Downloads\locallink_app_327_2026-11-18.zip" -DestinationPath "C:\Users\sajjad Ahmed\Downloads\LocalLink" -Force; Select-String -Path lib\core\config\app_build.dart -Pattern "kAppBuild = "; flutter pub get; flutter test test/bundle327_test.dart; flutter test test/conversations_314_test.dart; flutter test test/bundle325_test.dart; flutter test test/bundle326_test.dart; flutter test test/bundle223_logs_test.dart; git add -A; git commit -m "327: 3.0.121+192 - your own phones help each other (phone to phone, 0 MB)"; git push origin main; git log --oneline -1
```

Expected: `kAppBuild = 192` → **11 passed** → **22 passed** → **19 passed** → **14 passed** → **7 passed** → push.

---

## What is in it

| File | Change |
|---|---|
| `chat_answer_reader.dart` | `_resolve()` returns `mine` (the phones it used to drop); the Get chat card, the file card and a Waiting that fires all use **`[...who.mine, ...who.targets]`** — my phones first; the request row adds **phone to phone · 0 MB** when the answer came from one of my phones |
| `lib/l10n` en + ur (+ gen) | `phoneToPhone327` = "phone to phone · 0 MB" |
| `app_build.dart`, `pubspec.yaml`, `bundle223_logs_test.dart` | `3.0.121` / `192` |
| **new** `test/bundle327_test.dart` | 11 tests |

**Deliberately unchanged:** `delete_completely` still goes to the other phones only (327 is about asking, not deleting), and a chat that exists *only* on your phones is still refused with 314's words — there is nobody to ask.

## Verified here

| Check | Result |
|---|---|
| `bundle327_test.dart` | **11 passed** — my phones are kept and used first · a chat only on my phones is still refused · the row says 0 MB only when my phone answered · words in both languages · delete path untouched · pins follow the constants |
| `conversations_314_test.dart` | **22 passed** (the `_resolve` change did not break 314) |
| `bundle323_test.dart` | **18 passed** |
| `bundle325_test.dart` | **19 passed** |
| `bundle326_test.dart` | **14 passed** |
| `bundle223_logs_test.dart` | **7 passed** (pins at `121/192`) |
| Patch applies clean on your `f09ef6f` | ✅ fresh clone |

**Not run here:** full `flutter analyze` and the biggest widget suites (1.9 GB RAM on this sandbox kills the analyzer). CI is the real check.

## One honest limit

"Stop the other cards when my phone answers" (D2) is **not** a new call. The existing one-receipt rule (`need: 1`) plus part-id dedupe already end the ask when an answer lands; I did not add a second stop path, because there was nothing truthful to test here. If you see two answers on a real phone, tell me and I'll make it explicit in the next build.
