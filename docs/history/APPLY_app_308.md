# APPLY app 308 - both maps show the true path (3.0.102+173)

Base: app 307 (3.0.101+172) = `74b7642` (pushed, CI OK).
Scope: TODO 308 F1 + F2 + F3, plus TODO 309 G2 + G3 (user picks 15 Nov). F4 not needed (already OK); F5, G1, G4 not in.

## What changes for the user
- Admin › Link paths and Chats › My links now use ONE rule:
  - a person counts as near if ANY of their phones is near (kiran no longer drops off the admin map);
  - a phone near now is never hidden as a "stale twin" (same model name / old phone id);
  - Mesh lines go through the real next phone (sumaira via ayesha on both maps), never a guessed chain;
  - "Phones near" = the people on the admin map.
- Server off: the dashed line now has a red X and "Off" beside it (small and full map).
- 309 G2: each phone gets its right owner (server card, then the NEWEST card; before, the oldest card won).
- 309 G3: a phone near now is merged with another only when PresenceHub says it is the same account (kiran no longer "hidden_dupes").

## Files (14)
- `lib/features/admin/presentation/widgets/own_links_308.dart` (NEW) - one rule for both maps + 309 owner/duplicate rules
- `lib/features/admin/presentation/screens/admin_panel_screen.dart` - person rule, near-now = live, own lines, newest card, hub owner for duplicates
- `lib/features/admin/presentation/widgets/link_map_network_272.dart` - `merge(ownEdges:)`
- `lib/features/admin/presentation/widgets/link_paths_map.dart` - red X + "Off" on the down server line
- `lib/features/contacts/presentation/widgets/my_links_map_273.dart` - uses OwnLinks308 (same output)
- `lib/core/config/app_build.dart`, `pubspec.yaml` - 3.0.102+173
- `test/own_links_308_test.dart` (NEW, 19 tests)
- `test/link_paths_zoom_222_test.dart` - sha lock updated (308 F3)
- `test/bundle223_logs_test.dart`, `test/nearby_190_test.dart` - version
- `docs/history/TODO_308.md`, `docs/history/TODO_309.md`, `docs/history/APPLY_app_308.md`

## Tests
| Check | Command | Result |
|---|---|---|
| New tests | `flutter test --no-pub test/own_links_308_test.dart` | 19 pass, EXIT 0 |
| Full app suite | 316 files in 11 chunks | 3103 pass, 0 fail, all EXIT 0, `[E]`=0 |
| Analyze | `flutter analyze --no-pub` | 361 issues, all old; 0 in the 308 files |
| Look | painted small map light + dark | red X on the dashed line, "Off" beside it |

## Not checked
- Real phones (4 phones, server off, ZTE far): both maps show the same people and the same sumaira line. NOT VERIFIED.
- 11:51 log proved kiran was removed by the duplicate rules (`hidden_dupes=2`); the exact rule is NOT VERIFIED. G2+G3 cover all of them.
- sumaira can still show "Wi-Fi Direct" on admin from her own flag (G1 not picked).
- Real Android build: CI builds it.

## Phone checks
1. Server off, all phones near: admin "Phones near" = number of people on the admin map; kiran shows with his own name and photo.
2. ZTE (sumaira) out of direct range, reached through ayesha: both maps draw ayesha -> sumaira, no line You -> sumaira.
3. Mesh through a phone that is not your contact: My links shows the LinkUp logo in the middle; admin shows the person if they are on the admin map, else the logo.
4. Server off: dashed line with a red X and "Off"; server on: blue line, no X.
5. Regression: Wi-Fi / Wi-Fi Direct lines, blocked grey lines, full-screen map zoom, calls and chats unchanged.
