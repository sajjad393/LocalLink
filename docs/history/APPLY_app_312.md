# APPLY app 312 - LinkUp starts again (3.0.105+176)

Base: app 311 (3.0.104+175) = `f5440d6`. App only.

## What changes for the user
- LinkUp opens normally again. Since 3.0.101 every phone stopped at start (grey screen / error screen):
  the Get chat request card (307) was made before the notifications part existed.
- Nothing else changes. The 311 error screen stays (only shows if a screen breaks).

## Files (8)
- `lib/app/app_dependencies.dart` - request card made after notifications (code moved, not changed)
- `lib/core/config/app_build.dart`, `pubspec.yaml` - 3.0.105+176
- `test/app_start_312_test.dart` (NEW, 2 tests)
- `test/bundle223_logs_test.dart`, `test/nearby_190_test.dart` - version
- `docs/history/TODO_312.md`, `docs/history/APPLY_app_312.md`

## Tests
| Check | Result |
|---|---|
| New `test/app_start_312_test.dart` | 2 pass |
| Fix proof | fix taken out -> same `LateInitializationError: Field 'notifications'` as the phone; back in -> pass |
| Full app suite (319 files, 11 chunks) | 3129 pass, 0 fail, all EXIT 0 |
| Analyze | 361 old issues, 0 new |

## Not checked
- Real phones: NOT VERIFIED until you open 3.0.105.
- 307 / 308 / 310 features never ran on a phone before: their phone checks are still open.

## Phone checks
1. Install 3.0.105 on the C71 over 3.0.104: LinkUp opens to Chats.
2. Owner: make a Get chat request -> the request card shows in notifications; tap it -> the answer opens.
3. Regression: chats, calls, My links map, admin panel open as before.
4. Then update the other phones (kiran + ayesha first) and run the 310 checks (APPLY_app_310.md).
