# APPLY app 303 - ring screen always opens + call card + earpiece start + real voice note bars + one-line recorder (3.0.99+170)

Zip: `locallink_app_303_2026-11-15.zip`, on top of 302 (3.0.98+169). Apply and commit 302 FIRST, then 303.
Plan: `docs/history/TODO_303.md`. App only, no backend change.

## What changes
- **A. The ring screen opens while LinkUp is on screen.**
  - Before, it opened only when Android said "resumed". When LinkUp was visible but its window had lost focus
    ("inactive": heads-up, notification shade, a system popup), the ring screen was skipped without a word.
  - Now it opens in "resumed" or "inactive".
  - It tries again every second while a call is ringing to you and the ring screen is not open.
  - An id left over from an old call no longer blocks it.
  - Every skip writes `CALL_SCREEN_SKIP reason=…` (app_paused / app_hidden / leftover_cleared / no_navigator /
    other_call_screen).
- **B. One call card (style C) under the top bar of EVERY screen** (chat, group chat, contacts, settings, Chats, Calls):
  - Light green card (dark green in dark mode): photo with a small green phone badge, the name in bold, a green line.
  - Ringing to you: "Incoming call" + red **Decline** and green **Answer** buttons (they work right in the card;
    Answer then opens the call screen).
  - Your call, not answered: "Calling…" + green **Return** button.
  - Answered: "01:23" (live clock) + **Return**. Reconnecting: "Reconnecting…".
  - Tap the card or Return to open the call screen. Hidden while the call screen is open.
  - The old bottom bars on Chats and Calls, and the small "Return" chip in a chat, are gone (the card replaces them).
- **C.** While LinkUp is on screen ("inactive" too), no extra call notification is posted; the ring screen shows instead.
- **D. Calls start on the earpiece** (speaker OFF) for both people, outgoing and incoming. The speaker button still
  turns the loudspeaker on. A Bluetooth headset is used first when one is connected (same as before).
- **E. Proximity like WhatsApp:** with the speaker off, the screen goes dark at the ear and lights up when you take the
  phone away. Speaker on = screen stays on. New log line `CALL_PROXIMITY … sensor=on/off/unsupported` (a phone without
  the sensor feature shows `unsupported`).
- **G. Voice note bars from the real sound** (pick B, like WhatsApp):
  - Each voice note shows its own shape: tall lines = loud, short = quiet, flat = silence (was the same fake pattern on
    every note). Thin 2 px lines with 1 px gaps; the played part turns blue and a round dot moves while playing.
  - The phone reads each file once with Android's own decoder (off the screen thread, one file at a time, never during
    a call) and remembers it, also after a restart. Old voice notes get real bars too.
  - The length ("0:07") shows as soon as the file is on the phone. Before, a note never played showed "43.3 KB".
    The size only shows while the file is still coming. Same in group chats.
  - Log lines (native): `VOICE_WAVE ok ms=… took=…` / `VOICE_WAVE fallback why=…`.
- **G6. Message box while recording** (pick A, one line, same height as the normal message box):
  - Holding: red dot, timer, live blue wave, "< Slide to cancel" + the big mic and the lock (as before).
  - Locked: red bin | pill with dot, timer, live blue wave, soft red pause | send.
  - Paused: red bin | pill with blue play, wave (grey + blue + dot, same as the bubble), timer, soft red mic to
    continue | send. The white two-line panel with the grey line is gone. Hold / lock / slide-to-cancel work as before.
- The 302 changes are not touched. Video calls are not touched (they still switch to the speaker).

## Files (21)
- new `lib/features/calls/presentation/widgets/call_strip_303.dart`
- `lib/app/local_link_app.dart`
- `lib/features/calls/presentation/screens/call_screen.dart` (`visibleCallId` is now listenable; same use)
- `lib/features/calls/data/services/call_session_manager.dart` (inactive = on screen; speaker off at start)
- `lib/features/calls/data/platform/call_audio_platform_service.dart` (CALL_PROXIMITY log)
- `android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt` (sensor result returned for the log)
- `lib/features/home/presentation/screens/home_screen.dart`, `lib/features/calls/presentation/screens/calls_screen.dart`,
  `lib/features/messaging/presentation/screens/chat_screen.dart` (old bar / chip hide when the strip is on)
- `pubspec.yaml`, `lib/core/config/app_build.dart` (3.0.99+170)
- new `lib/features/files/data/services/voice_wave_book.dart` (reads + remembers the bars)
- new `android/app/src/main/kotlin/com/sajjad/locallink/VoiceWaveNative.kt` (Android decoder -> loudness per slice)
- `lib/features/files/presentation/widgets/attachment_tile.dart` (real bars + length in the bubble)
- `lib/features/messaging/presentation/voice/voice_recording_widgets.dart` (thin bars + dot; one-line recorder)
- `MainActivity.kt` also gets the `voice_wave` call; `home_screen.dart` also starts the bar memory
- new `test/call_strip_303_test.dart` (15 tests), new `test/voice_wave_303_test.dart` (13 tests)
- `test/bundle223_logs_test.dart`, `test/nearby_190_test.dart` (version lines only)
- `docs/history/TODO_303.md`, `docs/history/APPLY_app_303.md` (git add -f)

## Tests
- `flutter analyze`: 0 errors; no issues in the new or changed files (175 old infos/warnings, same as before).
- Full Flutter suite (`-j 1` chunks): 311 files, **3018 tests, all passed** (2990 + 15 `call_strip_303_test.dart`
  + 13 `voice_wave_303_test.dart`).
- Voice bars test checks: real shape, loudest = full height, silence = low flat bars, a bar turns blue only after its
  middle played (none at 0:00), length shown when the file is on the phone / KB when not, one read per file, one
  file at a time, remembered after restart, the native code is wired. "0:03 / 0:06" while playing was seen in a
  real-app picture only; "no reads during a call" is checked in the code only (not run).
- `VoiceWaveNative.kt` compiled alone with kotlinc + android.jar: exit 0. The full Android build (MainActivity) was
  NOT run here; CI / your PC build will show it.
- Real-app pictures (light + dark) of the bubbles and the recorder were compared with the picked mocks.
- The card test checks: Decline / Answer while ringing (Answer answers and opens the call screen), Return + clock
  when answered, the card sits right under the top bar of the screen in front, light + dark pictures.
- Speaker / proximity are checked in the code only (speaker off at start in both places; sensor log). The real sound
  route and the sensor are **NOT VERIFIED** without phones.
- The widget test also checks that a chat with typed text stays the same when the card comes and goes (the screens
  are not rebuilt) and that the card is hidden while the call screen is open.
- **NOT checked here:** real phones and CI. The cause (window focus lost = "inactive") is still **NOT VERIFIED**; the
  new `CALL_SCREEN_SKIP` lines will show it.

## Phone checks
1. Open a chat on phone A and call it from phone B. The ring screen should open at once.
2. Do the same with the notification shade pulled down on A. When you close the shade, the ring screen should be there.
3. Press back on the ring screen (do not answer): the green card "B / Incoming call" with red and green buttons shows
   on every screen. Press green: the call is answered and the call screen opens. Try again and press red: declined.
4. Answer, then press back: the card shows "B / 00:12" + Return in the chat, Contacts and Settings. Return opens the call.
5. Call out: the card shows "Calling…" until they answer.
6. **Earpiece:** on both phones the voice comes from the top earpiece, not the loudspeaker. Check that it is clear and
   loud enough on Realme, Tecno and ZTE. The speaker button still switches to the loudspeaker.
7. **Proximity:** speaker off, put the phone to your ear: the screen goes dark; take it away: it lights up. Speaker on:
   the screen stays on at the ear. If the ZTE does nothing, send the `CALL_PROXIMITY` log line.
8. With LinkUp in the background or the screen locked, the full-screen call notification should still show as before.
9. If a ring screen is still missed, send the log lines with `CALL_SCREEN_SKIP` and `CALL_SCREEN_OPEN`.
10. **Voice bars:** open a chat with old and new voice notes. Each note shows its own bar shape (talk, pause, talk =
    tall, flat, tall). The length shows without playing. Play one: the bars turn blue behind the dot, "0:03 / 0:06".
    A note still coming shows flat bars + size. On the ZTE, check the bars come within a second or two; if not, send
    the `VOICE_WAVE` log lines.
11. **Recorder:** hold the mic: one line with red dot, timer, live wave, "< Slide to cancel". Slide up to lock: bin |
    wave + pause | send. Pause: play button + grey/blue wave + red mic. Send, delete and slide-to-cancel work as before.
