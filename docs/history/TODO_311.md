# TODO 311 - grey screen on start (3.0.103, Sajjad's realme C71)

Reported 15 Nov: after installing 3.0.103 over 3.0.100 ("Open" after install), LinkUp shows a plain grey
screen every time (recents thumbnail grey too). Phone: RMX5303 / C71, owner account.

## What the grey screen is
Flutter's release error box (colour 0xF0C0C0C0 over black = the grey in the screenshot): a widget threw
while it was being built. Release builds hide the message. Here it covers the whole screen, so a
screen-level (or app-level) widget broke. The user has no logs and the grey screen blocks the in-app
log share (tap Chats 5 times).

## Code check (3.0.100 `228ed49` -> 3.0.103 `5da6831`)
Read every start-path change of 307 / 308 / 310 (app_dependencies, local_link_app, MainActivity,
home list items, My links / OwnLinks308, link map painter, admin action service): no clear cause.
Cause NOT VERIFIED.

## Fix 1 (this build, user pick "Build 3.0.104 now: show the error on screen")
- `lib/core/widgets/error_screen_311.dart` (NEW): `ErrorWidget.builder` shows "LinkUp could not draw this
  screen", the app version, the error, the widget being built ("While: building ..."), the top 14 stack
  lines, and a Copy button. Needs no theme / MediaQuery / Directionality (works as the whole app).
  Inside a list it stays a card (max 640 px), not an endless grey wall.
- `lib/main.dart`: `ErrorWidget.builder = ErrorScreen311.builder;` (the error log stays).
- Version 3.0.104+175.

## Next
User installs 3.0.104 on the C71, sends a screenshot of the error screen -> fix the real cause (TODO 312).
