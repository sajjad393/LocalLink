# TODO 215: group "Pending" member instead of the top strip + Account arrow

- Status: **PLAN only. Freeze ON.** Nothing is built until you say "go ahead" for 215.
- Built on top of 214 (pushed: app `c0552f9`, backend `1fd6e6b`).
- Target: app **3.0.56+127**, DB stays **v34**, **no backend change**, no new permissions.
- Mock: `mock_215_page1..5.png` + `mock_215_all.jpg`.

---

## 0. Your words
- "I have added sumaira into family group but she is not active online, WiFi direct or mesh. Why banner continuously showing on top. Show pending in group members not on main page."
- "Instead of pencil icon show next arrow like other screen for goto edit profile."

## 1. Code facts (checked in the pushed code today)
**Why the strip stays**
- `group_chat_screen.dart` L1407-1408: `if (_adding) GroupAddingBanner(...)`.
- `_adding` (L465) = group active AND any invite whose state is not `added`.
- Invite states (`group_nearby_service.dart`):
  - `waiting`: set for every new member of a phone-made group (L398-403).
  - `added`: set only when that member's phone confirms it got the group card (L921-925).
  - `failed`: set after 7 days with no reach (L683-687).
- So while Sumaira is not Online / Wi-Fi Direct / mesh, her state stays `waiting` and the strip never goes. That is by design today (bundle G3, mock 6).

**What already exists and is reused**
- Sumaira is already in the group member list at once (`store.replaceMembers`, L396). Group info shows her today, just without "Pending".
- `GroupNearbyHub.loadInvites` (who is waiting / added / failed) and `GroupNearbyHub.retry` (send the group again now).
- The chat already shows the small line "You added sumaira" (`group_event.dart` L127). It stays.
- Group info reloads on every `GroupChangeHub` change (L104-106). `added` and `failed` both fire a change, so the tag can clear by itself.
- Member row `_MemberRow` (group_info_screen L919), member sheet `showGroupMemberSheet` (group_info_sheets L183).

**Account pencil**
- `account_center_screen.dart` L233: `Icon(Icons.edit_outlined, key: ValueKey('account_profile_edit'))` at the end of the profile card. The card already opens Edit profile on tap (`_openProfile`).
- Old test `bundle183` L793 looks for the key `account_profile_edit`, and L794 checks the card height is 104. **Keep the same key and size**, so the old test stays unchanged.

## 2. Files
| File | Change |
|---|---|
| `lib/features/groups/presentation/screens/group_chat_screen.dart` | Remove the strip from the chat page (`_adding`, `_openAdding`, `_loadInvites`, `_invites`, the banner line). |
| `lib/features/groups/presentation/widgets/group_nearby_widgets.dart` | New `GroupPendingTag` (orange "Pending" pill) and `groupPendingLine(invite, near)`. **Keep** `GroupAddingBanner` + `showAddingPeopleSheet` (old test `groups_g3` uses them; no longer shown in the app). |
| `lib/features/groups/presentation/screens/group_info_screen.dart` | Load invites; members title "3 members · 1 pending"; pending tag + line on the row; pass it to the sheet; handle Try again. |
| `lib/features/groups/presentation/widgets/group_info_sheets.dart` | `showGroupMemberSheet(..., pending:)` optional: Pending block + **Try again**. New enum value `GroupMemberChoice.retry` (added at the end). |
| `lib/features/account/presentation/screens/account_center_screen.dart` | Pencil → arrow `Icons.chevron_right` (same key, same colour as other rows). |
| `pubspec.yaml`, `lib/core/config/app_build.dart`, `test/nearby_190_test.dart` | Version 3.0.56+127 (as every bundle). |
| New tests | `test/bundle215a_test.dart` (chat), `test/bundle215b_test.dart` (group info + sheet), `test/bundle215c_test.dart` (Account arrow). |

Nothing else changes: no service, DB, Kotlin or backend change (except §8 point 2 if you say yes).

## 3. Phases

### Phase A: group chat page clean (mock page 2)
- [ ] A1. Remove `if (_adding) GroupAddingBanner(...)` from the chat body.
- [ ] A2. Remove `_invites`, `_loadInvites()` (and its call in `_reload`), `_adding`, `_openAdding()` from the chat screen. Remove imports only if they become unused.
- [ ] A3. The "You added sumaira" chat line and the top bar ("Ali, sumaira, You") stay as they are.
- [ ] A4. Sending to the group, auto-adding when she comes Nearby / Online, and the 7-day retry timer: **no change** (service code untouched).

### Phase B: "Pending" in Group info (mock page 3)
- [ ] B1. `_reload` also loads invites through `GroupNearbyHub.loadInvites` (only for phone-made groups, `_group.worksNearby`). Map: member id → invite. Pending = state `waiting` or `failed`.
- [ ] B2. Members title:
  - none pending: "3 members" (as today);
  - pending: "3 members · 1 pending".
- [ ] B3. Member row for a pending member:
  - orange **Pending** tag right after the name (`ValueKey('member_pending_<id>')`), colours: text `#C26A00`, background `#FFF1DC` (dark theme: text `#FFB547`, background `#3A2A12`);
  - line under the name, instead of the Online / Offline status:
    - `waiting` and not near: "Gets the group when Nearby or Online";
    - `waiting` and Nearby now: green dot + "Nearby now · adding…";
    - `failed`: "Not reached in 7 days · tap to try again".
  - The Owner / Admin badge on the right stays as it is.
- [ ] B4. Sorting: pending members stay in the same place as today (by role, then name). No new section.
- [ ] B5. Live: when her phone gets the group (`added`), Group info refreshes by itself (GroupChangeHub), the tag goes and the normal status line comes back. Same when `waiting` → `failed`.
- [ ] B6. Only the phone that added her knows she is pending (the invite list is kept on that phone). On Ali's phone she shows as a normal member.

### Phase C: tap a pending member (mock page 4)
- [ ] C1. `showGroupMemberSheet` gets an optional `GroupInviteState? pending` and `bool canRetry`.
- [ ] C2. When pending, under the name: **Pending** tag + text:
  - `waiting`: "Her phone has not got the group yet. It is added by itself when she is Nearby (Wi-Fi Direct or mesh) or Online.";
  - `failed`: "Not reached in 7 days. Tap Try again to send the group again.";
  - small grey line: "Added by you · <time>" (from the invite time).
  - Use the member's name ("sumaira"), not "her": "sumaira's phone has not got the group yet…".
- [ ] C3. Blue **Try again** button (`ValueKey('member_retry')`) → returns `GroupMemberChoice.retry` → `GroupNearbyHub.retry(gid, id)` → reload → snackbar "Sending the group to sumaira again".
- [ ] C4. All the usual rows stay below (Message, View profile, Add friend, Make admin, Remove from group, Close), with the same rules as today.
- [ ] C5. A member who is not pending: the sheet looks exactly as today.

### Phase D: Account screen arrow (mock page 5)
- [ ] D1. `account_center_screen.dart` L233: `Icons.edit_outlined` → `Icons.chevron_right`, colour `onSurfaceVariant` (same as the Settings rows). **Same key** `account_profile_edit`, the card stays 104 high.
- [ ] D2. Tapping the card still opens Edit profile (no change). "Tap to edit name and photo" stays.
- [ ] D3. Update the comment "(tap the card or the pencil)" → "(tap the card)".
- [ ] D4. The group name pencil in Group info (`info_name_edit`) is **not** changed (you asked about the profile only). Say if you want that too.

### Phase E: tests
- [ ] E1. `bundle215a_test.dart` (source scans): `group_chat_screen.dart` has no `GroupAddingBanner(`, `_adding` or `_openAdding`; the "You added" line code is untouched; `GroupAddingBanner` still exists in the widgets file.
- [ ] E2. `bundle215b_test.dart` (widgets, fake `GroupNearbyHub.loadInvites` / `retry`):
  - title "3 members · 1 pending"; no pending → "3 members";
  - Pending tag + "Gets the group when Nearby or Online";
  - Nearby now line (with `groupMemberNearNow` swapped);
  - `failed` → "Not reached in 7 days · tap to try again";
  - invite becomes `added` + GroupChangeHub change → tag gone, status line back;
  - tap → sheet with Pending text + Try again → `retry(gid, id)` called once + snackbar;
  - not pending → sheet has no Try again;
  - no loader (server groups) → no tag, as today.
- [ ] E3. `bundle215c_test.dart`: Account card has `chevron_right` with key `account_profile_edit`, no `edit_outlined` in the card, tap opens Edit profile, height 104.
- [ ] E4. Run the whole suite in chunks, `flutter analyze` (stay at 166), all old tests unchanged except `nearby_190` version.

## 4. Old tests
- Only `test/nearby_190_test.dart`: version → 3.0.56+127 (as every bundle).
- `groups_g3_test.dart` (tests `GroupAddingBanner` and the adding sheet by themselves) stays unchanged, because the widgets are kept in the file.
- `bundle183_test.dart` L793-794 stays unchanged (same key, same height).

## 5. Phone tests (APPLY_215.md)
- [ ] 215-1 Realme: add Sumaira to Family while ZTE is off / far. Group chat has **no** blue strip, only "You added sumaira".
- [ ] 215-2 Group info: "3 members · 1 pending", Sumaira with orange **Pending** and "Gets the group when Nearby or Online".
- [ ] 215-3 Tap Sumaira → sheet with the Pending text, **Try again**, Message / View profile.
- [ ] 215-4 Bring ZTE near (Wi-Fi Direct) with Group info open: line turns "Nearby now · adding…", then the tag goes by itself and she shows Nearby.
- [ ] 215-5 Same with ZTE coming Online (server group sync).
- [ ] 215-6 ZTE (Sumaira) sees the group and the old messages, as today.
- [ ] 215-7 Settings → Account: the profile card ends with the arrow ›, tap → Edit profile.
- [ ] 215-8 Dark theme: Pending tag readable.

## 6. Safety
- No DB, Kotlin or backend change; only 5 screen/widget files + version files (plus one line in the group receive code only if you say yes to §8 point 2).
- Adding people, sending, retry timers and the 7-day give-up work exactly as today.
- Old widgets are kept (unused) so no old test changes.

## 7. Mock (made)
- Page 1: now (strip stays on top). Page 2: chat clean. Page 3: Group info Pending. Page 4: tap Pending → Try again. Page 5: Account arrow.

## 8. Points to confirm before build
1. Pending shows only on the phone that added her (other members see her as normal). **(my advice: OK as is.)**
2. Extra precaution: if a **group message from Sumaira** reaches my phone (so she clearly has the group, e.g. she got it from Ali), clear her Pending at once. This touches one line in the group receive code. **(my advice: yes.)**
3. Group name pencil in Group info stays a pencil. **(my advice: keep, it edits in place.)**

## 9. Delivery
- One app zip `locallink_app_215_<date>.zip`, one commit, plus `APPLY_215.md` + `TODO_215.md`. No backend zip.
- Commit: `v3 3.0.56+127 bundle 215: group pending members shown in Group info (Pending tag, Try again) instead of the strip on the chat page, arrow instead of pencil on the Account profile card`
