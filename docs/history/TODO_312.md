# TODO 312 - fix: LinkUp broke on start since 3.0.101 (grey screen)

## Proof (3.0.104 error screen, Sajjad's C71, 15 Nov 8:29 PM)
`LateInitializationError: Field 'notifications' has not been initialized.`
Stack: `AppDependencies._buildAdminActions` <- `new AppDependencies` (app_dependencies.dart:240) <- `new _LocalLinkAppState`.

## Cause (VERIFIED by a test)
Bundle 307 (C3) made the Get chat request card (`ChatRequestNotifier307`) at the end of
`_buildAdminActions()` with `taps: notifications.platform.chatRequestTaps307`. The constructor calls
`_buildAdminActions()` (line 240) long before `notifications = LocalLinkNotificationService(...)`
(line 565), so reading `notifications` threw. This is in the constructor every phone runs:
**3.0.101, 3.0.102, 3.0.103 and 3.0.104 could not start on any phone.** No test built
`AppDependencies`, so CI stayed green.

## Fix (smallest)
- `lib/app/app_dependencies.dart`: the same card code moved to `_buildChatRequestCard307()`, called
  right after `notifications` is set. Nothing else changes.
- Kept: the 311 error screen (shows the reason if a screen ever breaks again).
- Version 3.0.105+176.

## Tests
- NEW `test/app_start_312_test.dart`: `AppDependencies()` builds (the whole start wiring, every
  field set before use) + the order lock. Without the fix it fails with the same
  LateInitializationError as the phone; with the fix it passes.

## After
All phone checks of 307, 308 and 310 are still open (those versions never started on a phone).
