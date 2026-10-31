# Bundle 174 - calls + chat video + transfer circle (v3.0.5+76)

Apply on top of **173**. Your GitHub is still at 172 (d8d002f), so do 173 first (step 1 below).
Zip: `locallink_app_fixes174_2026-11-01.zip`.

## What changed
1. **Missed calls**: a call that rang and nobody answered shows a red **"Missed"** on its own row
   in Calls (never grouped).
2. **Incoming voice call screen** (same as the approved mock):
   - photo with a soft ring, name, "Incoming call";
   - big green button that bounces, 3 green arrows above it, "Swipe up to answer";
   - **swipe up = answer**. A tap does nothing. Small red **Decline** bottom-left.
   - Video calls, the notification and the lock screen are NOT changed.
3. **Floating video player**:
   - starts **top-right** under the name bar; drag to move it;
   - **25% bigger** (240 x 135, tall 135 x 240);
   - **pinch with 2 fingers** = bigger / smaller (smallest = old size, biggest = about 70% of
     the screen width). The size is remembered.
   - Tap the video = show / hide its buttons. The small corner button (top-left) opens full screen.
   - **3b**: a video that finishes in its bubble goes back to its **preview + play + length**.
4. **Video inside the bubble**: real time and length (e.g. 0:12 / 1:30), the bar moves, only the
   middle pause button (the small one at the bottom is gone).
5. **All chat video players** (bubble, floating, full screen): buttons hide 3 s after it starts
   playing; tap shows, tap again hides; touching a button starts the 3 s again; paused or
   finished = buttons stay.
6. **Sending / receiving photo or video**: the blue circle shows **only "35%"**.
   - Tap the circle -> an **X** shows (back to the percent after 3 s).
   - Tap X -> **"Cancel this video?"** Yes / No.
   - Sender after cancel: **"Not sent - tap to retry"** (tap = Resend / Delete as before).
   - Receiver after cancel: **"Tap to download"** (asks the sender's phone to send it again;
     both phones must be connected).
7. **Message times** always use your phone's time (also while sending / receiving), and the
   "Today" line too.

**Not changed:** video calls (paused), call sound / speaker / earpiece, status icon, Nearby, search.

## Step 1 - apply 173 first (only if you did not push 173 yet)
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Path "$HOME\Downloads\locallink_app_fixes173_2026-10-31.zip" -DestinationPath . -Force
git rm -q --ignore-unmatch lib/features/connectivity/presentation/screens/wifi_direct_screen.dart
git rm -q --ignore-unmatch lib/features/home/presentation/screens/nearby_experiments_screen.dart
git rm -q --ignore-unmatch lib/features/directory/presentation/nearby_devices_screen.dart
git rm -q --ignore-unmatch assets/animations/radar_pulse.json
git add -A
git commit -m "v3 173: you are hidden from your own search, search cards like Nearby with Add, Nearby tests moved to Admin panel, strict mode in Privacy, old code removed - 3.0.4+75"
```

## Step 2 - apply 174
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Path "$HOME\Downloads\locallink_app_fixes174_2026-11-01.zip" -DestinationPath . -Force
git add -A
git commit -m "v3 174: missed calls in red on their own row, swipe-up incoming voice call screen, bigger floating video with pinch, video players with real time and auto-hiding buttons, percent-only transfer circle with cancel, phone-local message times - 3.0.5+76"
git push
flutter clean
flutter pub get
flutter build apk --release
```

## Phone test
1. Let a call ring without answering -> red "Missed" on its own row.
2. Incoming voice call -> green button bounces; tap does nothing; swipe up answers; red declines.
3. Play a chat video, scroll away -> floating player top-right, bigger; drag, pinch, size kept
   for the next video.
4. Let a video finish in its bubble -> preview + play button again.
5. Play in the bubble -> real time, moving bar, one pause button; buttons hide after 3 s.
6. Send a big video -> only "35%"; tap -> X; tap X -> "Cancel this video?" -> Yes ->
   "Not sent - tap to retry" (receiver: "Tap to download").
7. Times while sending / receiving match the phone clock.

Logs: `adb logcat -s flutter | findstr "MEDIA_ CALL_"`
(MEDIA_CANCEL_SEND, MEDIA_CANCEL_RECEIVE, MEDIA_RESEND_ASK, MEDIA_REPUSH show the cancel / resend steps.)
