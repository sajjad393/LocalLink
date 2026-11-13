# TODO 287 - Forgot password screen redesign  [BUILT 13 Nov in 3.0.90+161 - zip locallink_app_3.0.90_2026-11-14.zip, not pushed, not phone-tested]

Owner (13 Nov, screenshots `uploads/Screenshot_20261113-010044.png`, `-010050.png`): "UI is ugly and very bad, show the latest updated mock".
Mock: `mocks/forgot_password_287.html` (dark) + `mocks/forgot_password_287_light.html`, made by `mocks/m287/make.py`.

## Code (de70ef7) - `lib/features/recovery/presentation/screens/account_recovery_screen.dart`
- `ForgotPasswordScreen222` :194; build :268; `_chip` :293 (light green `_greenBg` box, also in dark mode);
  `_tabs` :313 (picked tab = `scheme.surface` = darker than the track, label "I have my recovery code" cut on small phones);
  password fields :353/:368; `_haveCode` ~:405 (Username :414 shows "0/32" counter, Recovery code :423, button :431, note :435);
  `_noCode` ~:445 (button "Ask the admin" :454, note :455); request card :468; one-time code :500; `_done` :525.
- Button = default M3 filled (flat lilac), not the brand gradient.

## Changes (only this screen; same bloc `ForgotPasswordBloc222`, same steps and server calls)
1. Top: key badge + "Reset your password"; the chip becomes a small live pill ("Server connected" / "Offline · works on this phone").
2. Switch: "I have a code" / "I don't have it" with icons; picked side blue.
3. Fields: shared rounded field style, floating label, no counter; code field auto-adds dashes (XXXXX-XXXXX-XXXXX-XXXXX).
4. Live checks: tick on good code format, strength bar, "Match"; errors red under the field.
5. Brand gradient button, faded until filled.
6. No code: 3 steps; after sending a live "Waiting" card with steps; one-time code + new password; "Cancel request".
7. Done: green tick, hidden code box (Show/Copy), "Save on WhatsApp" (same parts as 286).
8. Light version; Roboto; text cap 1.3x (283 S-1..S-6).

## Tests that may lock texts (NOT CHECKED): keys `forgot222-*`, texts "I have my recovery code", "Server connected",
"Set new password", "Ask the admin" in `test/*222*`. Keep the keys; list any text change.
