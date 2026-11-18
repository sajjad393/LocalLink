# 326 — the answering phone gets a say (`3.0.120+191`)

**What the user gets:** the phone that HAS a file no longer pushes it the moment somebody asks. Its owner is asked first — **Send this file? · clip.mp4 · video · 6.0 MB** — with **Send / Wi-Fi only / No**. Nothing leaves until they answer. A chat with only text is never asked about (a few KB is not worth a tap). No server, no internet.

**All commands in one block:**

```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Path "$env:USERPROFILE\Downloads\locallink_app_326_2026-11-18.zip" -DestinationPath "C:\Users\sajjad Ahmed\Downloads\LocalLink" -Force
Select-String -Path lib\core\config\app_build.dart -Pattern "kAppBuild = "
flutter pub get
flutter test test/bundle326_test.dart
flutter test test/bundle325_test.dart
flutter test test/bundle223_logs_test.dart
git add -A
git commit -m "326: 3.0.120+191 - the answering phone gets a say (consent before a file goes out)"
git push origin main
git log --oneline -1
```

Expected, in order: `kAppBuild = 191` → `All tests passed!` (14) → `All tests passed!` (19) → `All tests passed!` (7) → commit → `main -> main` → `326` on top.
If any test says **failed**, stop before `git add -A` and paste it here.

---

## What is in it (7 changed, 2 new)

| File | What it does |
|---|---|
| **new** `lib/features/admin/data/actions/consent_326.dart` | the question, the three answers, this phone's store, the 5 MB "not worth a tap" line, "Wi-Fi only" waiting |
| **new** `lib/features/admin/presentation/widgets/consent_326_dialog.dart` | the card: file name · kind · size · **Send / Wi-Fi only / No** |
| `chat_answer_builder.dart` | `beforeFirstSlice` — asked once, with the **real** size (`bytes.length`), before the first slice is sealed |
| `admin_action_doers.dart` | the gate: `No` → `refused:owner_said_no_326` (the other side greys out) · not answered yet → **rethrow = tried again later**, never thrown away |
| `local_link_app.dart` | shows the card, one at a time, over the app; nothing is decided for the owner |
| `l10n` en + ur (+ gen) | "Send this file?", "Send", "Wi-Fi only", "No" |
| `app_build.dart`, `pubspec.yaml`, `bundle223_logs_test.dart`, `bundle325_test.dart` | `3.0.120` / `191` |

## Verified here

| Check | Result |
|---|---|
| `bundle326_test.dart` | **14 passed** — small files skip the card · asked once, no nagging · Send / No / Wi-Fi-only · decisions survive a restart · broken store asks again · the card's three buttons return the right answer · the gate sits before the first slice · no `http`/`Uri` anywhere in it |
| `bundle325_test.dart` | **19 passed** (325 not broken) |
| `bundle223_logs_test.dart` | **7 passed** (pins at `120/191`) |
| Compile probe of the new files | ✅ (consent, dialog, doers, builder) |
| Patch applies clean on your `98b440b` | ✅ checked on a fresh clone |

**Not run here:** full `flutter analyze` and the big widget suites — this box has 1.9 GB RAM and the analyzer/compiler gets killed. Same caveat as 325; CI is the real check.

## The four decisions, as built

| | Built |
|---|---|
| D1 | A chat with no files is **never** asked about (under 5 MB → straight through) |
| D2 | **Wi-Fi only** waits off Wi-Fi, goes on Wi-Fi, expires never |
| D3 | **No** is final for that request, the asking card greys as "said no", the ask stays until Stop |
| D4 | The numbers are the **real** ones (read from the file before it is sliced) |

**Note:** the CI annotation rider is **not** in this build — your pushed `325` already took `119+190` and this build carries the feature. If the red is still there after 326, I'll add the annotation in 327 (or as a 3-line commit if you prefer it sooner).
