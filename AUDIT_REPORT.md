# LocalLink — Detailed Project Audit Report

**Date:** 2026-10-14 · **Auditor:** Arena Agent (autonomous senior-engineer pass)
**Codebase state:** workspace tree rebuilt from `phase5_work.patch` (122 files) applied on
upstream `main` @ `1786dbd` — after the 8th observed silent workspace reset. The patch is the
authoritative artifact; the workspace is a working copy.
**Method:** static analysis (`flutter analyze`), full test suite + coverage (`flutter test --coverage`),
manual code inspection of every audit target, and structural inventory. Native Kotlin was audited
by inspection only (no Android SDK in the audit environment).

---

## 1. Executive summary

LocalLink is a **local-first, offline-capable messaging/calling app**: Flutter UI + Dart
services over a **native Kotlin transport service** that does LAN discovery/sockets,
Wi-Fi Direct, and multi-hop mesh routing with store-and-forward. A backend API
(39 endpoints) handles auth, directory, sync, groups, admin, and recovery.

**Overall verdict: the project is in good, coherent shape.** Architecture is layered and
consistent, reliability mechanics are real (outbox + ack + retry + backoff + dedupe +
store-and-forward), the at-rest encryption stack is intact and well-wired, and the quality
gates pass (0 analyzer errors, 144/144 tests). The recent removal of device-to-device content
crypto was executed cleanly and left no dangling references.

**Main audited risks, in order:**
1. **Release-build HTTPS requirement** — the app deliberately refuses `http://` and
   cleartext traffic in release builds. The backend *must* serve HTTPS on a
   private/local host or release APKs cannot connect at all. (Deployment prerequisite.)
2. **Coverage gaps in the highest-risk code** — `LocalStore` (2.3k LOC, the outbox/messages
   database) sits inside `core/services` at **1.2% coverage**; `files` 1.4%,
   `notifications` 7.5%. The reliability path is tested *through* fakes, not directly.
3. **Friendly-error policy only partially adopted** — 10 UI sites across 9 files still print
   prefix-stripped exception text (3 files mix both patterns).
4. **No CI** — no `.github/` workflows; tests/analyze run manually only.
5. **Device-level alpha/beta testing is owed** — the sandbox cannot build/run the APK.

---

## 2. System inventory (measured)

| Dimension | Value |
|---|---|
| Dart source | **220 files, 28,434 LOC** (`lib/`) |
| Features | 13 (`messaging` 2,969 · `calls` 2,610 · `connectivity` 2,075 · `directory` 1,963 · `admin` 1,726 · `recovery` 1,403 · `account` 1,354 · `groups` 1,239 · `files` 1,200 · `home` 1,138 · `authentication` 775 · `transfer` 260 · `notifications` 181) |
| Screens | 43 |
| Blocs/Cubits | 20 |
| Native Kotlin (main) | 27 files, 5,975 LOC |
| Native Kotlin (tests) | 20 files, 2,282 LOC |
| Tests (Dart) | 45 files, 4,032 LOC — **144 tests, all passing** (14.2% test:lib LOC ratio) |
| Local persistence | SQLite **SQLCipher-encrypted**, schema v21, **26 tables** |
| Backend API | **39 unique endpoints** across 47 call sites |
| Android permissions | 15 (network/Wi-Fi/BT-nearby, camera, mic, FGS×3, notifications, full-screen intent) |
| Lint | 0 errors · 27 warnings · 171 info (198 total; historical baseline 199–200) |

---

## 3. Architecture

```
┌─ Flutter UI (43 screens) ─────────────────────────────────────────────┐
│  Material 3 + brand design system (gradient brand, Lottie, toasts)    │
├─ 20 Blocs/Cubits (flutter_bloc + equatable) ──────────────────────────┤
├─ Feature services & repositories ─────────────────────────────────────┤
│  ReliableMessagingService · CallSessionManager · FileTransferService  │
│  GroupMessagingService · LocalRoutePolicyService · PresenceService …  │
├─ Core adapters ───────────────────────────────────────────────────────┤
│  LocalStore (SQLCipher) · LocalLinkApi (REST) · WebSocketService      │
│  SecureStorageService (Keystore) · SensitiveFileProtection (AES-GCM)  │
│  SecurityPolicy (local-only hosts, HTTPS-in-release) · AppLogger      │
├─ Platform channel ────────────────────────────────────────────────────┤
│  locallink/wifi_direct_transport  (MethodChannel + EventChannel)      │
└─ Native Kotlin: LocalLinkTransportService (foreground service) ───────┘
   ├─ LAN transport (TCP :8989, UDP discovery :8990, beacons)
   ├─ Wi-Fi Direct (TCP :8988, group owner handling)
   ├─ MeshRouter (TTL/hop budget, max 8 hops, route table + advertisements)
   ├─ Store-and-forward queue (age-limited, Keystore-encrypted at rest)
   ├─ Replay/duplicate tracking (seen-packet trackers, ephemeral + persistent)
   └─ Calls: Opus (MediaCodec) audio, H.264 video over the same router
```

**Data flow (direct message):** UI → ChatBloc → MessagingRepository →
`ReliableMessagingService.send()` → outbox (SQLCipher) → route policy
(LAN → Wi-Fi Direct → mesh priority) → native transport → peer; delivery state is
flipped **only** by the recipient's `direct_delivery_ack`, which returns through the
transport event stream and clears the outbox entry.

**Route selection invariant (verified in tests):** a direct route requires an
*authenticated + connected* peer — a merely `DISCOVERED` peer is never usable.

---

## 4. Feature-by-feature audit

| Feature | State | Evidence / notes |
|---|---|---|
| **Messaging (direct)** | ✅ Solid | Outbox + ack + retry/backoff + rate-limit cooldown; duplicate suppression; plaintext body over local transports per decision; 36.6% covered |
| **Groups** | ✅ Solid | Group outbox, member management, owner-gated add/remove, reactions; 61.8% covered (best-covered business feature); full design pass applied |
| **Calls** | ✅ Good | Ring-after-invite-ack, cancellable waiting state, route fallback mid-call; Opus via MediaCodec; H.264 video; app-level media encryption intentionally disabled (documented in code); 34.8% covered |
| **Files** | ⚠️ Adequate | Direct chunked transfer, progress/resume/cancel, sensitive-file lifecycle (AES-GCM at rest + view copies with TTL); **1.4% covered** |
| **Connectivity/routing** | ✅ Strong | `LocalRoutePolicyService` central priority policy; Wi-Fi Direct fallback automation; topology events; 64.1% covered |
| **Directory/contacts** | ✅ Good | Signed directory profiles (Ed25519), autoadd-on-message, dedupe of multi-device users; QR add flow; trust states on devices screen |
| **Account/identity** | ✅ Good | X25519 identity keys retained for **identity/signing** (not content crypto); key rotation with server history; Keystore storage |
| **Recovery/restore** | ✅ Good | Recovery codes with idempotency keys; restore manifest + encrypted identity-backup envelope; 1,403 LOC |
| **Admin** | ✅ Good | Separate admin capability/view-mode, admin session model, permissions tests; server-side role checks asserted by contract |
| **Transfer** | ✅ Adequate | Device-to-device account transfer flow (scan/confirm/complete); smallest feature (260 LOC) |
| **Auth** | ✅ Good | Register/login/logout/me, token in Keystore; one analyzer warning (`override_on_non_overriding_member`) worth a look |
| **Notifications** | ⚠️ Adequate | Action receivers (call + message), policy tests exist; notification internals at 7.5% coverage |
| **Home** | ✅ Good | Conversation list with user-level dedupe, contacts/groups unified "People" concept; back-press guard |

---

## 5. Security posture

### 5.1 Protected (verified present and wired)

| Layer | Mechanism | Where |
|---|---|---|
| Database at rest | **SQLCipher**, 32-byte random key in Keystore-backed secure storage; plaintext→cipher migration with verification reopen | `DatabaseEncryptionService` ← `LocalStore.open()` |
| Local files at rest | **AES-GCM** per-file envelope (`LLFILE1`), Keystore storage key, encrypted `.enc.part` parts, 5-min TTL plaintext view copies | `SensitiveFileProtectionService` ← `FileTransferService` |
| Transport state & mesh queue | Keystore AES-GCM blobs | `LocalTransportService` (`persistState`, mesh queue) |
| Credentials/tokens/keys | `flutter_secure_storage` (Android Keystore), 24 call sites | `SecureStorageService` |
| Server address policy | **Private/link-local/loopback/explicitly-local hosts only**; plain HTTP **rejected in release**; length/scheme/port validation | `SecurityPolicy.normalizeServerUri` |
| Network config | `usesCleartextTraffic=false`, `allowBackup=false`, `dataExtractionRules` set | `AndroidManifest.xml` |
| Identity/signing | Ed25519 directory-profile signing + verification enforced on contact ingest | `IdentityCryptoService` |
| Trust states | unverified/verified/changed/revoked; changed/revoked blocks calls | `IdentityTrustService` |

### 5.2 Intentionally open (by your decision, this cycle)

- **Message/file content is plaintext between devices.** The X25519/HKDF/AES-GCM content
  layer and its key-exchange plumbing were removed. Traffic is still gated by a
  known-peer roster (revoked devices excluded) and the transport handshake, but a
  network observer on the LAN can read message content. Calls were already in this mode.
- **Call video/audio**: app-level media encryption is documented as intentionally disabled.

**Net effect:** confidentiality of *stored* data (device at rest) is strong; confidentiality
of *in-flight* data on the local network relies on the network being trusted. That is a
coherent, deliberate position — it should be stated in user-facing copy and release notes.

### 5.3 Deployment prerequisite (finding F-01)

Because release builds refuse `http://` **and** cleartext traffic, a release APK can only
talk to an **HTTPS server on a private/local host with a certificate the device trusts**
(self-signed requires a user-installed CA or a debug build). This *will* look like
"app can't connect" if the beta backend is plain HTTP. Decide before beta:
serve HTTPS on the LAN, or ship beta as a debug/profile build.

---

## 6. Reliability & data integrity

Verified by tests (`transport_phase5_integration_test`, `alpha_smoke_test`,
`beta_soak_test`) and code inspection:

- **Delivered-by-ack only** — no optimistic "sent"; a message stays in the retry pipeline
  until the receiver acks; duplicates are re-acked (bounded) so lost acks recover.
- **At-most-once UI surface** — duplicate transport deliveries never double-emit to the UI.
- **Waiting states** — messages queue while no route exists and drain automatically when a
  route appears; calls enter a cancellable `connecting` state and ring only after invite-ack.
- **Route priority & promotion** — LAN preferred; Wi-Fi Direct fallback; restored higher
  priority path replaces a lower one.
- **Mesh guardrails** — max 8 hops, TTL/hop budget validation, path-loop detection, replay
  trackers (persistent + ephemeral), packet-id immutability across hops.
- **Load behavior** — 300-message burst and 150-message outbox drain complete with no loss
  and no duplicate sends; malformed/unknown traffic is ignored without killing the service.

---

## 7. Quality gates

| Gate | Result |
|---|---|
| `flutter analyze` | **0 errors**, 27 warnings, 171 info (baseline 199–200 total → 198) |
| `flutter test` | **144/144 passing** (was 114; +23 widget, +4 alpha, +3 beta, +0 loss) |
| Coverage | **30.3%** overall (2,066/6,821 lines) |
| Test campaign | Widget: 23 new across splash/toast/bubble/composer/group-chat · Alpha: roster+plaintext+malformed · Beta: 300-burst, duplicate storm, outbox drain |
| Native tests | 20 Kotlin test files updated for plaintext envelope — **not run here** (owed: `./gradlew :app:testDebugUnitTest`) |

**Coverage by area (highest → lowest):**

| Area | Lines | Comment |
|---|---|---|
| core/widgets | **88.4%** | design-system widgets well locked-in |
| connectivity | 64.1% | route policy strong |
| groups | 61.8% | best business feature |
| core/models | 42.5% | |
| home | 42.1% | |
| messaging | 36.6% | service tested through harness |
| calls | 34.8% | |
| core/notifications | 7.5% | ⚠️ |
| files | 1.4% | ⚠️ |
| core/services | 1.2% | ⚠️ **contains LocalStore (2.3k LOC)** |

---

## 8. Findings register

| # | Sev | Finding | Evidence | Recommendation |
|---|---|---|---|---|
| F-01 | **High (deploy)** | Release builds require HTTPS on a private host (by policy); plain-HTTP beta backend = "cannot connect" | `SecurityPolicy` + `usesCleartextTraffic=false` | Decide beta transport (LAN HTTPS vs debug build) before shipping |
| F-02 | **High (quality)** | `LocalStore` (outbox/messages core) effectively untested (1.2% area) | coverage lcov; `FakeStore` shadows it in tests | Add direct `LocalStore` tests on a temp SQLCipher DB (round-trip outbox, ack, upgrade path) |
| F-03 | Medium | Friendly-error policy only partially adopted: 10 prefix-strip sites / 9 files (3 files mix both patterns) | `profile_screen:162,158,194`, `devices_screen:71`, `admin_login:65`, `call_screen:42`, `privacy_security:65`, `my_qr:189`, `add_contact:243,257`, `home_screen:189`, `chat_screen:149` | Route all through `friendlyErrorMessage()` |
| F-04 | Medium | No CI pipeline | no `.github/` | GitHub Actions: analyze + test + `./gradlew test` on PRs |
| F-05 | Medium | Device-level alpha/beta flight still owed (pair, LAN→Wi-Fi Direct fallback, group send, airplane-mode drain) | no Android SDK in audit env | Execute `TESTING_REPORT.md` checklists on 2 physical devices |
| F-06 | Medium | Send-failure UX double surfaces (inline error + toast) | `group_chat_screen_test` expects both | Pick one surface per context |
| F-07 | Low | Dead code: `AttachmentCryptoService` (173 LOC, zero users), `GroupListTile` (zero users) | grep — no references | Delete |
| F-08 | Low | Legacy crypto remnants: `peer_keys` table + `savePeerKey`/`peerKeys()` (no callers), `resetDerivedEncryptionState` still called by identity rotation | `local_store.dart:321,1396–1417`; `identity_repository.dart:45` | Remove table usage (schema-table drop on next migration) |
| F-09 | Low | Cosmetic leftovers from crypto removal: `decrypted` variable name (×5) and "encrypted" comment | `reliable_messaging_service.dart` | Rename to `payload`/`parsed` |
| F-10 | Low | 27 analyzer warnings incl. one possibly-meaningful pair: `override_on_non_overriding_member` (authentication_repository:171), `unawaited_return_in_try_block` (call_repository:39), unused `_recoveryAttempts`/`_onTransportState` in call_session_manager | analyze output | Triage warnings; fix the two semantic ones |
| F-11 | Low | `_cleanError` duplication (same helper re-implemented in ≥6 screens) | grep | Fold into `error_toast.dart` as shared helper |
| F-12 | Info | Workspace instability: 8 silent resets observed across the project; recoverable only via the patch | session history | Apply + commit the patch promptly; keep `phase5_work.patch` backed up |

---

## 9. Risk matrix

| Risk | Likelihood | Impact | Exposure | Control |
|---|---|---|---|---|
| Beta/release cannot reach HTTP backend | High if unchanged | High | F-01 | Decide + test before beta |
| Undetected store regression (outbox corruption) | Medium | High | F-02 | Direct LocalStore tests |
| Raw exception text in UI (policy violation) | Medium | Low | F-03 | Finish friendly-error sweep |
| Regressions undetected between pushes | Medium | Medium | F-04 | CI |
| Silent workspace resets lose work | High (observed ×8) | High *if* patch lost | F-12 | Patch + backup (already mitigated) |
| LAN content sniffing | Medium | Medium (accepted) | design decision | State it in release notes; re-add crypto later if threat model changes |

---

## 10. Prioritized recommendations

**P0 — before any beta distribution**
1. Resolve F-01 (HTTPS vs debug-build decision) and verify on a real device.
2. Apply `phase5_work.patch`, run `flutter test` (144 expected) + `./gradlew :app:testDebugUnitTest`.

**P1 — first hardening sprint**
3. Direct `LocalStore` test suite (F-02) — outbox lifecycle, ack cleanup, schema upgrade v20→21.
4. Finish the friendly-error sweep (F-03, F-11).
5. Stand up CI (F-04) running analyze + Dart tests + Gradle tests.

**P2 — cleanup**
6. Delete dead code (F-07), retire `peer_keys` table (F-08), rename leftovers (F-09), triage the 2 semantic warnings (F-10).
7. Execute device checklists (F-05) and record results in `TESTING_REPORT.md`.

**P3 — roadmap**
8. Re-introduce transport security if the threat model demands it (the removal was clean and the seams are known: handshake version bump, roster-gate, packet envelope).
9. Coverage floor for `core/services` + `files` (target ≥40% each).

---

## 11. Appendix — verification commands

```bash
flutter pub get
flutter analyze                                   # expect: 0 errors
flutter test                                      # expect: 144/144
flutter test --coverage                           # coverage/lcov.info
flutter test test/alpha_smoke_test.dart           # alpha campaign
flutter test test/beta_soak_test.dart             # beta campaign
./gradlew :app:testDebugUnitTest                  # native (needs Android SDK)
flutter build apk --release                       # verify HTTPS policy on device
```

---

*Audit based on the workspace rebuilt from `phase5_work.patch` (122 files, +3,996/−1,498)
on upstream `main` @ `1786dbd`. All numbers measured at audit time; re-run the appendix
commands to reproduce.*
