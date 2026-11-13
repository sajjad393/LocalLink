# APPLY app 3.0.95+166 (TODO 298 A-I)

Zip: `locallink_app_298_2026-11-14.zip`, on top of GitHub `23c09b7` (3.0.94+165).
App only. Any server works (no backend change for 298). Apply this zip BEFORE app 299.

## What changes
- **A. Full screen map:** big map > "Full screen" (under the zoom buttons). Map fills the phone, status and navigation
  bars hidden, "Exit full screen" pill. Back leaves full screen first. Bars come back on exit.
- **B. One search look everywhere:** one grey pill; a thin round ring while you type. No blue box inside.
  Chats, chat search, New group, Add members, Forward, People, admin lists. Add Contact keeps its ring.
- **C. Call crown:** the role crown on an incoming / running call no longer covers "LinkUp voice call".
- **D. Small map (Chats card):** people spread on both sides of You. Pinch 0.5x-4x. "Reset" pill only after a zoom or move.
  One finger still scrolls Chats at normal size. Admin card: only the spread.
- **E. Way in chat:** no divider lines. A tiny way icon before the time on received messages; tap = toast "Came by ...".
  Long press > Info still shows the full way.
- **F. Calls in chat:** WhatsApp-style call bubbles (old calls too). Tap = call back.
- **G. Clock card:** shows 3 s, then slides away.
- **H. Crown tip:** stays 7 s.
- **I. Recovery code to WhatsApp:** a designed card picture; the caption is only the code. If the picture cannot be
  made, only the code is sent as text.

## Files
Dart: new `core/widgets/search_pill_298.dart`, `link_balance_298.dart`, `mini_map_zoom_298.dart`, `route_mark_298.dart`,
`call_bubble_298.dart`, `recovery_card_298.dart`; changed `link_paths_full_screen.dart`, `link_paths_map.dart`,
`my_links_map_273.dart`, `chat_search_bar.dart`, `chats_search.dart`, `new_group_screen.dart`, `group_info_screen.dart`,
`forward_screen.dart`, `contacts_screen.dart`, `admin_list_page.dart`, `admin_kit216.dart`, `chat_screen.dart`,
`message_bubble.dart`, `incoming_voice_call_body.dart`, `call_header.dart`, `crown_tip_290.dart`,
`recovery_code_save_235.dart`, version files.
Android: `MainActivity.kt` (picture to WhatsApp), new `ShareFileProvider298.kt`, `res/xml/share_paths_298.xml`, manifest provider.
Tests: new `search_map_298_test`, `call_crown_298_test`, `mini_map_298_test`, `chat_calls_298_test`.
Old tests changed on purpose (listed in the plan): `link_paths_zoom_222` sha (map file changed), `crown_tip_290` (7 s),
version lines. Nothing removed.

## Tests (here)
- `flutter analyze`: 0 errors.
- Full Flutter suite: 303 files, 13 chunks, **2948 tests, all passed**. One chunk was killed by the sandbox running out
  of memory (not a test failure); its 25 files were run again alone: 244/244 passed.
- NOT checked here: real phones, WhatsApp, the Kotlin build (CI builds the release APK).

## Phone check
1. Big map > Full screen: bars hidden; Back = exit first; bars back.
2. Type in every search: grey pill + ring, letters show at once.
3. Incoming call from an admin on the Realme / ZTE: crown does not cover "LinkUp voice call".
4. Chats map card: people on both sides; pinch in/out; Reset appears and works; one finger scrolls Chats.
5. A chat: no way lines; tap the tiny icon by the time = "Came by ..."; call bubbles; tap one = call back.
6. Clock card 3 s; crown tip 7 s.
7. Settings > recovery code > Save on WhatsApp: the card picture, caption = only the code.

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_298_2026-11-14.zip" .
git add -A
git add -f docs/history/TODO_298.md docs/history/APPLY_app_298.md
git commit -m "v3.0.95+166: full screen map, one search pill everywhere, call crown no longer covers the title, small map spread both sides + pinch + Reset, way icon by the time instead of divider lines, WhatsApp-style call bubbles with call back, clock card 3 s, crown tip 7 s, recovery code card picture with code-only caption"
git push
```
