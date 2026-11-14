# TODO 308 - Both maps must show the true path (analysis only, freeze ON)

Report (15 Nov 11:11): "Map is not showing truly connected path. Check both maps connection between users".
Screens: `uploads/Screenshot_20261115-111144.png` (Admin Link paths), `uploads/Screenshot_20261115-111133.png` (Chats My links).
Code read: app `228ed49` (304). 307 does not touch these files.

## What the two maps show (server off)

| Thing | Admin Link paths | Chats My links |
|---|---|---|
| kiran | missing | Local Wi-Fi line to You |
| ayesha | Local Wi-Fi to You | Local Wi-Fi to You |
| sumaira | Mesh line straight to You | Mesh via ayesha |
| Server line | dashed red/grey to You | dashed red/grey to You |
| Count | "2 Phones near" | "3 live" |

## Root causes (from code)

### R1 - The two maps read different data
- **My links** (`my_links_map_273.dart`): your contacts + `PresenceHub.wayInfoOf(id)`.
  `wayInfoOf` -> `statusOf` = best of ALL phones of that PERSON (`_devicesOf[user]`).
- **Admin** (`admin_panel_screen.dart` `_onLink` l.490): rows of the `known_devices` table.
  A row is shown only if `adminHubNearby254(d.id)` = `statusOfDevice(d.id)` (THIS ONE phone id, no person merge)
  or the table flags (`wifiDirectConnected` / `meshAvailable` / `lanAvailable`) or `presence_local_at` < 4 min.
- So if kiran's live link is on a phone id that is not the id in the admin table
  (old id after reinstall, or a new id never saved in `known_devices`), My links shows kiran and admin drops kiran.
- Second way kiran can vanish: `dedupeNodes` rule 3 (`link_paths_map.dart` l.157):
  "same phone name, live beats stale" uses `presence_local_at` only, not the hub.
  If kiran's row is not stamped in the last 4 min and another live row has the same phone model name, kiran is hidden.
- Which of the two hit kiran: **NOT VERIFIED** (needs the `MAP_NODES shown= hidden_dupes=` log line; no logs now).
- The count "2 Phones near" = `onLink.length` (l.887), so it is wrong for the same reason.
  Note: My links counts contacts only; admin counts all phones. After the fix they match when all near phones are contacts.

### R2 - Admin mesh line is a guess, not the real route
- Admin `_nodesFor` (l.416) makes a mesh node with no `via` and default line.
- `link_paths_map.dart` l.1043 draws all mesh nodes as ONE chain sorted by distance on screen, ending at You.
  With one mesh phone (sumaira) that is a straight line to You. It never reads the route.
- My links uses `wayInfoOf(id).via` = the phone next to us on the last real answer (fresh <= 15 s,
  `presence_hub.dart` `_meshWay`), else the route table. So **My links (sumaira via ayesha) is the true one**.
  NOT VERIFIED on phones.

### R3 - Server line while the server is off
- Not a data bug: `link_paths_map.dart` l.1024 always draws the self->Server line; when off it is dashed red/grey on purpose (Bundle 216).
- Small map has no "offline" word (only the full map shows it, l.1124), so it looks like a link.
- Any change here needs `link_paths_map.dart` (sha-locked) + updating its 5 lock tests:
  `link_paths_zoom_222`, `bundle217ui`, `bundle254`, `mini_map_298`, `link_apart_291`.

### R4 - (checked at build: NOT a bug)
- My links already drops `self -> friend` when the friend has its own line (`clean` step). F4 not needed.

## Fix plan (build only on "Build")

- **F1 (R1, R2)** One shared builder `OwnLinks308` (new file) used by BOTH maps:
  input = people (admin: `known_devices` rows grouped by user; My links: contacts) + `PresenceHub`.
  - person status / way = `statusOf` / `wayInfoOf` (person merge), node id = the phone that is near now.
  - mesh: `noLine: true` + extra edges along `via` (friend node or LinkUp relay logo) - same as My links today.
  - Admin `_onLink`: keep a row if the PERSON is near (`statusOf`), not only this phone id.
  - `dedupeNodes` rule 2/3: a phone the hub says is near always wins (`ownIds`-style `nearIds` set), never hidden.
  - Admin also adds a near phone that is missing from `known_devices` (name from `PresenceHub.nameOf`).
- **F2 (R1)** "Phones near" = the same list the map uses (count from F1).
- **F3 (R3)** depends on user pick (see questions). Needs the sha lock update.
- **F4 (R4)** draw `self -> friend` only if the friend has no own line.
- **F5 (server ON)** admin then shows the server's map (`link_map_network_272.dart` `merge`), which has no via lines yet = TODO 281 F-1/F-2 (on hold). Not in 308 unless picked.

Files: `my_links_map_273.dart`, `admin_panel_screen.dart`, `link_map_network_272.dart`, new `own_links_308.dart`, (+ `link_paths_map.dart` only if F3 changes the line).
No backend change (unless F5). Mesh voice / 8 hops untouched.

## User picks (15 Nov)
- Server off: keep the dashed line + red X and the word "off" on the small map too (F3, sha lock + 5 lock tests updated).
- Scope: F1 + F2 + F3. F4 and F5 NOT in 308.

## Tests (when built)
- Unit: person with 2 phone ids, near on the new id -> admin node shown, id = new id (kiran case).
- Unit: same model name, stale stamp but hub near -> not hidden.
- Unit: mesh via a contact -> both maps give edges You->ayesha, ayesha->sumaira, no You->sumaira.
- Unit: mesh via a non-contact -> relay logo in both maps.
- Unit: "Phones near" count == admin map nodes.
- Regression: all old map tests (`link_*`, `mini_map_298`, `bundle216*`, `bundle254`, `my_links_273*`, `link_map_network_272*`) + full suite.
- Phone check: 4 phones, server off, ZTE far: both maps show the same people and the same line for sumaira.

## BUILT 15 Nov (app 3.0.102+173, on top of 307)
- New `lib/features/admin/presentation/widgets/own_links_308.dart`: `OwnLinks308.meshLines` / `clean` / `admin`,
  `adminPersonNear308`, `adminPersonTag308`, `adminSeenAt308`.
- My links uses `OwnLinks308.meshLines` + `clean` (same output as before).
- Admin: `_hubNearby` / `_hubTag` = person rule; dedupe `seenAt` = `adminSeenAt308` (near now = live); userId falls back to `PresenceHub.userOf`;
  `_network272` builds own nodes + lines with `OwnLinks308.admin` and passes `ownEdges` to `merge`.
- `link_map_network_272.dart`: `merge(ownEdges:)` kept server off and on; a phone turned Server drops its own lines and gets the server line back.
- `link_paths_map.dart`: red X + "Off" in the middle of the down server line (beside the line); sha lock in `link_paths_zoom_222_test.dart` updated.
- Tests: `test/own_links_308_test.dart` (14).
