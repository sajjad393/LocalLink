# Cycle 3 - Release Validation Report (LinkUp 3.0.84+155)

Decision: **READY WITH KNOWN LIMITATIONS** (test release; debug key; dev plain-HTTP server)

## A. Baseline
- App: origin `390de01` (3.0.84+155 + bundle 270 CI fix). Backend: `86aa525` (bundle 267).
- APK: release build with `--dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true`, installed over the old app.
- Server: dev mode, `REQUIRE_TLS=false`, `TLS_AUTO=false`, `http://192.168.18.27:8080`.
- Phones (physical): Realme RMX3938 (Android 15, ...81c0), Realme RMX5303 (Android 16, ...19f3), TECNO BG6 (Android 13, ...237e).
- Evidence: 6 phone logs (12 Nov 13:15-13:33 and 13:33-13:58). The server window text was not sent.

## B. Test counts
| Kind | Result |
|---|---|
| Flutter unit/widget (sandbox) | 2707 pass (Cycle 2); 2711 pass / 0 fail after bundle 271 |
| Kotlin Gradle `:app:testDebugUnitTest` | 488 run / 0 failed |
| Go backend | 309 pass, race + vet OK |
| App CI run 43174431627 / Backend CI | green / green |
| Runtime test 264 (emulator + Go) | NOT RUN in Cycle 3 (manual trigger) |
| Physical phones | 3 phones, 8 checks (table below) |

Physical results (from the logs):
| Check | RMX3938 | TECNO | RMX5303 |
|---|---|---|---|
| 1 Open, 3.0.84, plain http (`ws://...:8080`, http_only=1, all server replies 2xx) | OK | OK | OK |
| 2 Add Contact default list | OK (offline list, nearby) | OK (server, 1.3 s) | OK (server, 0.8 s) |
| 3 Server ON chat both ways (all acked; LAN direct chosen) | OK | OK | OK |
| 4 Server OFF: LAN, then Wi-Fi Direct (2.4 GHz group) | OK | OK | OK |
| 5 Photo/file (sha checked) | receive OK; send NOT TESTED | send + receive OK | send + receive OK (9.8 MB over WD) |
| 6 Voice call both ways (voice played 88-100%) | OK (out to TECNO 36 s, to RMX5303) | OK | OK |
| 7 Kill + reopen (service stays, BG engine <1 s, server back in 3-4 s) | OK | OK (x3) | NOT TESTED (not required) |
| 8 Server back on (13:53): reconnect + sync + queued sends re-sent within 4 s | OK | OK | OK |

Call connect (invite -> accept): 3.4-5.9 s (one 15.6 s while the callee answered late). First voice 75-1294 ms.
The short 2-4 s calls at 13:28-13:30: the caller hung up on purpose (confirmed by the user).

## C. Gaps (not physically verified)
- Server relay between two app phones: every chat went LAN/WD direct (direct is chosen first), so the server-relay path was only used for the ZTE (unknown to this server).
- RMX3938 file send; ZTE not in this cycle; group voice (250); video STOPPED (by rule).
- Server window text not received.

## D. Defects
| ID | Pri | Status | Note |
|---|---|---|---|
| R268-1 | P0 | fixed (b923423) | release HTTP flag |
| S-1 | P2 | fixed (269) | seal downgrade only after proof |
| CI-K1 | - | fixed (270) | Kotlin tests in CI |
| D-271-1 | P3 | fixed (bundle 271) | one LateInitializationError on the first open after update (8 s timer beat an 8.2 s DB open); no user effect; self-recovers |
| R268-2 | P2 | open (investigation) | dev server plain HTTP |
| S-2 / T-2 / T-3 / Q-1 | P3 | open | from Cycle 1 |

No new defect from the retest window (13:33-13:58): 0 app errors (only vendor mali_gralloc / MediaCodec lines).

## E. Risks / known limitations
- Plain HTTP dev server (user rule "keep http"); release needs the dart-define flag.
- S1-4: plain inbound that claims to be a friend is accepted; strict link check is off.
- APK signed with the debug key (not for store release).
- Messages to a device the server does not know (ZTE) wait in the outbox ("sending") and are re-offered to the server on each reconnect; they deliver when that phone is nearby. This is by design, not a defect.
- Server PC clock was 79 min slow in run 1 (the app clamped it); after sync, no warning.
- Android 17 local-network permission (future).

## F. Modified files per repo (since 3.0.84 d4bfe39)
- App (bundle 270): `.github/workflows/app_ci.yml`, `android/app/build.gradle`, `android/app/src/test/kotlin/com/sajjad/locallink/mesh/MeshFinalRecipientDeliveryTest.kt`, `.../mesh/MeshRoutingTest.kt`, `docs/history/APPLY_app_270.md`, `docs/history/TODO_270.md`. No app code change.
- Backend: none since `86aa525`.
- Bundle 271: `lib/core/services/local_store.dart` (2 guards), `test/bundle271_store_guard_test.dart` (new), docs/history notes.

## G. Decision
**READY WITH KNOWN LIMITATIONS** for 3.0.84+155 as a test release on the user's LAN:
all 8 checks passed on at least 2 physical phones; no P0/P1 open; D-271-1 fixed in bundle 271 (tests only, no phone retest needed: no user-visible change).
Limitations: section C + E.
