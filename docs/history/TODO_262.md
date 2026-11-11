# TODO 262 - fix every problem from the 11 Nov 19:57 logs (3.0.78 -> 3.0.79+150)

Status: BUILT as 3.0.79+150 (user: "Keep http not https" + "Continue", 11 Nov). Phase C was changed by the user: HTTP only (see C below).
Base: app `e03e680` (3.0.78+149). Backend: no change unless the server rows (D2) show a server bug.
Logs: `LOG_CHECK_2026-11-11_1957.md`.

## Build phases
| Phase | What | Files |
|---|---|---|
| A | Wi-Fi Direct groups on 2.4 GHz (ZTE can't see 5 GHz) | NearbyRadio.kt |
| B | Wi-Fi Direct switched off by the phone: pause, come back fast, unstick | NearbyRadio.kt, wifi_direct_fallback_service.dart |
| C | HTTP only (user: "Keep http not https") - no HTTPS, so no cert loop (Note 9 min) | tls_pin_243.dart, app_dependencies.dart |
| D | Server signs the phone out: stop the silent 401 loop, "Sign in again" | new session_dead_262.dart, locallink_api.dart, websocket_service.dart, home card |
| E | Show @username, not "My LinkUp phone" | display_label.dart |
| T | Tests + version | test/bundle262_test.dart, Kotlin test, version lines |

---

## A. ZTE alone after router off = C71's group is on 5 GHz (ROOT CAUSE, verified in logs + spec)
Facts:
- C71 log `WD_LINK ... freq=5745 band=5` for group ZcBmLT (19:53-19:54). With the router on, the group was `freq=2422 band=2.4` (it follows the router channel); with the router off, Android picked 5 GHz.
- ZTE Blade A35 (Z2453, Unisoc SC9863A) is Wi-Fi 802.11 b/g/n = 2.4 GHz only (gsmarena / mobgsm spec).
- That is exactly what the logs show on both days: C71 never in ZTE `WD_PEERS`, every ZTE join to C71's group `timed_out` (19:51:01, 19:51:13, 19:53:09, 19:53:55; 15:04 on 3.0.77), while ZTE joined TECNO's 2.4 GHz group BWTHzd at once (19:49:22).
- Code: `NearbyRadio.kt` createGroup (`WifiP2pConfig.Builder().setNetworkName(name).setPassphrase(..)`, ~line 609) and the friend group open (~line 648) set no band.

Fix:
- A1: both builders add `.setGroupOperatingBand(WifiP2pConfig.GROUP_OWNER_BAND_2GHZ)` (API 29+, same `SDK_INT >= 29` branch). Every phone can then hear and join every group.
- A2: log the band asked: `group create grp=.. band=2.4`. The existing `WD_LINK freq=` line proves it on the phone.
- A3: if `createGroup` fails with the band (some phones refuse), try once more without the band (`group create retry no_band reason=N`), so no phone loses Wi-Fi Direct.
- Not changed: joining (members follow the host), `lastGroupChangeAt` count (Call189Test needs exactly 5 - the retry reuses the same call path).
- Cost: 2.4 GHz is slower than 5 GHz for big files; voice and chat need very little. Groups were already 2.4 GHz whenever the router was on.

## B. Wi-Fi Direct switched off by the phone (TECNO 2x, ZTE 3x)
Facts:
- TECNO `WD_GROUP_LOST ... why=p2p_off` 19:49:54 (host, at router off) and 19:53:59 (member of C71's 5 GHz group). Then `group join failed reason=2` (busy) every 20 s and `tag publish failed reason=2`; app frozen in background 19:54:38-19:57:05.
- ZTE p2p_off 19:46:24, 19:52:43, 19:56:57, 19:57:13.
- Code: `NearbyRadio.kt` receiver sends `{type: state, enabled}` to Dart on every change, but `wifi_direct_fallback_service.dart _handleWifiEvent` ignores type `state` -> joins/creates keep firing while it is off (busy loop) and nothing restarts at once when it comes back. No log says when it came back.
- The app can't switch Wi-Fi Direct on (Android rule) - but it can stop wasting tries and be back within 1 s.

Fix:
- B1 (native log): `WD_P2P state=off` and `WD_P2P state=on off_s=N` (once per change).
- B2 (Dart): handle `state`:
  - off -> `_p2pOff262 = true`: no join / create / tag publish / pair while off (log `group wait why=p2p_off` once).
  - on -> clear cooling + join-fail memory (same as G2 `wifi_gone`), publish tags, start a search, evaluate the group now (`group resume why=p2p_on`).
- B3 (stuck busy): 3 `reason=2` failures within 60 s while the phone says Wi-Fi Direct is ON -> re-make the channel with the existing `reinit()` (already limited by `NearbyBackgroundPolicy.mayReinit`), log `WD_BUSY_REINIT n=3`.
- A (2.4 GHz) may also stop the TECNO drop inside C71's 5 GHz group - NOT VERIFIED; B1 will show it.

## C. Note off the server 9 min while it was up (HTTPS fallback)
Facts:
- 19:38:48 `TLS_243 result=fallback_http` (one HTTPS check failed while the server was starting; C71/TECNO got wss 10 s later).
- Pin off, but the socket kept `wss://..:8443` -> `cert_refused got=362bc3bf` x17 till the swipe-away 19:47:52.
- Code: `tls_upgrade_243.dart _tick` saves `active=false` and returns `fallback_http`; `tick()` calls `onHttpsOn` only for `on/ok`; `_wssSwitch255` (app_dependencies.dart) only moves ws->wss; `websocket_service.dart` reconnects with the saved `_url`.

Fix (CHANGED by the user, 11 Nov: "Keep http not https"):
- ~~C1-C3 (move the socket back to ws, 2 failed checks, retry HTTPS after 2 min)~~ - not built.
- C (built): the app uses plain HTTP / ws:// only.
  - `TlsPin243.httpOnly262` (set in `bindServerReach`, both engines, before the pin loads) makes `TlsPin243.active` false: `upgrade()` never moves a call to https, no certificate is ever checked.
  - The saved pin stays in settings (nothing deleted); a saved https address still goes back to http (`downgrade`).
  - `_startTls243` starts no HTTPS checks: log `TLS_262|mode=http_only`; a socket still on wss:// reconnects on ws:// (`WS_TLS_SWITCH|from=wss to=ws`).
  - Server: no change, HTTP 8080 stays on (the old plan "HTTP off after HTTPS everywhere" is dropped).

## D. ZTE signed out by the server, 401 for the rest of the hour, nothing shown
Facts:
- 19:42:19 ZTE account @alex linked; WS ws/wss OK; 19:42:53 server closed the socket; then 401 on everything (`CONTACTS_SYNC_FAILED unauthorized` x15, WS upgrade `401`, `MESSAGE_SYNC_FAILED unauthorized`) every 30 s till 19:57.
- Server keeps ONE token per phone (`devices.token_hash`); a login revokes all sessions of that phone (`auth.go` LoginAccount); `join_relay_222.go` can also make a token (`lockJoinToken222`) when a phone has no live session. What revoked ZTE at 19:42:53 is NOT VERIFIED.
- App: no code handles a dead own session (no 401 handler) -> endless retries, user not told.

Fix:
- D1 (app): `SessionDead262` counts 401 answers for THIS phone's own session (HTTP API + WS upgrade). 3 in a row with no success between -> dead:
  - log `SESSION_DEAD_262 n=3 first=<route>` once;
  - server calls back off to one try per 10 min (a success clears it);
  - Home card "Signed out from the server - Sign in again" -> password box -> normal login. Nearby / Wi-Fi Direct / mesh keep working the whole time (no logout, nothing deleted).
  - not shown for an admin console 401 (admin keys have their own flow).
  - files: `lib/core/network/session_dead_262.dart` (counter, back-off, `sessionWords` body rule: a 401 counts only when its body says the session/token is bad, not BAD_LOGIN), card `lib/core/widgets/session_dead_banner_262.dart` on Home.
- D2 new clue (found while building): the server sent an `admin_action` socket event to TECNO at 19:42:59 and to C71 at 19:43:00, 6 s after it closed the ZTE socket (19:42:53). The server sends that event only after something done on the admin console (Sign out a session, Remove phone, block, Wi-Fi rule, badge...). So the ZTE was most likely signed out from the admin console, not by an app bug. NOT VERIFIED - the `admin_audit` query in LOG_CHECK shows which action.
- D2 (server cause): read the rows in LOG_CHECK (auth_sessions / security_audit / admin_audit for `android-c891ac8ded16a834`, 14:40-14:45 UTC). If a second sign-in made by the app (e.g. the background publish stopped at 19:40:09, or a relay answer) did it -> fix that path too in this build. If nothing is sent -> D1 only, D2 stays open.

## E. "My LinkUp phone" shown instead of @alex
Facts: C71 19:55 screen. ZTE never set a name; the default phone name became the display name (server login also fills a new profile with the device name, `auth.go` profiles insert). `displayNameFromProfile` (lib/core/identity/display_label.dart) returns display_name when not empty, even a default label. `isDefaultPhoneLabel255` exists (admin pages only).
Fix:
- E1: `displayNameFromProfile`: display_name that `isDefaultPhoneLabel255` -> use `username` (shown as `alex`), else the old rule.
- E2: NameBook258 never remembers a default label as a person's name.
- A custom name you typed always wins (unchanged).

## T. Tests
- `test/bundle262_test.dart` (15): B (pause rule; off = no join/create/search; on = marks cleared + search + join at once; first ON no change), C (HTTP only: pin never used, set before load, no HTTPS checks), D (3x 401 -> dead once; success clears; admin key / login / wrong password ignored; one try per 10 min; new token ends it; HTTP client stops; socket rules; the card + dialog), E (default label -> username; name book).
- Kotlin `Band262Test.kt` (5): 2.4 GHz in both builders, retry without band (not on busy), off/on lines, the attach re-send, busy x3 in 90 s -> reinit; Call189Test count stays 5.
- Old tests: only version lines (`bundle223_logs_test`, `nearby_190_test`) unless a source-lock test needs a listed change (told in APPLY).
- Full Flutter suite + Kotlin suite. Compile/unit tests only - phone checks below.

## Phone checks (after Build)
1. Router off: C71 log `WD_LINK ... band=2.4`; ZTE joins C71's group (no `timed_out`), all 4 green.
2. If any phone logs `WD_P2P state=off`: the next `state=on` is followed within ~1 s by `group resume why=p2p_on`; no `reason=2` loop.
3. Every phone log: `TLS_262|mode=http_only`, sockets on `ws://..:8080/ws`, no `wss://`, no `cert_refused`.
4. ZTE: if the server signs it out again -> `SESSION_DEAD_262` + the card; sign in -> green.
5. C71 chat list shows `alex` for the ZTE.

## Not in this TODO
- Wi-Fi call gaps while a group changes (19:53:41, played 81-92%) - watch after A/B.
- Sync requests 250-370/h (was 900) - OK.
- Note `group dead` 19:42:15 (left a spare group while on the router) - harmless.
- Video (stopped).
