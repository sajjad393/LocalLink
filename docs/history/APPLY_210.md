# APPLY 210 - Share LinkUp with a nearby phone (QR + hotspot, no internet)

Version **3.0.51+122**. Database stays **v34**. No new permission, no new package, no backend change.
Plan: `TODO_210.md`. Mock: `mock_210_all.jpg` (in the workspace, not in the zip).

## What changed (simple)

Sajjad taps **Settings → Share LinkUp** (or **People → Invite a friend nearby**).
LinkUp turns on its own small Wi-Fi (Android "local hotspot") and a tiny web page on the phone.
- **Step 1:** the friend scans QR 1 with the camera / Wi-Fi settings → joins the Wi-Fi (or types name + password).
- **Step 2:** the friend scans QR 2 → Chrome opens the page (English + Urdu) → Download → Keep → Install.
- The sharer sees **Phone 1 64%**, then **Done, 62 MB · 12 s**.
- Leaving the screen, **Stop sharing**, or **10 min with no download** turns everything off.
- Your own phone hotspot is on → screen shows QR 2 + "Open hotspot settings" (friend joins your hotspot).
- Same home Wi-Fi → QR 2 uses the router address.
- Battery 10% or less (not charging) → warning with **Share anyway**.

| Phase | What |
|---|---|
| A | Kotlin: `AppShareNative.kt` (channel `locallink/app_share`), `AppSharePolicy.kt`; `LocalNetManager` hotspot **owners** (mesh / share): share never sets the nearby tag, the hotspot closes only when no owner is left; `NearbyRadio` passes owner mesh; `MainActivity` registers the channel |
| B | `wifi_direct_fallback_service.dart`: a hotspot event owned only by share is ignored (mesh never stops it). Old events (no `for`) = mesh, same as before |
| C | Page server on port 8080 (8081-8089 if busy): `/` page, `/LinkUp.apk` with resume (Range), max 3 downloads at once (4th gets a "busy, try in a minute" page), 60 s idle per client, 10 min auto stop |
| D | Wi-Fi QR text (WPA / SAE / open, special characters escaped), picks the hotspot address (Android 11+ picks a random one) |
| E | Screen (starting, Step 1, Step 2 jumps by itself when a download starts, problem cards), Settings row (NEW badge 14 days), People card (hidden while searching), screen kept on |
| F | Version, 66 new tests, this file |

## Small differences from the TODO (please note)

1. `home_screen.dart` has one added line: it passes your name to the People tab (`shareOwnerName`) so the page says "Sajjad shared LinkUp". Nothing else in home_screen changed.
2. The note "Nearby chats may pause for a moment" is shown on the "Turning on…" screen every time (not only on phones that can't do both).
3. Very big request headers: Dart's own HTTP limit closes them (no custom 8 KB check). A 4th phone at once gets a simple "busy" page (503).
4. The server file has one test-only setter (`activeDownloadsForTest`); the app never uses it.

## Logs to look for (tag `SHARE_APP`, no names or passwords in logs)

- `ready reused=false ip_found=true`, `server port=8080`
- `get page`, `apk start phone=1 from=0 ip=.23`, `apk done phone=1`
- `stop reason=left|user|idle|stopped|restart`, `wifi stopped by android`, `idle`
- Native (logcat tag `SHARE_APP`): `start on=false`, `on reused=false iface=ap0 ip_found=true`, `failed reason=location_off|own_hotspot|couldnt_start|timeout|...`, `stop reason=...`

## Phone tests 210 (A = sharer with LinkUp, B = friend without LinkUp)

Mobile data + internet OFF on both, unless a test says otherwise.

| # | Steps | Expected | Result |
|---|---|---|---|
| 210-1 | A: Settings → Share LinkUp | "Turning on…" then Step 1 in ≤5 s | |
| 210-2 | A: People → Invite a friend nearby | Same screen | |
| 210-3 | B scans QR 1 (camera or Wi-Fi settings QR icon) | Joined; "no internet, stay?" → Yes | |
| 210-4 | B types name + password by hand | Joined (old phone path) | |
| 210-5 | B scans QR 2 | Page opens with no internet; English + Urdu look right | |
| 210-6 | B: Download → Chrome warning? (write what it says) → Keep → Install → "Allow from this source" | Installs and opens | |
| 210-7 | Watch A during 210-6 | Phone 1 %, then Done + seconds | |
| 210-8 | A leaves the screen | Hotspot off; Wi-Fi Direct / mesh chats work again within 2 min | |
| 210-9 | Wait 10 min, no download | "Sharing stopped" → Share again works | |
| 210-10 | B walks away mid-download, comes back | Chrome resumes (or restarts) and finishes | |
| 210-11 | A's own phone hotspot on, then Share LinkUp | Problem screen with QR 2; B joins A's hotspot; download works | |
| 210-12 | Both on the same home Wi-Fi (internet may be on) | QR 2 router address works | |
| 210-13 | A battery 10% or less, not charging | Warning → Share anyway works | |
| 210-14 | B has LinkUp 3.0.50 and installs the shared 3.0.51 over it | Chats kept | |
| 210-15 | Send logs from both phones (`SHARE_APP` lines) | | |

Honest limits: Android picks the hotspot name and password; QR join needs Android 10+ on B (older: type it);
Chrome may say "insecure download" and Play Protect may warn (tap Keep / Install anyway);
on some phones (likely ZTE) nearby chats pause while sharing; sharing works only while the screen is open;
Android phones only.

## Tests here (no phone)

RESULT: full `flutter test` **1772/1772 pass** (209: 1706). +66 new in `bundle210a..f_test.dart`
(server 12, QR + page, address picker, controller, hotspot owner, screen + entry points).
`flutter analyze`: **166** (same as 209). Kotlin compile check: clean.
Old tests changed: only the version stamp in `nearby_190_test.dart` (3.0.51+122).
