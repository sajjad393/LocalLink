# APPLY app 3.0.92+163 (TODO 291: phones send their lock key by themselves + maps keep people and lines apart)

Zip: `locallink_app_3.0.92_2026-11-14.zip`, on top of GitHub `452908d` (3.0.91+162).
Deploy the backend zip `locallink_backend_291_2026-11-14.zip` first (it also carries backend 290).

## What changes
- A (lock key): every time the phone reaches the server (start, sign-in, account switch, server back)
  it sends its lock key by itself, silently (`PUT /api/v1/device-key`). No pop-up, no setting.
  - 200 = done until the app restarts.
  - 409 (the server already has another key for this phone) = logged once, left alone. No automatic
    key change (a stolen login must not be able to swap the key).
  - No answer / error = tried again at the next connect, at most once in 10 minutes.
  This fixes: web "Request from phones" 409 "no keys yet", admin block / unblock cards that ended with
  0 phones, and key-change confirm. Why it broke: since `38cc872` (14 Oct) the old message sync,
  which also sent the key every 10 min, was replaced, and the key upload went with it.
- D (app maps: admin card, full-screen Link paths, Chats "My links" card): nobody sits on top of
  somebody else, me or the server; a line that would run under a third person's photo bows the other
  way / less; two lines on top of each other: the second moves. Free lines keep the 217 bow
  (0.60 full / 0.36 small card / 0.25 phone-to-phone). Colours, dashes and motion unchanged.
  - Room per person: an ellipse 2r+40 wide x 2r+26 high (r = photo radius, 24 on the full map), not
    the TODO's 2r+18: the name pill under the photo needs it. Small cards (r 14): 2r+22 x 2r+14.
  - A crowded small card (e.g. 12 people on the 104 px card): names may come closer, the room shrinks
    step by step, but photos never touch (always at least photo + 4 px).
  - Same people + same size = same map every frame (cached), so nothing jumps. Taps on the full map
    use the same spots.

## Files
`lib/core/services/identity_key_upload_291.dart` (new), `lib/core/services/locallink_api.dart`
(`putIdentityKey291`), `lib/app/app_dependencies.dart` (wiring),
`lib/features/admin/presentation/widgets/link_apart_291.dart` (new),
`lib/features/admin/presentation/widgets/link_paths_map.dart`, version files.
Tests: new `test/identity_key_291_test.dart`, `test/link_apart_291_test.dart`.

## Tests (here)
- `flutter analyze`: 0 errors, 0 warnings, nothing new in the changed files.
- `test/identity_key_291_test.dart`: 11/11. `test/link_apart_291_test.dart`: 18/18 (3 / 6 / 12 server
  phones + mixed tags at 320 dp and 411 dp full screen, small card at 320 dp, line routing, taps).
  With the keep-apart switched off 12 of them FAIL (even 3 phones overlapped before).
- Full suite (294 files, 10 chunks of 30, one job at a time): 2859 tests, all chunks "All tests passed", EXIT=0.
- Old tests changed (listed in the TODO only): `link_paths_zoom_222_test.dart:99` new sha256
  (`f3e46e29...18f6`, was `462d447f...50a4`), version lines in `bundle223_logs_test` / `nearby_190_test`.
  Nothing removed.
- Kotlin not touched. Release APK: CI builds it.

## Phone check
1. Install 3.0.92 on each phone, open it once with the server on.
2. Web: "Request from phones" for a chat -> no 409 any more.
3. Maps (web + app): no phone on top of another, no line under a photo.

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_3.0.92_2026-11-14.zip" .
git add -A
git add -f docs/history/TODO_291.md docs/history/APPLY_app_3.0.92.md
git commit -m "v3 3.0.92 bundle 291: phone sends its lock key to the server by itself on every connect (fixes web chat request 409 and admin cards skipping phones), maps keep people apart and move lines off other photos"
git push
```
