# APPLY 182 - emoji on the bubble edge + "Waiting" when friend is offline (3.0.13+84)

181 is already on GitHub (`9433407`, checked: it matches the 181 zip exactly). 182 goes on top.

## Steps (PowerShell)
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes182_2026-11-01.zip" .
git add -A
git add -f APPLY_182.md
git reset -q -- android/local.properties
git commit -m "v3 182: bubbles fit their content, emoji on the bubble edge, Waiting instead of the ring when friend is offline - 3.0.13+84"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter pub get
flutter build apk --release
```

Install over the old LinkUp (no uninstall).

## What changed
1. A message with an emoji no longer gets a wide bubble. The bubble fits the photo, video or words.
2. The emoji chip ("😂 1") sits on the bottom edge of the bubble (left corner), like WhatsApp.
3. Short text ("hello") gets a small bubble, the time is on the same line.
4. Long text still stops at the same width as before.
5. Same fix in group chats (the name stays on top).
6. Your photo/video not sent yet + friend **Offline** -> no ring, a clock + **"Waiting"**.
7. Tap "Waiting" -> "Cancel this photo?" / "Cancel this video?" (same as the ring).
8. Friend comes online -> "Waiting" goes away by itself, the ring starts, then ticks.
9. Documents and voice notes: no change. How sending works: no change.

## Phone checks (Realme and ZTE)
1. React with an emoji on your own photo -> bubble stays small, chip on the bottom edge.
2. React on your friend's photo -> same.
3. Send "hi" -> small bubble, time next to it.
4. Friend's phone off / far away (Offline) -> send a photo -> clock + "Waiting", no ring.
5. Friend comes back -> "Waiting" changes to the ring, then ticks.
6. Same with a video.
7. Tap "Waiting" -> "Cancel this photo?" -> Yes removes it, No keeps it.
8. Group chat: emoji -> bubble stays small.
9. Scroll a long chat -> smooth, no jumping.

## Honest notes
- If the friend shows "Online" but the network is bad, you still see the turning ring (the app can only follow the status).
- The status can take a few seconds to change, so "Waiting" may come a few seconds late.
- One old test was changed: it long-pressed the middle of the screen, which is now empty space (the bubble is smaller). It now long-presses the bubble.
- Not tested on a phone yet.
