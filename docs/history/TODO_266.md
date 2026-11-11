# TODO 266 - Instant calls on every path (server, Wi-Fi Direct, mesh)

Status: BUILT as 3.0.82+153 (14 Nov), approved A-D.
User answers (13 Nov): "instant" = fast when a link exists (~2 s), no drop when
the path changes; battery = friends only, smart; calls FIRST; analysis then TODO.
Base: pushed 3.0.80 (+ 265 if built first). 3.0.80/265 touch none of the call files.
Line numbers = GitHub `9d223ef` (app) and `ca4f41c` (backend).
Backend: NO change (the 251 voice relay is already in `ca4f41c`).

---

## 0. Analysis - where a call waits today (checked in code)

### 0.1 The server is NOT a call path today
- `call_transport_selection_policy.dart:9-13`: calls are local only (LAN, Wi-Fi Direct, mesh).
  "Server" calls are really phone-to-phone over the router Wi-Fi (LAN beacon, UDP 8990).
- If the router does not pass phone-to-phone traffic (broadcast filtered, client
  isolation, two access points, guest Wi-Fi) both phones show the server green but
  there is no LAN route -> the call can't ring and can't carry voice.
- Backend `internal/httpapi/voice_relay_251.go` (voice through the server) is BUILT
  and on by default (`LOCALLINK_VOICE_RELAY`), but the app part of 251 was never built
  (`PENDING`: "251 app part").

### 0.2 The server relay of call signals almost never runs (confirmed)
- `call_session_manager.dart:1777-1830` `_sendSignal`: the server copy is sent ONLY
  when the mesh send THROWS.
- Native `LocalLinkTransportService.sendRoutedPayload` (line 4220 `QUEUED -> !isLiveMedia`): no route ->
  `MeshRouter.route` -> `enqueue` -> `QUEUED` -> returns `true` for a call invite.
  `MeshRouter.kt:128`. So Dart sees "sent", and the server copy is skipped.
- Result: a friend reachable ONLY through the server never rings; the caller waits
  60 s ("Waiting for X to connect…") and gets "unreachable"
  (`CallNearbyWait.awayLimit`, `_onConnectWatchdog` 432-457).
- The same for `call_accept` / `call_end`: no server copy while a route is missing.
- Backend side is ready: `websocket.go:179-204` creates the call and forwards the
  invite; `205-259` accept/reject/end/busy; the receiver already de-duplicates
  (`_handleLocalCallSignal` 838-851, "dual-channel delivery").

### 0.3 No link at all (away call) - the long waits
- Caller: acts at once (`nearby_friend_link.dart:358-386` `call_open` / `call_join`).
- Callee with the app closed: Wi-Fi Direct search cadence
  `NearbySearchCadence.everyMs` (`nearby_group_planner.dart:255-300`):
  on router Wi-Fi + idle = 0 (never searches), off Wi-Fi idle = every 3 min,
  waiting = 60 s. One search window = 20 s (`SearchWindowPolicy.WINDOW_MS`).
  -> often longer than the 60 s call limit.
- Fast path that already exists: Bluetooth "wants call" flag (`NearbyBlePolicy.W_CALL`,
  `wifi_direct_fallback_service.dart:1905-1930` -> `_searchSoon`). Works only when
  Bluetooth is ON and allowed on both phones (the app never turns BT on - your rule).
- Joining a Wi-Fi Direct group itself: ~3-10 s (Android).

### 0.4 Path change in the middle of a call - the gap
- Two links to the same friend (LAN + Wi-Fi Direct) are kept: the second one is a hot
  standby (`MeshLinkSelectionPolicy.kt`). Good.
- But the choice is by priority first (LAN > Wi-Fi Direct), and a link is only declared
  dead after `HEARTBEAT_TIMEOUT_MS = 15 s` (`MeshTransportPolicy.kt:37`; ping every 5 s,
  `LocalLinkTransportService.kt:4551-4566`).
- So when the router Wi-Fi drops silently (walking away), voice keeps going into the
  dead LAN link for ~15-20 s although the Wi-Fi Direct link is alive. This matches the
  open "Wi-Fi call gaps" item (to confirm with a log, `CALL_PATH` + `WD_LINK` lines).
- After answer, "Reconnecting…" ends the call after 20 s with no nearby way
  (`noNearbyAfter`, 2141-2196) - there is no server fallback for voice.

### 0.5 Checked and fine (no change)
- Invite resend every 5 s + the native queue flushes the invite the moment a link
  appears (`_trySendPendingInvite` 1623-1700).
- Voice by UDP on a direct link with TCP fallback (`CallVoiceUdp.kt`).
- Mesh voice limit 8 hops (`VoiceCallHopPolicy.maxHops = 8`) - unchanged (your rule).
- `CALL_CONNECT_MS` log exists (answer -> first voice). There is no "tap -> ringing" line.

---

## A. Ring through the server too (Dart only)

Goal: if the server reaches the friend, the friend rings in ~1 s, whatever the nearby state.

A1. `call_session_manager.dart` `_trySendPendingInvite` (1623-1700)
- After the mesh send: if `socket?.isConnected == true` -> also send the invite through
  the server (the same fields as today's relay, WITHOUT the voice key field),
  once per call + again only if the server answered with an error (no 5 s spam;
  the server de-duplicates by call id: `createCall(...existing)`).
- Remember the call as `_serverKnown.add(callId)`. Log `CALL_INVITE_SERVER sent call=..`.
- Mesh copy stays exactly as today (nearby first).

A2. `_sendSignal` (1777-1830)
- For `call_invite_ack`, `call_accept`, `call_reject`, `call_busy`, `call_end`:
  if the call is in `_serverKnown` (sent OR received through the server) and the socket
  is up -> ALWAYS send the server copy too (not only on a throw).
- Calls never seen by the server: unchanged (no server copy -> no server errors).
- Incoming server invite (`_handleServerCallSignal` 821-832) -> `_serverKnown.add(callId)`.

A3. New log `CALL_RING_MS call=.. ms=.. via=mesh|server` (tap -> first `ringing` ack),
  in `_handleInviteAck` (1566-1604).

## B. Voice through the server when there is no nearby way (251 app part)

Goal: a call that rang through the server also TALKS through the server; nearby comes
first again as soon as it exists. Server = the existing 251 relay
(`call_voice` {call_id, voice}, only for a `connected` call of these two phones,
<= 80 pieces/s, <= 1400 base64 chars, refused -> `call_voice_stop`).

B1. Voice key without the server seeing it (decision, my advice)
- Today the call key travels only inside the sealed mesh invite and is removed from the
  server copy (`_voiceKeyForInvite`, 1813-1814). A call that rang only through the server
  has no key.
- New rule (both sides compute the same key, nothing is sent): call key =
  HKDF-SHA256(pair link key [Bundle 160], info = "linkup-voice-266|" + call_id), 32 bytes.
  - Caller uses this key and still puts it in the sealed mesh invite (old apps keep working).
  - Callee: key in the invite -> use it (old caller); no key -> derive.
  - No link key with this friend -> no server voice (calls stay nearby-only, as today).
- Locked end to end: the server only passes sealed bytes (AES-GCM, `CallVoiceSeal`).

B2. Kotlin `LocalLinkTransportService` call media (~3280-3320 voice send; 2761-2779
`handleIncomingSealedVoice`)
- When the sealed send finds no route (`sendRoutedPayload` false) AND Dart said
  "server voice allowed" for this call -> emit event `call_voice_out`
  {call_id, voice = base64(len(vs) | vs | nonce12 | cipher)} instead of the plain fallback.
- New method `relayVoiceIn(call_id, sender, voice)` -> unpack -> the SAME
  `CallVoiceSeal.open` + `handleIncomingCallMediaPayload(.., locked = true)` path.
- Never plain voice to the server.
- Counters for `CALL_PATH`: new path word `server` (`CallPathPolicy.kind`), logs
  `CALL_PATH ... path=server` and `VOICE_SERVER tx=.. rx=.. stop=<reason>` every 30 s.

B3. Dart bridge (`native_mesh_call_transport.dart`, `websocket_service.dart`)
- `call_voice_out` event -> `socket.send({'type':'call_voice', ...})` (no log per piece).
- Incoming WS `call_voice` -> native `relayVoiceIn` (handled BEFORE
  `_handleServerCallSignal`; no dedupe, no log per piece).
- `call_voice_stop` -> stop server voice for this call, one log line.

B4. Call manager rules
- "Server voice allowed" = call in `_serverKnown` AND socket up AND link key exists.
- `_recoverLostMeshTransport` (1834-1845), `_onNoNearbyTimer` (2169-2196) and the
  stats check (2075): count "server voice allowed + socket up" as a way, so the call
  is NOT ended while it talks through the server.
- Nearby first: the 2 s path check (Bundle 192) - when LAN / Wi-Fi Direct / mesh is back,
  voice goes back there by itself (the native side already prefers a route; server voice
  is only the no-route branch).
- Jitter buffer starts at 120 ms on the server path (TODO_251 item 5).

B5. Screen: NO new widget. The existing chip words in
`core/widgets/presence_way.dart:29-35` already say `Online call` for the server way.
While server voice runs, the chip shows `Online call`; back on nearby it shows the
nearby words. (Video button untouched - your rule.)

## C. No gap when the path changes during a call (Kotlin)

Goal: Wi-Fi drops -> voice moves to the standby Wi-Fi Direct link in ~2-3 s, not 15-20 s.

C1. `LocalLinkTransportService` active link choice (`activePeerConnection` /
`MeshLinkSelectionPolicy.selectActive`)
- Only while a call with THIS friend is live (call media running):
  if no voice from the friend (UDP or TCP) for 2.5 s AND the active link had no line
  for 2.5 s -> send one ping on the other link(s) to the same friend; the first link that
  answers within 1 s becomes active for this friend. The old link is NOT closed (the 15 s
  rule still decides its death).
- When the old link talks again it is preferred again (LAN > Wi-Fi Direct, as today).
- Outside calls: nothing changes.
- Logs: `CALL_LINK_SWITCH call=.. from=lan to=wifi_direct quiet_ms=..`.

C2. Policy in a small pure object `CallLinkSwitch266` (Kotlin) so it is unit-tested.

## D. Friend wake for the away call (Dart, battery: friends only)

D1. Callee gets a server invite and has NO nearby route to the caller -> set the caller
as the call target for nearby (the same as `_activeCallTarget` on the caller side): one
urgent search + join the pair's group (`call_join`), BLE "wants call" on. Ends when
the call ends / connects / 60 s.
- Effect: when both are near each other but the router blocks phone-to-phone, the call
  starts through the server (B) and moves to Wi-Fi Direct by itself a few seconds later.
- Only for a friend who is calling - nothing new for idle phones (battery rule).

## E. Not in this TODO
- Add contact instant + network switching (messages): next TODOs after calls (your order).
- Group voice (250): separate.
- No change to search cadence / BLE timers / hop limit / Realme mic / video.
- A phone-only phone with no server: unchanged (nearby only).

## F. Tests (new `test/bundle266_test.dart` + Kotlin `Call266Test.kt`)
1. Invite with no route + socket up -> one server invite; mesh invite still sent.
2. Socket down -> no server invite (today's behaviour).
3. Server-known call: accept / end / busy / reject go on BOTH ways; not server-known: mesh only.
4. Incoming server invite marks the call server-known.
5. Duplicate accept (mesh + server) -> handled once (existing dedupe still works).
6. `CALL_RING_MS` line on first ringing ack, `via=server` when it came from the server.
7. Key: both sides derive the same 32 bytes from a link key + call id; a key in the invite wins; no link key -> no server voice.
8. `call_voice_out` -> one WS `call_voice` frame, no log per piece; `call_voice_stop` -> stop + one log.
9. Incoming WS `call_voice` -> `relayVoiceIn` with the right call id / sender; other call ids ignored.
10. No nearby route + server voice allowed -> `_onNoNearbyTimer` does NOT end the call; socket down -> ends as today.
11. Kotlin: pack/unpack `len|vs|nonce|cipher` round trip; > 1400 base64 refused; never plain.
12. Kotlin `CallLinkSwitch266`: quiet 2.5 s + other link answers -> switch; other link silent -> stay; no call -> never switch; old link back -> LAN preferred.
13. Kotlin `CallPathPolicy.kind` gives `server` for the server branch.
14. Callee wake: server invite + no route -> call target set; route present -> not set; ends on connect/end.
Old tests changed: only the version lines (`bundle223_logs`, `nearby_190`) unless a
source-grep lock is hit - any other old-test change will be listed before the build.
Locks to respect (from memory): `Call189Test`, `friend_call_225` (`_activeCallTarget(now) != null ||`),
`link_201`, `bundle207g`, `CallPathPolicy` tests, NearbyRadio.kt not touched.

## G. Phone tests (after build)
1. Same router, both on server: call -> rings < 2 s (`CALL_RING_MS`), `CALL_PATH path=lan`.
2. Router with client isolation / two access points (or one phone on another Wi-Fi that
   reaches the server): call rings via server, talks `path=server`, chip `Online call`.
3. Then bring the phones together (Wi-Fi Direct): voice moves to `wifi_direct` by itself.
4. Call on Wi-Fi, walk out of router range while Wi-Fi Direct is up: gap <= 3 s
   (`CALL_LINK_SWITCH`), no "Reconnecting".
5. Server off: calls behave exactly as 3.0.80.

## H. Risks
- B is the biggest piece (Kotlin + Dart + key rule). Old app <-> new app: old caller keeps
  its random key in the invite -> new callee uses it -> nearby voice works; server voice
  only between two new apps.
- C changes link choice during calls only; guarded by "friend's voice quiet 2.5 s".
- Server load: ~15 KB/s each way per server call (251 note); server max 20 calls.
- HTTP only: voice stays sealed end to end; signalling is visible on the Wi-Fi (as today).

## I. Delivery
ONE app zip + ONE commit `v3 3.0.8x+15x bundle 266 …` + `APPLY_app_3.0.8x.md`.
Backend: none. Build mode: all phases A-D without stopping.
