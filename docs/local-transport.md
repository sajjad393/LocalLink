# LocalLink — Local transport behavior (what to expect on real devices)

This page documents the direct-transport user-visible behavior: LAN, Wi-Fi Direct, pairing, and the associated constraints. Source of truth: `LocalLinkTransportService.kt`, mesh package, Nearby/Contacts screens.

## Ports

| Port | Purpose |
|---|---|
| 8988 | Wi-Fi Direct mesh session TCP (group owner listens) |
| 8989 | LAN mesh session TCP (every device listens) |
| 8990 | LAN discovery beacons (UDP broadcast every 3 s) |

Fixed by design in `MeshTransportPolicy`. If any other app on the phone or network squats these ports, transport can't session (L1 — known limitation).

## LAN discovery & the roster rule

Every device broadcasts a tiny signed-absent beacon (`lan_peer_discovery`, v1) every 3 s. Any LocalLink device on the same broadcast domain is discovered — that discovery is:

- **visible in the UI**: Nearby screen → "On this network" section shows discovered devices (connected, connecting, and *not yet paired* alike);
- **not a session**: sessions open only between **paired contacts**. A discovered-but-unknown device will never be connected automatically, and it cannot read, relay, or send anything.

Pair two devices (Contacts → Add contact → scan each other's QR, or search by registered phone number on both ends), and the smaller `deviceId` dials the packet TCP session within one beacon interval. This roster-only posture is deliberate (privacy), not a bug.

## Wi-Fi Direct

- Keep Wi-Fi Direct enabled (Location on pre-Android 13 for discovery grants; `NEARBY_WIFI_DEVICES` post-13).
- With **exactly one** eligible nearby peer the app may auto-connect; with **two or more** visible WFD peers, Android exposes no LocalLink identity during discovery, so **you must pick a peer manually** in Nearby → Connect (product limitation, documented as M3 in the audit).
- The WFD group owner starts a TCP server; the other side dials `192.168.49.1` (typical GO address) :8988. Disabling Wi-Fi Direct tears down only the WFD link — LAN sessions and the background service keep working.
- Group-invitation dialog acceptance ("accept without prompt") cannot be forced: the OS shows it to the invited device on first group formation.

## Offline semantics

- With the LocalLink server unreachable but devices on the same LAN/WFD: 1:1 messaging, file transfer (≤50 MiB), and calls continue; delivery acks return over the same path; outbox retries persist across restarts (encrypted store).
- Discovery of a **contact's identity** never depends on the server for already-paired contacts — pairing data is local after first exchange.
- **Group chats are server-backed only** (fan-out, ordering, delivery receipts live on the server); group messaging is intentionally absent over pure LAN/mesh (H2 — scope decision pending).
- If a receiver is offline, the sender's outbox keeps the message; the packet is queued inside the mesh store-and-forward queue when an intermediate path exists but the final hop is down.

## Multi-hop mesh (1:1 direct traffic)

- Path-vector routes with `hopCount ≤ 8`; every forwarder appends itself to `mesh_path`; a packet that loops back to a node already on its path is dropped.
- Relay nodes forward opaque payloads only the final recipient surfaces locally (`MeshFinalRecipientPolicy`).
- Route table is bounded: ≤512 destinations, ≤4 routes per destination, ≤64 destinations per next hop.
- Route advertisements flood along established connections only; an ad for a node that would loop a path is rejected.

## Trust now, and next

- **Today:** sessions are plain TCP framed JSON; peer identity is roster-membership only (no cryptographic handshake). Network observers can read traffic and any device knowing a roster id can claim it.
- **Planned (design approved pending your sign-off):** C1/C2 transport handshake v2 — Ed25519 challenge-response against roster-pinned signing keys + per-link X25519/DH-derived AES-256-GCM framing (`docs/transport-crypto-c1-c2-design.md`).

## Four-device validation

See audit report §12 (`LocalLink_networking_audit_2026-10-16.md`) for the physical A/B/C/D test matrix (LAN pair, WFD pair, A→B→C relay, A→B→C→D 3-relay, file integrity, call media, offline queueing, WFD-loss re-queue).
