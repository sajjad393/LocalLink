# Bundle 189 - voice breaking in the first 2 minutes + sound facts in the log (3.0.20+91)

## Why
2026-11-02 logs (Realme 3.0.19 + ZTE 3.0.19, call 02:34-02:42):
- Both phones heard broken voice for the first ~2 minutes (gaps up to 1 s),
  then 100 % clean - both directions at the same moment.
- Both phones had started a Nearby (Wi-Fi Direct) search while the call was
  ringing. Bundle 184 only blocks NEW searches during a call; the running one
  kept going ~2 minutes (Android's search time) and kept pulling the Wi-Fi
  away from the router.

## What changed
A. When call voice starts, a Nearby search that is already running is stopped
   (`stopPeerDiscovery` + clear the tag search request). Skipped only if a
   nearby group create/join was asked for in the last 30 s. Search comes back
   2 s after the call (unchanged, from 184).
   Log: `CALL_NEARBY_STOP peers=ok|fail_N|skip_joining|none services=ok|fail_N|none`
B. Log only: `CALL_SOUND_STATE call= at=call|end vol=cur/max out=speaker|ear|bluetooth|wired
   battery=N% charging=y/n saver=y/n mic_mute=y/n mode=communication`
   Written when something changes (checked every 10 s), else once a minute,
   plus one at the end. Reads run on their own short thread, never on the
   speaker thread.

Nothing else changes: no change to call screens, speaker button, voice line,
UDP, or Nearby outside calls.

## Files
- android/app/src/main/kotlin/com/sajjad/locallink/CallVoiceUdp.kt (CallSearchStop)
- android/app/src/main/kotlin/com/sajjad/locallink/CallVoiceHealth.kt (CallSoundState)
- android/app/src/main/kotlin/com/sajjad/locallink/NearbyRadio.kt (stopSearchForCall)
- android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt
- android/app/src/test/kotlin/com/sajjad/locallink/Call189Test.kt (new)
- test/bundle189_test.dart (new), test/bundle188_test.dart (version moved)
- lib/app/local_link_app.dart, pubspec.yaml (3.0.20+91)

## Phone test (both phones on 3.0.20)
1. Call for 3-5 minutes. Use speaker AND ear. Put the phones in different rooms
   (two phones on speaker in the same room can make the voice break by itself).
2. Share logs from BOTH phones within 1 hour.
3. Pass:
   - `CALL_NEARBY_STOP peers=ok` (or `fail_` = nothing was running) at call start.
   - First 2 minutes: `CALL_VOICE_HEALTH` `gap_max_ms` under ~300, `cut_talk=0`.
   - `CALL_SOUND_STATE` lines present on both phones.
