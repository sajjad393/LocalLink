# TODO 288 - Welcome / Log in / Create account redesign + ONE loading  [BUILT 13 Nov in 3.0.90+161 - zip locallink_app_3.0.90_2026-11-14.zip, not pushed, not phone-tested]

Owner (13 Nov, screenshot `uploads/Screenshot_20261113-010116.png`): "Perfect mock (287). Also update sign in, sign up,
welcome screen, show me updated mock, don't show double loading."
Mock: `mocks/welcome_login_288.html` (dark) + `mocks/welcome_login_288_light.html`, made by `mocks/m288/make.py` (reuses m287 CSS).

## Double loading (VERIFIED in code, de70ef7) - `lib/features/authentication/presentation/screens/setup_screen.dart`
- :434-442 `FilledButton` child = `CircularProgressIndicator` while `state.busy`.
- :444 `if (state.busy) _stage256(...)` = a SECOND spinner row "Signing you in…" / "Creating your account…" (:113-133, Bundle 256 A4 / 263 B8).
- Fix: one loading only = the gradient button shows a small ring + the stage words inside it; delete the `_stage256` row.
  Fields + "Forgot password?" + switch link disabled/faded while busy (already disabled; add fade).

## Other code refs
- setup_screen build :352: AppBar 'Register'/'Log in' :359; `Icons.forum_rounded` :371; 'Create your account'/'Welcome back' :377;
  Username `maxLength: 32` (shows "6/32") :384; Password :395; Forgot :416-422; error text :424-432; switch :446-451.
- `welcome_screen.dart` `WelcomeView` :120 (tagline :127), `_WelcomeContent` (logo `LocalLinkLogoMark`, ShaderMask "LinkUp",
  3 `_FeatureCard`, `GradientPillButton` 'Create account', TextButton "I already have an account · Log in" :283);
  `welcome_mesh_background.dart` (261 lines) top mesh.

## Changes (same AuthenticationBloc logic: server first, then offline; same restore + onboarding profile step)
1. ONE loading inside the button (see above).
2. Welcome: live mesh with friend dots + moving dashed curves, gradient logo badge, "LinkUp" gradient title, app-style feature cards,
   gradient "Create account" + outlined "I already have an account".
3. Log in: logo badge, "Welcome back" + "Log in to your account", 287 field style, no counter (keep the 32 limit via inputFormatter),
   gradient button faded until filled, "New here? Create an account".
4. Errors: red card above the fields (same words), wrong field red border.
5. Create account: "Pick a username your friends know", live rule ticks (3-32 letters, numbers, . _ - ; At least 8 characters),
   strength bar, "Have an account? Log in". AppBar "Create account" (was "Register").
6. Light version; Roboto; text cap 1.3x (283 S-1..S-6).

## Tests that may lock texts (NOT CHECKED): keys `signup_stage_*` (row removed -> keep the key on the button label),
`forgot-password-222`, texts 'Register', 'Log in', 'Signing you in…', 'Creating your account…', `WelcomeView.tagline`,
`welcome_jump_227:209-214`, bundle256/263 tests. List every change; never delete tests.
