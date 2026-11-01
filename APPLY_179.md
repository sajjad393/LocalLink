# APPLY 179 - shorter voice delay, one Accept, call alerts (3.0.10+81)

Your PC must be at the latest GitHub version (178 + your cleanup commit). Then:

```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes179_2026-11-01.zip" .
git add -A
git add -f APPLY_179.md
git reset -q -- android/local.properties
git commit -m "v3 179: much shorter voice delay (catch-up instead of growing delay), notification Accept answers once even on slow phones, call notification checks with a STATUS warning when blocked - 3.0.10+81"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter pub get
flutter build apk --release
```

Install over the old LinkUp. No need to uninstall this time.

## What changed (simple)
1. **Voice delay** (Wi-Fi and Nearby): sound no longer waits in 4 long lines.
   - The mic never waits for the network.
   - Each line is short: mic about 80 ms, sending at most 60 ms, receiving 60-120 ms, speaker about 80 ms.
   - If a line grows, the oldest sound is skipped, so the delay comes back down instead of staying long.
2. **Files wait during a voice call**: a photo/video that is sending shows a pause sign and **"Sends after the call"**. It continues by itself when the call ends. Messages still go at once.
   - Safety: after 8 minutes it continues anyway, so the other phone does not forget the half-sent file.
3. **One Accept** (ZTE): Android remembers your notification Accept for 60 seconds. Even if the screen is rebuilt, or the call reaches the app late, it is answered automatically. It never answers a different call. The wait went from 10 s to 60 s.
4. **Realme fix**: when "Allow full-screen notifications" is OFF, LinkUp now posts a normal pop-up with Accept / Reject instead of a full-screen one. (Some Realme/Oppo phones dropped the whole notification before.)
5. **STATUS card** (Keep LinkUp running), new last line:
   - green "Call alerts on";
   - red "Call alerts off - tap to turn on" (card turns red);
   - orange "Lock-screen calls off - turn on" (Android 14+).
   Tapping opens the right Android page.
6. If call alerts are off, the phone **still rings** (as you chose).
7. Oppo / Realme / OnePlus phone tips: new step "Notifications: allow LinkUp, turn on Banners, Lock screen and Full-screen".

## Phone checks
| # | Do this | Pass |
|---|---|---|
| 1 | Voice call, same Wi-Fi, count "1, 2, 3" | Other phone hears it almost at once (under ~0.3 s) |
| 2 | Same on Nearby | Same |
| 3 | Walk away until the sound breaks, come back | Delay comes back to short |
| 4 | 10-minute call | Delay stays short |
| 5 | Send a video, then start a voice call | Video shows pause + "Sends after the call"; voice stays clear; video continues after hang-up |
| 6 | ZTE closed, B calls, tap Accept | App opens, call connected. No second Accept |
| 7 | Same, phone locked | Same |
| 8 | Realme, full-screen OFF, app in background, B calls | Pop-up with Accept / Reject shows |
| 9 | Realme: Keep LinkUp running screen | Orange "Lock-screen calls off - turn on"; tap opens the full-screen switch |
| 10 | Turn the "LinkUp incoming calls" category off | STATUS red "Call alerts off"; calls still ring |

Logs: `adb logcat -s LocalLinkCall LOCAL_LINK_TRANSPORT flutter`
- `CALL_AUDIO_DELAY rx_queue_ms=.. speaker_ms=.. tx_queue_ms=.. skipped=..` (every 10 s in a call)
- `CALL_ACCEPT_SAVED`, `CALL_ACCEPT_RESTORED`, `CALL_ACCEPT_APPLIED source=handover|ring`, `CALL_ACCEPT_EXPIRED`
- `CALL_NOTIFY_MODE mode=full_screen|popup`, `CALL_NOTIFY_POSTED shown=yes|no`, `CALL_NOTIFY_BLOCKED reason=..`, `CALL_NOTIFY_FAILED error=..`
- `FILE_PAUSED_FOR_CALL`, `FILE_RESUMED_AFTER_CALL`

## Honest notes
- On very bad Wi-Fi you may hear small gaps instead of late sound. Normal phone calls do the same.
- Only files sent FROM the phone on the call wait. A file a third person sends TO you during a call still comes in.
- Video call code was not changed. Files also wait during a video call, because it uses the same voice line.
- If the Realme still shows nothing, send me the `CALL_NOTIFY_POSTED shown=..` line. It tells us whether Realme hides it.
- Not tested on a real phone yet. Only the compile check and the automatic tests have run.
