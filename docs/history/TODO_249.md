# TODO 249 - Mesh voice calls A -> B -> C (Phase 13)

## Result: already built - no new code
Checked in the code and in your logs. A voice call already goes through a middle phone:

- Route: `startCall` uses the mesh route when there is no direct link (`CALL_PATH path=mesh hops=2 via=<B>`).
  Limit today: `VoiceCallHopPolicy.maxHops = 8` (call_session_manager.dart). D1 was skipped by your choice, so it was not cut to 1 middle phone.
- Locked end to end (bundle 159, `CallVoiceSeal.kt`): a new 32-byte key per call, sent inside the locked invite;
  each 20 ms frame AES-256-GCM. B sees only a random stream id + cipher text, so B can pass it on but can't hear it.
- B passes frames without opening them (`sealed_v` packets in `LocalLinkTransportService.kt`) and shows nothing on screen.
- B's battery/load limit (`MeshRelayVoiceBudget`): at most 2 calls through B at once, at most 160 frames a second per call, a stream is forgotten after 5 s quiet.
- B keeps its Wi-Fi Direct group open while a call passes (bundle 167 `VoiceRelayTracker`).
- Logs: `RELAY call stream=...`, `RELAY_VOICE_HEALTH ... passed= dropped= gap_max_ms=` on B.

## Proof in your logs (RMX5303, 2026-11-06 22:13)
- `call-b49fa7...`: `CALL_PATH at=start path=mesh hops=2 via=27380d`, ran 2 min 21 s, `CALL_VOICE_HEALTH played=97%`.
- 10 mesh calls with hops=2 in total, and 0 errors on the path.

## Your choice (listed at the end)
- Keep up to 8 hops (today), or cut to 1 middle phone (`maxHops = 2`, one line). My advice: keep today's. Longer paths show "Couldn't reach them" anyway when the sound breaks up.
