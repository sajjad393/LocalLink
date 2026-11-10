# TODO 257: friends locked out of Wi-Fi Direct / Local Wi-Fi / mesh

Status: BUILT as 3.0.75+146 (user said "Go ahead", 2026-11-10). See Build notes at the end.
Version when built: 3.0.75+146. ONE app zip, ONE commit. No backend change.
Checked against the code at app HEAD `1eec747`.

## Problem (from the 10 Nov logs, 15:42-16:52, all 3 phones)
- The TECNO refused links 1352 times in 1 h. The Note refused the C71 141 times. All with `LINK_AUTH reject ... reason=auth_required`.
- All 3 links were refused: C71-Note, C71-TECNO, Note-TECNO. With the server on, chats went through the server. With the server off (16:39:23) there was no path at all: `MESSAGE_ROUTE_UNAVAILABLE route=none`.
- Why:
  - The C71 started fresh at 16:33 and had 0 link keys (`keys peers=0`). Its keys had also changed at about 15:57 (KEY_CHANGE_245).
  - The Note has had no key for the TECNO since 15:51:31, right after `ID_MOVED old=8cd082 new=b71c0e`.
  - The TECNO and the Note remember that the others "passed before", so they refuse them.

## Where it is in the code
- `android/.../mesh/MeshLinkAuth.kt` `decide()`: `if (verifiedBefore) return Decision(Verdict.REJECT, "auth_required")`.
- `android/.../LocalLinkTransportService.kt`:
  - `linkVerified` (line ~278) is saved in `persistState()` and NEVER removed. `noteLinkAuth()` only adds to it (`linkVerified.add(peer)`).
  - `authenticateClient()` (dial, ~1785) and `acceptHandshake()` (answer, ~1839) both call `decide(..., linkVerified.contains(peer))`.
- Added in commit a38b879 (30 Oct 2026). Before that date, the links worked.
- Dart `lib/features/connectivity/data/services/sealing_peer_transport.dart` `pushLinkKeys()`:
  - Runs only from `configure()` (~905) and `updateKnownPeers()` (~919).
  - It is NOT run when a friend card arrives, when "Accept new code" is tapped (security_code_245.dart `accept()`), or when `KeyChange235.bump()` runs.
  - `contactPublicKey()` (~89) returns null when: the friend is not in `localDevices()` / is revoked / is blocked, there is no card (`directoryProfileByDeviceId`), there is no `identity_public_key`, or the key length is wrong. None of these is logged.

---

## A1 Allow the old way instead of refusing (main fix)
File: `android/.../mesh/MeshLinkAuth.kt` `decide()`
- Now: verifiedBefore + no shared key -> `REJECT "auth_required"`.
- New: verifiedBefore + no shared key -> `LEGACY "rekey"`. The link works the old way.
- Unchanged:
  - Wrong MAC with a matching key -> `REJECT "bad_mac"` (a real fake phone).
  - No local key -> `LEGACY "no_local_key"`.
  - Strict mode (setting, off by default) -> `applyStrict()` still turns any LEGACY contact link into `REJECT "strict_unchecked"`.
- Safe because chats and files on the link are still sealed per friend (SealingPeerTransport), so a fake phone can't read them. Calls are the same.
- `noteLinkAuth()`: a `rekey` link logs at INFO and adds `transportEvent("peer_link_rekey", peer_id)` (only logged by Dart, no UI).
- OLD TEST CHANGE (tell the user): `android/app/src/test/.../mesh/Scale160Test.kt` lines 314-315 expect `REJECT "auth_required"`. Change them to `LEGACY "rekey"`.
  - Lines 307/308/312/313/317 stay as they are.
  - `Link164Test.kt` (strict) stays as it is.

## A2 Forget "passed before" when a friend's key changes
File: `LocalLinkTransportService.kt` `updateLinkKeysInternal()` (~726)
- Before `linkKeys.clear()`: for each peer whose offer set (`ownKid.peerKid` list) is different from before, or is gone, call `linkVerified.remove(peer)`.
- Log `LINK_AUTH verified_reset peer=<last8> why=key_changed|key_gone` (max 1 per peer per 10 min).
- `persistState()` is already called there.
- New Kotlin test: put a key, mark verified, then push a different key -> not verified any more. Push the same key -> still verified.
  - The diff logic goes in a small pure helper (e.g. `MeshLinkAuth.changedPeers(old, new)`) so it can be tested without the service.

## A3 Push link keys again when keys can change
File: `sealing_peer_transport.dart`
- Keep the last peer list from `configure()` / `updateKnownPeers()` in `_lastPeerIds257`.
- New `refreshLinkKeys257(String why)`:
  - Waits 2 s (debounce) and then runs once.
  - Resets the key-access cache (`_trustedAt` to 0, clears `_publicKeys`; add a `forgetContactKeys()` next to `forgetOwnKeys()`).
  - Then `pushLinkKeys(_lastPeerIds257)`.
  - The existing signature check still skips a push when nothing changed.
- New tiny hook `LinkKeyRefresh257` (static `void Function(String why)? onRequest`), set by SealingPeerTransport in its constructor. Called from:
  - `directory_repository.dart` `_saveVerified()`, right after `store.saveDirectoryProfile(...)` succeeds (why=card).
  - `security_code_245.dart` `accept()`, after `save(...)` (why=accept).
  - `dup_account_235.dart` `KeyChange235.bump()` (why=key_change).
  - `moveFriendId218()` after a move (why=id_moved).
- Log `LINK_AUTH keys refresh why=<why>` only when a push really happens.
- New Dart test (pattern of `test/nearby_160_test.dart` ~230):
  - Friend without a card -> 0 keys. Add the card + `LinkKeyRefresh257.onRequest('card')` -> keys pushed with the friend.

## A4 Stop the 5-second refuse loop (small)
File: `LocalLinkTransportService.kt`
- `connectTransportToOwner()` (~1689), the WD dial: when `authenticateClient()` returns null after a handshake answer, call `noteLinkEnded(lastWdOwnerPeer, 0L)`. Use the peer last seen at that owner address. If it is unknown, do nothing.
- Before dialling, if that peer is held (`flapGuard.holdLeftMs > 0`), skip and log `WD_REDIAL later why=flap` (the same line as today).
- `acceptHandshake()`: on REJECT, call `noteLinkEnded(peer, 0L)` so our own dials to that peer back off too. Answering stays allowed (the Bundle 224 rule).
- With A1, most refusals are gone. A4 only limits what is left (bad_mac / strict).
- Old tests unchanged (`Flap224Test.kt`).

## A5 Logs show which friend
File: `LocalLinkTransportService.kt` `noteLinkAuth()` (~829-842)
- `peer.take(8)` prints `android-` for everyone -> change to `peer.takeLast(8)` in the 3 LINK_AUTH lines.
- Also `LINK_AUTH contact link closed` (~864) and `reject ... strict_unchecked` (~877) use `link.peerId.take(8)` -> `takeLast(8)`.
- The `LINK_AUTH_DAY` line stays exactly as it is (bundle239_test locks it).

## A6 "Accept new code" must not block the link
- With A1, a friend with a new key (waiting for Accept, security_code_245 `_pending`) gets a `rekey` link instead of a refusal.
- A3 makes the keys push right after Accept, so the next link is verified again.
- No other code change. Test: covered by the A1 + A3 tests.

## A7 Log why a friend has no link key
File: `sealing_peer_transport.dart` (key access `contactPublicKey()` ~89 + `pushLinkKeys()`)
- Record a reason when null is returned: `not_friend` (not in localDevices), `revoked`, `blocked`, `no_card`, `no_key`, `bad_key`.
- After each push: `LINK_KEY_MISSING peer=<last6> why=<reason>` for each friend in the peer list with no key. Log once per peer+reason per hour.
- This finds out why the Note lost the TECNO key at 15:51 (NOT VERIFIED today).
- Dart test: one friend with no card -> `why=no_card` logged once, not again on the next push.

## A8 Stop the account move repeating on every start
File: `lib/features/directory/data/repositories/directory_repository.dart` `_moveOfflineIds218()` / `moveFriendId218()` (~1062-1102)
- Today `ID_MOVED old=8cd082 new=b71c0e` repeats on every start, on both the Note and the TECNO. The old offline card row is never removed.
- After `moveFriendId218(oldId, newId)` succeeds (after `_flushPendingEdgesFor(oldId)`), delete the old offline card row: `store.dropDirectoryProfile235(oldId)`. This deletes only `directory_profiles` rows for that user id; contacts / chats are not touched.
- `local_store.dart` `directoryProfileByDeviceId()` (~1913): prefer the server row. `orderBy: "CASE WHEN user_id LIKE 'offline_%' THEN 1 ELSE 0 END, updated_at DESC"`, limit 1.
- Dart test: 2 rows for one phone (offline + server) -> the server row is returned. After a move -> the old row is gone and a 2nd `_saveVerified` logs no ID_MOVED.
- Fakes in `test/support/phase5_fakes.dart` / `profile_photo_204_test.dart` have their own `directoryProfileByDeviceId`: no change needed.

---

## Scope (files)
- android/app/src/main/kotlin/com/sajjad/locallink/mesh/MeshLinkAuth.kt (A1, A2 helper)
- android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt (A2, A4, A5)
- lib/features/connectivity/data/services/sealing_peer_transport.dart (A3, A7)
- lib/core/services/link_key_refresh_257.dart (NEW, A3 hook)
- lib/features/directory/data/repositories/directory_repository.dart (A3 call, A8)
- lib/core/security/security_code_245.dart (A3 call)
- lib/core/identity/dup_account_235.dart (A3 call)
- lib/core/services/local_store.dart (A8 order)
- lib/core/constants (version 3.0.75+146) + pubspec.yaml
- Tests:
  - NEW `test/link_257_test.dart`, NEW `android/app/src/test/.../mesh/Link257Test.kt`.
  - CHANGED: `Scale160Test.kt` (2 lines, A1), `bundle223_logs` + `nearby_190` (version only).

## Not touched
- Strict mode default (stays off). Seal / encryption code. Server / backend. Map (222 lock). UI.

## Notes
- Kotlin can't compile here. The Kotlin changes are small and checked by reading only. The Kotlin tests run on the user's PC (`gradlew test`).
- After install: no data clear is needed. The first key push after start resets the stale "passed before" entries (A2), and A1 lets links work at once.

## How to check after install (server OFF)
- No `LINK_AUTH reject ... auth_required`. At most a few `LINK_AUTH legacy ... reason=rekey`, then `verified` once keys match.
- `LINK_FLAP hold` rare. `MESSAGE_ROUTE_AVAILABLE transport=wifi_direct|lan` on all 3 phones.
- `LINK_KEY_MISSING` lines show the reason for any friend still without a key.
- `ID_MOVED` once, not on every start.

## Build notes (3.0.75+146)
- A1: done as planned. `noteLinkAuth` logs `legacy ... reason=rekey` at most once per peer per 10 min. No new transportEvent (kept smaller).
- A2: `MeshLinkAuth.changedPeers()` + `resetVerifiedFor257()` in `updateLinkKeysInternal()`. Log `verified_reset` once per peer per 10 min.
- A3: `lib/core/services/link_key_refresh_257.dart`. `SealingPeerTransport.refreshLinkKeys257()` (2 s debounce) / `refreshLinkKeysNow257()`. Called from `_saveVerified` (card), `moveFriendId218` (id_moved), `SecurityCode245.accept` (accept), `KeyChange235.bump` (key_change).
- A4 (smaller than planned): a REJECT in `authenticateClient` (not LAN, which already notes it) and in `acceptHandshake` calls `noteLinkEnded(peer, 0L)`. The extra WD-dial gate was NOT added (risk of a 5 min WD wait after normal flaps).
- A5: takeLast(8) in all LINK_AUTH peer lines. LINK_AUTH_DAY unchanged.
- A7: new optional interface `LinkKeyCache257` (forgetContactKeys257 / missReason257) on `StoreSealKeySource`. Test fakes of `SealKeySource` are unchanged.
- A8: `_saveVerified` refuses an `offline_` card whose id already moved (`movedId218`), log `ID_MOVED_OLD_CARD_SKIP` once. `directoryProfileByDeviceId` orders server rows first, then `updated_at DESC`. Note: `moveUserId218` already deleted the old row; the repeat came from the old card being saved again.
- Tests: NEW `test/link_257_test.dart` (5), NEW `Link257Test.kt` (5). CHANGED `Scale160Test.kt` (2 lines), `bundle223_logs`, `nearby_190` (version).
- The Kotlin main + JVM tests compiled and ran here: OK (452 tests).
