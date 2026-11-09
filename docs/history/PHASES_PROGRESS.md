# Build progress (all phases, freeze off) - working notes

## Done (in ws_app / ws_be wip commits)
- Phase 1 = 237: one chat per person (app + backend).
- Phase 2 = 236: offline account goes up by itself (lock mode, no pairing code for offline, wait card).
- Phase 3 = 238: block state never dropped (slow tries + link back + logs); rename sheet gone with 236 (3.2 done); old offline admin rows hidden + "Show hidden (N)" (app + web). Mock: mocks/mock_238_show_hidden.jpg
- Phase 4 = 239: 'yellow' = server connected ('gray' reads back too); LINK_AUTH_DAY line.
- Phase 7 = 242: letter circle in notifications with no picture; My QR on Add Contact + Settings card. Mock: mocks/mock_242_qr_notification.jpg

## Checked, skipped (need your input)
- Phase 5 (240) acks + link key: 11-09 logs: Note 60x pushed `keys contacts=0` (its new noshad account has no contacts), C71 shows 63x no_local_key + 22x no_shared_key. No ack drop visible. Needs: a log with both phones together for 1 h after noshad re-adds sajjad.
- Phase 6 (241) voice: calls play 97-99%; mic start 1.1-1.9 s; no proven cause. Needs: one call recorded on Wi-Fi with gaps + Realme log.

## Phase 8 - Bundles 243+244 (HTTPS, audit S3 A+B) - DONE
- Backend: `internal/tlsauto` makes a self-signed ECDSA P-256 cert once in `data/tls/` (LAN IPs + localhost, 5 years), reused after restart. HTTPS on `:8443` (`LOCALLINK_TLS_AUTO` default true, `LOCALLINK_TLS_ADDR`), HTTP 8080 stays. Any TLS failure only logs `TLS_AUTO_243 ...`; HTTP keeps working.
- Pairing info with `?nonce=..&proof=2` gets `proof_v=2`, `tls_port`, `tls_cert_sha256`, signed as `ll-pair-v2|id|fp|nonce|ts|port|sha`. Old apps (no proof=2) get v1 unchanged. Discovery adds `tls_port`.
- App: `lib/core/network/tls_pin_243.dart` (pin + `PinnedHttpOverrides243`, installed in both engines' main) and `tls_upgrade_243.dart` (20 s after start, then every 15 min). Uses the cert hash only from a v2 proof signed by the server key this phone ALREADY pinned; tries HTTPS `/health` first; only then switches. All server calls move through `SecurityPolicy.normalizeServerUri` (saved address stays plain http). WebSocket `wss://` gets its own HttpClient (test proved dart:io's shared WebSocket client skipped the rule).
- Falls back to HTTP by itself if HTTPS stops answering while HTTP answers (`TLS_243 result=fallback_http`).
- Decision (differs from TODO text): a changed certificate is refused at the TLS level; a NEW certificate is accepted only through a new proof signed by the pinned server key (no "Reset setup" needed, nothing silently trusted).
- You: open TCP 8443 in the Windows firewall on the server PC. Logs to look for: `TLS_243 result=on url=https://...:8443`.
- Tests: Go `pairing_tls_243_test.go`, `tlsauto_test.go`; app `test/bundle243_test.dart` (13, incl. a real TLS server + wss echo + wrong pin refused).

## Phase 9 - Bundle 245 (Security code, audit S7) - DONE (mock: `mocks/mock_245_security_code.jpg`)
- Chat ⋮ > Conversation info > "Security code" opens a new screen: 12 groups of 5 digits (same on both phones; SHA-512 x5200 Signal style, computed off the UI thread), a QR of the code, "Scan Ali's code" (match = verified, else "The codes don't match"), "Mark as verified" / "Remove verified mark".
- A friend's card with a NEW signing key was dropped with no word (a reinstalled friend never updated). Now (contacts only) it is kept aside: the chat shows "Ali's security code changed. Check", the sheet row turns red "Security code changed", the screen shows "Accept new code". The card is checked again before saving. Nothing automatic.
- Only a friend I marked Verified becomes "changed" (calls then refuse until Accept, the existing rule). Unverified friends: calls work as before.
- Kept in settings `key_change_245` (no DB change). Logs `KEY_CHANGE_245`, `KEY_ACCEPT_245`, `SECURITY_CODE_245`.
- Not done: "or proven by the server's key history" (Accept is always manual); Urdu text (app is English only).
- Tests: `test/bundle245_test.dart` (9).

## Phase 10 - Bundle 246 (tidy repos + key, S10) - DONE (your part: back up the key)
- You: back up `C:\Users\sajjad Ahmed\.android\debug.keystore` (USB + cloud).
- App `android/app/build.gradle`: a release build signed with the debug key prints a clear WARNING (only for release tasks). Signing itself unchanged.
- Both repos: old `APPLY_*.md` / `TODO_*.md` moved to `docs/history/`.
- Backend: deleted unused `web/admin.html` (admin pages are embedded `adminweb`), `test_output.txt`, `tmp_test.ps1`; moved `generate_dev_cert.sh`, `diagnose-locallink.ps1` to `tools/`.
- A zip can't delete files: the final APPLY has the exact PowerShell Remove-Item list for the old places.

## Phase 11 - Bundle 247 (video issue, 193 logs) - checked; logs-only change
- What the 193 logs show (C71 + ZTE, 11-05..11-07): 10 plays. 2 "paused" lines at 52852/52879 ms and 16679/16734 ms were really the END (the stop comes a few ms before the length). One stop at 1347 ms came 6 ms before the player was released = the viewer was closed. One stop at 531 ms (11-07 03:13:13, 5.4 MB 480x848) with the player kept open 17 s - the log can't tell if you tapped pause or the player waited for data. No error lines, no codec failure.
- So: no proven cause -> no playback change (your rule "Video: no fix unless the logs prove it").
- Change (log only, `chat_video_controller.dart`): reason=user / buffering / end (300 ms tolerance) / paused, `VIDEO_PLAY_RESUME`, and reason=closed when the viewer closes while playing.
- Needs: one log after this build where a video stops early (say the time).
- Tests: `test/bundle247_test.dart` (2); old 193 test unchanged and passing.

## Phase 12 (248) - video call back: DONE
- Camera button back in the in-call pill, only for a connected nearby call (WD/LAN). Receive side unchanged. Dart only.
- Mock `mocks/mock_248_video_button.jpg`; `TODO_248.md`; 2 new tests; 174/146/video_ui tests pass.
- Needs phone test: ZTE 2 GB camera memory, WD bandwidth with video.

## Phase 13 (249) - mesh voice A->B->C: ALREADY BUILT (no code)
- Bundles 158/159/167/192 already do it: sealed end to end, B forwards without decoding, B limited to 2 calls / 160 frames/s.
- Logs: 10 calls `path=mesh hops=2`, one ran 2:21 at 97% played. `TODO_249.md`.
- Choice for the user: keep maxHops 8 (advice) or 2.

## Phase 14 (250) - group voice: PLAN + MOCK only
- Needs a new native mixer (Kotlin, can't compile here). `TODO_250.md`, `mocks/mock_250_group_call.jpg`.

## Phase 15 (251) - server voice relay (P9): SERVER BUILT, app = plan + mock
- Backend `voice_relay_251.go` + `Hub.TrySendTo`; 5 new tests; full Go suite ok. Commit "wip 251 backend (voice relay)".
- App part needs Kotlin. `TODO_251.md`, `mocks/mock_251_internet_call.jpg`.

## Phase 16 - ZTE day: USER (skipped, listed)

## Phase 17 - how 3.0.63 got onto the C71: EXPLAINED (no code)
- 3.0.63+134 = bundle 223 (commit 7712558, built 6 Nov 00:05).
- C71 log 6 Nov 07:51 still shows 3.0.62+133. Next log starts 6 Nov 19:36:17 with 3.0.63+134, a NEW install folder
  (`/data/app/~~wCyVSPAZ...` vs `~~NH9iA4M3...` in the morning) and `ProfileInstaller Installing profile` at 19:36:23
  = Android updated the app just before 19:36, and LinkUp was not running 18:39-19:36.
- LinkUp can't install itself (Android always asks the person). The C71's `SHARE_APP` lines show it SENDING its APK
  to other phones (`apk done phone=1`), never receiving one. So it was a normal manual update (APK file / Android Studio) on 6 Nov ~19:35.
- Nothing wrong -> no code.

## Phase 18 - 228 idea: USER (skipped, listed)
## Phase 19 - HTTP off: needs go-ahead after all phones run HTTPS (skipped, listed)
## Phase 20 - structure cleanup: not done (each type move rewrites imports + old source-check tests; against "stable, no new issues")

## Phase 21 (254) - admin fixes from the 9 Nov screenshots: BUILT (app only)
- 21.3 "reached the phone · it must reach the server once": a phone that can't check the admin key yet sends a `admin_act_seen` note (why=no_trust), keeps the card, and checks it again when it trusts the server.
- 21.1 a newer Block/Unblock or Off/Active for the same person replaces my older pending card (signed cancel, tag "Replaced"; other phones see "Cancelled").
- 21.11 an Off/Active older than the last one done is closed as "already".
- 21.2 chat request: two accounts on the same phone are refused (red note + error); picker shows "Me (name)" + Me tag, @username and "old account".
- 21.12 a phone with no messages answers "empty" (no receipt); if ALL phones are empty the request closes as "No messages".
- 21.4 admin screen status now uses the same live status as the chat header (PresenceHub) first; blocked filter also matches by the owner's user id.
- 21.5 map "You" avatar uses your real name/photo (label stays "You").
- 21.6 card clips itself (padding included) -> "Link paths" L no longer cut.
- 21.8 "No server" bar pinned under the title (never scrolls away).
- 21.9 pending rows that can be stopped show "Tap to cancel". Mock `mocks/mock_254_actions.jpg`.
- 21.7 no change (server line is static by design). 21.10 needs logs (skipped).
- Tests: `test/bundle254_test.dart` (21 tests). Old test setup change only: `test/support/b220_fakes.dart`.
