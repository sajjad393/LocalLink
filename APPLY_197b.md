# Bundle 197b - media storage (3.0.31+102)

Scope: TODO_197b + mock 197b v1 + your answers Q1-Q5. Nothing else.

**Both phones should have 3.0.31.** (An older phone still works; it just doesn't clean up or make small pictures.)

## What is new

1. **Small pictures** (320 px JPEG, about 15-40 KB each, encrypted like the other files)
   - Made for every photo and video, sent and received, the first time it shows in a chat.
   - Old media gets them once, in the background: starts 2 min after the app opens, 1 file every 2 s, stops during a call or when the app goes to the background.
2. **Free up space automatically** (switch ON by default, Settings › Storage)
   - Removes LinkUp's copy of photos, videos and documents **not opened for 10 days**, only when the phone is **more than 70% full**.
   - Oldest first. **Stops as soon as the phone is at 70% or less** (Q3).
   - Never: voice notes, my unsent / undelivered media (group: not yet accepted by the server), anything during a call.
   - Runs 60 s after the app opens, then on app resume if the last run was more than 24 h ago, and after a download bigger than 20 MB.
   - "Opened" = full-screen photo, video played, document Open, Save to phone, Forward. Scrolling past does not count.
3. **Removed media in the chat**
   - Photo / video: the small picture, blurred and a bit darker, plus the chip "Removed to save space". A video keeps its length chip ("0:42").
   - No small picture: a dark box with the same chip.
   - Document: grey name, "Removed to save space", no button. Voice note (only removable by hand in Storage): label, no play button.
   - **Ali taps** -> "Removed to save space. Ask Sajjad to send it again." If he saved it to his phone first, the saved copy opens in the phone's viewer.
   - **You tap your own** -> while the photo is still in your Gallery it looks normal and a tap copies it back and opens it. If it's gone from your Gallery too -> "This photo is no longer on your phone." (video: "This video...", document: "This file...").
   - No Download button for removed media, ever.
4. **Save to phone** (hold sheet only, Q1)
   - Row "Save to phone" after Forward, only on received photos / videos / documents that are downloaded, and only on Android 10 or newer (Q5).
   - Photos and videos -> Gallery › LinkUp (Pictures/LinkUp). Documents -> Download › LinkUp.
   - Snackbar "Saved to Gallery › LinkUp" / "Saved to Download › LinkUp". The bubble shows "✓ Saved" (documents: "· Saved" after the size).
   - LinkUp never deletes or changes a saved copy.
   - On removed media the hold sheet has no Forward and no Save to phone (Select bar: no Forward either).
5. **Settings › Storage** (row between "Keep LinkUp running" and "Reset setup")
   - Row subtitle "LinkUp uses 1.2 GB" ("Checking…" until counted).
   - Screen: size + colour bar (Photos / Videos / Documents / Voice), "Phone: 78% full · 6.9 GB free", the switch, "Last clean-up: today, 9:10 AM · 23 files, 410 MB", CHATS, BIGGEST FIRST.
   - A chat: chips All / Photos / Videos / Docs / Voice, 3-column grid biggest first. Tap a photo = full screen. Hold = pick; tap more; red "Delete 3 files (19.7 MB)" -> asks first -> the messages stay with the small picture + "Removed to save space" (Q2).
6. **Admin panel › "Test clean-up now"** (Q4): asks first, then one run as if every file were 11 days old and the phone 80% full. Voice notes and unsent media still stay. Switch OFF -> nothing removed.
7. **Leftover fixes**
   - L1: Delete on a failed (red !) message now also deletes its files.
   - L2: the picker's extra copy (`files/locallink_picks`) is deleted 24 h later, at app start, unless a message still uses it.
   - L3: deleting a message / clearing a chat also deletes its small picture and the server's `-thumb` file.
   - L4: files no message uses are only counted in the log (`STORAGE_ORPHANS`), not deleted.

## How it works (differences from TODO_197b)

- **Database v27 = one new side table** `media_state(file_id, thumb_path, media_ms, source_uri, opened_at, removed_at, saved_uri)` instead of 6 new columns in the two attachment tables. Message saving, history re-save and the Attachment model stay untouched (nothing can wipe the new data).
- Small pictures: `<db>/attachments/thumbs/<fileId>.jpg.enc`. Made from the plain view copy the chat already decrypts (no extra decrypt), and for the sender right after staging.
- The picker copy is swept after 24 h (not right after staging), so an outbox retry can never lose its file. Group sends still read from that copy, so it is kept while a message uses it.
- No "open now" registry: opening sets "last opened", so a file you just opened is never 10 days old.
- A file can be on disk as `name` or `name.enc`; delete / size checks look at both.
- Kotlin: new helpers only in `MainActivity` (channel `locallink/voice_notes`) + 2 new files `MediaStorageNative.kt`, `MediaStoragePolicy.kt`. The Kotlin service is unchanged. No new Android permission.
- Android keeps at most 512 Gallery links per app (128 on Android 10). When an old one drops, that own photo counts as "gone from Gallery".

## Logs (one line per action / run)
`STORAGE_CHECK used=78% free_mb= linkup_mb=`, `MEDIA_CLEANED count= mb= photos= videos= docs= skipped_recent= skipped_unsent= ms=`, `MEDIA_CLEAN_SKIPPED reason=off|under70|call|busy|recent_run`, `MEDIA_CLEAN_TEST`, `THUMB_BACKFILL made= failed= left= ms=`, `THUMB_FAILED` (max 5 per run), `GALLERY_LINKS kept= max=`, `GALLERY_LINK_DEAD`, `MEDIA_RESTORED_FROM_GALLERY kind=`, `MEDIA_SAVED_TO_PHONE type= kb=`, `MEDIA_SAVE_FAILED`, `MEDIA_DELETED_MANUAL count= mb=`, `STORAGE_AUTO_CLEAN on|off`, `PICKS_SWEPT count= mb=`, `STORAGE_ORPHANS count= mb=`, `MESSAGE_FAILED_DELETED id= files=`.

## Checks done here
- `flutter analyze`: 0 errors.
- Full test suite `-j 1`: 1075 passed (2 old tests updated: the 197a "no DB change" guard now allows the v27 side table; the bundle183 Blocked-people test scrolls the row fully on screen because the new Storage row pushes it lower).
- Kotlin compile check (kcheck): clean. Kotlin unit tests: all pass (incl. new `Media197bTest`).
- Not tested here (needs the phones): MediaStore saving, Gallery links, StatFs numbers, thumbnail making, encryption of thumbnails.

## Phone tests - Sajjad (Realme) + Ali (ZTE), both on 3.0.31
| # | Do this | Expected |
|---|---------|----------|
| R1 | Send a photo and a video to Ali | Both look as today. Log has no THUMB_FAILED |
| R2 | Settings › Storage | Row under Keep LinkUp running; screen shows size, colour bar, "Phone: N% full", switch ON, chats biggest first |
| R3 | Ali: Admin › Test clean-up now | Old photo / video / document show a small picture + "Removed to save space"; voice note still plays |
| R4 | Ali taps the removed photo | "Removed to save space. Ask Sajjad to send it again." |
| R5 | Sajjad: Test clean-up now, tap your sent photo | Opens (copied back from your Gallery). No Download button anywhere |
| R6 | Sajjad: delete that photo from the Gallery, clean-up again, tap it | "This photo is no longer on your phone." |
| R7 | Send a photo with Ali's phone off, run Test clean-up | That photo is NOT removed (not delivered) |
| R8 | Ali holds a received photo › Save to phone | "Saved to Gallery › LinkUp"; photo is in the Gallery app; bubble shows "✓ Saved" |
| R9 | Ali saves a PDF | In Files › Download › LinkUp |
| R10 | Ali: Test clean-up, then tap the saved photo | The saved copy opens (phone's own viewer) |
| R11 | Hold a removed photo | No Forward, no Save to phone |
| R12 | Storage › Ali › hold 3 files › Delete 3 files | Asks first; files gone; chat shows the small pictures + label; size goes down |
| R13 | Switch OFF, Test clean-up | Nothing removed; log `MEDIA_CLEAN_TEST removed=0 reason=off` |
| R14 | Start a call, then open the app | Clean-up does not run during the call (`reason=call`) |
| R15 | Send 3 files, reopen the app after 24 h | `PICKS_SWEPT count=` > 0; Storage size not doubled |

Note R3: a photo sent less than a minute ago by a phone still on 3.0.30 has no small picture -> dark box + label (expected).
