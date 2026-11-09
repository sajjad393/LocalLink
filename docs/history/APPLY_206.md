# APPLY 206: move the round button on Chats, Calls and People (app 3.0.47+118)

Base: app `8c87aa4` (205, 3.0.46+117, push checked: same as the 205 zip).
Plan + mock: `TODO_206.md`, `mock_206_page1.png`, `mock_206_page2.png`.
Zip: `locallink_app_206_2026-11-04.zip` (app only, no backend change).

## What it does (your choices)
- **Quick tap:** opens as before (New conversation / New call / Add contact).
- **Press and hold 0.5 s:** a short buzz, the button grows to 115 % and lifts. "Drag to move" shows the first 2 times only.
- **Drag:** the button follows the finger, always inside the tab (never over the title, the tab bar, the "call in progress" bar or the keyboard).
- **Let go:** it slides (0.2 s) to the nearest side, left or right edge, at the same height.
- **One place for all 3 tabs:** move it on Chats, and it is in the same spot on Calls and People.
- **Kept:** saved on the phone (`fab_side`, `fab_y`), so it stays after closing the app or a restart. No Reset button: hold and drag it back.
- The height is saved as a share of the tab, so on a smaller space (keyboard open, turned phone) it stays inside; the saved place does not change.
- Log line on every move: `FAB_MOVED side=left y=0.42`.

## Code
- New `lib/core/widgets/movable_fab.dart`: `FabPosition`, `FabPlaceRules` (pure), `FabPlace` (shared place + saving), `MovableFabArea` (the tab body with the button on top).
- `home_screen.dart` (Chats), `calls_screen.dart` (Calls, under the call bar), `contacts_screen.dart` (People): the button moved from `Scaffold.floatingActionButton` into `MovableFabArea`. People now uses the shared `BrandGradientFab` (same look).
- The button's long-press tooltip is off (holding moves it); TalkBack still reads its name.
- `pubspec.yaml` 3.0.47+118, version stamp, `test/nearby_190_test.dart` scan.
- New `test/movable_fab_206_test.dart` (15 tests).

## Checks done here (no phone)
- Flutter tests: 1540 / 1540 pass (150 files, chunks of 8; 15 new).
- `flutter analyze`: no new issues compared with 205 (same 169 old ones).
- These are unit / widget checks only; the feel on the phone (buzz, slide) needs the phone tests.

## Phone tests
1. **206-1** Tap the button on each tab: opens as before.
2. **206-2** Hold 0.5 s: buzz + grows + "Drag to move". Drag to the middle-left, let go: slides to the left edge.
3. **206-3** Switch to Calls and People: the button is in the same spot.
4. **206-4** Close the app (swipe away) and open it: still there. Restart the phone: still there.
5. **206-5** Scroll the Chats list fast: the button never moves.
6. **206-6** Drag it down onto the tab bar: it stops above it. During a call: it stays above the "call in progress" bar (Chats) / below it (Calls).
7. **206-7** Open the keyboard (People search): the button stays inside, above the keyboard, and goes back after.
