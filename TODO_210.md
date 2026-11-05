# TODO 210: Share LinkUp with a nearby phone by QR, using a hotspot (no internet)

Status: **BUILT** (go ahead 2026-11-05) on app HEAD `99ba5a9` (209, 3.0.50+121). See `APPLY_210.md`.
Mock: `mock_210_all.jpg` (7 pages; also `mock_210_page1..7.png`).
Target: **3.0.51+122**. No database change (stays v34). No new permission. No new package.

---

## 0. Your decisions (2026-11-05)
| # | Question | Decision |
|---|---|---|
| 1 | Where is the button | **Settings row "Share LinkUp" + People tab card "Invite a friend nearby"** (both open the same screen) |
| 2 | Download page language | **English + Urdu together** (each line English, Urdu under it) |
| 3 | Battery ≤10% | **Warn, with "Share anyway"** |
| 4 | Auto stop with no download | **10 minutes** |
| - | Way to send | Hotspot made by LinkUp (Android "local hotspot"), page served by the phone, no internet |

## 1. How it works (simple)
1. Sajjad taps **Settings → Share LinkUp** or **People → Invite a friend nearby**.
2. LinkUp turns on its own small Wi-Fi. Android gives a random name + password.
3. **Step 1:** QR 1 = join Wi-Fi (`WIFI:T:WPA;S:<name>;P:<password>;;`). Name + password are also written.
4. **Step 2:** QR 2 = `http://<hotspot ip>:8080`. Friend opens it in Chrome.
5. The page (served by Sajjad's phone) has **Download LinkUp** + install steps in English + Urdu.
6. Sajjad sees each phone's % and "Done". Stop sharing → page off, Wi-Fi off.

---

## 2. What the code already has (checked at `99ba5a9`)
| Thing | Where | Use for 210 |
|---|---|---|
| Local hotspot start/stop, reads name + password (Android 11+: `softApConfiguration`, older: `wifiConfiguration`) | `android/.../LocalNetManager.kt` `startHotspot()` L164, `stopHotspot()` L221, `hotspotOn()` | Re-use. Needs "owners" (see A2) |
| Hotspot failure names (`no_channel`, `generic`, `incompatible_mode`, `tethering_disallowed`) | `mesh/LocalNetPolicy.kt` `hotspotFailure()` L84 | Map to simple text |
| Channel `locallink/wifi_direct`: `startLocalHotspot` / `stopLocalHotspot` / `localNetStatus` | `NearbyRadio.kt` L302-305 (`hasPermission` L202: NEARBY_WIFI_DEVICES 13+, FINE_LOCATION ≤12) | Same permission check |
| `NearbyRadio.localNet` (one shared LocalNetManager) | `NearbyRadio.kt` L53 | New share channel talks to it |
| Battery (charging, level) | `NearbyRadio.battery(context)` L212 | Battery warning |
| Wi-Fi settings intent (Panel on 10+) | `MainActivity.kt` L418-424 | "Turn on Wi-Fi" button |
| Mesh hotspot is only a **test switch** (`nearby_test_share_hotspot`, off by default) | `nearby_experiments.dart` L21, planner `nearby_local_net_planner.dart` L135-141 | Normally the hotspot is off, so sharing starts it |
| QR drawing | `qr_flutter` in `pubspec.yaml` (My QR, group QR, account transfer) | QR 1 + QR 2 |
| HTTP server | `dart:io` `HttpServer` (built in) | Download page |
| Settings tab rows | `messenger_settings_screen.dart`, group "This phone": Keep LinkUp running → Storage → Reset setup (L200-220), widget `MessengerSettingsRow` (`core/widgets/messenger_list_group.dart` L105) | New row |
| People tab | `directory/presentation/contacts_screen.dart`: search box (L218) → filter chip → Requests (L241) → Your contacts | New card |
| Logs | `AppLogger` (`core/services/app_logger.dart`) | `SHARE_APP` lines |
| Version stamp test | `test/nearby_190_test.dart` L291 `version: 3.0.50+121` | Change to 3.0.51+122 |

### Problems found in the code (must fix in 210)
- **P1 (important):** if sharing starts the hotspot, the native `hotspot` event `state=on` reaches `wifi_direct_fallback_service.dart` `_applyHotspotEvent()` → sets `_hotspotOn = true` → the planner sees `shareHotspotOn=false && hotspotOn=true` → **stops the hotspot at once** (`stopHotspot 'switch_off'`). Fix: events carry an `owner`; the planner only reacts to `owner=mesh` (A2, A3).
- **P2:** `startHotspot()` always puts the name + password in the nearby tag (`tags()?.setHotspot`). For sharing, the password must **not** go in the nearby tag (other LinkUp phones with the test switch on would join it). Only the mesh owner sets the tag.
- **P3:** `stopHotspot()` closes the hotspot for everybody. With two owners it must close only when the last owner leaves.
- **P4:** the hotspot IP is not known today. LocalOnlyHotspot gives no IP; Android 11+ uses a random `192.168.x.1`. Need an address finder (A4).
- **P5 (Chrome):** Chrome may say **"insecure download"** for a file over `http://` and ask **Keep / Download anyway**. We can't use https without a certificate. Fix: the page step 1 says so (EN + UR), already in mock page 6.
- **Mock note:** the Settings mock (page 1) left out the existing **Storage** row. The real order will be: Keep LinkUp running → Storage → **Share LinkUp** → Reset setup.

---

## 3. New and changed files
**New (Android):**
- `android/.../AppShareNative.kt`: channel `locallink/app_share` (start/stop/status, apk info, addresses, battery, screen-on, settings intents).
- `android/.../AppSharePolicy.kt`: plain functions (split-APK check, interface pick, failure → reason, security → QR type). Checked with `kcheck.sh`.

**Changed (Android):** `LocalNetManager.kt` (owners), `NearbyRadio.kt` (mesh owner on old calls), `MainActivity.kt` (register channel).

**New (Dart), folder `lib/features/share_app/`:**
- `data/app_share_channel.dart`: channel wrapper + `AppShareNativeContract` (fake in tests).
- `data/apk_share_server.dart`: the HTTP server.
- `data/apk_share_page.dart`: builds the HTML page (EN + UR, inline CSS, inline logo SVG).
- `domain/wifi_qr.dart`: Wi-Fi QR text + escaping.
- `domain/share_address_picker.dart`: picks the right IP.
- `domain/app_share_controller.dart`: the steps and states (ChangeNotifier).
- `presentation/share_app_screen.dart`: the screen (mock pages 3, 4, 5, 7).
- `presentation/share_app_entry.dart`: Settings row + People card widgets.

**Changed (Dart):** `messenger_settings_screen.dart`, `contacts_screen.dart`, `home_screen.dart` (one line: passes your name to the People tab, `shareOwnerName`), `wifi_direct_fallback_service.dart` (`_applyHotspotEvent` owner filter), `pubspec.yaml` (version), `test/nearby_190_test.dart` (version stamp).

---

## 4. Phases

### Phase A: Native (Kotlin)
- [ ] **A1 APK info** (`AppShareNative.apkInfo`)
  - Returns `path = applicationInfo.sourceDir`, `size` (File.length), `versionName`, `versionCode`, `split = !splitSourceDirs.isNullOrEmpty()`.
  - `split = true` → Dart shows "This copy of LinkUp can't be shared (installed in parts)". Our `flutter build apk --release` is one file, so normally `false`.
  - Never throws; error → `{error: "apk_missing"}`.
- [ ] **A2 Hotspot owners** (`LocalNetManager.kt`)
  - Add `owners = mutableSetOf<String>()`, values `"mesh"` and `"share"`.
  - `startHotspot(owner)`: add owner. Already on → answer at once with the saved name/password (re-use; nothing restarts). Starting → wait for it.
  - Only when `"mesh"` is an owner: `tags()?.setHotspot(ssid, key)` (fixes P2). When mesh leaves but share stays: `tags()?.setHotspot(null, null)`.
  - `stopHotspot(owner, reason)`: remove owner; close the reservation only when `owners` is empty (fixes P3).
  - `onStopped` (Android stopped it): clear owners, send event to both.
  - Events: `{"type":"hotspot","state":..,"reason":..,"owners":[..]}`.
  - Save `ssid`, `key`, `security` from `onStarted` in memory (not logged).
- [ ] **A3 Old calls stay "mesh"** (`NearbyRadio.kt` L302-303): `startLocalHotspot` → `startHotspot("mesh")`, `stopLocalHotspot` → `stopHotspot("mesh", reason)`. Nothing else changes for mesh.
- [ ] **A4 Address finder** (`AppShareNative.addresses`)
  - List IPv4 of all up interfaces with names: `{iface, ip}` (re-use `NetworkInterface` like `ownAddresses()` L133).
  - Snapshot before start; after `onStarted` check every 250 ms up to 3 s for a **new** address → that is the hotspot IP (handles the random 192.168.x.1).
  - Name hints if no new address: `ap0`, `swlan0`, `wlan1`, `wlan2`, `softap0` = hotspot/tether; `wlan0` = normal Wi-Fi.
  - Also returns `wifiIp` of the normal Wi-Fi (router) when connected (for D2).
- [ ] **A5 Security type**: Android 11+ `softApConfiguration.securityType` → `WPA2` / `WPA3_SAE` / `WPA3_SAE_TRANSITION` / `OPEN`; older → `WPA2`.
- [ ] **A6 Keep screen on**: `keepScreenOn(true/false)` → `window.addFlags/clearFlags(FLAG_KEEP_SCREEN_ON)` on the UI thread. Also cleared in `onDestroy`.
- [ ] **A7 Settings buttons**: `openHotspotSettings()` → tethering settings (`android.settings.TETHER_SETTINGS`), if missing → Wi-Fi settings; `openWifiSettings()` → re-use L418 code; `openLocationSettings()` (≤ Android 12, Location off).
- [ ] **A8 Battery**: `battery()` → `{charging, level}` from `NearbyRadio.battery(context)`.
- [ ] **A9 Failure reasons** (`AppSharePolicy.reasonFor`): `incompatible_mode` → "own hotspot on"; `tethering_disallowed` → "blocked on this phone"; `no_channel`/`generic` → "couldn't start"; SecurityException → `permission`; Wi-Fi off → `wifi_off`; Location off on ≤12 → `location_off`; start not answered in 15 s → `timeout`.
- [ ] **A10 Channel** `locallink/app_share` registered in `MainActivity.configureFlutterEngine` (next to `locallink/device` L245). Methods: `apkInfo`, `startShare`, `stopShare`, `shareStatus`, `addresses`, `battery`, `keepScreenOn`, `openHotspotSettings`, `openWifiSettings`, `openLocationSettings`. `startShare` answers **after** `onStarted`/`onFailed` (or 15 s timeout).
- [ ] **A11 Logs** (tag `SHARE_APP`): `start owner_reuse=true/false`, `on iface=ap0`, `failed reason=..`, `stop reason=..`. **Never log name or password.**

### Phase B: Dart side of the hotspot (P1 fix + channel)
- [ ] **B1** `wifi_direct_fallback_service.dart` `_applyHotspotEvent()`: if the event `owners` doesn't contain `mesh` (and has `share`), ignore it (don't set `_hotspotOn`, don't call `_hotspotFailed`). Old events without `owners` = mesh (safe for old code paths).
- [ ] **B2** `app_share_channel.dart`: typed methods for A10, returns `ShareHotspot {ssid, key, security, ip, reused}` or `ShareFailure {reason}`. Contract class so tests use a fake.
- [ ] **B3** Status poll every 5 s while sharing (`shareStatus`): if the hotspot went off (Android stopped it) → message "Wi-Fi stopped" + [Try again].

### Phase C: Download page server (`apk_share_server.dart`, `apk_share_page.dart`)
- [ ] **C1 Bind**: `HttpServer.bind(InternetAddress.anyIPv4, 8080)`; busy → try 8081..8089; all busy → reason `port_busy`.
- [ ] **C2 `GET /`** → the page (C6). `Content-Type: text/html; charset=utf-8`, `Cache-Control: no-store`.
- [ ] **C3 `GET /LinkUp.apk`** →
  - `Content-Type: application/vnd.android.package-archive`
  - `Content-Length: <size>`
  - `Content-Disposition: attachment; filename="LinkUp-<version>.apk"`
  - `Accept-Ranges: bytes`; `Range: bytes=a-` / `a-b` → `206` + `Content-Range` (Chrome resume). Bad range → `416`.
  - Streams with `File(path).openRead(start, end)`; never loads 60 MB into memory.
- [ ] **C4 Other requests**: `HEAD` same headers without body; other paths (incl. `/favicon.ico`, `/generate_204`) → `302` to `/`; `POST`/others → `405`.
- [ ] **C5 Limits and safety**
  - Serves **only** the page and the APK file. No chats, contacts or other files; read only.
  - Max **3 downloads at the same time**; 4th → small page "Busy, try again in a minute" (`503` + `Retry-After: 60`) in EN + UR.
  - Request line/headers too big → Dart's own HTTP limit closes them (built: no custom 8 KB check). More than 3 downloads at once → 503 "busy" page.
  - Each client idle (no bytes sent) 60 s → connection closed.
- [ ] **C6 Page (EN + UR)**, built in Dart, no outside files (no internet on the friend's phone):
  - Inline CSS; logo as inline SVG (blue → teal gradient, "L").
  - `<html lang="en">`; Urdu parts in `<p lang="ur" dir="rtl">`; the friend's phone uses its own Urdu font (no font file sent).
  - Text: "LinkUp" · "Chat and call without internet" · "Shared by {name} · {version} · {size MB}".
  - Big button **Download LinkUp** (`<a href="/LinkUp.apk" download>`) + Urdu "لنک اپ ڈاؤن لوڈ کریں".
  - "How to install / انسٹال کرنے کا طریقہ", 4 steps:
    1. Tap Download LinkUp. If Chrome warns, tap Keep / Download anyway. (UR)
    2. Tap the file (or open Downloads) and tap Install. (UR)
    3. If Android says "not allowed to install unknown apps", tap Settings → turn on "Allow from this source" → go back → Install. (UR)
    4. Open LinkUp. You can now chat with {name} with no internet. (UR)
  - Note: "Play Protect may say unknown app… tap Install anyway." (EN + UR)
  - `{name}` = my display name (fallback username), HTML-escaped (`< > & " '`).
  - Works on small screens (360 px) and old Chrome (no JS needed).
- [ ] **C7 Progress per phone**: key = client IP. Track bytes sent / total, start time, done. Phones named "Phone 1", "Phone 2" in arrival order. A resumed download (Range) counts for the same phone. Done when all bytes are sent.
- [ ] **C8 Auto stop**: 10 min with no download running and none started → stop (reason `idle`). A running download keeps it alive. Timer reset on each new download.
- [ ] **C9 Stop**: `server.close(force: true)`, cancel all streams, then `stopShare` (owner `share`). Synchronous teardown order: timers → server → native.
- [ ] **C10 Logs**: `SHARE_APP server port=8080`, `get page`, `apk start phone=1 range=0`, `apk done phone=1 ms=12000`, `stop reason=idle|user|left|app_closed|error`. No IPs in full (last part only, e.g. `.23`).

### Phase D: QR text and address picker (`wifi_qr.dart`, `share_address_picker.dart`)
- [ ] **D1 Wi-Fi QR**: `WIFI:T:<type>;S:<ssid>;P:<pass>;;`
  - Escape `\` `;` `,` `:` `"` with `\` in name and password.
  - Type: WPA2 / WPA3 transition → `WPA`; pure WPA3 → `SAE`; open → `nopass` (and no `P:`).
  - Hidden flag never set.
- [ ] **D2 Download QR**: `http://<ip>:<port>` (no path, so the page always opens first).
- [ ] **D3 Address pick order**: (1) new address after start (A4); (2) name hint `ap0/swlan0/wlan1/wlan2/softap*`; (3) only one private IPv4 that isn't `wlan0` → use it; (4) else show the list so the user can tap the right one (rare).
- [ ] **D4 Fallbacks**: own hotspot on (`incompatible_mode`) → use the tether interface IP (often `192.168.43.1`); same router → `wifiIp`.

### Phase E: Controller and screens
- [ ] **E1 `AppShareController` states**: `checking` → `batteryLow` (optional stop) → `starting` → `step1` ⇄ `step2` → `stopped(reason)`; side states `ownHotspot`, `failed(reason)`, `cantShare(split)`.
  - `checking`: apk info, battery. Split → `cantShare`.
  - Battery ≤10% and not charging → `batteryLow` card "Sharing uses a lot of battery. Plug in the charger first." [Share anyway] [Cancel] (decision 3).
  - `starting`: `startShare`; then server; then address. Any step fails → undo the ones done.
  - `incompatible_mode` → `ownHotspot` (QR 2 only, tether IP).
  - Leaving the screen, app closed, back button → stop (no question).
- [ ] **E2 Settings row** (`messenger_settings_screen.dart`, group "This phone", after `StorageSettingsRow`, before "Reset setup"): `MessengerSettingsRow(icon: Icons.ios_share_rounded, title: 'Share LinkUp', subtitle: 'Give the app to a nearby phone · no internet')`. "NEW" badge for 14 days after first seen (memory in prefs `share_app_new_seen_at`). Key `settings_share_app`.
- [ ] **E3 People card** (`contacts_screen.dart`, after the search box / filter chip, before Requests): card "Invite a friend nearby / Give them LinkUp · no internet", icon `Icons.ios_share_rounded`, NEW badge (same 14 days). Hidden while the search box has text. Key `people_invite_nearby`.
- [ ] **E4 Screen: starting** (mock page 3): ring + "Turning on LinkUp Wi-Fi…" + "Your friend will join this Wi-Fi to download the app. No internet used." + note "Nearby chats … may pause …" (shown only when Wi-Fi Direct/mesh is on) + "What your friend needs" (Android phone, about {size} MB free, no internet/SIM) + [Cancel].
- [ ] **E5 Screen: Step 1** (mock page 4): step chips; QR 1 (size 210, white card, `QrImageView`, error level M); "On the new phone: Settings → Wi-Fi → tap the QR icon and scan this code. (or scan with the camera app)"; "Or type it" name + password in mono font + Copy (copies `name` then shows "Copied"; long-press copies password); tip "If the new phone says 'This Wi-Fi has no internet. Stay connected?' tap Yes / Stay."; [Next: Download →]; "Stop sharing"; "Screen stays on while sharing".
- [ ] **E6 Screen: Step 2** (mock page 5): QR 2 + "Scan with the camera, open in Chrome" + "or type: 192.168.x.1:8080" + "LinkUp {version} · {size} MB"; list "Phones getting LinkUp" (bar + % + "38 of 59 MB", Done + seconds); note "Sharing stops by itself after 10 minutes with no download, or when you leave this screen."; [← Back to step 1]; [Stop sharing] (red).
  - When the first download starts while on Step 1 → jump to Step 2 by itself.
- [ ] **E7 Screen: problems** (mock page 7):
  - Own hotspot on → blue note + QR 2 (tether IP) + "Name and password: in your phone's hotspot settings" + [Open hotspot settings] + [Stop sharing].
  - Same router (phone on Wi-Fi, no hotspot possible) → QR 2 with router IP, same steps.
  - "Couldn't turn on Wi-Fi" → [Turn on Wi-Fi] [Try again]; Location off (≤12) → [Turn on Location].
  - "Sharing stopped. No downloads for 10 minutes." → [Share again].
  - "Wi-Fi stopped" (Android stopped it) → [Try again].
  - "This copy of LinkUp can't be shared" (split) → [OK].
- [ ] **E8** Keep screen on while the share screen is open (A6); off on leave.
- [ ] **E9** Mesh note: when the share hotspot is on and Wi-Fi Direct can't run beside it, nothing is forced; existing mesh code keeps trying; after stop it comes back by itself (phone test 210-8).
- [ ] **E10** Large text / small phones: screen scrolls; QR never smaller than 180.

### Phase F: Tests, full run, zip
- [ ] **F1 Server tests** (`test/bundle210a_server_test.dart`): page 200 + contains EN + UR text + escaped name; APK bytes equal file; Range `0-`, `100-199`, `100-` → 206 + right bytes; bad range → 416; `/x` → 302; POST → 405; HEAD no body; 4th download → 503; idle stop at 10 min (fake clock); running download blocks idle stop; progress per IP, resume = same phone.
- [ ] **F2 QR tests** (`bundle210b`): escaping of `\ ; , : "`; WPA / SAE / nopass; URL format.
- [ ] **F3 Address tests** (`bundle210c`): new address wins; `ap0` vs `wlan0`; random subnet; one-only rule; none → list.
- [ ] **F4 Controller tests** (`bundle210d`, fake native): normal path; re-use (`reused=true`); `incompatible_mode` → ownHotspot; battery 8% → warning, Share anyway → starts; charging at 8% → no warning; split → cantShare; start fail after server bound → server closed; leave → stop called once; Android stopped → message.
- [ ] **F5 P1 test** (`bundle210e`): hotspot event with `owners:[share]` → fallback service `_hotspotOn` stays false, planner makes no `stopHotspot`; event with `owners:[mesh]` → old behaviour.
- [ ] **F6 Widget tests** (`bundle210f`, 800×600, no pumpAndSettle with ring): Settings row present between Storage and Reset; People card present, hidden with search text; Step 1 shows name/password/QR; Step 2 list shows 64% and Done; problem cards.
- [ ] **F7 Kotlin** (`kcheck.sh`): `AppSharePolicy` split check, reason map, iface pick, security map; owners logic in a small pure helper.
- [ ] **F8 Source scans**: no new `<uses-permission>` in the manifest; `SHARE_APP` logs have no `ssid`/`key` values; `owners` in hotspot events; version stamp `3.0.51+122` in `nearby_190_test.dart`.
- [ ] **F9** Full `flutter test` (all old + new pass) + `flutter analyze` ≤ 166.
- [ ] **F10** Zip `locallink_app_210_<date>.zip` + `APPLY_210.md` (phone tests below) + update `PENDING.md`.

---

## 5. Phone tests (go into `APPLY_210.md`)
Phones: Realme (Sajjad) shares; ZTE (Sumaira) or a 3rd phone without LinkUp receives.
- [ ] 210-1 Settings → Share LinkUp → "Turning on…" → Step 1 in ≤5 s.
- [ ] 210-2 People → Invite a friend nearby → same screen.
- [ ] 210-3 Receiver scans QR 1 (Wi-Fi settings QR icon) → joined; "no internet, stay?" → Yes.
- [ ] 210-4 Receiver types name + password by hand → joined (old phone path).
- [ ] 210-5 Receiver scans QR 2 → page opens with **no internet**; English + Urdu look right.
- [ ] 210-6 Download → Chrome warning? (note what it says) → Keep → 100% → Install → "Allow from this source" → installs → opens.
- [ ] 210-7 Sharer shows Phone 1 %, then Done + seconds.
- [ ] 210-8 Leave the screen → hotspot off; Wi-Fi Direct / mesh chats work again within 2 min.
- [ ] 210-9 Wait 10 min with no download → "Sharing stopped" → Share again works.
- [ ] 210-10 Walk away mid-download → come back → Chrome resumes (or restarts) and finishes.
- [ ] 210-11 Own phone hotspot on → problem screen with QR 2 → friend joins your hotspot → download works.
- [ ] 210-12 Both phones on the same home Wi-Fi → QR 2 router address works.
- [ ] 210-13 Battery ≤10% (not charging) → warning → Share anyway works.
- [ ] 210-14 Update path: phone with LinkUp 3.0.50 installs the shared 3.0.51 over it → chats kept.
- [ ] 210-15 Send logs from both phones (`SHARE_APP` lines).

## 6. Limits (said plainly)
- Android picks the hotspot name and password; we can't make it "LinkUp-Sajjad".
- QR Wi-Fi join needs Android 10+ on the friend's phone; older phones type name + password.
- The friend's phone must be at least the app's minimum Android version (from Flutter's default; exact number checked in phase A and written on the page).
- First install always asks "Allow from this source"; Chrome may say "insecure download"; Play Protect may warn. We can't skip these.
- On some phones (likely ZTE) hotspot and Wi-Fi Direct can't run together → nearby chats pause while sharing.
- Sharing works only while the Share screen is open (screen kept on).
- Only Android phones (no iPhone).
- The shared file is the one installed on the sharing phone (same signing key → later versions update over it).

## 7. Not in 210 (out of scope)
- Sending the app over Wi-Fi Direct/mesh to a phone that already has LinkUp (updates in chat).
- Bluetooth sending (Android often blocks `.apk` over Bluetooth).
- A captive "sign in" page that opens by itself (needs a DNS server on port 53, not possible without root).
- Choosing the hotspot name/password.

## 8. Safety: no effect on the rest of the app (checked 2026-11-05 at `99ba5a9`)
**Rule:** all new work lives in new files (`lib/features/share_app/`, `AppShareNative.kt`, `AppSharePolicy.kt`). Existing files get only small, listed changes:

| Existing file | Change | Why it is safe |
|---|---|---|
| `LocalNetManager.kt` | hotspot "owners" (mesh / share) | Mesh path behaves exactly as today: owner `mesh` sets the nearby tag, stop closes when mesh is the only owner. Kotlin check covers mesh-only, share-only, both. |
| `NearbyRadio.kt` L302-303 | pass owner `"mesh"` | Same calls, same answers. |
| `MainActivity.kt` | register channel `locallink/app_share` | New channel name, no other channel touched. |
| `wifi_direct_fallback_service.dart` `_applyHotspotEvent` | ignore events that are share-only | Events without `owners` (old) = mesh → old behaviour; `nearby_161_test` must stay green. |
| `messenger_settings_screen.dart` | 1 new row after Storage | Other rows unchanged; `bundle183_test` must stay green. |
| `contacts_screen.dart` | 1 card before Requests, hidden while searching | Search, filter, Requests, contacts unchanged; `bundle183_test` T5 must stay green. |
| `home_screen.dart` | passes `shareOwnerName` to `ContactsScreen` (added while building) | One named argument with a default; nothing else changed. |
| `pubspec.yaml`, `nearby_190_test.dart` | version 3.0.51+122 | Normal version bump. |

**Checked, no clash:**
- Ports: app uses 8988 (Wi-Fi Direct), 8989 (LAN), 8991 (local net), 8992 (call voice), 45454 (discovery). Share uses **8080-8089** → no clash.
- No new permission, no new package, no DB change, no backend change, no background service change.
- The mesh hotspot test switch (`nearby_test_share_hotspot`, off by default) keeps working; if it is on, sharing re-uses its hotspot.
- Nothing runs unless the Share screen is open; leaving it stops everything.

**Only while sharing is on (expected, told on screen):**
- On phones that can't do two Wi-Fi jobs at once, Wi-Fi Direct / mesh chats may pause, and on some phones the home Wi-Fi may drop (mobile data takes over). Both come back after Stop sharing (phone test 210-8).

**Proof before the zip:** full `flutter test` (all old tests must pass unchanged; if an old test needs an edit, it is only an added expectation, and I'll list it), analyze ≤ 166, Kotlin check.

## 9. Delivery
One app zip with one commit (`v3 3.0.51+122 bundle 210: …`), `APPLY_210.md`, `PENDING.md` updated. No backend change.
