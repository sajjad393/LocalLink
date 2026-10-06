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

## Existing worktree caution

The repository already has a large set of uncommitted user changes, including
changed/deleted tests and new transport files. Do not discard or reset unrelated
work while implementing this plan. Restore or replace deleted test coverage
before relying on regression results.

## Phase 1 — Establish the shared route policy

- Add `LocalRoutePolicyService` under connectivity.
- Consume native transport topology/events and Wi-Fi Direct connection events.
- Maintain a route state per peer: `searching`, `connecting`, `connected`, or
  `waitingForRoute`.
- Only expose direct routes after peer identity/authentication and connection
  are verified.
- Explicitly choose LAN first, then Wi-Fi Direct, then mesh.
- Emit diagnostics that explain route selection and rejection without exposing
  sensitive key material.

**Acceptance:** A peer has one observable route state, and a valid LAN route
is selected ahead of Wi-Fi Direct and mesh routes.

## Phase 2 — Use the policy for reliable messaging

- Use the shared policy before attempting direct delivery.
- Keep messages queued when no route exists and flush them when a route appears.
- Retain recipient-acknowledgement-only delivery status.
- Test route changes, app restart retry behavior, and duplicate prevention.

**Acceptance:** A message remains queued when no route exists and is delivered
once when a valid route appears, with delivered status set only by recipient
acknowledgement.

## Phase 3 — Use the policy for calls

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

- When LAN cannot reach a target peer, start Wi-Fi Direct discovery automatically.
- Establish the Wi-Fi Direct group/connection without normal-flow manual
  Find/Connect controls.
- Return to LAN automatically when it becomes usable.
- Keep manual controls and detailed topology counters only in diagnostics.

**Acceptance:** When LAN cannot reach a peer, Wi-Fi Direct discovery and
connection begin automatically; restored LAN becomes the selected route.

## Phase 5 — Verification and physical-device testing

- Unit-test route priority, stale routes, authentication requirements, and
  topology-event route transitions.
- Add integration tests for waiting messages, waiting calls, invite acknowledgement,
  and route promotion.
- Test two physical devices in both directions: LAN, Wi-Fi Direct fallback,
  mesh fallback, total route loss, and restoration to LAN priority.
- Run static analysis and the complete relevant test suite after the worktree is
  stable.

**Acceptance:** Two physical devices successfully exchange acknowledged messages
and complete calls over LAN, Wi-Fi Direct fallback, and mesh fallback; they wait
truthfully while all routes are unavailable and return to LAN priority when it
is restored.
