# Bundle 199 - v3 3.0.33+104

Pinch to zoom message text, swipe right to reply, reply pictures, blue jump border.
Base: `2a881e2` (198 + X1). One zip, one commit.

## Apply (PowerShell)

```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes199_2026-11-03.zip" .
git add -A
git add -f APPLY_199.md
git reset -q -- android/local.properties
git commit -m "v3 3.0.33 bundle 199: pinch to zoom message text, swipe right to reply, reply pictures, blue jump border"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter pub get
flutter build apk --release
```

## What changed

| Part | What you see |
|---|---|
| 1 Zoom | Two fingers in any chat or group: spread = bigger message text, pinch = smaller. 100% (normal) is the smallest, 200% the biggest, 10% steps. A tiny tick on every step and once at the limit. No number on screen. Saved when you lift your fingers; same size in all chats; stays after closing the app or restarting the phone. Two quick two-finger taps = back to normal. |
| 2 Swipe | Slide any message (yours or theirs, chats and groups) to the right: an arrow comes in, a tiny vibration when far enough, let go = reply bar + keyboard opens. Hold > Reply and Select > Reply now open the keyboard too. |
| 3 Picture | Reply to a photo / video: a small square of it on the right of the quote, in the bubble and in the reply bar while typing. Video has a small play mark. Picture not on this phone = text only. Nothing new is sent. |
| 4 Border | Tap a quote: jumps to the original, a blue border for 2 s, then it fades. (Was a grey ring for 1.4 s.) |

Only the message text grows. Time, ticks, reactions, quote box, Forwarded, names, date lines, photos, the typing box, Chats list and Message info stay the same.

## New files
- `lib/features/messaging/data/chat_text_scale.dart` - the saved size (`chat_text_scale` setting)
- `lib/features/messaging/presentation/widgets/pinch_text_zoom.dart` - two-finger gesture + message text
- `lib/features/messaging/presentation/widgets/swipe_to_reply.dart`
- `lib/features/messaging/presentation/widgets/quote_thumb.dart`
- `test/chat_text_scale_199_test.dart`, `test/chat_reply_zoom_199_test.dart`

## Changed files
- `chat_screen.dart`, `group_chat_screen.dart` - pinch around the list, swipe on bubbles, `_startReply` (keyboard), quote picture, 2 s border
- `message_bubble.dart`, `group_message_bubble.dart` - `ChatBodyText`, `flashed`, `quoteThumb`
- `message_options.dart` - `ReplyBar` / `QuoteBox` picture, new `FlashRing`
- `chat_composer.dart`, `group_composer.dart`, `local_link_text_field.dart` - optional `focusNode`
- `app_dependencies.dart` - loads the saved size at start
- `pubspec.yaml`, `local_link_app.dart` (stamp `bundles 104-199`), `test/nearby_190_test.dart`, `test/group_chat_screen_test.dart`

## New logs
- `CHAT_TEXT_SCALE set=1.4 from=pinch` / `from=reset` (only when the size really changed)
- `CHAT_TEXT_SCALE load=1.4` (at start, only when not normal)
- `CHAT_TEXT_SCALE_SAVE_FAILED`
- `REPLY_START from=swipe|hold|select kind=text|photo|video|voice|file` (`group=y` in groups)

## Phone tests - Part 1 zoom (Z1-Z14)
- Z1 Open a chat with Sajjad. Put two fingers on the messages and spread them: message text gets bigger step by step, small tick on each step.
- Z2 Pinch them together: smaller, but never smaller than normal. One tick when you hit normal.
- Z3 Keep spreading: stops at 2x, one tick at the limit, no more growth.
- Z4 No number or % appears anywhere while zooming.
- Z5 While two fingers are down the list does not scroll.
- Z6 At the bottom of the chat, zoom in: you stay at the bottom (newest message still visible).
- Z7 Time, ticks, reactions, quote box, Forwarded label, date lines, photos and the typing box stay the same size.
- Z8 Photo / file caption text grows like normal text.
- Z9 Open another chat and a group: same bigger size.
- Z10 Close the app (swipe away from recents), open again: same size. Restart phone: same size.
- Z11 Two quick taps with two fingers: back to normal at once.
- Z12 One finger: scroll, tap, hold menu, play voice, open photo all work like before.
- Z13 Mini video player pinch still resizes the player (not the text).
- Z14 Logs: `CHAT_TEXT_SCALE set=... from=pinch` once per lift, `load=` after restart.

## Phone tests - Parts 2-4 (S1-S12)
- S1 Slide a friend's message right: arrow comes in from the left, tiny vibration when far enough, let go: reply bar opens and the keyboard opens.
- S2 Same for your own message.
- S3 Short slide and let go: springs back, no reply.
- S4 Slide left: nothing happens.
- S5 In a group: slide right works the same.
- S6 Select mode (hold > Select): sliding does not reply. Blocked chat: no sliding.
- S7 Slide a video bubble's seek bar: it seeks (no reply).
- S8 Hold > Reply: reply bar + keyboard opens. Select one > Reply arrow: same.
- S9 Reply to a photo: small square of the photo on the right of the reply bar; send: the bubble quote shows the square too (on both phones if both have the photo).
- S10 Reply to a video: square with a small play mark.
- S11 Quote of a deleted message or a photo not on this phone: text only, no square.
- S12 Tap a quote: jumps to the original, blue border for 2 s, then fades. Own group bubble (blue): white border.
