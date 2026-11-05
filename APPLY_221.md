# APPLY 221 - chats from phones, server postman, soft delete, delete completely (app 3.0.61+132 + backend)

**Order (after 220):**
1. **Backend 221 zip**, then commit, `go test ./...` and deploy (migration 60). The first clean-up can take a minute on a big database; it is logged (`POSTMAN_...`).
2. **App 221 zip**, then commit and build the APK.

Phones older than build 132 keep working but never answer a Get chat. The request shows **Pending · old app**.

## PowerShell

Backend:
```
cd "C:\Users\sajjad Ahmed\Downloads\localLinkBackend"
Expand-Archive -Force -Path "C:\Users\sajjad Ahmed\Downloads\locallink_backend_221_2026-11-06.zip" -DestinationPath .
go test ./...
git add -A
git commit -m "v3 bundle 221 backend: server keeps messages only until delivered, chat list without text, owner gets chats from phones, delete completely"
git push
```

App:
```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force -Path "C:\Users\sajjad Ahmed\Downloads\locallink_app_221_2026-11-06.zip" -DestinationPath .
flutter pub get
flutter test
git add -A
git commit -m "v3 3.0.61+132 bundle 221: chats from phones (full or dates, parts over every link), soft delete for users, delete completely"
git push
```

## What the Owner sees
- **App -> Admin -> Conversations** (new row, Owner only, mock A-1):
  - Green bar "Server connected · requests go by the server", or orange "No server · requests go by Wi-Fi Direct / mesh".
  - **Chats** tab: 2 letters for a private chat or 1 for a group, "42 messages · 12:21" / "Group · 5 members", and **Ask phones** (or the request state: Pending / "40 of 80 parts" / Ready).
  - **Requests N** tab: "Pending · since 7 Nov · Full chat" + **Cancel**. Offline requests say "Sent by Wi-Fi Direct · passes phone to phone / No time limit · goes to the server log later".
  - **New request** (mock A-2): Private chat (First / Second person) or Group; Full chat / 7 days / 30 days / Dates; "Their phones send these messages (also ones they deleted). They see nothing."
- **Viewer** (mock A-3):
  - Header: "1 Nov - 7 Nov · from Ali's phone"; route tag per message (Server / Wi-Fi Direct / Mesh / Local Wi-Fi).
  - Grey tag "Deleted by user · 5 Nov 14:02"; faded "Outside the dates (phone clock)" for the +1 day margin.
  - Thumbnail + **Get full photo**; after 60 days "File removed after 60 days · thumbnail only".
  - Strip "40 of 80 parts · the rest is on the way" (half answers can be read).
  - Long-press: Copy text / **Delete completely** (from every phone, also deleted copies). Menu: Delete chat completely (Full / 7 / 30 days, with counts) / Close.
- **Web -> Conversations:** the list shows who / how many / when (no text), plus Get chat, Requests and Delete completely (already rendered in the 221 web shots).
- **Admin actions** list: Get chat rows show the parts tag + bar.

## What users see
Nothing. There is no "Admin viewed" note. Delete for me / exit + delete group now **hides** messages (soft delete): text is kept forever, media for 60 days (thumbnails kept). Only the Owner's Delete completely removes everything.

## How it works (short)
- **Server postman:** a direct message stays on the server until it is delivered, then for 7 days (max 60 days if never delivered). Groups: 60 days, or 7 days after everyone got it. Daily VACUUM. `conv_index` keeps the chat list (counts only).
- **Get chat / Get file** are 220 cards (need 1). They go to all phones, friends or not. A phone of the chat builds the answer: 32 KB parts, locked for the server or the admin phone (llaa1 box).
- **Parts travel over every link** (server, router Wi-Fi, Wi-Fi Direct, mesh: Kotlin frame `admin_act_parts`).
  - A carrier says "I carry parts 1-40 of 80", never "stop". Others fetch only the missing parts.
  - Only the server or the admin phone sends the real stop (`answer_ack`, signed). Unsigned stops are ignored.
  - A full file goes only to the admin phone or the server. A carrier holds at most 20 MB for others.
- **No time limit:** Pending until a phone of the chat answers.
- **Delete completely:** the ids go to `purged_ids` first (60 days). Then live rows + notification, hidden rows, files (+ `.enc`). A late copy that still arrives by mesh is removed at once.

## Files

**Backend (new):**
- `internal/httpapi/admin_chat_221.go`
- `internal/httpapi/postman_221.go`
- `internal/httpapi/admin_chat_221_test.go`, `postman_221_test.go`, `admin_web_221_test.go`

**Backend (changed):**
- `cmd/server/main.go`
- `internal/store/store.go` (migration 60)
- `internal/httpapi/admin_conversations.go`
- `internal/httpapi/adminweb/app.js`, `views.js`, `styles.css`

**App (new):**
- `lib/core/services/hidden_store_221.dart`
- `lib/features/admin/data/actions/chat_answer_builder.dart`, `chat_answer_carrier.dart`, `chat_answer_reader.dart`, `delete_completely_doer.dart`
- `lib/features/admin/presentation/screens/admin_conversations_screen.dart`, `admin_chat_request_sheet.dart`, `admin_chat_viewer_screen.dart`
- `test/bundle221a_test.dart` (8 tests), `test/bundle221b_test.dart` (7 tests)

**App (changed):**
- `lib/app/app_dependencies.dart` (wiring), `lib/core/config/app_build.dart`, `pubspec.yaml` (3.0.61+132)
- `lib/core/services/local_store.dart`: the 3 x 2 added lines (`deleteMessageLocal`, `deleteGroupMessageLocal`, `deleteGroupLocal`: copy to hidden, keep files) + the `hide221` field
- `android/.../mesh/MeshBlockPolicy.kt` (`admin_act_parts`)

**Outside the TODO file list (needed):**
- `admin_action_card.dart`, `admin_action_doers.dart`, `admin_action_service.dart`: the 3 new actions, the reply key, the `chat221` doer
- `admin_actions_screen.dart`: parts tag + bar
- `admin_panel_screen.dart`: the Conversations row
- `chat_answer_carrier.dart`: `isAdminPhone` (only an admin phone fetches its answers from the server)

**Old test changed (expectation only):** `test/nearby_190_test.dart` version line -> `3.0.61+132` (same as every bundle).

## Differences from TODO_221
- App DB version stays 34: the hidden tables use CREATE TABLE IF NOT EXISTS (no 35 -> 36 step needed).
- Backend: `conv_index` by triggers; `admin_chat_request_meta` table; clean-up runs in the postman tick; file answers up to 72 MB on the server (50 MB per file on the phone).
- Offline cards skip the admin's own phones. A phone with no copy sends no receipt (another phone answers). Delete receipt = `ok`.
- The admin phone's copy of an answer goes 24 h after it is first opened (or on Close).

## Phone tests
- 221-1 Server clean-up (test clock): server rows gone; both phones still show the chat with ✓✓; web Diagnostics DB size drops after the night VACUUM.
- 221-2 Sumaira deletes 2 messages (for me) -> Get chat (Full) -> both shown "Deleted by user".
- 221-3 Get chat Last 7 days -> only that week (+ greyed margin).
- 221-4 Both phones offline -> Pending; Sumaira online -> ready.
- 221-5 Offline Owner app (no server): request by Wi-Fi Direct; a 3rd phone carries; the answer arrives.
- 221-6 Walk away halfway -> "40 of 80 parts" (half readable) -> another meeting finishes it.
- 221-7 Get full photo (online and on a direct link).
- 221-8 Delete completely by range -> gone on both phones, also from a new Get chat.
- 221-9 Exit a group and delete it -> messages hidden; Get chat for that group still shows them.
- 221-10 Users see nothing during 221-2..8.
- 221-11 Old phone (3.0.60) -> "Pending · old app" for Get chat.

Logs to send if something fails: `ADMIN_ANSWER_BUILT`, `ADMIN_ANSWER_PARTS_SENT`, `ADMIN_ANSWER_STOP`, `ADMIN_ANSWER_CAP_FULL`, `ADMIN_PURGE_DONE`, `ADMIN_PURGE_LATE_COPY`.
