# TODO 303 - incoming call screen does not open while LinkUp is open (BUILT 15 Nov, 3.0.99+170)

Base: 302 (3.0.98+169, local commit f991397, not pushed yet). Next version would be 3.0.99+170.

## What the user sees
- Someone calls while LinkUp is open. The ring screen (Answer / Decline) does not open.
- Chats / Calls tabs: only the green bar "Call in progress · X · Calling… — Tap to return".
- Chat screen: no bar at all, only a small green "Return" chip in the top bar (and only when the caller is the
  person of that chat).

## Code facts (5e34ade / f991397)
1. Only ONE place opens the ring screen: `local_link_app.dart:388 _maybeShowIncomingCall()`.
   - It gives up when the app is not exactly `resumed` (`:389`). Android reports `inactive` whenever the LinkUp window
     loses focus while it is still on screen (heads-up notification, notification shade, a system popup, the
     ColorOS floating window and similar).
   - It also gives up when `_shownIncomingCallId` is still set (`:405`).
   - It writes no log when it gives up. Only `CALL_SCREEN_OPEN` is logged when it works, so a skip is silent.
   - It tries again only on a call change or on `resumed` (`:361`, `:678`, post-frame in build `:746`).
2. When the state is `inactive`, `call_session_manager.dart:663 onAppLifecycleState` thinks the app is in the
   background (`_appInForeground = state == resumed`) and posts the call notification instead.
3. The green bar is only on Chats (`home_screen.dart:1651 _OngoingCallBar`) and Calls (`calls_screen.dart:365`).
   It always says "Call in progress … Calling… — Tap to return", even for a call that is RINGING to me (wrong words).
4. Chat screen: `chat_screen.dart:1585 _ReturnToCallChip` shows "Return", only for a call with THAT person
   (by design since Bundle 136). A call from someone else shows nothing there. Group chat, Contacts, Settings and
   others also show nothing.

## Likely cause (NOT VERIFIED - needs logs)
The ring screen is skipped at fact 1 (app `inactive`, or a leftover id), and nothing else on the chat screen tells you a
call is ringing.

## Logs to ask for (one missed ring while LinkUp is open)
`CALL_SCREEN_OPEN`, `CALL_SCREEN_CLOSE`, `CALL_SCREEN_SKIP`, `CALL_NOTIFICATION_ACTION`, `CALL_RING` (whole log
around the ring time is best; there is no log line today for "ring arrived" or for app lifecycle).
- No `CALL_SCREEN_OPEN` for that call = skipped (fact 1).
- `CALL_SCREEN_OPEN` then `CALL_SCREEN_CLOSE` = opened and closed at once (different bug).

## Plan (after "Build")
- **A. Ring screen always opens while LinkUp is on screen.**
  - Accept `resumed` OR `inactive` in `_maybeShowIncomingCall`.
  - Clear a leftover `_shownIncomingCallId` when no ring screen is really open.
  - Retry every 1 s while a call is ringing to me and no ring screen is open (stops when it opens or the call ends).
  - Log `CALL_SCREEN_SKIP reason=…` for every give-up.
- **B. Call bar on every screen.** One bar for the whole app (MaterialApp builder), above all screens, including chat,
  group chat, contacts and settings, not only Chats / Calls.
  - Ringing to me: "Incoming call · ayesha", tap = open the ring screen.
  - My call ringing out: "Calling ayesha…"; answered: "ayesha · 01:23".
  - Hidden while the call screen is open. The chat "Return" chip goes away (the bar replaces it).
- **C. Call manager:** treat `inactive` as foreground (no extra call notification while LinkUp is on screen).
  Paused / hidden behaves as now.
- Mock: skipped, the user said "Build" straight after the TODO. The strip uses the app's call green (#1E7D4F light /
  #17663F dark), white text, like the old bar.
- Tests: ring screen opens while inactive; skip logs; leftover id cleared; bar shows on the chat screen; bar words per
  state; bar hidden on the call screen; old locks (`bundle136`, `bundle137`, `bundle146`, `bundle227`) checked first.

## 303 v2 (15 Nov) - BUILT (user: "C, Build") - same version 3.0.99+170, replaces the built 303 zip
User: "strip303.jpg not looks good" -> new mock `~/mocks/call_strip_303.html` (styles A / B / C, light + dark); the
user picks one. Plus: calls start with the speaker OFF for both people, and the proximity sensor works like WhatsApp.

### Code facts (5e34ade, unchanged by 302/303)
- `call_session_manager.dart:764` (outgoing) and `:1438` (incoming) create the session with `speakerOn: true`
  (Bundle 144: the user chose the speaker because the 143 earpiece "sounded filtered").
- Proximity already exists: `_syncCallUi` (`:2831`) -> `setCallUi(inCall, proximity)` -> `MainActivity.kt:1348-1385`
  `PROXIMITY_SCREEN_OFF_WAKE_LOCK`. It is on only when: the call is live (my call ringing out counts; a call ringing to
  me does not), no video, and the speaker is OFF. Today the speaker starts ON, so the sensor only works after the user
  taps the speaker off.
- `:1379`: if the phone does not support the proximity wake lock, nothing happens (no screen-off).
- Video calls move to the speaker (`_speakerForVideo`), not touched (video is stopped).

### Plan (after "Build")
- D. Both sessions start with `speakerOn: false` and the audio route is set to the earpiece at call start (check
  `audioPlatform.setSpeakerphoneOn(false)` is applied on both sides, including Bluetooth headsets left as they are).
- E. Proximity: no new code if D works (screen black near the ear, back on when away; speaker on = screen stays on).
  Add a log `CALL_PROXIMITY on/off supported=…` so the ZTE / Tecno case is visible.
- F. The picked strip style (A / B / C) replaces the 303 strip.
- Tests: speaker starts off (outgoing + incoming), proximity flag follows speaker, strip style keys/words.
- Phone check: earpiece sound must be clear (143 complaint) on Realme, Tecno, ZTE.

### 303 v2 BUILT (15 Nov)
- F: style C card (green tint, photo + phone badge, bold name, green line; Decline + Answer while ringing to me,
  "Return" otherwise). Floats under the top bar of the screen in front (route observer + top bar measure).
- D: `speakerOn: false` for outgoing and incoming calls (call_session_manager.dart, 2 places).
- E: no rule change (sensor on = live call, no video, speaker off). New log `CALL_PROXIMITY in_call=… want=… sensor=on/off/unsupported/error`.
- Speaker ON + phone at the ear: speaker and screen stay on (like WhatsApp).

## 303 v3 (15 Nov, FREEZE ON) - G: voice note bars from the real sound - same 3.0.99+170, replaces the 303 zip again
User (screenshot of the sumaira chat): "In message bubble audio waves are not like Whatsapp according to sounds".
Choices (check boxes): old voice notes get real bars too (decode the file); fix "43.3 KB" (always show the length);
mock first; keep it in 303. Mock: `~/mocks/voice_wave_303.html` (Now / A / B, light + dark) - user picks A or B.

### Code facts (GitHub 7afb6ea)
- `lib/features/files/presentation/widgets/attachment_tile.dart` ~997: "Faux waveform" = 24 bars,
  height `8 + 10 * ((i * 7 % 11) / 10)` - the SAME pattern on every voice note, not from the sound.
  Fill rule `(i / 24) <= playbackFraction` makes bar 0 blue even at 0:00 (the blue first bar in the screenshot).
- Same file ~938: label = length only when `_audioDurationMs > 0`, and `_audioDurationMs` is set ONLY by the
  `play` call (~785). A note never played shows `_sizeLabel(size)` = "43.3 KB". That is why 2 notes show KB.
- Voice notes are AAC `.m4a` (MainActivity.kt ~1149 MediaRecorder MPEG_4/AAC 44.1 kHz 96 kbps; parts joined by
  `VoiceNoteJoiner.kt`). Channel `locallink/voice_notes` (MainActivity.kt ~1037); `mediaBg` (~170) runs work off the UI thread.
- Same tile is used in 1-to-1 (`message_bubble.dart:182`) and groups (`group_message_bubble.dart:187`).
- No test locks the fake bars or the KB label.

### Plan
- G1 native: new `voice_wave` on `locallink/voice_notes` via `mediaBg`: MediaExtractor + MediaCodec decode the
  file to PCM, peak loudness per bucket (48 buckets), duration from the track format. Returns
  `{duration_ms, peaks[0..100]}`. Built-in Android only (no new deps). Failure -> `{duration_ms}` from
  MediaMetadataRetriever, peaks empty; log `VOICE_WAVE fail=...`.
- G2 Dart `voice_wave_303.dart`: one decode at a time (ZTE CPU), memory + small disk cache (`voice_waves.json`,
  key = file path + size) so each file is read once - old notes too.
- G3 tile: 28 bars from the peaks (normalised to the note's loudest part, min 3 px, max 22 px; each line 2 px wide, 1 px gap, as many lines as fit (~56) - user: thinner lines twice (4 -> 3 -> 2 px), then "Remove spaces from in between"); silence = low
  flat bars. File not on the phone yet = low flat bars + size (same loading ring as now). Fill: a bar is blue when
  its middle is played (no blue first bar at 0:00). Style A = bars only; style B = + round dot that moves.
- G6 message box (user: "same design for input compuser audio as well"): the recording panels already draw real
  mic levels (`voice_recording_widgets.dart` `VoiceWave` / `_WavePainter`: 3 px bars every 6 px; locked = blue live
  wave `voice_live_wave`, paused preview = light blue + blue played). Change the painter to 2 px lines, 1 px gap;
  paused preview = grey unplayed + blue played (+ dot if B). The bubble uses the SAME `VoiceWave` (fit = whole
  note), so both look the same. Keep the key `voice_live_wave` and the theme primary colour
  (`bundle202_media_grid_test` checks `Theme.of(context).colorScheme.primary` right after the key).
- G4 label: the length from G1 shows as soon as the file is on the phone ("0:07"); playing = "0:03 / 0:06".
  KB only while the file is not on the phone.
- G5 tests: peaks -> 28 bars, normalising, silence, fill rule, label rule (no KB with a known length), cache
  (one decode per file), source checks for the native handler. Old tests unchanged.
- NOT VERIFIED until phones: decode speed on the ZTE for long notes, real shapes.

### 303 v3 decisions (15 Nov)
- Bars: user picked **B** (thin close lines + round dot that moves while playing) - "Go with B".
- Message box while recording: user: "i need to redesign input compuser not looks good". New mock
  `~/mocks/voice_composer_303.html` (Now + A one line / B rounded card / C bubble-style preview; holding, locked,
  paused; light + dark). Waiting for the pick. Files: `voice_recording_widgets.dart` (VoiceLockedPanel,
  VoicePausedPanel, _Panel, VoiceHoldingContent), `chat_composer.dart` (hold mic + VoiceLockBox ~240). Keep keys
  voice_live_wave / voice_locked_panel / voice_paused_panel / voice_play / voice_pause / voice_continue /
  voice_send / voice_delete / voice_timer (tests use them). The hold gesture, lock and slide-to-cancel logic stay.
- Message box: user picked **A - one line** (same height as the message box):
  - Holding: pill [red dot, timer, live wave, "< Slide"] + big gradient mic with the lock above (as now).
  - Locked: red outline bin on the left | pill [red dot, timer, live blue wave, soft red pause button] | gradient send.
  - Paused: red outline bin | pill [small blue play, wave with grey + blue + round dot, timer, soft red mic = continue] | send.
  - Replaces the two-row white `_Panel` with the grey top line. Same keys, same gesture / lock / cancel logic.

## Build notes v3 (G) - what differs from the plan
- G2 file is `lib/features/files/data/services/voice_wave_book.dart` (`VoiceWaveBook`), not `voice_wave_303.dart`.
- The memory is the app setting `voice_waves_303` (key = path + size), not a `voice_waves.json` file.
- Native peaks are 0..32767 (raw loudness), not 0..100. The app turns them into bars on a dB scale measured from each
  note's own loudest part (36 dB range), so a soft voice still shows its words.
- No reads during a call; one file at a time.
- Message box A: the holding pill fits 360 px wide phones ("Slide to cancel" shortens with "..." if needed).
