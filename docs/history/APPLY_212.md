# APPLY 212: admin blocks / unblocks any user with no internet

App 3.0.53+124 · DB v34 (no change) · no new permissions.
Backend: separate zip `locallink_backend_212_2026-11-05.zip` (migration v55). **Deploy the backend first.**
**Apply and push 211 first** (app + backend). 212 is built on top of 211.

## What changed
**A. Admin panel: "Block users (all phones)"** (it replaces "Local moderation")
- A status line at the top:
  - "Offline blocking is ready", or
  - "Connect to the server once to turn on offline blocking", or
  - "Only the owner admin can block users".
- **Block or unblock a user**: anyone this phone has seen, or who is nearby. Search, and chips Active / Blocked by admin / Blocked · server later.
- **Blocked by admin**: the list, with Unblock.
- **Blocked on this phone**: the old list. It still works.
- The Block button by a nearby phone now blocks for everyone. Until offline blocking is ready, it still does the old block on this phone only.

**B. New pop-up (asks first)**
- Block: No messages or calls / Goes out right away / Old chats stay / Still helps the mesh.
- Unblock: Messages and calls work again / Goes out right away / No new sign-in.

**C. How it spreads**
- The admin phone signs the block. Phones check the signature, keep it, and pass it on one step at a time over local Wi-Fi, Wi-Fi Direct and mesh. That includes strangers' phones and blocked phones.
- Each phone sends a short check every 60 s and when a phone links. A phone that was away gets the missing blocks then.
- "Got it" notes go back, so the admin phone shows "Reached N phones".
- Server sync runs on connect and every 10 min. Newest block/unblock wins everywhere.
- Background: this works with the app closed (new background step after groups).
- A phone that has never reached the server ignores blocks (it can't check them).
- Signing out of Admin ends that phone's key. New blocks from it are ignored.

**D. The blocked phone**
- Red banner on Chats, Calls and People: "Your account is blocked by admin. You can read old chats but can't send or call."
- In chats the message box is replaced by "Blocked by admin. You can't send." No calls.
- One notification when blocked, and one when it is active again.
- Other phones show "Ali is blocked by admin" in their chat with Ali, and drop Ali's messages.

**E. Blocked phones still help the mesh** (your choice)
- This applies to admin blocks AND normal blocks. A blocked phone still carries other people's locked (sealed) messages. It can't read them.
- Its own messages are dropped at the first phone (log `RELAY BLOCK_DROP`).
- This changes bundle 164, where a blocked phone's link was cut.

**F. Link paths map**
- Blocked users show grey, with a red ring, a red badge and a grey dashed line. The legend says "Blocked · relays only".
- The new expand button opens a full-screen map: drag in any direction, pinch zoom (1x-4x), double tap, + / - / centre buttons, search a name, filter chips (All / Wi-Fi Direct / Mesh / Local Wi-Fi / Server / Blocked).
- Tap a user to open a sheet with Block / Unblock (it asks first).

**Backend**
- New: server key (`GET /api/v1/trust`), admin offline key (`POST /api/v1/admin/offline-cert`), block sync (`POST /api/v1/admin-blocks/sync`, `/mine`).
- Web Suspend/Unsuspend now makes a signed block/unblock record, so it spreads to offline phones too.
- **Behaviour change:** web "Suspended" no longer ends the user's sessions (only "Disabled" does). Unsuspend brings the phone straight back with no new sign-in.
- New Go tests (`admin_blocks_212_test.go`).

## Where things are kept (no DB change)
These go in the app settings table:
- `admin_blocks_v1`: block records.
- `admin_certs_ended_v1`: ended keys.
- `server_trust_key`: the server key, saved the first time.
- `admin_offline_cert_v1`: this phone's admin key.
- `link_map_hint_shown`: the map hint shows 3 times.

The plan said DB v35. I kept v34, because a DB bump breaks 3 old tests.

## Old test touched
- Version stamp in `test/nearby_190_test.dart` → 3.0.53+124 (done every bundle). No other old test changed.

## New tests
- Dart: `test/bundle212a..g_test.dart` + `test/support/b212_fakes.dart`.
- Kotlin: `Block212Test.kt`.
- Go: `admin_blocks_212_test.go`.

## Phone tests (in this order)
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

