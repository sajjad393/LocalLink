# TODO 250 - Group voice call, up to 4 people (Phase 14)

Note: this reverses your old rule "no group voice call" - it is here because you listed it.

## Status: PLAN + MOCK only. Not built in this zip.
Why: the call sound engine is native (Kotlin `CallMediaSession` in `LocalLinkTransportService.kt`:
one mic, one `CallJitterBuffer`, one `AudioTrack`, one peer). Group voice needs a new native mixer.
Kotlin can't be compiled or run here, and a Kotlin mistake breaks the whole APK build.
Your rule "make app stable, don't make new issues" -> this needs its own build + phone test cycle.

Mock: `mocks/mock_250_group_call.jpg` (2x2 tiles, green ring = talking, mic-off mark, "Ringing..." faded, same pill as 1:1 calls).

## Design (for the build cycle)
1. Start: group chat top bar -> phone icon (only admins? no - any member, nearby only). Pick up to 3 others.
2. Signaling (Dart, `CallSessionManager`): one `group_call_invite` per member with the same `group_call_id`,
   the member list and ONE random 32-byte key per pair (sealed per member like today's 159 invite).
   Each member answers on its own; a late joiner gets the current list.
3. Sound (Kotlin): one mic + one Opus encoder (encode once), sealed per receiver (cheap AES), sent to each
   other phone ("full mesh"; 4 people = 3 sends + 3 receives per phone, about 3 x 32 kbit/s each way).
   One jitter buffer per sender; mix (sum + clip) into the one `AudioTrack`.
4. Limits: max 4. If any phone in the call reports <= 3 GB RAM (ZTE Blade A35 = 2 GB) -> max 3.
   Wi-Fi Direct / LAN only (no server relay for groups). Through a middle phone: allowed, counts in B's 2-call budget.
5. Leave: a member leaves -> others drop its stream, the call goes on while 2+ remain.
6. Logs: `GROUP_CALL id= members= joined=`, per-sender `CALL_VOICE_HEALTH` lines.
7. Tests: Dart signaling + list rules (unit), mixer clip test (Kotlin unit test, runs in Android Studio).

## What you test (after that build)
- 3 phones on one Wi-Fi Direct group: 5 min call, everyone hears everyone, then ZTE leaves and comes back.
- Send logs from all phones.
