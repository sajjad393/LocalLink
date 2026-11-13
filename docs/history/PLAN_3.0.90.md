# PLAN 3.0.90+161 - all open points (TODO 282-289)   [BUILT 13 Nov - one zip, not pushed; see APPLY_app_3.0.90.md]

Owner (13 Nov): "Ok. Create a complete plan in phases for all discussed points. Make sure UI matches 100% with the mocks."
Base: pushed `de70ef7` (3.0.86) + the delivered, NOT pushed 3.0.87 / 3.0.88 / 3.0.89 zips (= the 280 tree).
3.0.90 is built ON TOP of 3.0.89. Backend: no change in this plan (backend 279 zip still goes first).
Delivery: ONE app zip `locallink_app_3.0.90_<date>.zip` + ONE commit (`v3.0.90 ...`) + `APPLY_app_3.0.90.md`.

| TODO | What | Mock | Status |
|---|---|---|---|
| 282 | New built-in tones (AOSP) | - (sound) | picks final |
| 283 | Add Contact redesign + same look on every phone + QR | `mocks/add_contact_improved_283*.html` | APPROVED |
| 284 | Profile photo Save spinner never stops | none yet (Phase 0) | cause verified |
| 285 | Calls: one row per person per day | none yet (Phase 0) | cause verified, rule chosen |
| 286 | Recovery code card + Settings row + password | `mocks/recovery_code_286*.html` | APPROVED ("Perfect mock") |
| 287 | Forgot password redesign | `mocks/forgot_password_287*.html` | APPROVED |
| 288 | Welcome / Log in / Create account + ONE loading | `mocks/welcome_login_288*.html` | APPROVED ("Ok") |
| 289 | One toast look everywhere (102 toasts + error toast) | `mocks/recovery_code_286*.html` section 3 | mock added, waiting for OK |

---

## Phase 0 - Mocks for the 3 points that have none (before any code)
- 286 APPROVED 13 Nov: `mocks/recovery_code_286*.html` (Home card states + Settings row + password + code + section 3 toasts = 289).
- 284 / 285: still to do.
"100% like the mock" needs a mock for every screen that changes. Missing today:
- 285 Calls row: "noshad (9)" row, red row "Ibrahim (4) · 2 missed", the list sheet when tapped.
- 286 Home card "Save your recovery code" (Show / Copy / Save on WhatsApp / Saved / Later), the old-account
  variant "Make a new code", Settings > Account row "Recovery code", password screen, code screen.
- 284 Profile photo: small ring on the photo while saving, then the new photo + "Profile saved".
Same style as the approved mocks (dark + light, made by a script in `mocks/m289/`). Owner says OK -> Phase 1.

## Phase 1 - Base (no screen change yet)
1. Fresh clone, check out `de70ef7`, apply 3.0.87, 3.0.88, 3.0.89 zips; check the tree equals the 280 tree.
2. Baselines must match before any change: Flutter suite 2762/0, Kotlin 488/0, analyze 175.
3. Grep every test that locks a text, key or file changed below (lists in each TODO, "NOT CHECKED" so far):
   `profile_photo_204`, `calls_group_171`, `bundle174`, `bundle256`, `bundle263`, `ble_cards_226`, `friend_ble_226`,
   `nearby_190`, `welcome_jump_227:209-214`, `*222*` (forgot), QR tests, UiSounds / channel-id tests, goldens.
   Write the list into the APPLY doc: every test that must change, old line -> new line. No test deleted or weakened.

## Phase 2 - Same look on every phone (283 S-1..S-6) = the base of every mock
1. S-1 Roboto for the whole app: pubspec family `Roboto` -> the 4 bundled ttf; `fontFamily: 'Roboto'` in `app_theme.dart`.
2. S-2 Text size cap 1.3x (MediaQuery textScaler clamp in `local_link_app.dart`).
3. S-5 Fixed colours: no Material You / dynamic colour; keep seed `0xFF1E5BFF`.
4. Design tokens from the mock CSS (new block in `lib/core/theme/app_tokens.dart`, one source for all screens):

| Token | Dark | Light |
|---|---|---|
| screen bg | `#121318` | `#F7F8FC` |
| card | `#1A1B22`, radius 20 | `#FFFFFF` + shadow `0 1 3 rgba(16,24,40,.08)` |
| field | `#1F2027`, h 56, radius 16, focus border 1.5 `#8EA6FF` | `#ECEEF4`, focus `#FFFFFF` + `#1E5BFF` |
| field label up | 11 sp `#8EA6FF` | `#1E5BFF` |
| text main / muted | `#ECEBF2` / `#9497A5` | `#1B1B1F` / `#6B7080` |
| brand gradient | 135 deg `#1E5BFF` -> `#23B5D8` | same |
| main button | h 54, radius 27, shadow `0 8 22 rgba(30,91,255,.35)`, 15.5 sp w700 | same |
| ok / error | `#86EFAC` on `rgba(34,197,94,.13)` / `#F87171` | `#067647` on `#DCFCE7` / `#B42318` |
| live pill teal / orange | `#5EEAD4` on `rgba(20,163,160,.14)` / `#FBBF24` | `#0F766E` / `#9A5B06` on `#FEF3C7` |
| segmented | track `#1A1B22` h 42+8, radius 18/14, picked = blue tint + `#8EA6FF` ring | track `#ECEEF4`, picked white |

5. Shared widgets (one each, used by 283/286/287/288/289; no copies): `LinkToast` (289),
   `LinkField` (floating label, icon, right tick / eye / "Match", red border + red line under),
   `BrandButton` (gradient, faded until valid, loading = ring + words inside, shine), `LivePill`, `StepList`,
   `SegmentSwitch`, `HeroBadge`; `RecoveryCodeBox235` / `SaveOnWhatsApp235` reused.
6. S-3 / S-4: width-based spacing 320-480 dp; animations 30 fps, no blur on low-RAM phones (ZTE Go), still frame when
   "Remove animations" is on, stop when the screen is hidden.
7. Golden test harness: 320x640, 360x800, 412x915 x dark/light x text 1.0/1.3.

## Phase 3 - Bugs
- 284 (`profile_screen.dart:578`): Save button inside `BlocBuilder<AccountBloc, AccountState>`; ring on the photo while saving.
  Tests: spinner stops after save; stops after an error; "Save changes" shows the spinner while saving.
- 285 (`call_history_groups.dart`): one row per person per day, missed inside (red + "N missed"), newest call shown,
  tap = list sheet. Tests: the exact screenshot order -> 2 rows (noshad 9, Ibrahim 4); `calls_group_171:44/:66` updated (listed).

## Phase 4 - Tones (282)
1. Copy `tones282/final/*.wav` over `android/app/src/main/res/raw/` (same names; ringback unchanged).
2. `MESSAGE_CHANNEL_ID` `locallink_messages_v4` -> `_v5`, delete the old channel.
3. NOTICE line "Sounds from the Android Open Source Project (Apache License 2.0)".
4. Kotlin tests for res names / channel id.

## Phase 5 - Log in / Create account / Welcome (288) and Forgot password (287)
- 288 `setup_screen.dart`: delete the `_stage256` row (:444) -> ONE loading inside `BrandButton`; fields fade while busy;
  logo badge, titles, `LinkField`s, no "6/32" (keep the 32 limit), error card, live ticks + strength bar, "Create account" title.
  `welcome_screen.dart` + `welcome_mesh_background.dart`: mesh, logo, cards, two buttons exactly as the mock.
- 287 `account_recovery_screen.dart` `ForgotPasswordScreen222`: hero + live pill, `SegmentSwitch` ("I have a code" /
  "I don't have it"), code field with auto dashes, live checks, steps, "Waiting" card, done screen.
- Same bloc logic (server first, then offline; restore; onboarding profile step). Keys kept.

## Phase 6 - Recovery code (286)
- R-1 Home card for new AND existing accounts until "Saved" (`recovery_saved_286`); "Later" = 1 day; no code -> "Make a new code".
- R-2 Settings > Account > Backup and safety: row "Recovery code" -> password (offline hash check) -> code screen.
- R-3 Profile "Recovery code" row opens the same screen. Logs `RECOVERY_CARD shown/saved/later`, never the code.

## Phase 6b - Toasts everywhere (289)
- `LinkToast` + `showErrorToast` redraw + snackBarTheme (app + admin) + move all 102 calls (same words) + round button moves up.

## Phase 7 - Add Contact + QR (283)
- Remove chips row + both BT cards; BT permission asked with Nearby; Wi-Fi / permission cards only when needed.
- New search animation (one painter), "Searching" pill, empty state, "✓ Contact" pill, gradient buttons, slide-in cards,
  not-found card, dashed QR hint, found loop.
- QR: scanner "My QR code" -> `MyQrScreen` (pushReplacement); NEW "From photo" (`image_picker` + `analyzeImage`,
  "No QR code found in this picture"); texts per mock section 5; "Paste code" stays.

## Phase 8 - Mock match check ("100%")
1. Goldens of every changed screen/state, all 12 sizes/modes (Phase 2.7).
2. Compare sheet: the mock phone and the Flutter golden at the same size side by side, one page per screen
   (`compare_3.0.90.html`). Checklist per screen: words, order, sizes, spacing, colours, radius, icons, animation, light.
3. Every difference is fixed, or listed for the owner with the reason (honest limit: a browser and Flutter do not draw
   fonts pixel-identical, and the status bar comes from the phone; layout, sizes, colours and words must match).
4. Owner checks the compare sheet before the release build.

## Phase 9 - Release
- Full suite + Kotlin + analyze (no new warnings above 175) + release build with
  `--dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true` + aapt2 (versionCode 161, 3.0.90).
- `git checkout` GeneratedPluginRegistrant + gradlew mode; ONE zip, ONE commit message (PowerShell block), APPLY doc, PENDING.
- Report every command with its exit code; nothing claimed that did not run.

## Phone test list (after install over 3.0.89)
1. Welcome -> Create account: one loading only; recovery card on Home; Save on WhatsApp; Saved hides it.
2. Log in wrong password -> red card; right -> one loading. Forgot password both tabs, online + offline.
3. Settings > Account > Recovery code: wrong password hidden, right shows the code.
4. Profile photo change: spinner stops; Save changes shows the spinner.
5. Calls tab: one row per person per day; red "N missed"; tap shows the list.
6. Tones: incoming call (Triton), message closed (Salacia), arrived in chat (NFC Start), sent (Volume blip).
7. Add Contact: no BT/Wi-Fi Direct words; search, not found, nearby; Scan QR / My QR / From photo.
8. Same look on C71, Note 60x, TECNO, ZTE; dark + light; big font setting.
9. Toasts: Profile saved, Contact added, an error (camera denied), back-to-exit; round button moves up and back.

## Risks
- Roboto app-wide changes text width everywhere -> some golden / text-width tests change (listed, not weakened).
- Big UI change in one version: if one phase fails its tests it is fixed before the next; nothing half-done is zipped.
- ZTE Go: animations reduced by design (S-4); NOT VERIFIED on the phone yet.
