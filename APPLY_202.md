# APPLY 202 - photo grid + swipe viewer + tighter picture bubbles + profile privacy (3.0.41+112)

Base: git b8edf97 (bundle 201). No group-phase code inside (the group chat only gets the same
bubble / reply / review-strip look). 3.0.39 and 3.0.40 stay reserved for the group zips.

## Steps (PowerShell)

    cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
    git pull
    Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes202_2026-11-04.zip" .
    git add -A
    git add -f APPLY_202.md TODO_202.md
    git reset -q -- android/local.properties
    git commit -m "v3 3.0.41 bundle 202: media grid + viewer + tight picture bubbles + reply grid + forward card + review strip + blue wave + status words + profile privacy"
    if ($LASTEXITCODE -eq 0) { git push }
    flutter clean
    flutter pub get
    flutter build apk --release

## What changed (mock pages 1-5)

1. Grid (A1-A6), 1-to-1 and groups. One message with 2+ photos / videos = one grid, 250 wide,
   2 px gaps: 2 = side by side, 3 = one wide + two, 4 = 2x2, 5+ = 2x2 with "+N" on the 4th.
   One photo keeps its real shape. Every square keeps its own ring / arrow / "Waiting" / retry /
   "Removed to save space". Videos: play mark + length. Documents and voice notes = rows under
   the grid. Order: grid, document rows, caption, time.
   New files: `media_grid.dart`, `media_tile_look.dart`, `media_gallery_viewer.dart`,
   `messaging/presentation/widgets/bubble_media.dart`.
2. Viewer (B1). Tap a square = full screen "Sajjad · 2 of 7 · 4:12 PM", swipe, small pictures
   at the bottom, pinch zoom. "+N" opens at item 4. Videos use the normal player. A square never
   opened in the chat shows "Not downloaded yet". One photo still opens the old photo viewer.
3. Picture bubbles (C1-C3): 3 px edge, picture corners follow the bubble, caption under the
   pictures with 12 px side space. No caption and no document = time + ticks on the picture
   (white on a soft shade); size chips move to the top-right then. Quote box padding 7,3,6,3,
   picture close to the right edge. Text bubbles unchanged.
4. Reply (D1-D2): 2+ photos/videos = small 2x2 (+N) and "📷 7 photos" / "📷 3 photos, 1 video",
   in the reply bar and in the quote. Uses this phone's copy; not found = old words.
5. Forward (E1): card on top "7 items / 5 photos, 1 video, 1 file / Sent as one message",
   several messages = "3 messages". Sending is unchanged.
6. Before sending (F1-F2): 44 px pictures, document tile (icon + short name), x on each, "+"
   adds more. Tap a picture = "Ready to send" viewer with Remove. Group composer too.
7. Recording wave (G2): blue while recording + locked. Red dot / pause / bin unchanged.
8. Status words (H1-H5): no icon next to the words (top bar, People, info card, call chip).
   The photo badge keeps its icon.
9. Profile privacy (page 5): Profile "Visibility" removed. New "Privacy" section there with the
   "Private profile" switch (moved from Settings; Settings > PRIVACY = Read receipts + Blocked
   people). Rule: Private OFF = anyone can find you by name and see your number (strangers still
   see it masked); ON = no name search, only friends get the number. Used by the switch and
   by "Save changes". One time after the update, a saved phone choice that does not follow the
   switch is fixed and the profile is published again - log
   `PHONE_VIS_ALIGN from=<old> to=<new> private=<y/n>` (setting `phone_vis_align_202`).
   Note: people with Private OFF who had chosen "Contacts" now share their number (as agreed).

No new permission, no server change (`phone_visibility` still sent), no file-transfer change.

## Checked here

- flutter analyze: 0 errors, no new warnings (156 old notes, same as before)
- Full test suite: 1236 passed, 0 failed (31 new tests in bundle202_media_grid_test.dart +
  bundle202_privacy_test.dart; 7 old tests updated: Private profile moved, chips -> strip,
  quote source check, version)
- Phone tests (TODO_202.md section 11) are the real proof.
