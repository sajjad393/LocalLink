# APPLY 178 - LocalLink becomes LinkUp (3.0.9+80)

Apply 173, 174, 175, 176 and 177 first. Then:

```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes178_2026-11-01.zip" .
git add -A
git add -f APPLY_178.md
git reset -q -- "%SystemDrive%" android/local.properties
git commit -m "v3 178: app renamed LinkUp everywhere people see it, new LinkUp logo (bubble + rings + up arrow), new app ID com.sajjad.linkup - 3.0.9+80"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter pub get
flutter build apk --release
```

## Install on each phone (IMPORTANT)
1. **Uninstall LocalLink** first (Settings > Apps > LocalLink > Uninstall, or `adb uninstall com.sajjad.locallink`).
2. Install the new APK (`adb install build\app\outputs\flutter-apk\app-release.apk`).
3. Open **LinkUp**, sign in again, allow the permissions again (Nearby, mic, camera, notifications, battery "No restrictions", Keep running, Lock in Recents).

LinkUp is a NEW app for Android, so chats, contacts and keys from LocalLink are not moved (fresh start, as you chose).

## What changed (simple)
1. App name under the icon: **LinkUp**.
2. New logo **A** (bubble + rings + up arrow): app icon (all sizes, round, Android 8+ icon), start screen, Android 12+ splash, small notification icon, logo on the Welcome screen.
3. All words people see now say LinkUp: screens, errors, "LinkUp user", Keep running screen, phone brand tips, QR share text, notifications, Android notification categories ("LinkUp messages", "LinkUp incoming calls", "LinkUp system"), permission texts.
4. App ID is now `com.sajjad.linkup`.
5. NOT changed (on purpose): code names, saved storage / key names, connection names, log names. So old LocalLink phones and LinkUp phones still talk to each other, and your adb log commands stay the same.

## Phone checks
| # | Do this | Pass |
|---|---|---|
| 1 | Install | Logo A with the name **LinkUp** on the home screen |
| 2 | Open it | Start screen + Welcome show the new logo and "LinkUp" |
| 3 | Sign in, get a message | Notification says LinkUp; the small white icon has the arrow |
| 4 | Android Settings > Apps | App is "LinkUp"; notification categories say LinkUp |
| 5 | Grant permissions | Texts say LinkUp |
| 6 | Look through screens (Settings, Keep running, Nearby, QR, Calls) | No "LocalLink" anywhere |
| 7 | A LinkUp phone + an old LocalLink phone (optional) | They still find each other and chat |
| 8 | `adb logcat -s LocalLinkBoot LocalLinkCall NEARBY flutter` | Still works (log names kept) |

adb commands now use the new ID, for example:
`adb shell am force-stop com.sajjad.linkup`
`adb shell dumpsys activity services com.sajjad.linkup`
`adb shell am set-standby-bucket com.sajjad.linkup restricted`

## Honest notes
- Your **server** may still call itself "LocalLink Server" - that name comes from the server settings.
- The Wi-Fi Direct group name in Android Wi-Fi settings stays `DIRECT-LL-...` (hidden name, kept so old and new phones connect).
- GitHub repo name and your PC folder `Downloads\LocalLink` stay. Rename them only if you want; not needed.
- Some launchers cache icons: if the old icon shows, restart the phone.
- Not tested on a real phone yet: compile + automatic tests only.
