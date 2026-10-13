# LocalLink Transport Findings and Next Steps

## Inspection summary

The native transport foundation already exists:

- Android includes LAN beacon discovery, TCP connections, peer authentication,
  Wi-Fi Direct integration, mesh routing, and topology events.
- Messages are persisted in an outbox, retried through `flush()`, and are
  marked delivered from recipient acknowledgements.
- Calls use native local signaling and media transport.

The missing part is one shared, per-peer route policy that coordinates the
existing mechanisms with this priority:

```text
LAN -> Wi-Fi Direct -> mesh
```

## Confirmed gaps

- `LocalRouteResolver` is used only by calls. Messaging does not use the same
  route policy.
- The resolver classifies routes but does not select, observe, retry, or
  promote routes.
- A `DISCOVERED` peer is currently accepted as a usable direct route. Calls
  should require an authenticated, connected peer.
- A call fails immediately when no local route exists. It should enter a
  cancellable waiting/connecting state and retry as topology changes.
- An outgoing call is marked `ringing` before its invite has been confirmed as
  received. It should ring only after invite acknowledgement.
- Wi-Fi Direct discovery and connection are still initiated from manual UI
  controls. There is no automatic LAN-failure -> Wi-Fi Direct fallback.
- LAN preference is not enforced centrally when several paths can reach the
  same peer.
- Physical-device validation has not yet demonstrated LAN, Wi-Fi Direct, or
  multi-hop messaging/calls end to end.

## Known legacy piece: `LocalRouteResolver`

`lib/features/calls/data/services/local_route_resolver.dart` predates the
shared route policy. It constructs its own private `LocalRoutePolicyService`
instance instead of consuming the application-scoped one, and nothing in the
app wiring uses it anymore (only its own test does). Treat it as a removal
candidate; do not build new work on it.

## Phase 1 — Establish the shared route policy

**Status:** Implemented in code and covered by focused unit tests. Physical-device
validation is still required before this phase is complete.

- Add `LocalRoutePolicyService` under connectivity.
- Consume native transport topology/events and Wi-Fi Direct connection events.
- Maintain a route state per peer: `searching`, `connecting`, `connected`, or
  `waitingForRoute`. Implemented as the fuller `LocalTransportState` state
  machine (`starting`, `searching`, `waitingForRoute`, `available`,
  `connected`, `stale`, `unavailable`) in
  `lib/features/connectivity/domain/local_route.dart`; write future tests and
  docs against those names.
- Only expose direct routes after peer identity/authentication and connection
  are verified.
- Explicitly choose LAN first, then Wi-Fi Direct, then mesh.
- Emit diagnostics that explain route selection and rejection without exposing
  sensitive key material.

**Acceptance:** A peer has one observable route state, and a valid LAN route
is selected ahead of Wi-Fi Direct and mesh routes.

## Phase 2 — Use the policy for reliable messaging

**Status:** The shared-policy integration is implemented. Integration and
physical-device verification are still required.

- Use the shared policy before attempting direct delivery.
- Keep messages queued when no route exists and flush them when a route appears.
- Retain recipient-acknowledgement-only delivery status.
- Test route changes, app restart retry behavior, and duplicate prevention.

**Acceptance:** A message remains queued when no route exists and is delivered
once when a valid route appears, with delivered status set only by recipient
acknowledgement.

## Phase 3 — Use the policy for calls

**Status:** The waiting and invite-acknowledgement flow is implemented. Integration
and physical-device verification are still required.

- Use the same shared policy as messaging.
- If no route exists, show cancellable `connecting/waiting` instead of rejecting
  the call.
- Retry when topology changes.
- Do not change an outgoing call to `ringing` until invite delivery/acknowledgement.
- Re-evaluate the route after failures and prefer a restored higher-priority
  path.

**Acceptance:** Calls wait cancellably for a route, ring only after the invite
reaches the recipient, and use the same route priority as messaging.

## Phase 4 — Automate Wi-Fi Direct fallback

**Status:** Automatic discovery and safe single-peer connection are implemented.
Multiple nearby peers remain a diagnostic/manual-selection case until discovery
can provide a verified LocalLink device ID.

**Physical-device evidence (2026-10-07):** `RMX5303` and `Z2453` both ran the
foreground transport service, automatically formed a Wi-Fi Direct group, and
established LocalLink TCP connections on ports 8988 and 8989. A previous
foreground-service startup crash on `Z2453` was fixed and the corrected debug
APK was installed on both devices. Message acknowledgement and call validation
remain pending.

- When LAN cannot reach a target peer, start Wi-Fi Direct discovery automatically.
- Establish the Wi-Fi Direct group/connection without normal-flow manual
  Find/Connect controls.
- Return to LAN automatically when it becomes usable.
- Keep manual controls and detailed topology counters only in diagnostics.

**Acceptance:** When LAN cannot reach a peer, Wi-Fi Direct discovery and
connection begin automatically; restored LAN becomes the selected route.

## Phase 5 — Verification and physical-device testing

**Status:** Integration tests implemented and passing; static analysis and the
full suite are green. Physical-device message-ack and call validation remain.

- Unit-test route priority, stale routes, authentication requirements, and
  topology-event route transitions.
- Add integration tests for waiting messages, waiting calls, invite acknowledgement,
  and route promotion. **Done (2026-10-13):**
  `test/transport_phase5_integration_test.dart` (11 tests, shared fakes in
  `test/support/phase5_fakes.dart`) drives the real `LocalRoutePolicyService`,
  `ReliableMessagingService` and `CallSessionManager` through all four flows,
  including duplicate suppression and delivered-only-by-recipient-ack.
- While adding those tests, one product fix landed: the direct-delivery-ack
  path now removes the outbox entry (previously it set `direct_delivered`
  and left a stale row, since `outbox(pendingOnly: true)` already excludes
  those entries).
- Test two physical devices in both directions: LAN, Wi-Fi Direct fallback,
  mesh fallback, total route loss, and restoration to LAN priority. Partially
  evidenced (see Phase 4); message acknowledgement and call runs still owed.
- Run static analysis and the complete relevant test suite after the worktree is
  stable. **Done (2026-10-13):** `flutter analyze` — no errors (29 warnings /
  171 info pre-existing lint); `flutter test` — 89/89 passing on Flutter
  3.47.7 stable.

**Acceptance:** Two physical devices successfully exchange acknowledged messages
and complete calls over LAN, Wi-Fi Direct fallback, and mesh fallback; they wait
truthfully while all routes are unavailable and return to LAN priority when it
is restored.

## App-flow fixes (2026-10-14)

- **Auto-contact:** exchanging a direct message now auto-adds the peer to the
  local contacts (keyed by directory user id), both when sending and when
  receiving. Peers that cannot be resolved to a directory user are skipped.
- **Duplicate conversations fixed:** the conversation list collapses multiple
  devices of the same directory user into a single tile (the online, most
  recently seen device represents the user). Devices with no directory
  mapping remain individual entries. Covered by
  `test/home_bloc_dedupe_test.dart` and the messaging integration tests.
- **Test totals:** `flutter test` — 96/96 passing. `flutter analyze` — no
  errors (29 warnings / 171 info pre-existing lint).

## Brand identity — splash & launcher icon (2026-10-14)

- **Launcher icon:** adaptive icon (`mipmap-anydpi-v26` + per-density
  `ic_launcher_foreground.png`) with the brand gradient background; legacy
  `ic_launcher` / `ic_launcher_round` tiles for pre-API-26; `monochrome` layer
  included so themed icons tint correctly. Wired via
  `android:icon` / `android:roundIcon` in the manifest.
- **Native splash:** `LaunchTheme` now paints `drawable/launch_background`
  (hero gradient centre with the centered `splash_logo` bitmap). Android 12+
  uses `values-v31/styles.xml`: solid brand blue + glyph system splash, then
  the gradient window until Flutter's first frame.
- **Flutter splash:** `LocalLinkSplashScreen` replaces the bare spinner during
  startup — same hero gradient, same logo asset, wordmark + tagline, short
  non-repeating entrance that is skipped when the platform disables animations.
- **Assets are generated, not hand-made:** `tool/generate_brand_assets.py`
  deterministically writes all icon/splash PNGs from the
  `LocalLinkBrand` gradient tokens (`#1E5BFF -> #23E0D8`). Re-run after brand
  token changes: `python3 tool/generate_brand_assets.py`.
- **Tests:** `flutter test` — 107/107 passing (adds `test/splash_screen_test.dart`).
  `flutter analyze` — no errors (199 total, pre-existing lint baseline).

## Group experience pass (2026-10-14)

- **Group avatars:** new shared `GroupAvatar` (brand-gradient circle, white
  groups glyph) now used by the home conversation rows, the group chat app
  bar, and the group details header, so groups read as one visual family.
- **Group chat:** date separators use the messenger pill divider
  (`MessengerDateDivider`, "Today" / d/m/y) instead of a stock Chip; empty
  state shows the bundled inbox Lottie; pick/send failures surface through the
  friendly error toast (no raw exceptions).
- **Group details:** gradient avatar header, `LocalLinkLoadingView` /
  `LocalLinkInlineError` states, add-member dialog uses `AccountAvatar`, and
  the remove-member confirmation is styled as a destructive action.
- **Create group dialog:** account avatars on member rows, and the Create CTA
  is the brand gradient pill (disabled until a name is entered).
- **Tests:** `flutter test` — 114/114 passing (adds `test/group_design_test.dart`).
  `flutter analyze` — no errors (199 total, pre-existing lint baseline).

## Device-to-device E2E content crypto removed (2026-10-14)

Scope (user-confirmed): remove the X25519/HKDF/AES-GCM content-crypto layer
between devices and the key-exchange plumbing it needed. **Kept:** SQLCipher
database encryption, encrypted local attachment storage, and Keystore-backed
secure storage (all at-rest). Clean break on old data — no migration shims.

- **Wire protocol:** transport lane AES-GCM removed. Frames carry the canonical
  `MeshPacket` JSON as plaintext `payload`; handshake bumped to
  `transport_auth_version=3` (hello/challenge/auth_ok, no keyed proof).
- **Peer keys → peer roster:** the native service now takes a `knownPeers`
  device-id roster (routing/admission gating only). Dart derives the roster
  from `store.localDevices()` (revoked devices excluded) via
  `PeerTransportContract.configure(knownPeers:)` /
  `updateKnownPeers()`.
- **Removed native pieces:** mesh origin-auth (HMAC) + `origin_auth` wire
  field, hop AEAD helpers and key-epoch policy, route-advertisement auth,
  unused `DirectFileSecurity.kt`; deleted their unit tests; updated routing,
  fuzz, TTL, property, chaos and adversarial harnesses to the plaintext
  envelope. Queued-packet and state-blob Keystore encryption retained.
- **Removed Dart pieces:** `IdentityCryptoService` peer-key cache/derivation
  (`deriveSharedKey`, `cachePeerPublicKeys`, `cachedPeerPublicKeys`,
  `derivePeerKeys`, key-history caches), the identity-key publish/fetch sync
  loop, QR identity-fingerprint verification, and the peer-key change check
  in the directory repository. `ReliableMessagingService` no longer depends on
  the crypto service.
- **Copy:** account/admin surfaces no longer claim message encryption
  ("Encryption identity" -> "Identity key", notification note reworded).
- **Verification:** `flutter test` — 114/114 passing. `flutter analyze` — no
  errors (197 total). Native Kotlin unit tests updated accordingly (run with
  Gradle on a machine with the Android SDK).

## Widget → Alpha → Beta test campaign (2026-10-14)

- **Widget (Phase 1):** +23 widget tests — `error_toast_test` (friendly-message
  mapping, no raw exceptions), `message_bubble_test` (gradient outgoing /
  neutral incoming, reactions, semantics), `composer_test` (gradient send
  button, send actions, sending lock, chips), `group_chat_screen_test` (avatar,
  member count, empty state, divider, send + failure toast).
- **Alpha (Phase 2):** `alpha_smoke_test` — roster published to the native
  transport with revoked devices excluded; plaintext wire body; ack-verified
  delivery with no duplicate re-send; malformed/unknown traffic safely ignored.
  Also fixed `FakeStore` to implement `localDevices()` so the harness exercises
  the real roster path.
- **Beta (Phase 3):** `beta_soak_test` — 300-message inbound burst (stored /
  emitted / acked exactly once), duplicate storm (UI-dedupe with bounded,
  intentional re-acks), 150-message outbox drain.
- **Totals:** `flutter test` — 144/144 passing. `flutter analyze` — 0 errors
  (198 total). Coverage 30.3% (`flutter test --coverage`).
  Full report and on-device checklists: `TESTING_REPORT.md` (device-level
  alpha/beta steps are owed — no Android SDK in the sandbox).
