# TODO 283 - Add Contact screen cleanup (UI)  [BUILT 13 Nov in 3.0.90+161 - zip locallink_app_3.0.90_2026-11-14.zip, not pushed, not phone-tested]

Owner (12 Nov): "Looks very ugly and messy. Remove Bluetooth related ... end user don't know what WiFi direct so remove from ui."
Mock: `mocks/add_contact_improved_283.html` (NOW = owner screenshots, AFTER = mock). Script `mocks/m283/make.py`.

## Code checked (de70ef7; 3.0.87-3.0.89 do not touch these files)
- `lib/features/directory/presentation/add_contact_screen.dart` - empty text `PeopleToAdd267.emptyServer`
  ("Everyone is already in your contacts."), "Results", SearchResultCard ("@user · Contact" + "Added"),
  "No one called ... found.", "Or ask them to show their QR code".
- `lib/features/directory/presentation/nearby_people_section.dart` `_content` (~:613-727):
  `NearbyChips256` (:686-697), Wi-Fi card `_wifiCard256` (:163, text "Still looking with Wi-Fi Direct."),
  `_permissionCard` (:784), Bluetooth card `_bleCardFor/_bleCard` (:818-870, "Faster connect with Bluetooth" /
  "Bluetooth is off"), `_NearbyInfoCard` "Everyone nearby is already in your contacts." + "See contacts" (:710-718).
- `lib/features/directory/presentation/nearby_status_256.dart` - chips "Wi-Fi on/off", "Wi-Fi Direct on/off",
  "Bluetooth not allowed/off/on".
- `lib/features/connectivity/data/services/nearby_ble.dart` - BLE side channel (fast friend connect, wake), status.

## Planned changes (UI)
1. Remove the chips row (Wi-Fi / Wi-Fi Direct / Bluetooth) from Nearby. Keep NEARBY_LIST log.
2. Remove both Bluetooth cards from Nearby.
3. Wi-Fi card text: "Wi-Fi is off" / "Turn it on to find phones near you" (no "Wi-Fi Direct"). Still only opens settings.
4. Permission card text: "Find phones near you" / "LinkUp needs your OK once".
5. "Everyone nearby is already in your contacts" card -> one quiet line (no See contacts).
6. "No one called X found." -> small card "No one called "X" on LinkUp."; QR hint -> "Not here? Ask them to open My QR code and scan it below."
7. Empty Add Contact: icon + "You've added everyone" + text + 2 buttons (Show my QR code, Find people nearby).
8. Results: "✓ Contact" green pill instead of grey "Added". Section titles small grey capitals.
- Not changed: search, server list, Add / Add friend flow, Scan QR, My QR, discovery.

## Bluetooth - DECIDED (owner chose a): remove from screen, keep working in background
- BT permission asked in the same Android request as the Nearby permission (NEARBY_DEVICES group on 12+), no card / no pill.
- Plan: `_startSearch(askPermission:true)` also requests BLUETOOTH_SCAN/ADVERTISE/CONNECT; remove `_bleCardFor`, `_bleCard`, chips.

## Old options (for reference)
- UI-only removal leaves BLE working only where permission was already granted (BT permission was asked only via the card).
- Options: (a) ask BT permission together with the Nearby permission (same Android dialog group on 12+), no card;
  (b) remove BLE code completely (slower friend connect / call wake when offline; many locked tests);
  (c) UI only.
- Tests locking texts (NOT CHECKED yet): `ble_cards_226`, `friend_ble_226`, `nearby_190`, bundle256 chips tests,
  `bundle223_nearby`, `list_match_153`.

## Mock v2 (owner: "Animation not looks good more improve ui")
- `mocks/add_contact_improved_283.html` rebuilt by `mocks/m283/make2.py` (v1 script `make.py` kept).
- New search animation: "you" gradient circle in the middle, 3 soft waves going out, 2 slow dashed orbits, 5 grey
  phone dots floating; when someone is found a curved dashed gradient line draws to them, their circle pops in,
  "Found someone!" and the card slides up. Reduce-motion = still frame (replaces NearbySearchAnimation look).
- Live "Searching" pill (pulsing teal dot) replaces the 3 mini dots.
- Empty screen: glowing check, "You've added everyone", 2 action rows (Show my QR code / Find people nearby).
- Results: "✓ Contact" green pill; gradient Add / Add friend / Scan QR buttons (brand #1E5BFF -> #23B5D8); cards slide in.
- Wi-Fi card button "Turn on" (still only opens Android Wi-Fi settings - app never turns Wi-Fi on).

## SAME LOOK ON EVERY PHONE (owner 12 Nov: "Perfect mock i need same ui feel for every phone")
Mock v2 APPROVED. Code facts (de70ef7):
- Font: app text uses the PHONE's font (Realme / TECNO / ZTE each differ). Roboto is bundled but only as `Roboto216` for admin pages (pubspec).
- Theme: `local_link_app.dart:50` `ThemeMode.system` -> a phone in light mode gets the light theme.
- Text size: the phone's font-size setting is not limited -> big text on one phone breaks rows.
Plan:
- S-1 **Owner chose: Roboto for the WHOLE app** (bundled files already in the APK; add family `Roboto` in pubspec pointing to the same 4 ttf, `fontFamily` in `app_theme.dart`). Every screen changes a little; golden/text-width tests may need updates (list them, do not weaken).
- S-2 Limit text size on this screen to max 1.3x so rows / buttons never break (still bigger for people who need it).
- S-3 Layout by screen width: phones 320-480 dp wide all get the same spacing; small phones (ZTE) shrink the animation box, not the text.
- S-4 Animation light on slow phones: one painter, 30 fps cap, no blur/shadows on low-RAM (Android Go, e.g. ZTE Z2453); "Remove animations" = still frame; stops when screen not visible.
- S-5 Same colours: brand gradient + fixed card colours from the theme, no phone dynamic colours (Material You off).
- S-6 **Owner chose: light version of the same design** for phones in light mode (mock `mocks/add_contact_improved_283_light.html`); dark = `mocks/add_contact_improved_283.html`.
- Check: golden screenshots at 3 sizes (320x640 ZTE-like, 360x800, 412x915) in dark + light, text scale 1.0 and 1.3.

## QR buttons (owner 12 Nov: "Scan QR = scanner, not my QR; if someone shares a QR, show QR code" -> confirmed "Yes")
Code (de70ef7, `lib/features/directory/presentation/my_qr_screen.dart`):
- Add Contact bottom "Scan QR code" -> `_scan()` -> `ContactQrScannerScreen` (camera) - already right.
- Top-right round icon -> `_openMyQr242()` -> `MyQrScreen` - right.
- BUG: scanner "My code" button (:366-375) = `Navigator.pop` -> only goes back, never shows my QR.
Plan:
- Q-1 Scan QR code = camera only. My QR = my code only (one job per button).
- Q-2 Scanner button "My QR code" opens `MyQrScreen` (pushReplacement, so Back returns to Add Contact).
- Q-3 NEW "From photo" in the scanner: pick a QR picture (friend sent on WhatsApp etc.) -> `MobileScannerController.analyzeImage(path)`
  -> same `_handle(raw)` import path. Uses existing deps `image_picker` + `mobile_scanner` (no new dependency).
  No QR in the picture -> "No QR code found in this picture".
- Q-4 Texts: "Scan QR code", "Point at your friend's QR code", "My QR code", "Share my QR", "Scan instead". "Paste code" stays (moved into ⋮ menu? NOT decided - keep as is unless owner says).
- Mock: section 5 in both mock files.
