# TODO 302: right labels + new footer / banner / update sheet + stopped phones can still update

Status: TODO ONLY (freeze on). Base app `5e34ade` (3.0.97+168). Next app build would be 3.0.98+169.
Mock: `mocks/labels_footer_302.html` (light + dark in one page).

## What the user saw (14 Nov, 2:36-2:40)
- Sajjad (owner, 3.0.96) set Minimum version = 3.0.96 -> 3 phones on 3.0.92 stopped.
- Sajjad's chat with ayesha: header "Blocked", pill "You blocked ayesha", footer "ayesha has an old LinkUp...".
  Sajjad never blocked ayesha; only her app version is stopped.
- Ayesha's phone: Chats list shows sumaira "Blocked" (same cause).
- Ayesha's update: "New LinkUp found nearby 3.0.96 · 106.8 MB" stopped at 3.2 MB -> "Could not get it now".
- Footer (both phones) looks flat and ugly; banner and sheet do not match it.

## Code facts (checked in 5e34ade)
- `lib/core/services/local_store.dart:2615 blockedPeerIds()` = my blocks + admin blocks (`_adminBlockedIds`) +
  `VersionGuard.instance.droppedPeers` (version stopped).
- `lib/app/app_dependencies.dart:657` BlockHub `loadPeerIds: store.blockedPeerIds`, so
  `BlockHub.isBlockedDevice()` is true for admin-blocked AND version-stopped phones.
- `chat_screen.dart:1100+`: `iBlocked = hub.isBlockedDevice(device.id)` -> MutedAvatar, red "Blocked" subtitle (:1199),
  "You blocked X" chip (:1023 `_blockedChip`), `_blockedBar` (:977).
- Same `isBlockedDevice` -> `MessengerConversationTile._blockedTile` + `BlockedPill` (home_screen.dart:1442),
  `call_history_tile.dart:131`.
- Footer: `AdminBlockedBar` (`lib/core/widgets/admin_blocked_banner.dart:87`) and `_blockedBar`: flat
  `surfaceContainer` strip + top border line, 14 px grey text, TextButton. Texts from
  `adminBlockBarText()` (`admin_block_book.dart:98`). Group chat uses `AdminBlockedBar` too (group_chat_screen.dart:1465).
- Banner: `lib/core/widgets/version_banner.dart` (tint + small text + TextButton).
- Update sheet: `lib/features/share_app/presentation/update_sheet.dart` (text buttons only, no Try again).
- Update stall (NOT VERIFIED, needs logs): `version_rule_service.dart:468` dropped set changes ->
  `onDroppedChanged` -> blocked list pushed to native (`sealing_peer_transport.dart:1181 _pushBlocked`) ->
  `LocalLinkTransportService.kt:917 updateBlockedInternal` closes the contact link to that phone
  (`MeshBlockPolicy.closeLink`, log `LINK_AUTH contact link closed ... reason=blocked`).
  A download riding that link stalls; `silent_update_275.dart _httpDownload` gives up after 30 s with no data.

## Phases

### A. Right label for each case (no more "You blocked" unless I blocked)
| Case | Chats / Calls label | Chat header line | Avatar | "You blocked" chip |
|---|---|---|---|---|
| I blocked them | red "Blocked" | red "Blocked" | muted | yes |
| Admin blocked them | red outline "Admin blocked" (short, fits the row) | red "Blocked by admin" | muted | no |
| Their LinkUp stopped by admin | amber "Old LinkUp" | amber "Old LinkUp" | normal (crown stays) | no |
| They blocked me | none | normal | normal | no |
- BlockHub ids = my own blocks only (new `store.myBlockedPeerIds()`); admin from `AdminBlockBook`,
  old from `VersionGuard.isPeerDropped`. New `PersonState302` helper picks one case (order: mine > admin > old).
- New pills next to `BlockedPill`: `AdminBlockedPill302`, `OldAppPill302`.
- Sending/receiving rules do not change: `isBlockedPeer()` still refuses messages/calls for all 3 cases.

### B. New footer (one widget for every case, chat + group chat)
- `ChatNoticeBar302`: floating rounded card (radius 20, margin 12, no top line), round tinted icon 36 dp,
  bold title + one muted line, optional filled pill button.
| Case | Title | Line | Button |
|---|---|---|---|
| I blocked them | You blocked kiran | They can't message or call you. | Unblock |
| They blocked me | You can't message kiran | - | - |
| Admin blocked them | ibrahim is blocked by admin | You can't message or call ibrahim. | - |
| Admin blocked me | Blocked by admin | You can read chats but can't send. | - |
| Their old LinkUp | ayesha has an old LinkUp | You can message and call after they update. | - |
| My old LinkUp | Your LinkUp is old | Stopped by admin. Update to send and call. | Update |
- Replaces `AdminBlockedBar` + `_blockedBar`; same keys kept (`chat_admin_blocked_bar`, `chat_blocked_bar`,
  `chat_blocked_unblock`, `chat_version_update`).

### C. Chats banner
- Same card look as B: red icon circle, "Stopped by admin", "Read chats only. Update to send and call.",
  filled "Update" pill. Yellow warning banner: same card, amber, keeps the × (hide for today).

### D. Update sheet
- Bigger title, size line, progress with "16.0 of 34.6 MB · 46%".
- "Could not get it now": line "LinkUp tries again by itself." + buttons OK (tonal) and Try again (filled).
- Cancel as a tonal pill. No names (Bundle 275 rule stays).

### E. Stopped phones can still get the update
- Version-stopped phones are NOT pushed to the native blocked list (links stay up); only my blocks + admin
  blocks are. Messages/calls from them are still refused by `isBlockedPeer()` (unchanged).
- Confirm first with logs (both phones, ~2:39): Sajjad `VERSION_PEERS_DROPPED`, `LINK_AUTH contact link closed`;
  ayesha `APP_UPDATE_SILENT download_fail=...`.

## Note
- A phone shows the new look only after it has 3.0.98. Ayesha (3.0.92) keeps the old banner/footer/sheet until
  she updates; E (on Sajjad's phone) is what lets her get it.

## Tests (planned)
- New: labels per case, footer per case, banner, sheet Try again, blocked list without version-stopped phones.
- Old tests that lock texts/keys stay; only the ones listing the old flat bar would be updated (to be listed at build).
