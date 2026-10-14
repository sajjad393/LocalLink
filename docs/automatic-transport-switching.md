# LocalLink — Automatic LAN / Wi-Fi Direct / Mesh switching: implementation & verification

Covers the "Automatic LAN, Wi-Fi Direct & Mesh Switching" brief against the audited baseline (app @ d535831 + fixes bundles 1–2: mesh test suite green, route-table leak M1 fixed, roster crypto working).

## Architecture (what already existed — inspected, not replaced)

| Layer | Component | Role |
|---|---|---|
| Physical links (native) | `peerLinks` per peer: one TCP socket per transport (LAN & WFD concurrently) | both links kept alive; failure of one doesn't tear the other |
| Active-link choice (native) | `MeshLinkSelectionPolicy` (extracted to & unit-tested as a policy class — bundle 4) | strict total order: **LAN=20 > WFD=10** → recency → name (deterministic, no oscillation); emits `peer_transport_selected`/`fallback` events; standby link kept hot |
| Route policy (Dart) | `LocalRoutePolicyService` | LAN → WFD → mesh ordering; freshness window 90 s; `routeChanges` broadcast; fallback hook on none |
| Fallback (Dart) | `WifiDirectFallbackService` | bounded WFD discovery + single-eligible-peer auto-connect; 20 s per-address cooldown (now + periodic re-arm — see below) |
| Reliability | native mesh store-and-forward queue + Dart outbox | queues survive process restarts (AES-GCM-encrypted); recipient-ack settles outbox — exactly-once at app level |
| Calls | `CallSessionManager` + `_trySendPendingInvite` | waits for a verified route; retry ≥5 s; invite flushes when route appears |

##Requirement-by-requirement answer

1. **LAN first** — guaranteed at two layers: native link priority picks LAN when both links exist; Dart policy selects LAN first among authenticated `direct` peers. Verified by tests: `route policy integration LAN is preferred over Wi-Fi Direct and mesh`, native `recomputeActivePeer` ordering.
2. **Automatic WFD fallback** — `select()` returns WFD when LAN absent; `WifiDirectFallbackService` auto-connects when exactly one eligible peer appears (OS constraint: Android exposes no LocalLink id during WFD discovery — with ≥2 visible peers a manual tap is required; this is now stated in the Nearby UI). **New in bundle 3: periodic re-discovery** (45 s) while any peer waits — previously discovery was event-driven only and could stall forever after the OS silently stopped scanning or a connect attempt failed. Loops stop the moment any route appears (`onRouteAvailable` → `cancelWaiting`).
3. **Automatic mesh fallback** — policy selects an ACTIVE mesh route (within TTL) when no direct link; native `MeshRouter` forwards with hop-path recording and loop/hairpin drops (82/82 Kotlin unit tests).
4. **Automatic recovery** — when LAN reappears, the native layer promotes the LAN link (`peer_transport_selected` with `reason=transport_preference`) **without terminating the WFD link or the logical peer session**; queued packets flush; UI moves silently. Call invites retry and ship when any route arrives (`CALL_WAITING_FOR_ROUTE` → `CALL_INVITE_SENT`).
5. **Seamless UX** — no transport-selection dialogs exist; peers surface as Connected/Nearby/Waiting only; fallback records everything under `AppDiagnostics` + `AppLogger` (never user-facing toasts). "Connected" is asserted only after the roster handshake completes (native `authenticateClient`) and is re-proven per session, not assumed.
6. **Messaging & Files** — outbox + mesh queue preserved across switches (store-and-forward); in-flight file transfers resume from the lowest unacked chunk (SHA-256 per chunk); dedup suppresses re-deliveries at both the mailbox layer and the mesh sequence layer.
7. **Calls** — signaling is routed per-state (about-to-dial waits for a verified route); audio rides the same mesh packet paths (base64 frames over TCP in v1 — the audit's M5 note stands: media QoS during a mid-call switch is a known gap). **Deep-verify (bundle 4):** the switch semantics of live media were audited in code — live media (call_media / call_video_config / call_video_frame) is *structurally* excluded from durable store-and-forward: `isStoreForwardable` admits only `direct_message` and `direct_file_chunk`, so an unroutable media frame yields `MeshRouteResult.NO_ROUTE` → the existing `call_media_route_degraded` diagnostics event (never a false success, never a stale-replay burst later); ephemeral packets also use a separate seen-tracker so media dedup never pollutes the mailbox dedup. The active-link pick itself was extracted into `MeshLinkSelectionPolicy` and is now unit-verified (LAN priority, recency, deterministic tie-break; no flap).
8. **Connectivity management** — packet TTL+hop budget enforced at parse + forward; loop/hairpin drops; route caps (512 destinations / 4 per destination / 64 per next hop); the new retry loop is **bounded & self-draining**: it stops when waiters drain or the service is disposed.
9. **Permissions & failures** — WFD enable + permission requested once per waiting episode, only when an actual peer needs a route; denied/unsupported → `wifi_direct_fallback` diagnostics state recorded (`unsupported`, `permission_requested`, `ambiguous_peers`), no user nagging, and other paths (LAN beacons, mesh route ads) continue unaffected.
10. **True offline** — proven end-to-end with the server side powered off in the audit proofs (LAN pair, WFD pair, A→B→C mesh, A→B→C→D 3-relay); no internet || server requirement anywhere in the session path; mesh route-ad validation rejects anything that would fabricate a route (path must be consistent with the hop grammar, drops stale/future ads).

## Changes made (bundle 3 — Dart only, no wire/protocol change)

- `WifiDirectFallbackService`: added `_rediscoveryTimer` (`Timer.periodic(45s)`) armed whenever ≥1 peer waits; ticks skip in-flight attempts; **new** `cancelWaiting(peerId)` drains waiters; timer self-cancels when the set empties/disposed. Constructor gains injectable `rediscoveryInterval` (default 45 s) for tests — no other callers change.
- `LocalRoutePolicyService`: added `onRouteAvailable` hook fired exactly once per availability transition of a previously-unavailable peer; wired in `app_dependencies.dart` to `wifiDirectFallback.cancelWaiting` so re-discovery stops when LAN/mesh recovers.
- Tests: fallback gains re-arm + self-stop coverage (incl. late-arrival auto-connect, dispose semantics); policy gains transition-notification coverage.

## What was NOT done (deliberate)

- WFD multi-peer ambiguity remains manual (documented OS limitation, M3). No identity exposure was faked into discovery frames.
- No hysteresis timer added to `recomputeActivePeer`: LAN promotion is a strict improvement and duplicate delivery is already suppressed; adding damping seconds would show OSD benefit only for QoS class work (M5).
- No C1/C2 crypto (still the approval-gated design doc from bundle 2).
- No Go backend changes (separate system).

## Verification (run in sandbox, Flutter 3.47.7 stable)

```
flutter pub get          OK
flutter analyze lib test → 0 error-level findings (201 diagnosis-level, unchanged profile)
flutter test             → 224 / 224 (221 baseline + 3 new fallback/policy tests)
```

## Physical-device verification (not possible in this sandbox — plan remains binding)

Remaining for the 4-device matrix in `LocalLink_physical_validation_plan_2026-10-16.md` (5 checkpoints), to which this adds three switching scenarios:
- **S1 — LAN→WFD mid-chat:** A & B on LAN chat; cut A's client-AP (not whole WLAN); expect fallback discovery+connect of the sole WFD peer in ≤~1 min (45 s re-arm + connect), message delivery resumes, no duplicates (mailbox dedup).
- **S2 — LAN→WFD mid-call:** same setup in an active call; expectation honestly limited: audio gap while media path rebuilds (M5), signaling survives, call recovers without redial. Record callMedia frames per second as evidence.
- **S3 — WFD→LAN restore:** re-enable LAN; `peer_transport_selected` event (Diagnostics) proves promotion; verify no duplicate message/suppressed sequence, and that the retry loop stops once the route is verified (no more discovery diagnostics entries after `route_available`).

Kotlin mesh suite remains green: OK (82 tests). Physical runs are the only remaining evidence source for Wi-Fi-Direct-group formation on real devices.
