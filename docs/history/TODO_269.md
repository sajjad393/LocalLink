# TODO 269: S-1 fix, an unchecked hello can't switch a proven friend to plain (3.0.84+155)
Approved 14 Nov ("Go ahead according to your advice"). Analysis: `CYCLE2_REPORT_R268.md` §8.

## Problem
`peer_connected` with `seal:false` comes from the other phone's own hello. The link MAC does not cover it, and a link with no key is accepted as LEGACY while strict mode is off (the default). Any nearby phone that claims a friend's id can send it. `SealingPeerTransport` then removes the friend from `_capable` (and saves that), and chats to the friend go out plain (`send()`).

## Fix (smallest)
File: `lib/features/connectivity/data/services/sealing_peer_transport.dart`
- New set `_proven` (saved as `seal_proven_peers_v1`): friends whose sealed message this phone OPENED with the friend's saved key (the `!stranger` path in `_openMessage`, next to `_setCapable(sender, true)`). Stranger, group and block-ack locks do NOT count.
- `peer_connected` with `seal:false`:
  - friend is in `_proven`: ignored, log `SEAL_DOWNGRADE_IGNORED peer=<id6>`;
  - otherwise: as before (an old app learned only from its hello still gets plain; `seal_relay_156` test unchanged).
- `seal:true` from a hello still adds, as before. That is harmless: it only adds encryption.
- `_loadCapabilities` loads `_proven`.

No native, transport, UI or server change. Current apps always send `seal=1` (`LocalLinkTransportService.kt:1777/1857`), so a real friend never hits this path.

## Not in scope (known limits, not changed)
- S1-4: plain inbound that claims to be a friend is still passed on (no approval to drop it; it could drop real messages from a friend on an old app).
- Strict link check stays OFF (bundle 257 lockouts).
- A friend proven before this update is protected after their next sealed message (the proof set starts empty).

## Tests
- New `test/seal_downgrade_269_test.dart` (from the S-1 repro, expectations flipped):
  - a proven friend stays sealed after a `seal:false` hello, also after a restart;
  - a hello-only friend still goes plain;
  - stranger locks don't make anyone proven;
  - the log line;
  - plain inbound still passes (S1-4 documents the limit).
- Mutation check: remove the guard and the new test must fail.
- Version 3.0.84+155 (`bump.py`): `app_build.dart`, `pubspec.yaml`, `bundle223_logs_test`, `nearby_190_test`.
- Related tests (seal / relay / sealing / fresh), full suite, analyze, release APK.
