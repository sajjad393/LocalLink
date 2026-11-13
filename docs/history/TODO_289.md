# TODO 289 - One toast look everywhere (like the 286 mock)  [BUILT 13 Nov in 3.0.90+161 - zip locallink_app_3.0.90_2026-11-14.zip, not pushed, not phone-tested]

Owner (13 Nov): "Perfect mock (286). Also update toast message same like mock everywhere."
Mock: `mocks/recovery_code_286.html` / `_light.html` section 1 (state 4 "Recovery code saved") + NEW section 3
"Toast messages: the same look everywhere" (error on Profile, done in a chat, info on Home with the round button moved up, all variants).

## Code today (VERIFIED, de70ef7 clone)
- 102 `showSnackBar` calls in 44 files under `lib/` (top: group_chat_screen 10, chat_screen 8, profile_screen 7,
  add_contact_screen 6, contacts_screen 5, forward/home/attachment_tile/admin_block_confirm 4 each ...).
- `lib/core/widgets/error_toast.dart` `showErrorToast` (20 uses): pink `errorContainer` bar.
- `lib/core/theme/app_theme.dart:153` `snackBarTheme`: only floating + radius md (colours = Material default).
- Admin themes have their own: `admin_theme.dart:334`, `admin_ui216.dart:306`.
- `home_screen.dart:1580` "Press back again to exit" SnackBar.
- `MovableFabArea` (`movable_fab.dart:144`) does not know about toasts -> a toast can cover the round button.
- No native `Toast.makeText`, no fluttertoast.
- Tests that touch SnackBar: `error_toast_test`, `group_chat_screen_test`, `chat_media_150_test`, `call_fix_146_test`, `bundle263_test`.

## Look (exact, from the mock CSS)
- Card: dark `#2A2D38`, light mode `#1F2937`; radius 14; min height 48; padding 12/14; shadow 0 8 24 rgba(0,0,0,.4);
  margin 16 left/right; floats 16 above the bottom bar (24 from the bottom on screens without it).
- Text white (dark `#ECEBF2`), 14 sp, line 1.35, wraps to 2 lines.
- Icon 20 left, gap 10: done = tick `#86EFAC`; error = warning sign `#F87171`; info = i `#8EA6FF`.
- Optional action on the right (e.g. "Undo") `#8EA6FF` 13.5 sp w700. Slide up 0.4 s; 3 s (exit toast 2 s as today).

## Plan
- T-1 One helper `LinkToast.show(context, text, {kind: done|error|info, action})` in `lib/core/widgets/link_toast.dart`.
- T-2 `showErrorToast` keeps its name and words, draws `LinkToast` error (no change for its 20 callers).
- T-3 `snackBarTheme` in `app_theme.dart` (+ both admin themes) gets the same colours/shape, so any SnackBar left over still matches.
- T-4 Move all 102 calls to `LinkToast` with the right kind (catch/fail = error, done words = done, others = info). Same words.
- T-5 Round button moves up while a toast shows (MovableFabArea listens to the toast height), back down after.
- Tests: helper look (colours / icon per kind, light + dark), FAB moves up and back, goldens; old tests find the same words.
  Text-locked tests listed in the APPLY doc (none weakened).
