# APPLY app 311 - show what broke instead of a grey screen (3.0.104+175)

Base: app 310 (3.0.103+174) = `5da6831`. App only (no backend change).

## What changes for the user
- If a screen breaks while it is drawn, LinkUp no longer shows a plain grey screen. It shows
  "LinkUp could not draw this screen", the version, the error, what was being drawn, the first stack
  lines, and a Copy button. Nothing else changes.
- On the C71 (grey on start in 3.0.103) this screen will now show the reason: send a screenshot.

## Files (9)
- `lib/core/widgets/error_screen_311.dart` (NEW)
- `lib/main.dart` - uses it for release builds (error log unchanged)
- `lib/core/config/app_build.dart`, `pubspec.yaml` - 3.0.104+175
- `test/error_screen_311_test.dart` (NEW, 6 tests)
- `test/bundle223_logs_test.dart`, `test/nearby_190_test.dart` - version
- `docs/history/TODO_311.md`, `docs/history/APPLY_app_311.md`

## Tests
| Check | Result |
|---|---|
| New tests `test/error_screen_311_test.dart` | 6 pass |
| Full app suite (318 files, 11 chunks) | 3127 pass, 0 fail, all EXIT 0 |
| Analyze | 361 old issues; 0 new (main.dart `dart:ui` note is old) |

## Not checked
- The real cause of the grey screen on the C71: NOT VERIFIED (needs the screenshot from 3.0.104).
- Real Android build: CI builds it.

## Phone checks
1. Install 3.0.104 on the C71 over 3.0.103 and open it.
2. If the red-titled error screen shows: screenshot it (scroll down for the whole stack) or tap Copy and paste it here.
3. If the app opens normally: tell me (then the grey came from something 3.0.104 does not hit).
