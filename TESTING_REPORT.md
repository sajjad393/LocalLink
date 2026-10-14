# LocalLink — Widget → Alpha → Beta test campaign

Date: 2026-10-14 · Flutter 3.47.x stable · `flutter test` headless in a build sandbox
(no Android SDK / emulator attached — device-level steps are listed as owed).

## Summary

| Phase | Scope | Result |
|---|---|---|
| **1. Widget** | 23 new widget tests over the reference-design surfaces (splash, bubbles, composer, group chat, error toast) + full suite | **144/144 passing** |
| **2. Alpha** | In-sandbox internal validation of the post-E2E-removal contract: roster wiring, plaintext transport, malformed traffic | **4/4 passing** |
| **3. Beta** | Soak/stress: 300-message burst, duplicate storm, 150-message outbox drain | **3/3 passing** |
| Static | `flutter analyze` | **0 errors** (198 lints, pre-existing baseline 199–200) |
| Coverage | `flutter test --coverage` | **30.3 %** (2066/6821 lines) |

Commands: `flutter test` (all) · `flutter test test/alpha_smoke_test.dart` ·
`flutter test test/beta_soak_test.dart` · `flutter test --coverage`.

## Phase 1 — Widget tests (new files)

| File | Tests | Covers |
|---|---|---|
| `test/splash_screen_test.dart` (existing) | 2 | brand splash, reduced-motion path |
| `test/error_toast_test.dart` | 7 | `friendlyErrorMessage` mapping (socket/timeout/401/403/404/409/413/429/5xx/unknown/null) and that raw exception text never surfaces; floating error-container toast |
| `test/message_bubble_test.dart` | 5 | outgoing = brand gradient + white text + right alignment; incoming = neutral surface; reaction chips with counts; long-press action; body exposed via semantics |
| `test/composer_test.dart` | 5 | gradient circular send button; tap and keyboard-send actions; white progress indicator + input lock while sending; removable attachment chips |
| `test/group_chat_screen_test.dart` | 6 | gradient group avatar + member count; animated empty state; "Today" divider; own messages in gradient bubble; compose→send→repo call; send failure = friendly toast, never raw error |
| `test/group_design_test.dart` (existing) | 7 | group avatar/date divider/member tile/create dialog |

Notable: widget tests avoid `pumpAndSettle` where Lottie loops would hang; they
pump fixed frames instead.

## Phase 2 — Alpha (internal validation, `test/alpha_smoke_test.dart`)

Alpha bar after removing device-to-device E2E content crypto: the peer **roster**
must reach the native transport, bodies must travel **plaintext**, and the
reliability guarantees must hold.

1. **Roster wiring** — `ReliableMessagingService.start()` publishes
   `knownPeers` (from `store.localDevices()`) to the transport; **revoked
   devices are excluded**. (This test found and fixed a gap: `FakeStore` never
   overrode `localDevices()`, so the harness had silently skipped the roster
   path — now the whole suite exercises it.)
2. **Plaintext end-to-end** — queued message drains once a route exists with
   the raw body in the wire payload (no ciphertext/`network_body` field), stays
   in the outbox until acknowledged, and ack clears the retry pipeline with no
   duplicate re-send.
3. **Inbound path** — stored once, acked once, emitted once; mesh duplicate
   suppressed in the UI.
4. **Malformed traffic** — non-JSON payloads, unknown types and unknown events
   are ignored without crashing; the service stays alive and delivers the next
   valid message.

### Owed on device (alpha checklist)

The sandbox has no Android SDK/emulator, so these remain for the alpha flight:

```bash
flutter build apk --debug        # or: flutter run -d <device>
./gradlew :app:testDebugUnitTest # native Kotlin mesh/transport unit tests
```

- [ ] Two physical devices pair; contact + nearby discovery works.
- [ ] Direct message LAN → delivered tick; kill Wi-Fi → Wi-Fi Direct fallback → message still delivers.
- [ ] Group create → group message to 2+ members.
- [ ] Airplane mode → messages queue; route restored → queue drains in order.
- [ ] Call invite rings only after invite ack (call flow untouched by this change but shares the transport).
- [ ] No raw exception text visible anywhere in the UI (toast policy).

## Phase 3 — Beta (soak, `test/beta_soak_test.dart`)

| Scenario | Volume | Asserted |
|---|---|---|
| Inbound burst | 300 messages | all stored, one UI event each, unique ids, exactly 300 acks, drains in < 30 s (guards regressions) |
| Duplicate storm | 60 ids × 2 deliveries | 60 stored, 60 UI events, every id acked, ack volume ≤ 2× bound |
| Outbox burst | 150 queued sends | all sent exactly once, unique ids, all remain `sending` until acked |

Finding: duplicates are **deliberately re-acknowledged** (only the UI emit is
suppressed) so a sender that lost an ack recovers — documented in the test so
nobody "fixes" it into a regression.

### Owed on device (beta checklist)

- [ ] Real beta cohort (5–10 users, mixed Android versions/vendors).
- [ ] Soak run: leave two devices idle 24 h; verify no ANR/crash and stable memory.
- [ ] Battery/network profile check of the foreground transport service.
- [ ] Cross-check message counts under intermittent Wi-Fi (airplane-mode toggling).
- [ ] Verify SQLCipher DB + local attachment at-rest encryption still applied (post-removal these layers were kept).

## Observations / follow-ups

- Send failures surface **both** the inline error row and the floating toast
  (friendly copy in both). Acceptable, but candidate for a UX polish pass.
- Coverage is 30.3 %: strongest in services/blocs, weakest in models and
  notification internals — the next coverage targets if we want a floor.
- Native Kotlin unit tests were updated for the plaintext envelope but cannot
  run in this sandbox; they must be executed in CI or on a dev machine
  (`./gradlew :app:testDebugUnitTest`).
