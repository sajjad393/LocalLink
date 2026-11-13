# TODO 282 - choose the tone for calls, messages, in-chat sounds and notifications  [BUILT 13 Nov in 3.0.90+161 - zip locallink_app_3.0.90_2026-11-14.zip, not pushed, not phone-tested]

Status: WRITTEN (freeze ON). Waiting for the user to pick tones, then "Build". Version: after 3.0.89 (to choose).
Code checked: app `de70ef7` (3.0.86). Backend: no change.

## User wish (12 Nov, ask_user)
- "I need for all like call, message, on messages screen when message arrive, notification, on message send."
- Source: LinkUp tone + phone tones from the Android system picker (no own music files).

## Where each sound comes from today (verified in code)
| Sound | Played by | File / setting |
|---|---|---|
| Incoming call ring | `CallRingtoneManager.kt:83` MediaPlayer, ring volume | `res/raw/locallink_ringtone.wav` |
| Outgoing call "ringback" | `CallRingtoneManager.kt:112` | `res/raw/locallink_ringback.wav` |
| Message notification (app closed / other screen) | channel `locallink_messages_v4` (`LocalLinkNotificationManager.kt:52`, sound set :80) | `res/raw/locallink_message.wav`, fallback system default |
| Friends notification ("X added you") | channel `locallink_friends_v1` | system default |
| System notification (pairing, security, update) | channel `locallink_system_v4` | system default |
| In-chat "message arrived" pop (chat open) | `UiSounds.kt` SoundPool via `ui_sounds.dart` (`app_dependencies.dart:548`, chat / group screens) | `res/raw/message_received.wav` |
| Message sent tick | `UiSounds.play(UiSound.messageSent)` (`chat_screen.dart:338`, `group_chat_screen.dart:561`, `forward_screen.dart:353`) | `res/raw/message_sent.wav` |
| Voice note start / send / cancel | `UiSounds` | `voice_start/send/cancel.wav` (not asked; unchanged) |
| Incoming call notification | channel `locallink_incoming_calls` with `setSound(null)` (the ring above is the sound) | - |

Android rule that matters: a notification channel's sound can NOT be changed by the app after the channel
exists (only the user in system settings can). So a new choice needs a new channel id.

## SCOPE CHANGED (user, 12 Nov): "change only the existing tones, send me, I will select; no need custom for every user"
- NO settings rows, NO picker, NO per-user choice. Only the app's own tone FILES are replaced (same file
  names in `android/app/src/main/res/raw/`), so every phone gets the tones the owner picks.
- Files to replace (only the ones the user picks; "current" = keep):
  `locallink_ringtone.wav` (call ring), `locallink_ringback.wav` (outgoing), `locallink_message.wav`
  (message notification), `message_received.wav` (arrived, chat open), `message_sent.wav` (sent).
- Other notifications (friends / system) use the phone's default sound today; unchanged unless the user asks.
- Message notification sound is fixed per channel by Android: a new file needs a NEW channel id
  (`locallink_messages_v4` -> `_v5`), else phones that already have the app keep the old sound. Old channel
  deleted (Android shows "1 category deleted" - harmless).
- Samples for the choice: `tones282/LinkUp_tones_282.html` (players, current + A/B/C per sound),
  `tones282_samples.zip` (the wav files), made by `tones282/make_tones.py` (synthesised here, no outside
  files, no licence issue). Note: the current files are quiet (peak about 22 %); new ones are louder.
- Tests: res names unchanged (UiSounds.resFor / CallRingtoneManager compile), channel id v5 in Kotlin test,
  full suite, analyze, release build, aapt2. Phone: call + message with the app open / closed.

## Old plan (superseded by the scope change above - kept for reference only)
## Plan (smallest, no new dependency, no new permission)
- P-1 Settings -> Notifications screen (`notification_settings_screen.dart`) gets a "Sounds" section with
  6 rows: Call ringtone, Outgoing call tone, Message notification, Other notifications (friends + system),
  Message arrived in chat, Message sent. Each row shows the current tone name.
- P-2 Tap a row -> Android's own picker (`RingtoneManager.ACTION_RINGTONE_PICKER`): type RINGTONE for the call
  rows, NOTIFICATION for the others; first item "LinkUp (default)" = our bundled file; "Silent" allowed only
  for the in-chat / sent sounds (calls and message notifications always make a sound).
- P-3 Saved per row on the phone (setting key per sound, a content URI or "linkup"). Never sent anywhere.
- P-4 Calls: `CallRingtoneManager` plays the saved URI, ring volume as today; if it can't open the URI
  (tone deleted) -> plays the LinkUp file + log `TONE_FALLBACK which=call`.
- P-5 Notifications: on change the app makes a new channel (`locallink_messages_v5_<n>` /
  `locallink_other_v1_<n>`) with that sound and deletes the old one; posts use the current id. The
  "Notification channels" button stays for everything else.
- P-6 In-chat + sent: `UiSounds` plays the chosen URI with a short MediaPlayer (SoundPool can't open
  content URIs); our files stay on SoundPool as today. Same Silent / Vibrate / in-call rule as now.
- P-7 "Reset all sounds to LinkUp" button.
- Not in scope: own music files, a tone per friend (user did not ask), voice-note sounds, video.

## Risks
- Deleting a channel shows "N categories deleted" in Android settings (harmless, Android rule).
- Some phones (ZTE Go, TECNO HiOS) may give a picker without "LinkUp" entries -> our own first row in the
  app covers it (NOT VERIFIED on those phones).

## Tests
- Kotlin: tone choice -> URI or our res; bad URI -> fallback; channel id changes only on a new choice.
- Flutter: Sounds rows show names, reset works, settings saved; full suite, analyze, release build, aapt2.
- Phone: pick a phone tone for calls and messages on C71 + ZTE; call and message with app open / closed.


## Round 3 (12 Nov) - Android open-source tones
- Owner rejected round 1 (A/B/C) and round 2 (D-H, synth). Round 3 = studio tones from AOSP
  `frameworks/base/data/sounds` (Apache-2.0, `default_applicable_licenses: Android-Apache-2.0`).
- Pick page: `tones282/LinkUp_tones_pick3.html` (79 options, numbered per sound). Originals: `tones282/aosp/*.ogg`,
  `tones282_android_full.zip`. Page script: `tones282/make_page4.py`.
- Build notes: convert the picked ogg to wav (same 5 file names), keep mono; ringtone may be trimmed for loop;
  add an Apache-2.0 NOTICE line ("Sounds from the Android Open Source Project").
- Risk: some phones ship the same tone as their default, so LinkUp may sound like the system.


## PICKS (12 Nov, owner) - FINAL
| res/raw file | New sound (AOSP) | Length |
|---|---|---|
| `locallink_ringtone.wav` | Triton (ringtones/material), **version 5: loudest + phone-speaker boost** (+5 dB, limiter 0.97) | 14.7 s, loops |
| `locallink_ringback.wav` | **unchanged (current)** | - |
| `locallink_message.wav` | Salacia (notifications/material) | 1.5 s |
| `message_received.wav` | NFCInitiated ("NFC Start") | 0.9 s |
| `message_sent.wav` | **24 Volume blip** (effects/wav/VolumeIncremental, level 0.35) | 0.6 s |

Ready files: `tones282/final/*.wav` (mono, 16-bit, 44.1 kHz, levels exactly as on the pick page).

### Build plan (on "Build")
1. Copy the 4 wavs over `android/app/src/main/res/raw/` (same names, so no Kotlin/Dart resource changes).
2. `LocalLinkNotificationManager.kt`: `MESSAGE_CHANNEL_ID` `locallink_messages_v4` -> `locallink_messages_v5`;
   delete the old v4 channel on create (so existing phones get Salacia).
3. Check tests that lock the channel id / raw names (NOT CHECKED yet); update only the listed ones.
4. NOTICE line: "Sounds from the Android Open Source Project (Apache License 2.0)".
5. Version: **3.0.90+161 (owner chose)**. Suite + analyze + release build, one zip + one commit.

### Ringtone loudness (12 Nov)
- Owner: "I want call ringtone louder". Code check (`CallRingtoneManager.kt` @de70ef7): ringtone player already at
  `setVolume(1f,1f)`, `USAGE_NOTIFICATION_RINGTONE` (follows phone ring volume) -> only the file can get louder.
- Louder versions (peak limiter, ceiling 0.97, no clipping) on `tones282/LinkUp_ring_loud_pick.html`;
  wavs `tones282/ring_loud/ring_v0..v5.wav`, script `tones282/make_ring_loud.py`. **Picked: 5 (loudest + clearer on phone speaker)** -> copied to `tones282/final/locallink_ringtone.wav`.
