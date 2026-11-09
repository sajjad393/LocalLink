# TODO 206: move the round button on Chats, Calls and People

> **Status (2026-11-04):** BUILT in app 3.0.47+118 (`locallink_app_206_2026-11-04.zip`, see `APPLY_206.md`). Waiting for phone tests 206-1..7.

Mock: `mock_206_page1.png`, `mock_206_page2.png` (HTML: `mock206/mock_206.html`).
Checked in code at `8c87aa4` (205 pushed, 3.0.46+117).

## 0. Your choices (2026-11-04)
- **How:** press and hold 0.5 s, then drag. A quick tap opens it as today.
- **When let go:** it slides to the nearest side (left or right edge), at the same height.
- **Place:** one place for all 3 tabs.
- **After the app closes / phone restarts:** it keeps its place. No Reset button (to move it back, hold and drag it).

## 1. The 3 buttons today (code check)
| Tab | Code | What a tap does |
|-----|------|-----------------|
| Chats | `home_screen.dart` `_chatsTab()` → `BrandGradientFab(heroTag: 'home_fab', icon: chat_bubble_outline_rounded)` | opens the Start sheet (new chat / new group) |
| Calls | `calls_screen.dart` → `BrandGradientFab(heroTag: 'calls_fab', icon: add_ic_call_rounded)` | `onNewCall` |
| People | `contacts_screen.dart` → its own `FloatingActionButton(heroTag: 'add_contact_fab')`, same gradient look, `+` icon | `_addContact` |

- All 3 sit in `Scaffold.floatingActionButton` (fixed bottom-right).
- Chats has the "call in progress" bar in `bottomNavigationBar` (`_OngoingCallBar`); Calls has `_CallInProgressBar` at the top of its body.
- The app already uses `SharedPreferences` (e.g. `home_screen.dart` ~224), so saving the place needs no new package.

## 2. How it works (mock)
1. **Tap** (short): opens as today. Nothing moves.
2. **Press and hold 0.5 s:** a short buzz (light haptic), the button grows to 115 % and lifts (bigger shadow); a small "Drag to move" hint shows (only the first 2 times, see P3).
3. **Drag:** the button follows the finger.
4. **Let go:** it slides (200 ms) to the nearest side: dropped left of the middle → left edge; right of the middle → right edge. Height stays where you let go.
5. **Limits (allowed area):** never over the title bar, the tab bar, the "call in progress" bar or the keyboard; 16 px from the edges. If the screen size changes (turned phone, keyboard, small phone) it is pulled back inside, but the saved place is not changed.
6. **Same place on Chats, Calls and People.** Switching tabs never makes it jump.
7. **Kept:** saved on the phone after every move; read at start.

## 3. Phases
1. **P1 One shared movable button widget**
   - New `lib/core/widgets/movable_fab.dart` (`MovableFab`): wraps the button; long-press (0.5 s) starts the move, drag follows, release slides to the side.
   - Saved place: `side` (left / right) + `heightFraction` (0.0 top … 1.0 bottom of the allowed area), so it fits any screen size.
   - One shared store (`FabPlace`, `ValueNotifier`) so all 3 tabs read the same place and update together. SharedPreferences keys: `fab_side`, `fab_y`.
   - Default (never moved): right side, bottom (today's place).
2. **P2 Use it on the 3 tabs**
   - Chats + Calls: `BrandGradientFab` inside `MovableFab`.
   - People: switch its own FAB to `BrandGradientFab(icon: Icons.add)` (same look) inside `MovableFab`.
   - Keep the hero tags and the tooltips, so the tests and TalkBack stay the same.
   - Placement (as built): the button moved from `Scaffold.floatingActionButton` into the tab body (`MovableFabArea` = body + button on top). The body already stops at the title, the tab bar, the "call in progress" bar and the keyboard. On Calls it wraps only the list, under the call bar.
   - The long-press tooltip of the button is off (holding it now moves it); TalkBack still reads "New conversation" / "New call" / "Add contact".
3. **P3 Small details**
   - The "Drag to move" hint: shown only the first 2 times you hold it.
   - TalkBack: a tap still works; moving is touch only (no new menu).
   - The list's last item is never hidden: the list keeps its bottom space as today.
4. **P4 Tests**
   - Tap opens (all 3); hold + drag + release → side and height saved; the place is the same on the other 2 tabs; the saved place is read at start; clamped inside the allowed area; a list scroll never moves it.
   - Version bump + extend the version scan in `nearby_190`.

## 4. Phone tests
1. **206-1** Tap the button on each tab: opens as before.
2. **206-2** Hold 0.5 s: buzz + grows. Drag to the middle-left, let go: slides to the left edge.
3. **206-3** Switch to Calls and People: the button is in the same spot.
4. **206-4** Close the app (swipe away), open it: still on the left. Restart the phone: still there.
5. **206-5** Scroll the Chats list fast: the button never moves.
6. **206-6** Drag it down onto the tab bar: it stops above the tab bar. During a call: it stays above the "call in progress" bar.
7. **206-7** Open the keyboard (search on People): the button moves up and comes back after.

## 5. Not in 206
- No Reset button (your choice).
- The chat screen buttons and the group screens' square buttons don't move.
- Needs your "go ahead 206" (freeze is on).
