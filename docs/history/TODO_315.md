# TODO 315 - remove the "Server PC clock is N h slow" banner everywhere

Status: TODO only (user pick 16 Nov: keep as TODO; keep the clock check hidden = my advice). Build only on "Build". Base: app `5bad575` (3.0.107+178, CI 43792729654 success). Backend: no change.
Source: `uploads/Screenshot_20261116-111707.png` (My links, "Server PC clock is 11 h slow").

## Code check (5bad575)
- The banner is ONE widget: `ServerClockBar255` (`lib/features/admin/presentation/widgets/admin_kit216.dart` l.119).
- It is shown in 2 places only:
  1. `AdminPage216` (same file, l.105) = every admin page (My links, Users, Devices, ...);
  2. `admin_conversations_screen.dart` l.293 (Conversations).
- Web admin: no clock banner (checked `adminweb/*.js`). Normal (non-admin) screens: none.

## Plan
- Remove the 2 `const ServerClockBar255(),` lines (and an import that becomes unused).
- KEEP (my advice): the clock check itself (`ServerClock255.noteReady`, the `SERVER_CLOCK_WRONG` log line)
  and the 314 time fix on the Get chat notification (it uses the same offset, shows nothing).
- The `ServerClockBar255` class stays in the code unused, so the old tests `bundle255_clock_test.dart`
  and `chat_calls_298_test.dart` (G clock card) stay unchanged.
- Version 3.0.108+179. New test: an admin page and the Conversations page with a wrong server clock show
  no banner (+ source check: no `ServerClockBar255()` in `lib/` pages); regression: notification time
  still corrected.

## Files
`admin_kit216.dart`, `admin_conversations_screen.dart`, `pubspec.yaml`, `app_build.dart`, the 2 version
tests, 1 new test, docs.
