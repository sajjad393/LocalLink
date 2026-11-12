# TODO 273 - "My links" map card for every user (contacts' live status)

Status: PROPOSAL ONLY (freeze ON). Build only after the user says "Build".
User request (14 Nov): show the map card on the user screen too, so a user sees their contacts' live
status. If noshad reaches bilal through shahbaz, and shahbaz is not a friend of noshad (or bilal),
show shahbaz as a LinkUp-logo profile (no name, no photo).
Code: app `LocalLink` @ `6bf30bd`. No backend change.
User choices (14 Nov): card at the TOP OF THE CHATS SCREEN; ALL contacts (offline in grey, no line);
build TOGETHER with TODO_272 as one app version 3.0.85+156.

## What each phone already knows (code)
- `lib/core/presence/presence_hub.dart`: per contact device, live way (`PresenceWay`: wifi, wifiDirect,
  mesh, online, connecting, offline) + for mesh `hops` and `via` (= the NEXT phone's device id only,
  lines 29-37, 443-449). Updated live, no server needed.
- Users already see the way as words: chat header "Nearby · Mesh, via 1 phone" and the info card
  "Your messages hop through 1 other LinkUp phone (X's)" (`lib/core/widgets/presence_way.dart:39-70`).
  So showing paths to users is already accepted; the map only draws the same facts.
- The admin map widget (`LinkPathsMap`, You in the middle, one line per phone, server cloud) is the same
  model, so it is reused (no second map system).

## What the card shows (each user, own phone only)
- You in the middle; ONLY your contacts (not blocked, not deleted) around you, with photo + name
  (existing avatar widget).
- Line per contact by its live way: Wi-Fi (teal), Wi-Fi Direct (yellow), Mesh (purple), server
  (blue, through the cloud). Offline contacts: grey circle, no line ("Connecting" = grey dashed).
- Card place: `lib/features/home/presentation/screens/home_screen.dart` `_chatsTab()` ListView, after
  `NearbyReadyCard()` and before the "Conversations" label (~line 1287). Small card (height ~110) with
  title "My links" and "3 live · 5 offline"; tap -> full map. Card menu "Hide map"; "Show My links map"
  switch to bring it back (saved setting). Hidden while the Chats search is open.
- Many contacts: the card shows live ones first; offline ones are placed on an outer grey ring.
- Mesh with a relay: You -> relay -> contact.
  - relay is one of YOUR contacts -> their photo + name;
  - relay is NOT your contact -> LinkUp logo circle (`assets/brand/splash_logo.png`), no name, no photo,
    no device id; tap -> "A LinkUp phone helping to pass your messages. It can't read them."
  - more than 1 phone in between (hops >= 3): the phone only knows the first relay; the rest is one
    logo circle with "+N" (N = phones between - 1).
- Never shown to users: links between OTHER people (e.g. noshad <-> Ibrahim), server map data, device
  ids, phone names. That stays admin-only (TODO_272).
- Tap a contact -> opens the chat (existing route). Card -> full screen with zoom (existing full map
  screen in a "user" mode: no blocking actions, no admin filters).

## Rules kept
- No new network traffic and no new background work: drawn only from PresenceHub while the card is on
  screen; motion off with reduce motion / battery saver and when the screen is hidden (existing 217 rules).
- Works offline (Wi-Fi / Wi-Fi Direct / mesh); server only adds the cloud line.
- Video, transport and routing unchanged; no pop-ups.

## Files if built (planned)
- New `lib/features/contacts/presentation/widgets/my_links_map_273.dart` (builds nodes from
  PresenceHub + contacts; the friend / logo rule; pure function + widget).
- `lib/features/admin/presentation/widgets/link_paths_map.dart`: a node kind "relay" drawn with the
  LinkUp logo, and You -> relay -> contact lines (needs the `extraEdges` from TODO_272 B-3; one lock
  hash update for both bundles).
- `link_paths_full_screen.dart`: user mode (no admin actions).
- `home_screen.dart` (the card) + the Settings switch + new `test/bundle273_my_links_test.dart`.
- Log `MYMAP_273 contacts=N live=L relays_known=K relays_logo=U` once per open.

## Honest limits
- For 2+ phones in between, only the first relay is known; the rest shows as one "+N" logo.
- Mesh relay info appears when a mesh route is in use (same as the chat header words today).
