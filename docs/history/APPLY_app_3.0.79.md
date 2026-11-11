# APPLY app 3.0.79+150 (TODO 262)

Zip: `locallink_app_3.0.79_2026-11-11.zip`, on top of GitHub `e03e680` (3.0.78+149).
There is no backend change, so there is no backend zip. The server stays as it is, with HTTP 8080 on.

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_3.0.79_2026-11-11.zip" .
flutter pub get
flutter test
git add -A
git add -f docs/history/TODO_262.md docs/history/APPLY_app_3.0.79.md
git commit -m "v3 3.0.79+150 bundle 262: Wi-Fi Direct groups on 2.4 GHz so the 2.4-only ZTE can see and join every group, one retry without the band if a phone refuses (A), when the phone turns Wi-Fi Direct off the app stops trying and comes back within a second when it is on again, and a radio stuck busy is reset (B), the app talks to the server over HTTP only, no HTTPS and no certificate check (C), after 3 refused sign-ins the app stops calling the server every 30 s and shows Sign in again (D), the username instead of My LinkUp phone (E)"
git push
flutter build apk --release
```

## Install
- Install on ALL 4 phones over the old app. Do NOT clear data.
- The server can be on or off. It must keep HTTP on port 8080, as it is now.

## What is in it
ZTE alone after the router goes off (A):
- Every Wi-Fi Direct group is now made on 2.4 GHz.
  - On 11 Nov the C71 made its group on 5 GHz (`freq=5745`).
  - The ZTE Blade A35 has 2.4 GHz Wi-Fi only. It never saw that group, so every join timed out.
- Some phones may refuse the 2.4 GHz request. Those get one more try without it, with the log `group create retry no_band reason=..`. So no phone loses Wi-Fi Direct.
- New log: `group create grp=.. band=2.4`. The host's `WD_LINK ... freq=24xx band=2.4` line proves it.

Wi-Fi Direct switched off by the phone (B):
- New native log: `WD_P2P state=off` and `WD_P2P state=on off_s=N`.
- While it is off, there are no join, create or search tries, so there is no "busy" loop. Log (once): `NEARBY|group wait why=p2p_off`.
- When it comes back on, the old "failed / full" marks are cleared, a search starts and the phone joins at once. Log: `NEARBY|group resume why=p2p_on off_s=N`.
- If 3 joins answer "busy" within 90 s while Wi-Fi Direct says it is on, the Wi-Fi Direct channel is made again. Log: `WD_BUSY_REINIT n=3`. This is limited like before: at most 3 in 10 min.
- A missed "on" never blocks for more than 5 min. Also, the screen or background engine that starts gets the current on/off state again.
- The app still can't switch Wi-Fi Direct on (an Android rule).

HTTP only (C, your choice "Keep http not https"):
- The app talks to the server only over `http://..:8080` and `ws://..:8080/ws`.
- There is no HTTPS check, no move to wss:// and no certificate pin in use, so the Note's 9-minute `cert_refused` loop can't happen.
- Log at start: `TLS_262|mode=http_only`.
- The saved pin stays in the phone settings (nothing is deleted). Nothing changes on the server.

Signed out from the server (D):
- If the server refuses this phone's sign-in 3 times in a row (401), the log shows `SESSION_DEAD_262|n=3 first=..` once.
  - After that, server calls go out once per 10 min instead of every 30 s.
  - The Chats tab shows a yellow card: "Signed out from the server... Sign in again". It opens a password box and does the normal login of this account on this phone.
  - Nearby, Wi-Fi Direct and mesh keep working the whole time. Nothing is deleted.
- These never count: admin console keys, the login itself, and a wrong password typed in a box.
- Why the ZTE was signed out at 19:42:53: the server sent an `admin_action` event to TECNO and C71 6 s later. That happens only after something is done on the admin console, so the ZTE was most likely signed out from the admin page. This is NOT VERIFIED. The `admin_audit` query in `LOG_CHECK_2026-11-11_1957.md` shows which action it was.

Name (E):
- "My LinkUp phone" (or "My Android Phone (..)") is not shown as a person's name any more. The username is shown instead (for example `alex`). A name you typed for a contact still wins.

## What to check (your steps)
1. All phones: `TLS_262|mode=http_only` and `ws://192.168.18.27:8080/ws`. There should be no `wss://` and no `cert_refused`.
2. All 4 on the Wi-Fi, then turn the router off and don't open LinkUp:
   - The host log should show `group create grp=.. band=2.4` and `WD_LINK ... band=2.4`.
   - The ZTE should join the host's group, with no `timed_out`.
   - All 4 should be green within about 1–2 min.
3. If a phone logs `WD_P2P state=off`: the next `WD_P2P state=on` should be followed within about 1 s by `group resume why=p2p_on`, with no `group join failed reason=2` loop.
4. C71 chat list: the ZTE shows as `alex`, not "My LinkUp phone".
5. If the ZTE is signed out again: `SESSION_DEAD_262` should appear with the card. Then Sign in again → it should go green.
6. Send the logs of all 4 phones from the same time.

## Tests
- New:
  - `test/bundle262_test.dart` (15).
  - Kotlin `android/app/src/test/kotlin/com/sajjad/locallink/Band262Test.kt` (5).
- Old tests changed: only the version lines in `test/bundle223_logs_test.dart` and `test/nearby_190_test.dart` (3.0.79+150).
- Run here:
  - `flutter analyze`: no new issues.
  - Full Flutter suite: 2630 passed (11 chunks, all EXIT=0).
  - Kotlin JVM tests: OK (460).
- Compile and unit tests only: nothing here was tried on a phone.
