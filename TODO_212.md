# TODO 212: Admin blocks / unblocks any user offline (local Wi-Fi, Wi-Fi Direct, mesh)

Status: **PLAN + MOCK only. Waiting for "go ahead" (freeze).**
- Based on the 211 code (app working copy `3.0.52+123`, backend `b17f935` + the 211 backend change).
- Push and deploy 211 first.
- Target: app **3.0.53+124**, DB **v35**.
- Backend: migration **55**, a separate zip, deploy first.
- Mock: `mock_212_all.jpg` (pages `mock_212_page1..10.png`).

## Phase overview (build order)
| # | Phase | What | Depends on |
|---|---|---|---|
| A | Trust | Server signing key, admin offline key (cert), key ends on sign out / revoke / reset | backend deployed first |
| B | Records + store | `admin_blocks` table (DB v35), record format, checks, `isBlockedPeer` includes admin blocks | A |
| C | Spread | One-step signed frames on every link: digest / records / got-it, hop to hop, also with the app closed | B |
| D | Enforce | Existing checks + blocked phone = relay-only mesh node + first-hop drop (Android side) + own-phone send guard | B, C |
| E | Admin UI | Panel card, picker, new confirm popup, blocked list, Link paths map + full-screen map | B |
| F | Others' phones + blocked phone | Chat bar, red banner, read-only | D |
| BG | Background | Runs in the no-screen engine; notifications | C, D |
| G | Server sync | `/admin-blocks/sync`, `/admin-blocks/mine`, web suspend = signed record | A, B |
| H | Tests + delivery | Dart + Go + Kotlin tests, full suite, zips, APPLY_212.md | all |

## 0. Your choices (2026-11-05, all "my advice")
| Question | Choice |
|---|---|
| Who stops talking to a blocked user | **Every LinkUp phone the block reaches** (spreads phone to phone over local Wi-Fi, Wi-Fi Direct and mesh) |
| Which users admin can pick offline | **Anyone this phone has seen** (chats, groups, People, server lists) + nearby |
| Blocked user's own phone | **Banner "Your account is blocked by admin"; can't send or call; can read old chats** |
| When a phone that has the block gets internet | **Sent to the server; applies everywhere; newest block/unblock wins** |
| Design | Mock v2 fixes 1-4 (Admin look, app banner style, one-letter avatars, one-line ⊘ bar) |
| Confirm popup | New look: red ⊘ on top, user box, 4 lines, big red "Block for everyone" |
| Map | Blocked phones stay on Link paths; full-screen map with drag-to-scroll + pinch zoom |
| App closed | Block / unblock also work in the background |
| Mesh node | A blocked phone still relays others' messages (**admin AND own blocks**); its own messages are dropped at the **first phone** |

## 0b. My decisions (tell me if you want other)
1. **Only the owner role can block.** On the server only `owner` has `manage_users` (`adminPermission`, `admin_auth.go` L263-277).
2. **Trust without internet:**
   - The server gets its own signing key (Ed25519).
   - Each phone saves the server key the first time it reaches the server.
   - The admin's phone gets an **admin key certificate** signed by the server, once online, after the update.
   - A phone that never reached the server can't check a block, so it ignores it (logged).
3. **The key ends when the admin sign-in ends:** Sign out, a revoke in Sessions, or a password reset. The server sends a signed "key ended" note. It spreads the same way as the blocks.
4. **Newest wins:**
   - Each record has `seq` = highest seq known for that user + 1, then time, then id.
   - The phone clock alone never decides.
5. **The admin can't block their own account.** The admin's own phone applies the block too.
6. **Server side:**
   - An offline block sets the user to `suspended`, and an unblock sets `active`.
   - The user's phone sessions are **not** revoked, so after an unblock the phone works again with no new sign-in.
   - A web-panel suspend or unsuspend becomes a server-signed record, so phones learn about it offline too.
7. **Old blocks from the panel's Block button (bundle 135)** stay as they are: in this phone's personal blocked list. The button now makes a network block instead.
8. **The record is not secret** (only ids, name, action and time). It is signed, so nobody can fake or change it.

## 1. Code facts (checked)
**App (w211):**
- `LocalStore.isBlockedPeer` L1940-1947 and `blockedPeerIds` L1929-1938 are THE common check. They are used by:
  - messaging receive: `reliable_messaging_service.dart` `_handleDirectEvent` L2333, `isBlockedPeer` near L2520;
  - groups: `group_messaging_service.dart` L96 / L869 (send to member) / L1672 / L1703 / L1728;
  - calls: `call_session_manager.dart` L334 / L448 / L863 / L1106;
  - pairing: `pairing_service.dart` L559;
  - seal drop: `sealing_peer_transport.dart` L496 / L509;
  - native link cut: `sealing_peer_transport.dart` L966 → `updateBlockedPeers` → Kotlin `updateBlockedInternal` L806 (closes contact links and relays). **212 changes this (see D2): blocked = relay-only, not cut.**
  - Kotlin places that use `blockedPeers` today (LocalLinkTransportService.kt): L755 `fileKeysFor`, L806 `updateBlockedInternal` (closes links), L1399 `shouldDialRelay` (never dials a blocked relay), L1931 / L1934 link read loop (`relay_blocked` / `contact_blocked` → link ends), L2551 sealed file from blocked, L3999 send via a blocked next hop refused, L4964 persist.
  - Old Kotlin tests: `Link164Test` and `MeshRelayPolicyTest` assert `MeshRelayPolicy.trustFor(isBlocked = true) == null`. **`trustFor` is NOT changed**; a new `MeshBlockPolicy` wraps it, so these tests pass unchanged.
- **One-step frames (bundle 195c) already exist:** `MeshRelayPolicy.isNameQuestion` (MeshRelayPolicy.kt L56), `isOneStepName` L60 (came straight from the linked phone and is for me), `canSendOneStepName` L64. Send: `sendTransportInternal` L837 sends it only to the phone on the link (`activePeerConnection(target)`), never routed. Receive: link read loop L1981 accepts it on ANY link (contact or relay) when one-step, else `mesh_dropped reason=name_not_one_step`. Carry check L3999 allows it on relay links. → 212 spread frames and 213 update frames use the same rule (new types), so they reach strangers and blocked phones too, without being routed.
- `LocalStore.blockedChanges` (stream) makes the seal transport reload the list (L227).
- Personal block: `blocked_users` table L584; `blockUser` / `unblockUser` L1867-1886; `blockDeviceAndUser` L1892 (bundle 135 panel button).
- `directory_profiles` L567 (user_id, device_id, username, display_name, `signing_public_key`, source …). `contacts` L582, `group_members` L372.
- DB: `DatabaseConfig.version = 34` (`core/storage/database_config.dart`); `onUpgrade` L160-192; fresh create calls `_upgradeTo34` L365.
- Device signing key (Ed25519): `IdentityCryptoService.signingPublicKey()` L254, `signPayload` L265, `verifyPayloadSignature` L271.
- Spreading pattern: `GroupNearbyService.start()` L235 listens to direct events and calls `flush()` every 20 s. Direct events arrive as `type: 'message'` with a `payload` JSON string (`reliable_messaging_service.dart` L2576-2616).
- `PeerTransportContract.send` / `broadcast` (broadcast = contacts only, Kotlin L839).
- Admin panel: `_confirmBlock` L240 (the Block button by a nearby phone, L565); `_moderationCard` L599; `_showBlocked` L279.
- Chat: `_blockedBar` (`chat_screen.dart`, ~L826) is the bar that replaces the message box; `BlockHub` decides `iBlocked` / `blockedMe`.
- Admin sign-in (211): `AdminLoginScreen._login`, `AdminCapabilityService.signOut`, `app_dependencies` reconnect hook (L159-166).

**Backend (wb211):**
- `AdminSetUserStatus` (`admin_panel.go` L166-197): statuses active / suspended / disabled; a non-active status revokes `auth_sessions`.
- `authorizeDevice` (`api.go` L990): a suspended user fails device auth, so the blocked phone can't use normal device calls.
- `authorizeAdminSession` L248; `requireAdminPermission` L279; routes in `cmd/server/main.go` (e.g. L145 `admin/logout`).
- Migrations: `orderedMigrationSpecs()` in `store.go`; the last is **54** (`retire-group-payload-crypto`), so the new one is 55.
- No signing key exists on the server yet (no ed25519 in the Go code).

## 2. Files
**App, new:**
- `lib/features/admin/data/models/admin_block_record.dart`: record, cert, canonical JSON, newest-wins compare.
- `lib/features/admin/data/services/admin_trust_service.dart`: server key pin, cert fetch, verify.
- `lib/features/admin/data/services/admin_block_service.dart`: make / verify / save / apply / spread / server sync.
- `lib/features/admin/presentation/screens/admin_block_users_screen.dart`: the picker (mock page 2).
- `lib/features/admin/presentation/screens/admin_blocked_list_screen.dart`: the blocked list (mock page 6).
- `lib/core/widgets/admin_blocked_banner.dart`: banner for the blocked user's own phone (mock page 8).
- `lib/features/admin/presentation/screens/link_paths_full_screen.dart`: full-screen map (mock page 5).

**App, changed:**
- `local_store.dart`: DB v35 tables; `isBlockedPeer` / `blockedPeerIds` include admin blocks.
- `database_config.dart`: 35.
- `admin_panel_screen.dart`: new card; Block button → network block; blocked nearby phones stay in Link paths + "On this link" (marked Blocked, with Unblock).
- `link_paths_map.dart`: `LinkNode.blocked` (default false) → grey node, red ring, ⊘ badge, grey dashed line (no ✕), "Blocked · relays others' messages only" in the legend. Optional `selectedId` / `scale` for the full-screen map; old calls unchanged.
- `admin_login_screen.dart` / `account_switch_sheet.dart`: fetch the cert after sign-in; drop it on Sign out.
- `app_dependencies.dart`: start the service; sync on reconnect.
- `background_runner.dart`: new step `admin_blocks` after `groups` (the service runs with the app closed).
- `local_link_notification_service.dart`: none; uses the existing `showSystemNotification`.
- `chat_screen.dart`: admin bar.
- `home_screen.dart` + calls / people tabs: banner.
- `reliable_messaging_service.dart` / `group_messaging_service.dart` / `call_session_manager.dart`: refuse to send when my own account is admin-blocked (one guard each).
- `pubspec.yaml`.
- `LocalLinkTransportService.kt`: blocked = relay-only (D2). Small edits at L806, L1399, L1931/L1934, L3999 + the trust call site; first-hop drop of the blocked user's own packets; one-step types at L837 / L1981 / L3999 also accept the new admin frame types (via `MeshOneStep.isOneStep`, old `isNameQuestion` untouched).

**Android, new:**
- `android/.../mesh/MeshBlockPolicy.kt`: pure rules (relay-only trust for a blocked peer, first-hop drop, which packets a blocked next hop may carry) + `MeshOneStep.isOneStep(type)` = name question/answer OR `admin_block_digest` / `admin_block_records` / `admin_block_got` (213 adds `app_update_*`, `version_rule_*`).
- `android/app/src/test/.../mesh/Block212Test.kt`.

**Backend:**
- New: `internal/httpapi/trust.go`, `internal/httpapi/admin_blocks.go`, `admin_blocks_212_test.go`.
- Changed: `store.go` (migration 55), `admin_panel.go` (web suspend → signed record), `admin_auth.go` (end the cert on logout / revoke / reset), `cmd/server/main.go` (routes).

## 3. Phases
### A. Trust (backend + app)
- [ ] A1 Backend `trust.go`:
  - Make an Ed25519 key once and store it in the `admin_settings` table (key `server_signing_key`) so a redeploy with the same DB keeps it.
  - `GET /api/v1/trust` → `{server_key, key_id}`, no auth.
- [ ] A2 `POST /api/v1/admin/offline-cert` (admin token + `manage_users`):
  - Body `{device_id, signing_key}`.
  - Returns cert `{v:1, cert_id, admin_id, username, role, device_id, signing_key, session_id, issued_at}` + `sig`.
  - Saved in the new `admin_offline_certs` table.
- [ ] A3 End the cert on `AdminLogout`, `AdminRevokeAdminSession` and `ResetAdminCredentials`: `ended_at` plus a signed "ended" note `{kind:'cert_ended', cert_id, at}`.
- [ ] A4 App `admin_trust_service.dart`:
  - On the first server reach (any phone), `GET /trust` → save `server_trust_key` (setting).
  - If the key ever changes, keep the old key, log `TRUST_KEY_CHANGED`, and do NOT accept the new one. This is a precaution; Reset setup clears it.
- [ ] A5 After the admin sign-in succeeds online (and on reconnect while signed in): fetch the cert for this phone's signing key and save it in secure storage. Sign out deletes it.
- [ ] A6 Panel state: green "Offline blocking is ready", or amber "Connect to the server once…" (mock pages 1 and 10).

### B. Records + store (DB v35)
- [ ] B1 Table `admin_blocks`:
  - Columns: `target_user_id` PK, `target_devices` (JSON), `target_name`, `action` (block / unblock), `seq`, `at`, `record_id`, `record` (signed JSON), `source` (me / nearby / server), `server_done` 0/1, `reached` (count), `received_at`.
  - Plus table `admin_certs_ended(cert_id PK, at, note)`.
- [ ] B2 Record `{v:1, kind:'admin_block', id, target_user_id, target_devices[], target_name, action, seq, at, cert, sig}`, signed by the admin device key.
  - A server-made record has `signer:'server'` and no cert.
- [ ] B3 Check order:
  1. Server key known.
  2. Cert signed by the server and not ended.
  3. Record signed by the cert key.
  4. Role is owner.
  5. Target is not the cert's own account.
  6. Newer than what this phone has.
  - Anything else is dropped with `ADMIN_BLOCK_REJECT reason=…`.
- [ ] B4 `isBlockedPeer(peer)` = personal block OR an admin block with action=block (by user id or any `target_devices`, or a device mapped through `directory_profiles`). `blockedPeerIds()` adds the same ids. A change fires `blockedChanges`.
- [ ] B5 `myAdminBlock` (ValueNotifier): this phone's own user / device is blocked.

### C. Spread (local Wi-Fi, Wi-Fi Direct, mesh)
- [ ] C0 **Transport for spreading = one-step frames** (like the 195c name question): sent only to a phone directly on a link (local Wi-Fi, Wi-Fi Direct or a mesh link), on ANY link (contact, stranger relay link, or a blocked phone's relay link), never routed. Each phone that accepts a record passes it on one step to its own linked phones, so it travels hop to hop to every phone. Records are signed and not secret (0b-8), so plain frames are safe.
- [ ] C1 `admin_block_service.dart` listens to direct events (same as `GroupNearbyService`), payload types:
  - `admin_block_digest`: list of `target:seq` plus a hash;
  - `admin_block_records`: up to 20 records per packet;
  - `admin_block_got`: ids.
- [ ] C2 When a peer connects, and every 60 s to linked contacts, send a digest. A peer with older or missing records asks, and gets only those.
  - Limits: max 200 records kept; max 1 digest per peer per 30 s.
- [ ] C3 A new valid record: save, apply, pass it on one step to every linked phone once (not back to the sender), and send `admin_block_got` back. `got` notes also travel hop to hop back to the admin phone (dedupe by record id + phone id), which counts `reached` (mock page 6).
- [ ] C4 The record also goes to the blocked phone by a one-step frame (its owner sees the banner). The link is NOT cut (D2), so later unblocks reach it the same way. One-step frames are never routed, so the first-hop drop (D2) doesn't touch them.
- [ ] C5 Size: a record is about 1.5 KB; max 20 per frame; frames over 64 KB are split. Logs: `ADMIN_BLOCK_SPREAD to=… n=…`, `ADMIN_BLOCK_GOT`, `ADMIN_BLOCK_REJECT reason=…`.

### D. Enforce
- [ ] D1 Through B4 the existing checks apply: messages, group messages, calls, pairing, seal.
- [ ] D2 **A blocked phone still works as a mesh node for others** (your choice 2026-11-05: admin blocks AND my own blocks).
  - Link: a blocked peer is kept as a **relay-only** link (`TRUST_RELAY`) instead of being closed. `MeshBlockPolicy.trust(isBlocked, peerOffersRelay, relayLinks, isPaused)` → relay when blocked (paused / full still refused); otherwise the old `MeshRelayPolicy.trustFor`.
  - `updateBlockedInternal`: contact links to a blocked peer are closed once and come back as relay links; relay links stay.
  - `shouldDialRelay` (L1399): a blocked node may be dialled as a relay.
  - Read loop (L1931/L1934): no `relay_blocked` exit; a contact link from a blocked peer ends (`contact_blocked`) and returns as a relay.
  - Carry (L3999): a blocked next hop carries only sealed packets (`canCarry(TRUST_RELAY, …)`), which it can't read.
  - **First-hop drop (your choice):** any phone drops at once a packet whose origin (`sourceNodeId`) or final target (`destinationNodeId`) is a blocked user. It is not passed on and not delivered. Log `BLOCK_DROP origin=… hop=first` (rate-limited).
  - Own blocks are private (not spread), so for them only MY phone drops Ali's packets; other phones still carry them sealed. Admin blocks are spread, so every phone drops them at the first hop.
  - One-step frames (C0) are exempt: they are never routed.
  - Unchanged: blocked users' files (L755 / L2551), pairing, calls, presence, names, contact data.
  - The blocked phone itself keeps relaying others' sealed packets while locked (its own sends are refused in Dart).
  - **Note for you:** this also changes bundle 164 for normal blocks (today they cut the phone fully).
- [ ] D3 Own phone blocked: `reliable_messaging` send, group send and call start each refuse with "Blocked by admin" (one guard each, no other change).
- [ ] D4 Notifications from an admin-blocked user are not shown. This comes free with D1, since their messages are dropped; check it in a test.

### E. Admin UI (mock pages 1-6, 10)
- [ ] E0 Design rules (mock v2):
  - Picker and blocked list use the Admin look: `AdminTheme` title bar, `AdminListSearch` (round 24), `AdminListMoreButton` ("Show N more (X left)"), cards rounded 12 with the Admin border.
  - Two-letter tinted avatars as in "On this link right now".
- [ ] E1 Panel card "Block users (all phones)" replaces "Local moderation": status line, "Block or unblock a user", "Blocked by admin".
- [ ] E2 Picker:
  - "Nearby now" + "Seen before" (directory_profiles ∪ contacts ∪ group_members ∪ local devices), search by name / @username.
  - Chip on each row: Active / Blocked by admin / Blocked · server later.
- [ ] E3 Confirm dialog, new look (mock page 3): white, rounded 22; red ⊘ circle on top; title "Block {name}?"; under it "For everyone, on all LinkUp phones"; user box (avatar, name, @username · seen); 3 rows with icons (No messages or calls / Goes out right away / Old chats stay); full-width red "Block for everyone"; "Cancel" below. Unblock uses the same layout: green, "Unblock {name}?" / "Unblock for everyone".
- [ ] E4 Blocked list: who did it, when, "Reached N phones", "Server: waiting / done", Unblock.
- [ ] E5 The Block button by a nearby phone opens the same confirm (network block).
- [ ] E6 Link paths map (mock page 4): today blocked phones are removed from the live view (`_onLink` drops `_blockedIds`, bundle 135). Now a blocked phone that is nearby stays on the map: grey node, red ring, small red ⊘ badge, grey dashed line (no ✕) = relays others' messages only, label "{name} · Blocked" on a red pill. Legend adds "Blocked · relays only". Mesh lines through a blocked phone stay normal (it still carries others). "On this link right now" keeps the row: grey name, "Blocked" chip, "Unblock" (asks first); count line "N device(s) … · M blocked". Blocked phones that are not nearby are NOT drawn. New ⤢ button at the top right of the card opens E7.
- [ ] E7 Full-screen map (mock page 5), `LinkPathsFullScreen`:
  - Top: back, "Link paths", "N users · M blocked · server online/offline", shrink button.
  - Search "Find a user on the map" (jumps to and highlights the node) + filter chips with counts: All / Wi-Fi Direct / Mesh / Local Wi-Fi / Server / Blocked.
  - Map fills the screen: every device on the link (no 14-char name cut).
  - Scroll + zoom: `InteractiveViewer` (`constrained: false`, `boundaryMargin` 80). The map canvas is bigger than the screen and grows with the number of users (rings spread out, so nodes never pile up). One finger drags/scrolls in every direction (up, down, left, right); pinch zooms 1x-4x; double tap zooms in 2x at that spot (double tap again = back to fit). + / − / centre buttons bottom-left. No zoom % shown (you rejected it before).
  - A small hint "Drag to scroll · pinch to zoom" shows the first 3 times, then hides.
  - Mesh chains drawn as today; a blocked phone in a chain is drawn grey but the chain continues through it (it still relays).
  - Tap a user → bottom sheet: avatar, name, @username · link way, chip (Active / Blocked), block info (who, when, reached N, server waiting/done), buttons Block or Unblock (same confirm as E3) + "Blocked list".
  - The small card map stays as it is (same painter, `LinkPathsMap` gets optional `selectedId` / `scale`; old calls unchanged).

### F. Others' phones + blocked phone (mock pages 7, 8)
- [ ] F0 Design rules (mock v2):
  - The chat bar reuses `_blockedBar` (block icon 16, one line, 14 px).
  - The banner copies the home banner style (`_offlineAccountBanner`: rounded 12, icon 18, bodySmall) with a red tint and no close button.
  - Avatars stay `AccountAvatar` (one white letter on a solid colour).
- [ ] F1 Chat with an admin-blocked user: bar "{name} is blocked by admin. You can't message or call {name}." with no Unblock; call buttons hidden; note "{name} was blocked by admin · time".
- [ ] F2 Blocked phone: red banner on Chats / Calls / People; message box and call buttons replaced; old chats readable. Unblock brings everything back at once.

### F+. Background (mock page 9)
- [ ] BG1 `BackgroundRunner` step `(name: 'admin_blocks', run: deps.adminBlocks.start)` after `groups`. With the app closed the phone still gets, checks, saves and passes on blocks / unblocks, calls `updateBlockedPeers` (already in `BackgroundChannels.kt` L217; the D2 Kotlin rules live in the service, so they work with the app closed too), and syncs with the server when online.
- [ ] BG2 A block on MY account while closed: lock at once (send guards read the store) + notification "Your account is blocked by admin" / "You can read old chats but can't send or call." Unblock → "Your account is active again". Uses `showSystemNotification` (id `admin_block_self`, replaces the old one).
- [ ] BG3 Admin phone: one silent notification when the server confirms a block it made ("{name} block saved on the server"). Nothing per phone reached.
- [ ] BG4 When the app opens, the main engine takes over (BackgroundEngine stops first, as today); the state is in the DB, so nothing is lost.
- [ ] BG5 Existing source-scan tests on `background_runner.dart` (bundle177 routes < nearby, pairing; call_handover_176 calls / paused / `deps.calls.start()`) must still pass; the new step is added after `groups`.

### G. Server sync
- [ ] G1 `POST /api/v1/admin-blocks/sync` (device auth). Body `{records, ended}` → the server checks (same rules as B3) and applies to `users.status` when newer (no session revoke). It returns all current records + ended notes.
- [ ] G2 The blocked phone can't pass device auth, so it uses `POST /api/v1/admin-blocks/mine` (device id + token, checked against the device row WITHOUT the status check). It returns only its own record.
- [ ] G3 Web panel suspend / unsuspend: a server-signed record (seq + 1). Existing session revoke only for `disabled`, not `suspended`.
  - **Note:** today `suspended` revokes sessions. The change only makes suspended phones work again after unsuspend; tell the user.
- [ ] G4 App: sync on reconnect (with the 211 pending-revoke hook) and every 10 min while online; mark `server_done`.

### H. Tests + delivery
- [ ] H1 Dart tests `bundle212a..h`:
  - a: record sign / verify, fakes and changed records rejected, ended cert rejected, self-block rejected, newest wins.
  - b: store (DB v35 upgrade from v34, `isBlockedPeer` / `blockedPeerIds` include admin blocks, `blockedChanges` fires).
  - c: spread (digest → ask → records → got-it, hop-to-hop pass-on once, limits).
  - d: send guards (messages, groups, calls) + own-phone banner state.
  - e: panel card / picker / confirm popup / blocked list widgets.
  - f: Link paths map with a blocked node + full-screen map (search, filter, tap sheet).
  - g: chat bar + banner widgets.
  - h: background runner has `admin_blocks` after `groups`; self-block notification.
- [ ] H1b Kotlin `Block212Test.kt` (relay-only trust, first-hop drop, one-step types, blocked next hop carries sealed only). Runs with Gradle, not `flutter test`; old `Link164Test` / `MeshRelayPolicyTest` unchanged.
- [ ] H2 Go test (key, cert, sync, suspended not revoked, cert ended).
- [ ] H3 Full `flutter test`, analyze ≤166, `APPLY_212.md`, app zip + backend zip, `PENDING.md`.

## 4. Phone tests (go into APPLY_212.md)
- [ ] 212-1 Admin phone online → sign in to Admin → panel shows "Offline blocking is ready".
- [ ] 212-2 Server off. Admin (Realme) blocks Ali, who is not nearby → new popup → Ali "Blocked · server later".
- [ ] 212-3 ZTE comes near the admin (Wi-Fi Direct) → within 1 min ZTE's chat with Ali shows "Ali is blocked by admin"; "Reached 1 phone".
- [ ] 212-4 Ali's phone near ZTE → Ali sees the red banner, can't send; ZTE gets nothing from Ali.
- [ ] 212-5 Same on local Wi-Fi (same router, no internet).
- [ ] 212-6 Mesh node: Realme ↔ Ali (blocked) ↔ ZTE in a line (Realme and ZTE out of range of each other). Realme → ZTE message still arrives through Ali's phone; Ali can't read it; Ali's own message to ZTE is dropped at the first phone (log `BLOCK_DROP`). Repeat with a normal (own) block.
- [ ] 212-7 Admin panel offline with Ali nearby and blocked → Link paths shows Ali grey with red ring, ⊘ and a grey dashed line; the list shows "Blocked" + Unblock.
- [ ] 212-8 Tap expand on Link paths → full screen; drag to scroll in all directions, pinch zoom, double tap, search "Ali", filter Blocked, tap Ali → sheet → Unblock asks first.
- [ ] 212-9 Close LinkUp on ZTE and on Ali's phone (swipe away). Block Ali from the admin phone nearby → within 1-2 min ZTE drops Ali's messages and Ali gets the "blocked by admin" notification; unblock → "active again".
- [ ] 212-10 Server on → "Server: done"; web panel Users shows Ali suspended; admin phone gets one silent "saved on the server" note.
- [ ] 212-11 Unblock offline → spreads; Ali can send again without signing in.
- [ ] 212-12 Web panel unsuspend while phones are offline → the first phone online carries it to the others.
- [ ] 212-13 Sign out of Admin → new blocks from that phone are ignored by others.
- [ ] 212-14 A phone that never reached the server ignores blocks (log `ADMIN_BLOCK_REJECT reason=no_trust`).
- [ ] 212-15 Logs from 3 phones (`ADMIN_BLOCK_*`, `BLOCK_DROP`, `TRUST_*`).

## 5. Safety
- Personal blocks: same screens and BlockHub; only change = the blocked phone still relays others' sealed messages (D2, your choice).
- Kotlin: small, listed in D2; old Kotlin tests unchanged (`trustFor` untouched).
- Old tests unchanged. If one needs setup, only setup is added and I tell you.
- Limits on spreading (C2) so the mesh is not flooded. A record is about 1.5 KB.

## 6. Delivery
- App zip (one commit, `v3 3.0.53+124 bundle 212: …`).
- Backend zip (deploy first, `v3 bundle 212 backend: …`).
- Plus APPLY_212.md and the PowerShell commands.
