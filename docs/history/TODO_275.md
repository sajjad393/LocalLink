# TODO 275 - Silent nearby update: no names, no question on the other phone, auto start

Status: PROPOSAL ONLY (freeze ON). Build only after the user says "Build".
User request (14 Nov): "if sajjad app is older version and request from nearby dont show any other
username and popup auto start updating without tell other user".
Code: app `6bf30bd`, Bundle 213 (E) nearby update.

## Today (code)
- Sajjad (old app) opens "Get the new LinkUp" (`share_app/presentation/update_sheet.dart`): a LIST of nearby
  phones with a newer build, WITH their names (`UpdateRequestService.candidates`, `update_request_service.dart:148-162`),
  and he taps Ask next to one.
- The other phone shows a question "Sajjad wants the new LinkUp" with Share / Not now and its battery
  (`UpdateRequestService.confirm` -> `showUpdateAskDialog`, `local_link_app.dart:120-124`; `_onRequest` 288-340).
- Share -> that phone serves the app on the shared Wi-Fi / WD network (`_serve`, plain http on a private IP)
  and sends `app_update_offer`; Sajjad's phone opens the download address by itself (`_onOffer`, 418-440).
  No shared network -> the other phone opens the QR "Share LinkUp" screen (needs that person).
- The offer and the download page carry the sharer's name (`'name': myName()`, `ownerName: myName()`).

## Plan
U-1 Sajjad's phone - one popup, no names
- When this app is older than a nearby phone (and/or the admin's minimum version says update), a popup
  "New LinkUp found nearby - Getting it..." opens and STARTS BY ITSELF (Cancel button). No list, no names,
  no phone names; the best nearby phone is picked by itself (newest build, same Wi-Fi / WD first).
- Progress words only: "Getting it..." -> "Ready - tap Install". If that phone does not answer in 60 s,
  the next phone is tried by itself; none left -> "Try again later".
U-2 The other phone - nothing shown
- No question, no pop-up, no notification: it serves the app quietly when ALL are true:
  same Wi-Fi / WD network as the asker (no QR fallback - QR needs a person), battery >= 30 % or charging,
  not in a call, max 1 share at a time, max 1 per asker per 2 min (already).
  Otherwise it answers "not now" silently and the asker tries the next phone.
- The sharer's name is removed from the offer frame and from the download page (`apk_share_page.dart`
  owner name -> "LinkUp").
- Log only: `APP_UPDATE_SILENT_SHARE to=<6> ok|skip=reason`.
U-3 Install (Android limit)
- Android ALWAYS asks the user before installing an app (system "Update" screen) - this cannot be skipped
  on a normal phone. Today the download opens in the browser (Chrome warns about http downloads, user
  taps Keep, then opens the file). Option (a) keep the browser way. Option (b) the app downloads the file
  itself and opens the Android installer directly (needs the "Install unknown apps" permission for LinkUp,
  `REQUEST_INSTALL_PACKAGES`; Android asks once, the app never turns it on by itself).
- Android also refuses an update signed with a different key, so a phone can't push a fake LinkUp.

## Decisions (user, 14 Nov)
- Who serves silently: ANY LinkUp phone nearby (same Wi-Fi / WD network).
- Popup opens: WHENEVER a nearby phone has a newer build (not only with the admin banner).
  Max once per new build; Cancel = not again for that build today.
- Install: U-3 option (b): LinkUp downloads the file itself, then opens Android's "Update" screen.
  + AUTO DELETE: the downloaded file is deleted when the new version starts for the first time
  (it is in the app's own cache folder, so no storage permission). Also deleted when the user
  cancels / the install fails, and any leftover file older than 24 h is deleted at app start.
- Checked: the manifest has no `REQUEST_INSTALL_PACKAGES` and no FileProvider today -> both added
  (Android asks "Allow from LinkUp" once; the app only opens that settings page when the user taps).
- Download checks: size must match the offer, file must be a LinkUp APK (package `com.sajjad.linkup`)
  before the installer opens; Android also checks the signing key.

## Files if built (planned)
`update_request_service.dart`, `update_sheet.dart` (popup), `local_link_app.dart` (no confirm hook on the
sharer), `apk_share_page.dart` / `apk_share_server.dart` (no owner name), `version_banner.dart` (auto popup),
`AndroidManifest.xml` (permission + FileProvider), `res/xml` provider paths, native download/install/delete in `MainActivity.kt` or the share channel; new `test/bundle275_silent_update_test.dart`.
Old tests that check the Ask list / the confirm dialog (`bundle213*`) would change - listed test changes.
