# APPLY 229 - size limits on nearby socket lines (audit S1) (app 3.0.68+139, app only, Kotlin only)

- **One zip for 224 + 225 + 226 + 227 + 229:** `locallink_app_224-229_2026-11-09.zip`. It replaces `locallink_app_224-227_2026-11-09.zip`.
- If you already extracted the 224-227 zip, it doesn't matter: this zip has the full files and simply overwrites them.
- **No backend, no database, no new permission, no screen change.**

## PowerShell

```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force -Path "C:\Users\sajjad Ahmed\Downloads\locallink_app_224-229_2026-11-09.zip" -DestinationPath .
flutter pub get
flutter test -j 1
git add -A
git add -f APPLY_224.md TODO_224.md APPLY_225.md TODO_225.md APPLY_226.md TODO_226.md APPLY_227.md TODO_227.md APPLY_229.md TODO_229.md
git commit -m "v3 3.0.68+139 bundles 224-227 + 229: faster Wi-Fi Direct/LAN connect and never use Realme/XShare groups (224), a call wakes Wi-Fi Direct with Waiting for <name> to connect (225), Bluetooth LE finds friends with Allow and Bluetooth off cards in Add Contact Nearby (226), no jump to Welcome while logged in and the call screen closes once (227), size limits on nearby socket lines so no phone nearby can fill the memory (229)"
git push
```

Install so the app data stays: `flutter run --release` or `adb install -r` (not `flutter install`, which uninstalls first).

## Why (short)
- A nearby phone could send one endless line, and the app kept all of it in memory until the phone ran out. The 2 GB ZTE was most at risk.
- Now:
  - a handshake line is at most 64 KB;
  - a data line over 256 KB is skipped without keeping it (it was already thrown away before, just after keeping it);
  - one line over 8 MB closes only that link;
  - at most 24 link attempts can be in their handshake at once.

## What changes for the user
- Nothing visible. Chats, calls, video and files work exactly as before.

## New log lines (only when something is wrong)
- `LINE_TOO_LONG peer=xxxxxxxx side=data max=8388608`: a phone sent one huge line; that link was closed.
- `LINE_TOO_LONG peer=? side=hs ...`: a huge handshake line; the attempt was refused.
- `HANDSHAKES_FULL transport=... max=24`: too many link attempts at once (at most once a minute).
- In normal use you should **never** see these. If you do, send me the log.

## Files
- NEW `android/app/src/main/kotlin/com/sajjad/locallink/mesh/LineLimits.kt`
- `android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt`
- `pubspec.yaml`, `lib/core/config/app_build.dart` (3.0.68+139)
- NEW `android/app/src/test/kotlin/com/sajjad/locallink/mesh/Line229Test.kt` (16 tests)
- Old tests: only the version pins in `test/bundle223_logs_test.dart` and `test/nearby_190_test.dart`.
- Results: Kotlin 447 OK; full Flutter suite 2355 passed, 0 failed.

## Phone tests (229)
Do APPLY_225 / 226 / 227 tests as planned. Then:
1. Two phones on the same router: chat + send a 20 MB video file → arrives.
2. Wi-Fi Direct (router off): voice call 1 minute → clear sound, no drop.
3. Video call over Wi-Fi Direct or LAN for 1 minute → picture moves as before (no new freezes).
4. Mesh (3 phones, A–B–C, A and C far apart): a message A → C arrives.
5. ZTE in the group: same tests 1–2 with the ZTE as one of the phones.
6. Send the logs and search for `LINE_TOO_LONG` and `HANDSHAKES_FULL`: they should **not** appear.
