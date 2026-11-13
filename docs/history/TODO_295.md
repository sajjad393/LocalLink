# TODO 295 - BUILT 3.0.93+164 (locallink_app_295_2026-11-14.zip, on b5744ef)

Source: LinkUp-logs-RMX5303-2026-11-13-1916.txt, LinkUp-logs-Z2453-2026-11-13-1918.txt (3.0.92+163).
Question: mesh call sajjad (RMX5303) -> sumaira (ZTE Z2453) through ayesha failed.

## Findings (logs + code b5744ef)
- 6 calls 19:10-19:16. Wi-Fi Direct path broke again and again:
  - 19:10:16 the group host (82927a91) dropped; RMX and ZTE lost the group within 1 s.
  - ZTE: system Bluetooth service down -> Wi-Fi P2P off 2-3 s -> group lost:
    19:04:58, 19:05:53, 19:11:53, 19:15:09, 19:16:11 (log: BluetoothAdapter onBluetoothServiceDown, WD_P2P state=off). Not caused by a LinkUp line; root NOT VERIFIED.
  - ZTE needs ~30-60 s to host a group again (waiting_create).
- call-8092 (19:10:10): ZTE got invite 19:10:15.999, ack 19:10:16.021 lost (link died 19:10:15.883). ZTE rang 30 s (missed 19:10:46) after caller canceled 19:10:30 -> ghost ring.
- call-c90f / call-edbb (19:11): no route reached ZTE; ZTE got edbb end only at 19:17:00.
- call-d86c (19:15:01): worked, relay peer ...9654237e. Ring in 2.7 s, ZTE showed popup. Caller state ringing -> endCall() -> state=ended 1.4 s later. By code (call_session_manager.dart 945-973, 2815-2850, 1327, 2673; local_link_app.dart 606) only the End button fits the timing. USER CONFIRMED: he pressed End -> not a bug.
- call-6fbd / call-f682 (19:15:37, 19:15:55): ZTE had no group (P2P off 19:15:10, new group 19:15:41); invites arrived 80 s late with their end -> shown=no (correct).
- CALL_INVITE_SENT transport=mesh queued=false is logged even when no live route exists.

## Proposal
- A. Ghost ring: callee stops ringing when the caller's 5 s invite repeats stop for ~12 s -> "Missed call".
- B. Caller honesty: log route=none; screen says "Can't reach <name> nearby yet, still trying" instead of plain "Calling".
- C. ZTE quick re-host: when P2P comes back within 5 s after p2p_off, a host re-creates its group at once (now ~30-60 s).
- Test (no code): one run with ZTE Bluetooth off, see if onBluetoothServiceDown / P2P drops stop.

## User answers (13 Nov)
- 19:15 call: user pressed End (not a bug).
- ayesha = RMX3938 (...d5d181c0), sumaira = ZTE (...ed16a834).
- Parts chosen: A + B + C.
- Recovery screen: "Loading taking too much time on shimmering and one screens ui issues".

## Extra finding: path through ayesha
- 19:11:25-19:11:54 the path RMX5303 -LAN- ayesha -WD- ZTE was up. ZTE's own call_end reached Sajjad through it (19:11:32).
- Sajjad's invites at 19:11:38 and 19:11:43 never reached the ZTE (no call_invite parsed). Where they were lost: only ayesha's log (RMX3938, 19:10-19:13) can show. NOT VERIFIED.
- The call that rang (19:15:01) went through ...9654237e (TECNO), not ayesha.

## D (proposal) Recovery code: slow "Show my code"
- Log: tap ~19:02:56, KDF ms=2828 verify, password ok 19:02:59.000 (18:22: ms=2684). ZTE was 6.3 s (Bundle 223 note).
- Cause VERIFIED: recovery_code_286.dart checkPassword -> PasswordKdf.verifyAsync = 180,000 PBKDF2-HMAC-SHA256 rounds in pure Dart, 2 new byte lists per round (password_kdf.dart derive()).
- Fix: same maths, same result, faster loop (HMAC key pads prepared once, no new lists per round). Old saved passwords keep working. Lock test: same output as today for fixed vectors + backend vector.

## E (proposal) Recovery code password screen UI
- Password box and "Show my code" button touch (0 gap). Mock 286: 10 px gap. Code: `const SizedBox(height: 0)` when no error (recovery_code_286.dart ~779).
- Fix: 10 px gap like the mock.

## User answers (2)
- D + E: yes ("Go with option 1"). UI issue = the button touching the box (confirmed).
- ayesha log: user will send (RMX3938, 19:10-19:13).
- NEW F: "On profile screen show shimmering on profile instead of linkup User while loading."

## F (proposal) Profile screen: shimmer, not "LinkUp user", while loading
- Code (VERIFIED): profile_screen.dart:383 `displayName ... : 'LinkUp user'` while `bloc.profile` is null; avatar letter "L" from that name.
- Why it is slow (VERIFIED in code): account_repository.dart:24-51 loadProfile() first awaits _api.syncPendingProfile() (PUT /api/v1/profile), then reads the saved profile, then GET. With the server down each call waits 6 s (log: PUT /api/v1/profile ... (6002ms) offline, 67 lines on 13 Nov).
- Fix:
  1. Show the saved profile at once: read the saved copy first, show it, then do sync + server refresh in the background (screen updates when it answers).
  2. Only when nothing is saved yet: soft shimmer on the photo circle, name and @username lines (no "LinkUp user", no letter L).
  3. Name rule (standing): profile loaded with no display name -> username without @ (today it shows "LinkUp user").
- Files: profile_screen.dart, account_bloc.dart / account_repository.dart (load order only), new test.
- Mock before build (dark + light, like the real app).

## ayesha log (RMX3938 = ...d5d181c0, 18:39-19:39) - findings (VERIFIED from logs)
- Clocks of the 3 phones match within ~1 s.
- 19:10 call (8092): ayesha passed both invites (913 bytes, 19:10:12 / 19:10:16) to the ZTE; ZTE rang; ack lost when the group fell 19:10:15-16.
- 19:11:38 / :43 / :48 invites (c90f): ayesha received NOTHING from Sajjad 19:11:33-19:11:57, while ayesha -> Sajjad worked (ZTE call_end reached Sajjad 19:11:37.958 and 19:11:43.795). ayesha: 19:11:51 transport_heartbeat_timeout lan = Sajjad's phone sent nothing (not even heartbeats) for 15 s. Sajjad's phone had just made a Wi-Fi Direct group (19:11:34 bridge_create) and started a WD search (19:11:37). Why the send side stalled: NOT VERIFIED (likely the one 2.4 GHz radio busy).
- 19:11:56 / 19:12:01 invites (edbb): ayesha passed them on 19:11:57 / 19:12:01 into her Wi-Fi Direct link to the ZTE, but the ZTE's P2P had gone off at 19:11:54. ayesha found the link dead only at 19:12:11 (heartbeat timeout 15 s) -> invites lost.
- 19:15:37 / 19:15:55 invites: ayesha had no way to the ZTE -> "relay hold ... hold_ms=120000" x10, sent on 19:16:40 when she linked the ZTE again -> arrived late with their end (shown=no, correct).

## Map shows sumaira "through mesh" during the calls (user report) - VERIFIED
- Sajjad's PRESENCE for ZTE: Nearby 19:09:01-19:10:44, 19:11:32-19:12:34, 19:14:54-end (19:16:24). All 6 calls happened while it said Nearby.
- Why: Nearby = a mesh route exists (+20 s grace, presence_hub.dart:129). A dead hop two phones away is found only by the 15 s heartbeat (MeshTransportPolicy.kt:37), then withdrawn; learned routes live 90 s (MeshRouteDelta.kt:35) if no withdraw arrives. So the map stays "Nearby" 35-110 s after the way is gone.

## G (proposal v2, detailed in G_solution_295.md)
- G1 = honest map + honest call screen: no ack in 6 s -> drop the stale route for that friend (native), friend grey at once (no 20 s grace), call becomes an "away call" (existing CallNearbyWait: "Waiting for <name> to connect...", Nearby search for the friend, 60 s watchdog). Colour comes back only with proof from the friend (a packet from them or a verified direct link).
- G2 (quiet during call) WITHDRAWN: re-checked, it would not have saved any of the 6 calls (19:11:34 group start was 4 s before the call).
- C detailed: a host whose P2P was off < 10 s re-creates its group at once (today: idle -> 20 s search -> create = 29 s, 19:15:12 -> 19:15:41).

## H moved to TODO_296.md (user: own build after 295; checks only while LinkUp is open on screen).

## Mock D+E+F (13 Nov)
mocks/recovery_profile_295.html + _light.html (mocks/m295/make.py). E = 10 px gap. F = saved profile at once; shimmer only when nothing saved. Waiting for user OK.
Mock D+E+F: user said "Ok" (approved). Waiting for explicit "Build" for 295.

## BUILT (3.0.93+164)
- A: invite carries `ring_alive_295`; the caller repeats the invite every 5 s while the friend's phone rings (`ring_alive_repeat_295`); the called phone ends ringing as Missed 12 s after the last copy (`CALL_RING_ALIVE_LOST`) and sends call_end missed. Not for an older caller (no flag) or a call the server knows. 30 s ring timer unchanged.
- B: `CALL_INVITE_SENT ... route=none|unproven|ok` (ok = direct link, unproven = stored mesh way). Call screen: the existing away text "Waiting for <name> to connect…".
- G1: first invite on a stored mesh way + no answer in 6 s -> native `dropUnprovenRoute` (MeshUnproven295: route removed, same next hop ignored 15 s for adverts + route answers, neighbours asked again; a direct link is kept), PresenceHub.markUnproven (grey at once, no 20 s grace; colour back only on a packet from the friend or a direct link), routes read again, away call (Nearby search, 60 s). Log `CALL_ROUTE_UNPROVEN`, native `ROUTES unproven ...`.
- C: HostRehost295: host + Wi-Fi Direct off < 10 s -> plan `create reason=rehost_p2p` at once when the planner is idle (15 s window, one try; held create / back-off / busy rules unchanged). Log `group resume ... rehost=1`.
- D/E/F as planned (fast KDF same output; 10 px gap; saved profile first, shimmer only with nothing saved, username without @).
- Old tests changed: version lines in bundle223_logs_test / nearby_190_test only.
