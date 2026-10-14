# LocalLink — C1/C2 Transport Peer Authentication & Link Encryption (design, pending approval)

**Status:** design proposal — no code yet. Fixes audit findings C1 (transport peers are unauthenticated beyond a self-claimed id) and C2 (frames travel in cleartext JSON). Deliberately a wire-protocol change: `mesh_transport_version` **1 → 2**; v2 devices politely refuse v1 sessions and vice versa.

## 0. Why this exists

Today `authenticateClient`/`acceptHandshake` only checks `knownPeers.contains(claimedNodeId)`. Any device on the LAN that knows a roster id can claim it, or sit silently on the link and read every packet (messages, call signaling, file chunks, media frames). The mesh layer's own integrity rules are sound, but authenticity/confidentiality end at *application* E2E for message bodies only — everything else (file bytes, call media, route ads, ACKs) is observable and malleable on-wire.

## 1. Threat model (what C1/C2 must and need not do)

Covers: impersonation of a roster peer on LAN/Wi-Fi Direct; passive observers on the same network; TCP traffic modification (link tampering); replay of recorded frames.
Does not cover: rogue-but-paired contacts (roster compromise is an identity problem one layer up), payload-level content protection between non-paired relays of a *relayable* packet (application E2E stays responsible), denial of service beyond existing caps.

## 2. Identity source of truth — reuse, don't reinvent (recommendation)

The directory already owns exactly the binding we need. Every QR pairing carries and *verifies*:

```
{v:1, profile:{…, deviceId, signingPublicKey (Ed25519), identityPublicKey (X25519, versioned)}, signature}
```

`DirectoryRepository.importQrProfile` verifies the self-signed profile at intake; contacts persist it. So the roster already maps **deviceId → (signingPublicKey, identityPublicKey)** with TOFU pinning.

C1 therefore authenticates the *claim* "I am deviceId" against the pinned **Ed25519 signing key**; C2 encrypts links with ephemeral keys derived from an **X25519 handshake** (identity key + ephemeral, so links inherit forward secrecy from the ephemeral side).

No new key infrastructure. Profile/key rotation remains possible: versioned X25519 keys (`IdentityCryptoService` v2 scheme) rotate with machines keeping old versions available for a grace period; the transport only needs *any* currently-advertised key version.

## 3. Handshake v2 (replaces version-ping trio, same socket)

State machine per connection initiator / acceptor:

1. **hello** — `{type:"hello", version:2, node_id, nonce_b64 (16B), x25519_eph_b64}`  
2. **hello** (mirror from the other side)
3. **auth** — each side sends `SIGN_ed25519( "LLTRANSPORT2" || selfHello || peerHello )` plus its Ed25519 `signing_public_key` (transcript-bound = cannot be reused across links).
4. **auth_ok** — after *both* auths verified against roster pins and ids match the pinned `deviceId`s.
5. Nonce/session keys: `K = HKDF(X25519(eph_self, eph_peer) || X25519(eph_self, idkey_peer) || X25519(idkey_self, eph_peer), salt=transcript_hash, L=64)` split into two directional AEAD keys + 12B base nonces (initiator→responder, responder→initiator). Per-frame nonce = base ⊗ be64(seq), seq from 0, detached increment on resend never.

Rejections are logged to diagnostics (`handshake_auth_fail`, reason codes) and close the socket. A device with a keyed identity that is **not** in the roster is also rejected (C1 keeps the current roster policy — unknown devices never conversed).

## 4. Framing v2 (replaces line-delimited JSON)

Envelope per frame: `[u16be length ≤ 17500][12B nonce][ciphertext][16B GCM tag]`. Plaintext inside is the *same* canonical packet JSON (MeshPacket unchanged — application layer untouched). Length-prefixed binary instead of the `\n` text scan (also removes base64 tax on call_media and file chunks: binary payloads become first-class `bytes` inside a CBOR/MessagePack-lite frame later — optional phase 2; phase 1 keeps JSON inside the AEAD).

Wire-level *before* auth_ok: only hello/auth frames (length-prefixed, distinct marker byte); everything else is a protocol violation → close. Keeps the pre-auth surface tiny.

## 5. Rollout / compatibility

- `mesh_transport_version: 2` in LAN beacons; a v1 beacon from a peer is *not* connected to (discovery still shows the device as nearby — the pairing UX works regardless of version).
- WFD: no beacon — handshake does the version check.
- One-way upgrade: mixed-version pairs simply can't session; which side you upgrade first doesn't matter for correctness, only for availability. Documented in release notes: roster stays, no re-pairing needed.
- Rollback: revert commit, redeploy v1 build; nothing durable changes.

## 6. Touch-list (implementation estimate: ~2 focused days + tests)

Native (`LocalLinkTransportService.kt`):
- new `transport/v2/TransportAuthV2.kt` (handshake machine, transcript, HKDF): +~350 lines
- new `transport/v2/AeadFrameCodecV2.kt` (+~120)
- `connectLanPeer`/accept path: swap `authenticateClient`/`acceptHandshake` for v2 machine
- frame read/write: swap line-codec for frame-codec (single choke point, everything routes through it)
- `configure()` signature: add roster fingerprints map (Dart passes deviceId→{signingPublicKey, identityPublicKey, version}); persist encrypted like `knownPeers` today
- beacons carry version 2 + optional 4-byte key fingerprint (helps UI show version)

Dart:
- `wifi_direct_transport_service.dart`: pass roster fingerprint map through configure (from `store` directory profiles + own keys)
- No UX change needed; diagnostics gains handshake counters.

Tests (must all pass before shipping):
- unit: handshake happy path (both directions in-process), wrong-key reject, replay-of-recorded-auth reject, transcript-mismatch reject, frame bit-corruption reject (GCM), seq-replay reject, version-1-with-2 refuse margin, roster-pin-miss reject; 10k-frame session fuzz round-trip; frame codec fuzz (length/tamper).
- integration: existing Kotlin mesh suite unchanged on top of transport v2 mocks; Dart outbox/ack suites unchanged.
- physical (§12 of the audit): the same A/B pair on an open LAN with a third laptop running `tcpdump` — expectation: only hello/auth frames readable; a scripted impersonator with a stale id fails at auth.

## 7. Explicitly out of scope here
- group-over-mesh (H2 decision), M5 media-path isolation, M1-style table tweaks (done), WFD UX wording (done in bundle 2).
- Post-quantum hybrid KEM (KEM-ML768) — evaluated when platform support stabilizes; handshake's HKDF layout already tolerates concatenated secrets.

**Decision needed:** approve identity-to-roster pinning (recommended, zero new keys) vs. separate transport-only key ceremony; and confirm breaking v1→v2 for the next release train.
