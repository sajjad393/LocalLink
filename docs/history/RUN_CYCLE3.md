# How to run the phone test (Cycle 3)

## 1. Start the server (PC, window 1)
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\localLinkBackend"
$env:LOCALLINK_ENV="development"
$env:LOCALLINK_REQUIRE_TLS="false"
$env:LOCALLINK_TLS_AUTO="false"
go run ./cmd/server
```
- Leave this window open. It should say: `LocalLink server listening without TLS on :8080 (development mode)`.
- If you normally set a pairing code (`$env:LOCALLINK_PAIRING_CODE=...`), set it the same way before `go run`. Your accounts stay (same `data\locallink.db`).
- Check from the phone's browser: `http://192.168.18.27:8080/health` should show `"ok":true`.

## 2. Build the APK (PC, window 2)
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
flutter build apk --release --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true
```
- The APK is `build\app\outputs\flutter-apk\app-release.apk`.
- Without `--dart-define=...` the app can't reach the server.

## 3. Install on 2+ phones (over the old app, don't uninstall)
- With USB: `adb install -r build\app\outputs\flutter-apk\app-release.apk`
- Without USB: send the APK to the phone (USB copy, Drive or WhatsApp as a document), tap it, then Update.
- If the phone says "App not installed" (different signing key), tell me. Don't uninstall, or you lose the chats.

## 4. Test, on each phone, and note OK / NOT OK
1. Open the app: chats load, no "Plain HTTP" error, the version shows 3.0.84.
2. Add Contact: the list shows people without typing.
3. Chat both ways with the server on.
4. Turn the server off (Ctrl+C in window 1): chat both ways on the same Wi-Fi, then over Wi-Fi Direct.
5. Send a photo or a file.
6. Voice call both ways.
7. Swipe the app away (kill), open again: it reconnects and messages arrive.
8. Start the server again: everything sent offline reaches the server.

## 5. Send me
- From each phone: the log (tap **Chats 5 times**, then share the log file).
- The server window text (copy it, or a screenshot).
- Your OK / NOT OK list from step 4, with the phone names.
