# APPLY 175 - background service (3.0.6+77)

Apply 173 and 174 first (see APPLY_174.md). Then:

```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes175_2026-11-01.zip" .
git add -A
git add -f APPLY_175.md
git reset -q -- "%SystemDrive%" android/local.properties
git commit -m "v3 175: messages and notifications keep working after the app is closed (no-screen engine after swipe / Back / kill), events kept while closed, Wi-Fi watcher, 15-min health check, safe restarts, mic kept during voice calls, quiet notification with Open, STATUS card - 3.0.6+77"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter build apk --release
```

## What changed (simple)
1. The service never crashes when Android refuses a restart. It stops and tries again in about 1 minute.
2. Messages that arrive while the app is closed are kept (up to 500, for 10 minutes). Nothing is thrown away.
3. After a swipe, Back exit or a kill, the "no screen" part of the app starts by itself. It shows message notifications.
4. A Wi-Fi watcher reacts in about 2 seconds when Wi-Fi comes back. Wi-Fi without internet still counts as Wi-Fi.
5. A health check runs every 15 minutes. If LocalLink was stopped, it starts it again, or shows "Tap to reconnect".
6. After an app update the service comes back by itself. After a reboot it starts only when "Keep running" is on (it stays locked ON).
7. During a voice call the phone knows we use the mic, so the other person keeps hearing you after you press Home.
8. The notification is quiet: "LocalLink is running" with an Open button. It sits at the bottom, with no top-bar icon and no sound.
9. Closing the screen never stops the service. Only Log out does.
10. A STATUS card on Keep LocalLink running: green = running, red = stopped + Start.

## Phone tests
Do each one separately. Use 2 phones (A = test phone, B = sender) on the same Wi-Fi.
Log: `adb logcat -s LocalLinkBoot flutter`

| # | Do this on A | Then B sends a message | Pass |
|---|---|---|---|
| 1 | Press Home | yes | Notification on A |
| 2 | Swipe LocalLink away from Recents | yes | Notification on A within ~10 s. Log: `TASK_REMOVED`, `BG_ENGINE_START reason=task_removed` or `app_closed` |
| 3 | Press Back until the app closes | yes | Notification. Log: `BG_ENGINE_START reason=app_closed` |
| 4 | Reboot A (do not open the app) | yes | Notification. Log: `BOOT_START_OK`, `BOOT_ENGINE_START` |
| 5 | Install the new APK over the old one (do not open it) | - | Log: `UPDATE_START_OK`; "Tap to reconnect" notice shows |
| 6 | Turn Wi-Fi off for 20 s, then on | yes | Delivered within ~10 s of Wi-Fi coming back. Log: `NET_CHANGE wifi=true ... wifi_up=true` |
| 7 | Voice call A-B. On A press Home for 30 s and keep talking | - | B still hears A. Log: `CALL_FGS_MIC on ok=true`, at the end `CALL_FGS_MIC off` |
| 8 | Open Settings > Keep LocalLink running | - | Green "Running now" card |
| 9 | Settings > Apps > LocalLink > Force stop, then open Keep LocalLink running | - | Red "Stopped by your phone"; Start turns it green |
| 10 | Pull down the notifications | - | "LocalLink is running" is small, at the bottom, with Open; Open opens the app |
| 11 | Leave A locked for 1 hour | - | Battery use of LocalLink is 3% or less |

**Force Stop note:** after a Force Stop nothing can come back until the app is opened. That is an Android rule (test 9 shows the red card).
