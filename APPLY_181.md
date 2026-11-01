# APPLY 181 - voice notes like WhatsApp (3.0.12+83)

Your PC must be at the latest GitHub version (180). Then:

```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes181_2026-11-01.zip" .
git add -A
git add -f APPLY_181.md
git reset -q -- android/local.properties
git commit -m "v3 181: voice notes like WhatsApp - hold to record, slide left to cancel, slide up to lock, pause and listen before sending, wave that follows your voice - 3.0.12+83"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter pub get
flutter build apk --release
```

Install over the old LinkUp. No need to uninstall.

## How to use (same as the approved mock)
1. **Hold** the mic. After a moment it vibrates and the big blue mic shows. Talk.
2. **Let go** = sent.
3. **Slide left** = cancelled, nothing sent.
4. **Slide up** to the lock = locked. Let go and keep talking. Buttons: **Delete - Pause - Send**.
5. **Pause** = you can **Play** it first. Then **red mic = continue**, or **Send**, or **Delete**.
6. A **quick tap** on the mic shows "Hold to record, release to send".
7. Under 1 second = not sent.

## What changed (simple)
1. New recording bar: holding, locked and paused screens, exactly like `mocks/bundle181_full_mock.svg`. Picture check: `mocks/bundle181_compare.png` (mock left, real app right).
2. The wave follows your voice: soft talking makes clear bars, silence stays low, and it fills the whole bar.
3. Pause and continue make ONE voice note (the parts are joined on the phone).
4. Home key, screen off, a call screen, or playing a video while recording = **pause**, nothing lost.
5. Leaving the chat while recording: kept as a paused draft for that chat (until the app is fully closed).
6. 15 minutes = pauses by itself.
7. **Old phone fix:** recording now also works on Android 7-11 (it could crash before).
8. The microphone question now talks about voice notes, not calls.
9. The "Message" hint in the empty text box shows again (it was missing; it is in the mock).

## Phone checks (Realme and ZTE)
| # | Do this | Pass |
|---|---|---|
| 1 | Tap the mic quickly | Hint shows, nothing records |
| 2 | Hold, say "1, 2, 3", let go | Sent; plays on the other phone |
| 3 | Hold less than 1 s, let go | Nothing sent |
| 4 | Hold, slide left | Cancelled |
| 5 | Hold, slide up, let go, talk, Send | Sent |
| 6 | Lock, Pause, Play, Continue, Send | ONE voice note with both parts, plays fine |
| 7 | Talk softly while locked | Bars clearly move; silence stays low |
| 8 | Recording, press Home, come back | Paused, nothing lost |
| 9 | Recording, someone calls you | Paused; after the call you can send it |
| 10 | Recording, go back to the chats list, open the chat again | Paused bar is still there |
| 11 | Old phone (Android 11 or lower), if you have one | Recording works |

If something is wrong: tap "Chats" 5 times (bundle 180) and send me the log file. Voice lines: `VOICE_JOIN_FAILED`.

## Honest notes
- Joining the parts (pause / continue) is the hardest part. The automatic tests check the timing; the real sound needs your check (#6).
- You may hear a tiny gap (about 0.1 s) where you paused.
- Vibration follows the phone's touch-vibration setting.
- The draft survives leaving the chat, but not closing the app completely.
- Voice note bubbles, calls, video, chats list, status badge and groups were not changed.
- Not tested on a real phone yet. Only the compile check and the automatic tests have run.
