# TODO 320 - Conversations + chat viewer redesign (16 Nov, on top of 319 = 3.0.110+181)

Mock: `~/mocks/n320/requests_chat_mock.html` (light + dark). User picks (16 Nov): **A one list**, viewer **all 3 as in mock**, bugs into this TODO, 319 kept (user applies + pushes).
Freeze ON: code only after "Build". Planned version 3.0.111+182.

## Why (user: "very ugly and confusing")
- Requests tab shows a request twice: `_carousel` (Live, auto-advance `_syncAdvance` / `advanceEvery`) AND `_progressCard` under "In progress" (`admin_conversations_screen.dart` `_requestsTab` l.427).
- Rows carry 3-4 chips (`Chip307` step + New only + Kept + range + Cancel text) - `_progressCard` l.612, `_finishedRow` l.692.
- Chats and Requests are 2 tabs (`Tabs221`, `_tab`) for the same chat.
- Viewer: blank page + 2 px spinner while `v == null` (`admin_chat_viewer_screen.dart` build, `CircularProgressIndicator`); waiting = one grey line `_note(waitingForPhoneOfChat304)` (`_body` l.760).

## Plan (A)
| # | Change | Where |
|---|---|---|
| R1 | One list, no tabs: header, server pill, search "Find a chat", filter chips All / Coming / Ready / Kept (counts) | `admin_conversations_screen.dart` (drop `Tabs221` use, `_tab`) |
| R2 | "Now" card = only requests on their way (sent / waiting / coming), one row each: avatars, name, ONE status line with dot (blue coming / orange waiting / green ready / lock kept), thin bar + "40 of 80 parts" when coming, X = cancel (asks first). No carousel, no auto-advance, no "In progress" copy | same; `_carousel`, `_progressCard`, `_syncAdvance` removed from the tab |
| R3 | "Chats" card = every other chat ONCE (server chats + kept copies + finished requests merged by chat via `_requestOf`): one button - Open (ready) / New (kept copy -> Get new messages only, 318) / Get chat | `_chatRow`, `_readyTile`, `_finishedRow` -> one `ChatRow320` |
| R4 | Cancelled / up to date = status line only ("Cancelled 14 Nov", "Up to date"); no extra chips | same |
| R5 | Viewer loading: header + 3 shimmer bubbles instead of the spinner | viewer build |
| R6 | Viewer waiting card: route (You - avatars, grey when offline), "Waiting for X's or Y's phone", "It comes by itself ... no time limit", facts Asked / Sent to N phones / Last seen (only when known, else row hidden), Cancel request (red tonal, asks first) | `_body` (empty) |
| R7 | Viewer coming: thin strip under the header "Coming · 40 of 80 parts" + bar (replaces the B9 card); messages already here shown; 3 shimmer rows + "More messages on the way..." at the end. Time estimate only if 2+ updates give a rate, else hidden | `_progressCard`, `_body` |
| R8 | Viewer ready: "Kept on this phone until 23 Nov" one quiet green line at the top (instead of the long header); header sub = "Full chat · from kiran's phone"; photo/video still coming = "Coming by itself" tag on the thumb | `_sub`, bubble media |
| R9 | Same on the web owner viewer (310 rule: same as app) - list + viewer states | `admin_web` (backend) - only if user agrees, else app only |
| R10 | Words: new `.arb` keys en + ur (304 rule, LTR) | `app_en.arb`, `app_ur.arb` |

Not changed: grey bubbles (310), New request sheet (318), live notification card (307/317), sealing, calls, 319 carrier fixes.

## Bugs reported from screenshots - checked against the code
- Raw `llev:v1:{...}` text (Screenshot_20261116-113951): **already fixed in 317** (`GroupEvent.parse` -> `_systemLines317`, viewer l.792). The screenshot was taken on 3.0.107. Regression test only.
- "Get full photo / video" buttons (113845): **already removed in 317** (no `getFull*` use in the viewer; G6 test). Screenshot from 3.0.107. Regression test only.
- "Empty voice bubble" on the waiting page (113933): it is **Android's volume slider** (speaker icon + "..."), not the app. No fix.

## Tests (planned)
- One list: each chat once (server chat + request + kept copy -> one row); filter counts; no `live307_carousel`, no auto-advance timer.
- Now rows: status words per step; X asks then cancels; bar only when coming.
- Chats rows: button per state (Open / New / Get chat).
- Viewer: shimmer while loading (no spinner); waiting card facts (last seen hidden when unknown); coming strip + shimmer; ready kept line; llev line + no Get full button (regression).
- Full text on every phone (no ellipsis rule): 320 dp wide + big text, no overflow.
- Regression: 221 / 307 / 310 / 313 / 314 / 317 / 318 / 319 tests - old tests that lock the carousel / tabs will be listed and changed only where the design removes them (names given before Build).

## As built (16 Nov, 3.0.111+182 on `d6c0cab`, app only)
- R1-R4 Conversations: one list (`_list320`): header, server pill, "Find a chat", chips All / Coming / Ready / Kept with counts. "Now" card (`conv320_now`) = requests on their way, one status line (`StatusLine320`) + bar "40 of 80 parts" + X (asks first). "Chats" card (`chats221_list`) = every chat once (`_rows320`, merged by `chatKey320`), one button Open / New / Get chat. `Tabs221`, `_carousel`, `_progressCard`, `_syncAdvance` removed. New widgets in `conversations_kit320.dart`.
- R5 viewer loading = `BubbleSkeleton320` (3 grey bubbles), no spinner.
- R6 waiting card `_waiting320`: You -> avatars, "Waiting for X's or Y's phone" (group: "a phone in <group>"), "comes by itself ... no time limit", facts Asked ("Today 9:54") / Sent to N phones; **Last seen is not known on the Owner phone, so that row is never shown** (rule: unknown rows hidden). Cancel request (red tonal, asks first) only while nothing came.
- R7 coming strip "Coming · X of Y parts" + bar; messages already here; 3 shimmer rows + "More messages on the way..."; time guess only with 2+ updates (`AdminChatViewerScreenEta320`).
- R8 kept: green "Kept on this phone until 23 Nov" line; header sub "Full chat · from kiran's phone"; photo/video on its way = "Coming by itself" tag.
- R9 web: NOT done (app only, not agreed yet). R10: 31 new words en + ur.
- Old tests changed (they locked the old tabs/carousel/header): `bundle221b` b3/b5, `conversations_307` (3 carousel tests -> one-list tests, viewer test, fade-in assert), `conversations_313` (tab -> filter, matrix, E4), `conversations_314` (~l.465), `bundle318` K7 (viewer header). New `test/bundle320_test.dart` (23).
