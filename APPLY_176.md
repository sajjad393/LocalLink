# APPLY 176 - incoming calls ring while LocalLink is closed (3.0.7+78)

Apply 173, 174 and 175 first. Then:

```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes176_2026-11-01.zip" .
git add -A
git add -f APPLY_176.md
git reset -q -- "%SystemDrive%" android/local.properties
git commit -m "v3 176: incoming calls ring while the app is closed (call notification + ringtone from the no-screen engine), Accept opens the app and answers, Reject works while closed, ringing call handed over when the app opens - 3.0.7+78"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter build apk --release
```

## What changed (simple)
1. When LocalLink is closed (swiped away, Back, killed), a voice call now RINGS: the normal call notification (full screen on the lock screen) + the ringtone.
2. Accept opens the app and the call connects.
3. Tapping the notification opens the app on the normal incoming call screen (swipe up to answer).
4. Reject works with the app closed. The caller hears "declined" and it goes in the call list.
5. If the caller hangs up, or nobody answers in 60 s, the ringing stops and it shows as a missed call.
6. No new screens. Video calls not touched. Outgoing calls still need the open app.

## Phone tests
2 phones on the same Wi-Fi: A = closed app, B = caller.
Log on A: `adb logcat -s LocalLinkCall LocalLinkBoot flutter`

| # | Do this on A first | Then | Pass |
|---|---|---|---|
| 1 | Swipe LocalLink away from Recents, wait 15 s | B calls A | A rings + call notification. Log: `BG_CALL_RINGING` |
| 2 | Same as 1 | A taps Accept | App opens, call connects, both hear. Log: `CALL_HANDOVER_TAKE`, `CALL_HANDOVER_TAKEN` |
| 3 | Same as 1 | A taps Reject | Ringing stops; B sees declined. Log: `CALL_REJECT_BG_ENGINE` |
| 4 | Same as 1 | B hangs up before A answers | A stops ringing; missed call in red on A |
| 5 | Same as 1 | Nobody answers | After 60 s ringing stops; missed call |
| 6 | Lock A's screen after step 1 | B calls A | Full-screen incoming call on the lock screen |
| 7 | Same as 1 | A taps the notification (not Accept) | App opens on the incoming call screen; swipe up answers |
| 8 | Press Back until the app closes | B calls A | Same as test 1 |
| 9 | App open on A (normal) | B calls A | Works exactly as before |

## Android limits (honest)
- **Force Stop:** nothing rings until the app is opened again. Android rule.
- **Some phones (Xiaomi, Oppo, Vivo, ZTE...)** kill closed apps. Turn on "Keep running" / battery "No restrictions" for LocalLink.
- **Android 14+:** the full-screen call on the lock screen needs "Full screen notifications" allowed for LocalLink (Settings > Apps > LocalLink > Notifications). Without it you still get the ringing notification at the top.
- A call that rang for more than 60 s before the app opened is not handed over.
- Not tested on real phones yet: only compile + automatic tests here.
