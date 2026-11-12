# TODO 277: group voice not delivered via server + group message order + hide video button

Status: OPEN (build only on "Build"). Goes in a NEW version 3.0.86+157 (user choice), on top of the 3.0.85 commit.
Source: screenshot `Screenshot_20261112-155345.png` + `LinkUp-logs-RMX5303-2026-11-12-1554.txt` (C71, 3.0.84+155).

## What the log shows (Office group: You, Ibrahim, noshad; group works Nearby, origin=both)
| Time | Line | Meaning |
|---|---|---|
| 15:48:27 | `GROUP_CREATE members=2 origin=both` | group on server + phones |
| 15:48-15:49 | `send_group_message` + `group_message_ack` | texts went by server, OK |
| 15:50:20.164 | `FILE_UPLOAD_SEND_START bytes=33504 name=voice_...m4a` | voice 3:50 upload starts |
| 15:50:41-42 | `send_group_message` + `group_message_ack` | **server was ON and answering** |
| 15:50:20-15:51:08 | nothing for this file | no reply to the upload (no `FILE_UPLOAD_RESPONSE_HEADERS`), no error line, **no second try** although the group retry runs every 5 s while the socket is up |
| 15:51:08 | `WS_STREAM_DONE` / `WS_CLOSED` | user turned the server off (later, by hand) |
| 15:51:38 | `GROUP_FILE_QUEUED` + `GROUP_NEARBY_SEND` + `GROUP_FILE_SENT` x2 | voice 3:51 went Nearby at once, delivered |
| 15:52-15:53 | `GROUP_NEARBY_SEND kind=msg` | texts by Nearby, OK |

So the failure happened **with the server on**: the voice upload got no answer for more than 45 s while texts and
the socket worked. Turning the server off later is NOT the cause. The 3:50 voice never went Nearby (both members were
near on the same Wi-Fi) and still shows the clock.

Server side (`attachments.go:84 UploadFile`): a 33 KB file is quick; a busy server answers 429 at once (would be logged).
The server's reason is NOT VERIFIED. If the server window from 12 Nov 15:50 is still open, the lines for
`POST /api/v1/files` would show it.

## Causes (code)
**A. Delivery: a group message waits only for the server**
- A1 `group_messaging_service.dart:79` `_queue`: sends Nearby only `if (group.nearbyOnly || !socket.isConnected)`.
  With the server on, the message goes ONLY into the server outbox.
- A2 `group_messaging_service.dart:1083-1088` `flush`: the upload error is swallowed with no log line
  (`catch (_) { uploadFailed = true; break; }`). The upload has 40 s + 30 s timeouts
  (`file_transfer_service.dart:110/116`). No second `FILE_UPLOAD_SEND_START` came before 15:51:08, so the send
  loop (`_flushing`) stayed busy with this one upload; every other group message from this phone waited behind it.
- A3 `flush` starts with `if (_flushing || !socket.isConnected) return;`. Nothing hands
  queued group messages to Nearby when the upload fails or the server goes away.
  (Not related: the 1:1 item `...aadde09a31fa` to the ZTE waits with "recipient device not found"; that is by design.)

**B. Order: the group chat sorts by server number**
- `local_store.dart:4502` `groupMessages()` uses `orderBy: 'server_seq ASC,id ASC'`. A message that never reached the
  server (Nearby only, or still waiting) has `server_seq = 0`, so it jumps to the TOP when the chat opens
  (the voice notes at 3:50/3:51 above "You created group" and 3:48 "hello").
- `group_chat_bloc.dart` `_upsert` appends new messages at the end. That is why the 3:52/3:53 Nearby texts look right
  now; they jump to the top next time too.
- The Chats list preview and unread already use `created_at` (`local_store.dart:3292`, `4590`). 1:1 uses `created_at ASC`.

**C. Video button**
- `call_action_bar.dart:101` shows the camera button when `showVideoButton248(session)` (connected nearby call).
  Caller and callee use the same bar.
- `call_screen.dart:187` still opens "Switch to video call?" if the other phone (old app) turns its camera on.

## Fix (smallest)
- **A-1 hand off to Nearby:** in a group that works Nearby (`worksNearby && isActive && !nearbyOnly`), a queued message
  goes to Nearby (`near.fanOut`, the same packet the 3:51 voice used) once, when
  (a) its server upload fails or gets no answer, **with the server on** (this case), or (b) the server socket goes down
  while it is still in the group outbox.
  It is kept in the server outbox too: it still goes to the server later; members drop the second copy by id (already true).
  One hand-off per message id (a set + the existing `nearby_sent` mark). Log `GROUP_HANDOFF_277 why=upload_fail|server_down n=`.
- **A-2 voice / photo Nearby first (my advice):** while the server is on, a message WITH files in a Nearby group also
  goes Nearby at once to the members who are near now (`nearNow`). The existing G7 rule then skips the upload when all
  members have it (`GROUP_FILE_UPLOAD_SKIPPED`). Texts stay as now (server). Others are not touched.
- **A-3 log + no long block:** `GROUP_FILE_UPLOAD_FAILED reason=<timeout|http_NNN|socket|...> ms=` instead of the silent
  catch, so the cause shows next time. One upload may hold the group send loop for at most 45 s in total (send + reply);
  after that it is handed off (A-1) and retried later, and the other messages go on.
- **B-1 order by time:** `groupMessages()` orders by `created_at` (parsed time), then `server_seq`, then `id`.
  `_upsert` puts a new or late message in its time place, not always at the end. No DB change.
- **C-1 hide video:** `showVideoButton248` returns false (button gone for caller and callee). The "Switch to video call?"
  dialog is not shown; a camera request from an old phone is declined quietly (`declineVideoSwitch`).
  No other video code is changed (video stays STOPPED).

## Tests (new `test/bundle277_*`)
- Hand-off: server on, upload throws -> `fanOut` called once with the files; socket down with outbox items -> fanOut once
  each; nearbyOnly / not worksNearby -> not handed off; second trigger -> no second fan-out.
- A-2: files + member near -> fanOut at once; text only -> not.
- Order: rows with server_seq 0 / >0 and mixed times come back in time order; a late upsert lands in its place.
- Video: the bar has no `call_video_toggle_248` in a connected nearby call; the peer camera request -> no dialog, decline sent.
- Old test change (listed): `bundle248_test.dart:32` `isTrue` -> `isFalse`, `:43-45` button found -> findsNothing.

## Files
`group_messaging_service.dart`, `group_nearby_service.dart` (only if `nearNow` needs exposing), `local_store.dart`
(`groupMessages` order), `group_chat_bloc.dart` (`_upsert`), `call_action_bar.dart`, `call_screen.dart`,
`test/bundle248_test.dart`, new tests. No backend change. Version 3.0.86+157 (4 version anchors), own zip + commit after 3.0.85.
