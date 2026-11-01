# Bundle 184 - voice stops breaking in calls (3.0.15+86)

Plan: TODO_184.md. The voice part is all native (Kotlin). Dart changes are small.

## What was wrong (from your 2 logs)
- The network delivered about 99% of the voice.
- The app threw away about half of it (old 179 "catch up" rule + no waiting line).

## What changed
1. **Waiting line (jitter buffer)** - `CallJitterBuffer.kt`
   - Waits 60-300 ms (grows at once when Wi-Fi bunches, shrinks slowly).
   - Only quiet pieces are ever cut. Talking is never cut.
   - A missing piece is covered with the last sound (max 60 ms).
2. **Old 179 cut rule removed** (`CallAudioLatencyPolicy.kt`, `Call179Test.kt`).
3. **5 voice threads at audio priority**: mic, send (Opus encode here), decode, speaker, UDP.
4. **UDP voice** - `CallVoiceUdp.kt`, port 8992, same lock (AES-GCM).
   - Used only while the friend says it gets our UDP. Otherwise TCP like before.
   - Each piece also carries the previous piece, so one lost piece comes back.
   - Replayed old datagrams change nothing.
5. **Nearby search pauses during a call**, comes back 2 s after it ends.
6. **Wi-Fi lock that works with the screen off** on Android 10-13 (HIGH_PERF).
   Android 14+ has no such lock; the waiting line covers it.
7. **No app event per voice piece** (no `call_media_received`, no `mesh_delivered`
   for voice). Dart reads totals at the end like before.
8. **New log lines**
   - `CALL_VOICE_HEALTH` every 10 s (played %, cut while talking, delay, udp, screen).
   - `CALL_VOICE_SUMMARY` at the end of the call.
   - `CALL_MEDIA_STATS` now also shows `heard=..% hidden=.. udp_tx=.. udp_rx=..`.

## Files (14)
New:
- android/app/src/main/kotlin/com/sajjad/locallink/CallJitterBuffer.kt
- android/app/src/main/kotlin/com/sajjad/locallink/CallVoiceUdp.kt
- android/app/src/main/kotlin/com/sajjad/locallink/CallVoiceHealth.kt
- android/app/src/test/kotlin/com/sajjad/locallink/Voice184Test.kt
- test/bundle184_test.dart

Changed:
- android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt
- android/app/src/main/kotlin/com/sajjad/locallink/CallAudioLatencyPolicy.kt
- android/app/src/main/kotlin/com/sajjad/locallink/NearbyRadio.kt
- android/app/src/main/kotlin/com/sajjad/locallink/NearbyTagManager.kt
- android/app/src/test/kotlin/com/sajjad/locallink/Call179Test.kt
- lib/app/local_link_app.dart (stamp: bundles 104-184)
- lib/features/calls/data/transport/native_mesh_call_transport.dart
- lib/features/messaging/data/services/reliable_messaging_service.dart (comment only)
- pubspec.yaml (3.0.15+86)

## Apply (PowerShell)
```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes184_2026-11-01.zip" .
git add -A
git add -f APPLY_184.md
git reset -q -- android/local.properties
git commit -m "v3 184: voice stops breaking - waiting line, no cut while talking, UDP voice with backup piece, Nearby pauses in calls - 3.0.15+86"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter pub get
flutter build apk --release
```
Install the new APK on **both** phones (old + new phones still talk, but UDP only
turns on when both have 184).

## Phone checks (please do all 4, then send both logs)
1. 3-min call, phone at the ear (screen off). Count 1 to 100. No number missing?
2. 3-min call on loudspeaker.
3. Walk to another room during the call.
4. App closed, answer from the notification.

Pass looks like this in the logs:
- `CALL_VOICE_SUMMARY ... played=97%` or more
- `cut_talk=0`
- `empty=` 9 or less for a 3-min call (speaker ran out, 3 per minute)
- delay = `buffer_ms` + `speaker_ms` in the `CALL_VOICE_HEALTH` lines, 300 or less
- `CALL_UDP_MODE send=udp` shows on both phones (if your Wi-Fi allows it)

## Tested here (not on a phone)
- Kotlin: 267 tests pass (27 new for 184), clean compile.
- Simulator with Wi-Fi like your log: old rules played 49%, new rules 100%
  (no talking cut, average wait 215 ms). This is a simulation, not proof.
- Flutter: analyze no errors (150 info, same as 183); all 814 tests pass.
