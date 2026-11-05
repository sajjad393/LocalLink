# APPLY 213: admin stops old app versions (offline + web)

App 3.0.54+125 · DB v34 (no change) · no new permissions.
Backend: separate zip `locallink_backend_213_2026-11-05.zip` (migration v56). **Deploy the backend first.**
**Push order: 211 → 212 → 213** (app + backend each time, backend first). 213 is built on top of 212.

## What changed
**A. Every phone says its build**
- New `lib/core/config/app_build.dart`: `kAppBuild = 125`, `kAppVersion = '3.0.54'` (a test checks they match `pubspec.yaml`). Bump them with the pubspec from now on.
- Every server call sends `X-LinkUp-Build` (normal calls, login/profile calls, file upload/download, admin block sync, web socket).
- Nearby phones tell each other their build on link and every 60 s.

**B. Admin panel: "App version" card** (under "Block users")
- This phone's version, versions seen nearby (with phone counts), and **Minimum version**.
- Minimum version page:
  - Pick this phone's version or a lower one seen nearby.
  - Older apps: **Warn only** / **Stop now** / **Stop after N days** (default 3, use - / +).
  - **Also stop very old apps** switch.
  - "Affects N phones seen nearby".
  - Save rule → pop-up "Stop versions below 3.0.54?" → **Save for everyone**. There is also a Remove rule button.
- Works with no internet: it uses the 212 admin offline key (owner only), and the rule spreads phone to phone over local Wi-Fi / Wi-Fi Direct / mesh. It syncs with the server when online. Newest rule wins.
- Web panel: new **App version** page (owner): set or remove the rule, plus a phones-by-build table.

**C. The old phone**
- Warning: yellow banner "Update needed in 3 days. After that this version can only read chats." + **Update** + × (hidden until tomorrow).
- Stopped: red banner "This version is stopped by admin. You can read old chats. Update to send and call." + **Update** (no ×).
  - Chat box replaced by "Old version. Update to send." + **Update**.
  - No sending or calls (1:1, groups, calls).
  - One notification "This LinkUp version is stopped by admin" (also with the app closed).
- Banners show on Chats, Calls and People (same places as the 212 block banner).
- The server answers 426 to a stopped build. The phone then goes read-only at once, until the server's rule says it is fine.

**D. Other phones**
- Messages from a stopped phone are dropped at the first phone (they go in the same blocked list as 212, log `RELAY BLOCK_DROP`). It still relays other people's sealed messages.
- In their chat: "Ali has an old LinkUp. They need to update."
- **Very old apps** (switch on): the server refuses calls with no build header. Updated phones treat a linked phone that sends no build within 3 min as very old (relay only). Two old phones together offline still work; nothing can stop that.
- An admin phone never stops itself with a web rule above its own version (log `VERSION_RULE_ABOVE_ADMIN`).

**E. Update from a nearby phone** (210 share)
- Update → "Get the new LinkUp": nearby phones with a newer version, each with **Ask**.
- Sumaira's phone shows "Ali wants the new LinkUp" with Share / Not now. At battery ≤10% the button is "Share anyway".
- Share, both on the same Wi-Fi / hotspot / Wi-Fi Direct group:
  - Her phone serves the 210 download page.
  - Ali's phone opens it in the browser by itself. Chrome may say "insecure download": tap Download anyway.
  - A card "Sumaira is sharing LinkUp 3.0.54" with **Open download** stays.
- Linked by mesh only (no shared Wi-Fi): her phone opens the 210 QR screen. Ali sees the card "Only linked by mesh (no direct Wi-Fi)?" and scans it.
- Not now → "Sumaira said not now". No answer in 1 min → "No answer". You can ask the same phone again after 2 min.

**F. Testers: "Pretend old build"** switch, under Nearby tests in the Admin panel. The phone then says build 124, so you can test with two phones on 3.0.54.

## Android
- `mesh/MeshBlockPolicy.kt`: new one-step frames `version_digest`, `version_rule`, `app_update_request`, `app_update_answer`, `app_update_offer` (they go straight to the linked phone, also to a blocked or stopped phone).
- `MediaStorageNative.openUri`: an http link with no type opens in the browser.
- New Kotlin test `Version213Test.kt`.

## Where things are kept (no DB change, settings table)
`version_rule_v1`, `peer_builds_v1`, `pretend_old_build`, `version_warn_hidden_until`, `version_stop_noted`.

## Different from the TODO
- DB stays v34 (settings keys, no new table). A v35+ bump breaks 3 old tests.
- The rule uses its own one-step frames, not extra fields in the 212 block frames. This leaves the 212 code alone.
- The map has no "old" tag yet (I skipped it; say if you want it).

## Old tests
- `test/nearby_190_test.dart`: version expectation → 3.0.54+125 (as every bundle).
- No other old test changed.

## Checks here
- `flutter test`: see the numbers in the reply. `flutter analyze`: 166 (same as before).
- Kotlin compile check clean. Go: `go vet` clean, `go test ./...` ok.
- New tests: `bundle213a..f_test.dart` (+ `support/b213_fakes.dart`).

## Phone tests
- [ ] 213-1 Both phones on 3.0.54. Admin sets minimum 3.0.54 → nothing changes.
- [ ] 213-2 ZTE: Admin panel > "Pretend old build" ON. Admin (Realme) sets "Stop after 1 day" offline → ZTE yellow banner within about 1 min.
- [ ] 213-3 "Stop now" → ZTE read-only, red banner, can't send or call, can read.
- [ ] 213-4 ZTE taps Update → sees Realme → Ask → Realme dialog → Share → the download opens on ZTE (same Wi-Fi).
- [ ] 213-5 Same over Wi-Fi Direct; then mesh only → QR way.
- [ ] 213-6 Very old switch ON with a 3.0.53 phone: the server refuses it (426); 3.0.54 phones drop its messages after 3 min (`RELAY BLOCK_DROP`), and it still relays.
- [ ] 213-7 The web panel sets / removes the rule → phones get it online and pass it on offline.
- [ ] 213-8 App closed on ZTE: the stop time passes → notification, and read-only on open.
- [ ] 213-9 Turn "Pretend old build" OFF → ZTE works again (it may take up to 1 min).
- [ ] 213-10 Logs from both phones: `VERSION_*`, `APP_UPDATE_*`.

## PowerShell (app)
```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_213_2026-11-05.zip" .
git add -A
git add -f APPLY_213.md TODO_213.md
git reset -q -- android/local.properties
git commit -m "v3 3.0.54+125 bundle 213: admin minimum app version (warn / stop now / stop after days, offline spread + web, server 426), old phone read only with Update banner, update from a nearby phone (Ask, Share, download opens), very old apps switch, pretend old build for testers"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean; flutter pub get; flutter test; flutter build apk --release
```
