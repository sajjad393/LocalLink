# TODO 202 - media grid, less padding, blue recording wave, words without icon, Private profile moved

- Repo: https://github.com/sajjad393/LocalLink  (base `b8edf97`, bundle 201, 3.0.38+109)
- Server repo (NOT touched): https://github.com/sajjad393/LocalLinkBackend
- New version: **3.0.41+112** (3.0.39 / 3.0.40 were used by the parked group zips).
- No group-phase code. Freeze: "go ahead 202" given. Mock approved ("mock is good").
- Mock: `mock_202_page1.png` ... `mock_202_page5.png` (all pages: `mock_202_pages.pdf`).

## Decisions (yours)
| # | Decision |
|---|----------|
| 1 | Grid like WhatsApp: 1 = real shape (as today), 2 = side by side, 3 = one wide on top + two below, 4 = 2x2, 5+ = 2x2 with "+N" on the 4th |
| 2 | Photos/videos in the grid, documents as rows under it |
| 3 | Everywhere: bubble (1:1 + groups), reply, forward, review before sending |
| 4 | Wave blue only while recording |
| 5 | Padding: my advice (3 px edge, time on the picture, tight reply box) |
| 6 | Remove only the small icon next to the status words; photo badge stays |
| 7 | Profile "Visibility" removed; "Private profile" moves from Settings to Profile ("Privacy" where Visibility was). Phone number: anyone can see it when Private is OFF; only friends when ON |
| - | Viewer has "2 of 7" + strip of small pictures; time on the picture when there is no caption |

---

## 1. Grid in the chat bubble  (mock A1-A6)
**Today:** `message_bubble.dart` builds one full `AttachmentTile` per attachment; `bubble_layout.dart`
(`RenderBubbleContent.performLayout`) stacks every media child (`y += m.size.height`). Each tile is up to
250x360 (`media_frame.dart` `MediaFrame.maxWidth 250 / maxHeight 360`). Group bubble
(`groups/presentation/widgets/group_message_bubble.dart`) does the same.

**Change**
- [ ] New `lib/features/files/presentation/widgets/media_grid.dart` - `MediaGrid(items, width: 250, gap: 2)`.
  - 1 item: no grid, today's tile (bundle 147 shape rule kept).
  - 2: two squares (w-2)/2. 3: one wide (w x (w-2)/2) + two squares. 4: 2x2. 5+: 2x2, 4th darkened "+N".
  - Outer corners radius 15 (bubble 18 minus 3 px edge).
- [ ] `AttachmentTile(compact: true)` = one grid square: cover crop, video play + length bottom-left,
      own ring / download arrow / "Waiting" / "Not sent - tap to retry" / removed-to-save-space look.
      All transfer logic stays in `attachment_tile.dart`; keys stay `att:<msgId>:<attId>`.
- [ ] Split `message.attachments` into grid items (image/*, video/*) and rows (documents, audio). Order:
      grid -> document rows -> caption -> time.
- [ ] Same in `group_message_bubble.dart` (sender name above the grid for others).
- [ ] No sending / receiving change.

## 2. Viewer with swipe  (mock B1-B2, F3)
**Today:** `chat_photo.dart` `ChatPhotoViewer(path, title)` = one photo, `InteractiveViewer`; video opens
`chat_video_player.dart`. No `PageView` anywhere.
- [ ] New `MediaGalleryViewer(items, initialIndex, title)` - `PageView`, top bar "You / 2 of 7 · Today 9:41 PM",
      bottom strip of small pictures (tap = jump), zoom per page (reuse `ChatPhotoViewer` body), video page
      uses today's player.
- [ ] Tap a square -> opens at that item; tap "+N" -> opens at item 4.
- [ ] Single photo bubble: opens as today.
- [ ] Review-before-send mode: title "Ready to send", a "Remove" button instead of forward/menu.

## 3. Less padding  (mock C1-C2)
**Today:** every bubble `EdgeInsets.fromLTRB(md 12, sm 8, md 12, xs 4)` (`app_tokens.dart`); time under media
(`footerGap 3`).
- [ ] Bubble starting with media (photo / video / grid): padding 3 all round; media radius 15.
- [ ] No caption and no document row: time + ticks ON the picture (bottom-right, white, soft dark shade).
      Needs a "time-on-media" option in `bubble_layout.dart` (or an overlay inside `MediaGrid`).
- [ ] Caption: text keeps 9-12 px sides under the picture, time after the text.
- [ ] Text-only bubbles unchanged.
- [ ] `QuoteBox` (`message_options.dart`): bubble padding 3 when a quote is first; inner padding
      `9,5,10,5` -> `7,3,6,3`; picture flush right, full height (today 40x40 + 8 px gap in `quote_thumb.dart`).
- [ ] 1:1 + groups, both sides.

## 4. Grid in the reply  (mock D1-D2)
**Today:** `QuoteThumb.forAttachments` shows only `attachments.first`; `replyKindFor` uses the first attachment;
`ReplyRef` carries only `{id, from, snip, kind}` (no count).
- [ ] Words: "📷 7 photos", "🎥 2 videos", "📷 2 photos, 1 video" (photos/videos only; docs as today).
- [ ] Small 2x2 (40-44 px) with "+N" in `ReplyBar` and `QuoteBox`.
- [ ] Data: read the quoted message on this phone by `reply.id` (same lookup as bundle 199 jump). Fallback =
      today's label + single thumb. Optional new field `n` in `ReplyRef` JSON (old phones ignore it).
- [ ] Pictures from saved thumbnails (`MediaStorageService.thumbView`); nothing new sent.
- [ ] Tap quote -> jump + blue flash (as today).

## 5. Forward screen  (mock E1-E2)
**Today:** `forward_screen.dart` shows no preview. `forward_hub.dart` `forward()` already sends each
`ForwardItem` as ONE message with all its files -> grid works on the other phone.
- [ ] `ForwardScreen(items: ...)` new optional param; callers in `chat_screen.dart` and `group_chat_screen.dart`.
- [ ] Card on top: small grid + "7 items" / "5 photos, 1 video, 1 file" / "Sent as one message";
      several messages -> "3 messages".

## 6. Review before sending  (mock F1-F3)
**Today:** `pending_attachment_strip.dart` = name chips (54 px, 📎 + name + delete). Used in `chat_screen.dart`
l.1180 (+ group composer).
- [ ] 44 px thumbnails (video play mark), document tile (icon + short name), × on each, "+" at the end
      (calls the same pick action as the composer +).
- [ ] Tap a thumbnail -> `MediaGalleryViewer` review mode (photos/videos only).
- [ ] `ChatComposer` buttons unchanged; caption = the message box text (as today).

## 7. Recording wave  (mock G1-G3)
**Today:** `voice_recording_widgets.dart` `VoiceLockedPanel` -> `VoiceWave(color: VoiceBarColors.red)`.
- [ ] Live wave -> `Theme.of(context).colorScheme.primary`.
- [ ] Red dot, red pause, bin, send, paused panel (already blue) and sent voice notes unchanged.

## 8. Status words without the icon  (mock H1-H5)
**Today:** `core/widgets/presence_way.dart`: `PresenceWayLine` = `PresenceWayIcon` + 4 px + words;
`PresenceWayCard` title has an 18 px icon; `PresenceWayCallChip` has a 15 px icon.
- [ ] Remove the icon in all three (words, styles and colours unchanged).
- [ ] Keep `PresenceWayIcon` - the photo badge uses it (`messenger_conversation_tile.dart` l.281).
- [ ] Update tests that expect the icon in the line/card/chip (`bundle183_test.dart` l.964 checks the badge -> keep).

## 9. NEW: Profile "Visibility" removed, "Private profile" moved  (mock page 5, P1-P6)
**What "Visibility" does today:** `profile_screen.dart` l.~370-386 = one card "Phone visibility"
(Public / Contacts). It decides who gets your phone number inside your signed profile
(`directory_repository.dart` `_buildOwnProfile` l.~221 + `_redactForGossip` l.~452 + `_profileForRequester`):
Public = everyone who finds you (strangers see it masked `0301 ••• 5678`, bundle 170);
Contacts = only friends. Name search on/off is a separate thing = Settings > Private profile
(`discoverableByName`, bundle 196).

**Change (one switch decides both):**
- [ ] `profile_screen.dart`: delete the "Visibility" section and the `visibility` state.
- [ ] Move `PrivateProfileRow` out of `messenger_settings_screen.dart` into
      `lib/features/account/presentation/widgets/private_profile_card.dart`; show it in Profile under a new
      "Privacy" title (where Visibility was; hidden during onboarding like today). Key `profile_private_switch`.
- [ ] Settings > PRIVACY keeps Read receipts + Blocked people only.
- [ ] Rule: Private OFF -> `discoverableByName: true`, `phoneVisibility: 'public'`;
      Private ON -> `discoverableByName: false`, `phoneVisibility: 'contacts'`.
      Used by the switch AND by Profile "Save changes".
- [ ] Words under the switch: OFF "Anyone can find you by name and see your phone number."
      ON "Nobody can find you by name search. Only friends get your phone number."
- [ ] Turning ON still asks first (`showPrivateProfileSheet`, unchanged); OFF does not ask.
- [ ] One time after update: if the saved phone choice doesn't match the rule, fix it once, publish the
      profile, log `PHONE_VIS_ALIGN from=<old> to=<new> private=<y/n>`.
- [ ] Stranger screen still shows the number masked (bundle 170, unchanged). Server field `phone_visibility`
      still sent (no server change).

## 10. Tests (new `test/bundle202_*_test.dart`)
- [ ] Grid 1/2/3/4/7 items: sizes, "+3", time on the grid; docs under the grid; ring/"Waiting" per square; group bubble.
- [ ] Viewer opens at the tapped item, "2 of 7", swipe; review mode Remove.
- [ ] Padding: media bubble edge 3; text bubble unchanged; caption spacing; quote box padding.
- [ ] Reply "📷 7 photos" + 2x2; old single-photo reply unchanged; fallback when the original is gone.
- [ ] Forward card counts; forwarding still one message.
- [ ] Review strip thumbnails, × removes the right one, + calls pick.
- [ ] Locked wave colour == primary; paused panel unchanged.
- [ ] Line/card/chip have no icon; photo badge still has it.
- [ ] Profile: no "Phone visibility"; switch in Profile; ON -> discoverableByName false + contacts; OFF -> public;
      Save changes keeps the rule; Settings has no Private profile row; one-time align.
- [ ] Update old tests: `bundle183_test.dart` l.574 (`settings_private_switch`), `settings_read_receipts_198_test.dart`,
      version scans (`bundle173`, `read_receipt_apply_198`, `chat_reply_zoom_199`, `nearby_190`).
- [ ] Full suite in 8-file chunks; `flutter analyze` on touched files.

## 11. Phone tests after building
1. Send 2, 3, 4, 7 photos in one message - grid shapes, "+3", time on the picture.
2. Photos + a PDF - grid on top, PDF row below, caption under.
3. Tap a square - viewer opens on it; swipe through all incl. a video.
4. Receiving phone while downloading - arrow/ring per square.
5. Reply to the 7-photo message - "📷 7 photos" + small grid; tap the quote jumps.
6. Forward it - card shows counts; friend gets ONE grid message.
7. Pick 5 files before sending - thumbnails, × removes one, + adds, sends as one grid.
8. Record + lock a voice note - wave blue; pause = blue preview as today.
9. Top bar, People, info card, call screen - words only; photo badge still there.
10. Profile - no Visibility; Private profile switch works (ON asks first). Settings - no Private profile row.
    Friend sees your full number; a stranger (Private OFF) sees it masked; Private ON - stranger sees no number
    and can't find you by name.
11. Same in a group chat (server group).

## 12. Not touched
How files are sent/received, server, calls, `ChatComposer` buttons, voice-note bubble, groups phases,
the confirm sheet text for Private profile.
