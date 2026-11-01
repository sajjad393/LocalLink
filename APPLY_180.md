# APPLY 180 - tap "Chats" 5 times to share the last hour of logs (3.0.11+82)

Your PC must be at the latest GitHub version (179). Then:

```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes180_2026-11-01.zip" .
git add -A
git add -f APPLY_180.md
git reset -q -- android/local.properties
git commit -m "v3 180: tap Chats 5 times to share the last hour of LinkUp logs as one neat text file (app + Android side, summary at top) - 3.0.11+82"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter pub get
flutter build apk --release
```

Install over the old LinkUp. No need to uninstall.

## How to use
1. Open LinkUp. On the home screen, tap the word **Chats** at the top **5 times fast** (within 3 seconds).
2. A small box shows **"Preparing logs... Last 1 hour"** (Cancel stops it).
3. The Android share screen opens with `LinkUp-logs-<phone>-<date>.txt`. Send it to WhatsApp, email, Drive...
4. Open the file. Search **`!!`** to jump to errors, **`!`** for warnings.

## What changed (simple)
1. **App side:** every LinkUp app log line is also saved to a small private file, with full details. Nothing extra goes to logcat.
2. **Android side:** LinkUp's own Android log lines (calls, Nearby, transport, boot, crashes) are saved in the same folder. It runs inside the app and the existing Keep running service. No new service.
3. **Only the last 1 hour is kept** (one file per 10 minutes, max 10 MB). Older files delete themselves. It keeps saving while the app is closed, as long as the Keep running service is alive.
4. **Log out** (account reset) deletes all saved logs. A soft sign-out keeps them.
5. The file: phone, Android, LinkUp version, from - to, summary (errors, warnings, calls, files, Nearby), then one line per event: `TIME  LEVEL  AREA  EVENT  DETAILS`. Long details wrap onto the next line, never cut.
6. Nothing else on the screen changed. "Chats" looks the same.

## Phone checks
| # | Do this | Pass |
|---|---|---|
| 1 | Tap "Chats" 4 times, or slowly | Nothing happens |
| 2 | Tap "Chats" 5 times fast | "Preparing logs..." then the share screen |
| 3 | Tap Cancel in the box | No share screen |
| 4 | Open the shared file on a PC (Notepad) | Summary at top; columns line up; times in order |
| 5 | Make a voice call, then share | CALLS lines (CALL_...) are in the file |
| 6 | Close LinkUp (Keep running on), wait 10 min, open, share | Lines from while it was closed are there |
| 7 | Use LinkUp normally for a day | No slowdown, no extra battery use |
| 8 | Log out, log in, share | Old lines are gone |

## Honest notes
- Share within the hour: anything older than 1 hour is already deleted (as you chose).
- If Android kills LinkUp completely (no Keep running service), nothing can be saved during that time.
- The file can hold names, numbers and message details. Share it only with people you trust.
- Not tested on a real phone yet. Only the compile check and the automatic tests have run. Reading Android's log from inside the app works on normal phones, but some makers may limit it; if the file has no SYSTEM / Android lines, tell me.
