# TODO 309 - Map data check (15 Nov 11:51 screens + RMX5303 log 10:50-11:50)

Phone: RMX5303 (Sajjad, owner) on **3.0.100+171 (304)** - 307 and 308 are not on the phone yet.
Screens: `uploads/Screenshot_20261115-115122.png` (My links), `uploads/Screenshot_20261115-115129.png` (Admin).
Log: `uploads/LinkUp-logs-RMX5303-2026-11-15-1150.txt`. Code: app `74b7642` (307) + 308 zip.

## Who is who (from the 13 Nov logs of each phone)
| Id (last 8) | Person | How we know |
|---|---|---|
| `ed16a834` | sumaira (ZTE Blade A35) | never in the ZTE's own log |
| `d5d181c0` | ayesha (realme Note 60x) | never in ayesha's own log |
| `9654237e` | kiran (TECNO POP 8) | the 3rd near phone (in both other logs) |

## What the log shows (11:44-11:50)
- All 3 are near: `LINK_AUTH verified` + `PRESENCE_CHANGED ...>Nearby` for all 3 ids up to 11:49:08.
- 11:47-11:49 one Wi-Fi Direct group, ZTE is owner (`WD_PEERS ZTE Blade A35/0/go`); links fixed `lan -> wifi_direct`.
- 11:49:43 this phone is back on the Wi-Fi router (`NET_CHANGE wifi=true`). Log ends 11:50:01; screens are 11:51 (the last minute is NOT in the log).
- Admin map: **`MAP_NODES shown=2 hidden_dupes=2`** (11:49:21) = 4 phones passed the "near" check, **2 were removed as duplicates**. kiran is one of them.

## Screens vs truth
| Person | My links | Admin | Truth |
|---|---|---|---|
| kiran | Local Wi-Fi | missing | near (log) |
| ayesha | Local Wi-Fi | Local Wi-Fi | near |
| sumaira | offline | **Wi-Fi Direct** line | near until 11:49; at 11:51 NOT VERIFIED |

## Root causes (code)

### C1 - kiran removed as a "duplicate" (log proves the dedupe removed him)
- `dedupeNodes` rule 2 (one per account) and rule 3 (same phone name: stale goes) use table data only.
- The account of each phone comes from `_profiles` (`admin_panel_screen.dart` `_refreshBlocks`):
  `directoryProfiles()` is read **newest first**, but the loop writes `profiles[device] = ...` for every row,
  so the **OLDEST card wins** for a phone id. A phone that had another account before (one phone = one account, 235)
  is counted as the old account -> it can collide with another phone of that old account and be hidden,
  and it can show the old name/photo.
- PresenceHub uses `directoryProfileByDeviceId` = server card first, then newest. So admin and My links can
  disagree about who owns a phone id.
- 308 (built, not pushed) makes a phone near now "live", so it wins over stale rows. It does NOT help if two
  near phones get the same (wrong) account from `_profiles`. Which exact rule hid kiran: NOT VERIFIED.

### C2 - sumaira drawn as Wi-Fi Direct from her OWN flag, not from a link to us
- Admin `_onLink` keeps a row if `d.wifiDirectConnected || d.meshAvailable || d.lanAvailable || _recent(d)`,
  and `_flagTag` falls back to these flags when the hub says nothing.
- These flags come from the PEER's `direct_presence` (`home_bloc.dart` `_onDirectPresence`): "**I** am in a
  Wi-Fi Direct group / on Wi-Fi / mesh on" - not "I am linked to **you**". The ZTE was group owner, so it says
  `wifi_direct_connected=true`, and the row stays up to the stale sweep (+ `_recent` 4 min).
- My links uses only PresenceHub (proven path), so it shows offline once the path is gone.
- Same family as TODO 281 (ZTE shown wrong on admin).
- 308 does NOT fix this (flags are still the fallback).

### C3 - "Phones near 2" and hero "Wi-Fi Direct" use the same list/flags -> wrong for the same reasons.

## Fix plan (build only on "Build")
- **G1 (C2, C3)** Admin own view = PresenceHub only, like My links:
  `_onLink` keeps a row only if the PERSON is near (hub); `_flagTag` = hub way only (no peer flags).
  The peer flags stay for the People/device lists (they show the peer's own state there).
- **G2 (C1)** `_profiles`: the NEWEST card wins (stop at the first row per phone id), and the account for the
  duplicate rules = PresenceHub owner first (`directoryProfileByDeviceId` rule), `_profiles` second.
- **G3 (C1)** A phone whose own id is near now is never hidden by rule 2/3; two near phones are merged only
  when the hub says they are the same account.
- **G4** Log line `MAP_DUPES_309 hidden=<id8>:<rule>` once per change, so the next log shows exactly who was hidden and why.

Files: `admin_panel_screen.dart`, `own_links_308.dart` (+ tests). No backend. `link_paths_map.dart` not touched.

## User picks (15 Nov)
- Put the fixes INTO 308 (rebuild the 308 zip, one push, still 3.0.102+173).
- Scope: **G2 + G3 only**. G1 (stop using a phone's own Wi-Fi Direct flag on the admin map) and G4 (log line) are NOT in.
  So sumaira can still show "Wi-Fi Direct" on admin from her own flag (C2 stays open).

## Tests (when built)
- Unit: oldest + newest card for one phone -> newest account used.
- Unit: 2 near phones, wrong shared old account, hub says 2 accounts -> both shown.
- Regression: 308 tests + all map/admin tests + full suite.
- Phone check: same 4 phones; both maps show the same 3 people with the same way; then turn the ZTE off -> grey/away on both within ~70 s.

## BUILT 15 Nov - folded into 308 (app 3.0.102+173, base 74b7642)
- `own_links_308.dart`: `adminCardPerPhone309` (server card, then newest, per phone id) and
  `adminDupeUser309` (near phone: hub owner only; others: hub, then card).
- `admin_panel_screen.dart`: `_profiles` built with `adminCardPerPhone309`; dedupe `userId` = `adminDupeUser309`.
- Tests: 5 more in `test/own_links_308_test.dart` (19 total).
- NOT in: G1 (admin still uses a phone's own Wi-Fi Direct flag), G4 (log line).
