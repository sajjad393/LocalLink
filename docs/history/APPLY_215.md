# APPLY 215: group "Pending" member instead of the top strip + Account arrow

App 3.0.56+127 · DB v34 (no change) · no new permissions · **no backend change**.
Built on top of 214 (app `c0552f9`).

## What changed
**A. Group chat page is clean**
- The blue "Adding sumaira… · They are added when Nearby or Online" strip is no longer shown on the group chat page.
- The small chat line "You added sumaira" stays. Adding people, sending, auto-add when Nearby / Online and the 7-day timer work as before.

**B. Group info shows "Pending"**
- Members title: "3 members · 1 pending" (only while someone is pending).
- Orange **Pending** tag right after her name, with the line:
  - "Gets the group when Nearby or Online";
  - "Nearby now · adding…" (green dot) when she is near;
  - "Not reached in 7 days · tap to try again" after 7 days.
- When her phone gets the group, the tag goes by itself (Group info refreshes).
- Only the phone that added her shows Pending (other members see her as normal).

**C. Tap a pending member**
- The usual member sheet, plus at the top: Pending tag, "sumaira's phone has not got the group yet. It is added by itself when sumaira is Nearby (Wi-Fi Direct or mesh) or Online.", "Added by you · today 10:42", and a blue **Try again** button (snackbar "Sending the group to sumaira again").

**§8.2 (your "go ahead" = my advice): a group message from her clears Pending**
- If a signed group message from Sumaira reaches my phone (she got the group from another member), her Pending clears at once. Log: `GROUP_INVITE_DONE by=message`.

**D. Account screen**
- The profile card ends with the arrow › like the other rows (was a pencil). Tap → Edit profile, as before.
- The group name pencil in Group info stays (§8.3).

## Files
- `lib/features/groups/presentation/screens/group_chat_screen.dart` (strip removed)
- `lib/features/groups/presentation/screens/group_info_screen.dart` (Pending in members)
- `lib/features/groups/presentation/widgets/group_info_sheets.dart` (Pending block + Try again)
- `lib/features/groups/presentation/widgets/group_nearby_widgets.dart` (`GroupPendingTag`; old strip widgets kept, unused)
- `lib/features/groups/data/services/group_nearby_service.dart` (§8.2, one hook)
- `lib/features/account/presentation/screens/account_center_screen.dart` (arrow)
- Version: `pubspec.yaml`, `lib/core/config/app_build.dart`
- Tests: `test/bundle215a_test.dart`, `test/bundle215b_test.dart`, `test/bundle215c_test.dart`

## Old tests
- `test/nearby_190_test.dart`: version → 3.0.56+127 (as every bundle).
- No other old test changed.

## Checks here
- `flutter test`: see the numbers in the reply. `flutter analyze`: 166 (same as before).

## Phone tests
- [ ] 215-1 Realme: add Sumaira to Family while ZTE is off / far. Group chat has **no** blue strip, only "You added sumaira".
- [ ] 215-2 Group info: "3 members · 1 pending", Sumaira with orange **Pending** and "Gets the group when Nearby or Online".
- [ ] 215-3 Tap Sumaira → sheet with the Pending text, **Try again**, and the usual rows.
- [ ] 215-4 Bring ZTE near (Wi-Fi Direct) with Group info open: "Nearby now · adding…", then the tag goes by itself.
- [ ] 215-5 Same with ZTE coming Online.
- [ ] 215-6 ZTE sees the group and the old messages, as today.
- [ ] 215-7 Sumaira gets the group from Ali (Realme far away) and sends a message; when it reaches Realme, Pending goes.
- [ ] 215-8 Settings → Account: the profile card ends with the arrow ›, tap → Edit profile.
- [ ] 215-9 Dark theme: Pending tag readable.

## PowerShell (app)
```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_215_2026-11-05.zip" .
git add -A
git add -f APPLY_215.md TODO_215.md
git reset -q -- android/local.properties
git commit -m "v3 3.0.56+127 bundle 215: group pending members shown in Group info (Pending tag, Try again, clears when her message arrives) instead of the strip on the chat page, arrow instead of pencil on the Account profile card"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean; flutter pub get; flutter test; flutter build apk --release
```
