# 325 — Ask now, deliver later (`3.0.119+190`)

**What changed for the user:** an ask made while the other phone is away is **no longer thrown away**. It is saved on this phone, shows **Waiting · asked 3 h ago · goes the moment their phone is near**, and goes by itself when that phone is reachable. Nothing expires — only **Stop** removes it. No server, no internet, no LAN needed to make one.

---

## Run in PowerShell, one line at a time

Download **`locallink_app_325_2026-11-18.zip`** and extract it into `C:\Users\sajjad Ahmed\Downloads\LocalLink` (Replace = Yes), then:

```powershell
git status --short
```
*Expect 12 modified + 2 new (`waiting_325.dart`, `bundle325_test.dart`).*

```powershell
Select-String -Path lib\core\config\app_build.dart -Pattern "kAppBuild = "
```
*Must print `const int kAppBuild = 190;`*

```powershell
flutter test test/bundle325_test.dart
```
*Must say **All tests passed!** (19 tests). If it doesn't, stop and paste — don't commit.*

```powershell
flutter test test/bundle223_logs_test.dart test/nearby_190_test.dart
```
*Both must pass (the version pins moved to `119+190`).*

Then, **all files at once** (this covers new files too):

```powershell
git add -A
```
```powershell
git status --short
```
*Only the 14 build files should be staged (plus nothing else — if `fix325.patch` / `docs\` show up, that's fine, they are untracked; leave them untracked or delete them)*

```powershell
git commit -m "325: 3.0.119+190 - ask now, deliver later (Waiting requests)"
```
```powershell
git push origin main
```
```powershell
git log --oneline -1
```

Then the APK: `.\tool\build_release_apk.ps1` → **3.0.119+190**.

---

## What is in it

| File | What it does |
|---|---|
| **new** `lib/features/admin/data/actions/waiting_325.dart` | the saved ask: id, chat key, the picked chat, range, kinds, when it was asked, how many tries |
| `chat_answer_reader.dart` | **saves first, sends second**; the 17 Nov dead end (`throw StateError(unknownPhonesWords323…)`) is gone; `fireWaiting325()` tries once a minute; a real send clears its Waiting twin |
| `request_step_307.dart` | new step `waiting` — big text **Waiting**, sub `asked 3 h ago · goes the moment their phone is near`, amber, never buzzes, nothing expires |
| `chat_request_notifier_307.dart` | the card stays on screen; the row line says **Waiting**; **one buzz at Ready only**, as 317 says |
| `conversations_kit307.dart` | Waiting is amber (like "on its way"), never red |
| `lib/l10n/app_en.arb`, `app_ur.arb` + `gen/` | 3 new words, English **and** Urdu, wrapped RLI…PDI like the other 304 words |
| `app_build.dart`, `pubspec.yaml`, `bundle223_logs_test.dart` | `3.0.119` / `190` |
| **new** `test/bundle325_test.dart` | 19 tests |

**How it fires — no new timer:** every card check (app start, and the existing 5-second check while the app is open) calls `fireWaiting325()`, which **tries at most once a minute per ask**. One entry per chat (the 324 chat key), so a second tap opens the **same** Waiting card instead of asking twice — the 18 Nov 18:53 duplicate cannot come back.

**Where it does not reach (honest limit):** with the app fully closed *and* the phone's background engine asleep, nothing can fire. The ask fires on the next app open, or on the next background wake. Nothing is lost in the meantime — it is on disk.

---

## What I verified here

| Checked | Result |
|---|---|
| `flutter test test/bundle325_test.dart` | **19 passed** (store round-trip, broken store, tries, age, the card's words, English + Urdu, the reader source contract, the palette, the notifier, the version) |
| Compile of `chat_answer_reader.dart`, `request_step_307.dart`, `chat_request_notifier_307.dart`, `conversations_kit307.dart`, all l10n | ✅ (a missing `Step307.waiting` case in the notifier was found and fixed this way) |
| `bundle223_logs_test` pins | moved to `119/190` together with the code |

**What I could not run here:** the full `flutter analyze` and the big widget suites (`conversations_*`, `bundle317/318/321/322`) — this sandbox has 1.9 GB of RAM and the Dart compiler/analyzer gets killed (exit 9 / "compiler exited unexpectedly") before it finishes. Those ran fine at 324d–324h on the same box when memory allowed. **Your PC and CI will be the real check of those**; if any of them fails, the run page now names it and I fix it in the next build.

---

## The four decisions, as built (say if you want any changed)

| | Built | |
|---|---|---|
| D1 colour | **amber** from the start, never red | as recommended |
| D2 age words | **"asked 12 min ago"** under an hour, then **"asked 18:44"** / **"asked on 22 Nov"** | plainer than "3 h ago", reuses existing date words |
| D3 retry | **on triggers only** (card check) **+ at most once a minute** | no fast loop, no log storm |
| D4 group ask | **first phone that answers wins**, the rest can still add parts later | 324's top-up already does this |

Not built, as agreed: the other nine things in `TODO_MASTER_2026-11-18.md` (326 is next: the answering phone gets a say).
