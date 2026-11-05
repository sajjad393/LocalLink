# TODO 213: Admin stops old app versions (offline + web)

- Status: **BUILT 2026-11-05** (go ahead given). See `APPLY_213.md` for what was built and what differs (DB stays v34, own one-step frames, no map tag).
- Target: app 3.0.54+125, DB v34 (was planned v36), backend migration 56.
- Mock: `mock_213_all.jpg` (pages `mock_213_page1..8.png`).
- Repo: https://github.com/sajjad393/LocalLink (app), https://github.com/sajjad393/LocalLinkBackend (backend).

## Phase overview (build order)
| # | Phase | What | Depends on |
|---|---|---|---|
| A | Build number | `kAppBuild` constant; `X-LinkUp-Build` header on HTTP + socket | none |
| B | Rule + store | Signed version rule (212 admin key / server key), DB v36, my state ok / warn / stopped | 212 A-B |
| C | Spread + server | Rule rides on the 212 one-step frames; build `b` in the digest; server + web panel page | 212 C, G |
| D | Enforce | Warn banner, read-only through the 212 send guard, first-hop drop, very-old switch (server 426 + nearby) | B, C |
| E | Update from a nearby phone | Ask → asked phone says Share → 210 share → download opens | 210 share, C |
| F | Admin UI | "App version" card, Minimum version page, confirm popup | B |
| G | Tests + delivery | Dart + Go tests, full suite, zips, APPLY_213.md | all |

## 0. Your choices (2026-11-05)
- Bundle: new 213, after 212.
- Old phone when stopped: **read-only** (reads old chats, can't send or call) + banner with **Update**.
- Update button: gets the new app from a **nearby phone** (210 share). Flow: Ali taps Update → nearby phones with a newer version → Ask → Sumaira's phone asks "Ali wants the new LinkUp. Share?" → Share → download opens on Ali's phone by itself.
- When: admin picks each time: **Warn only / Stop now / Stop after X days** (default 3).
- During the wait: yellow banner "Update needed in N days" + Update, × hides it for the day.
- Where: **app Admin panel** (offline, spreads phone to phone) **+ web panel**.
- Very old apps (before 3.0.54, can't obey): admin switch **"Also stop very old apps"** → server refuses them, updated phones don't link with them. Two old phones together offline still work (nothing can stop that).

## 1. Code facts (checked in w211)
- No version is sent anywhere today: no `X-App-Version`, no build in nearby hello, no backend check (grep: nothing).
- `AppConfig.buildNumber` (app_config.dart L46) is a `--dart-define` with default `'32'`: **not reliable** (you build with plain `flutter build apk`). → new constant `kAppBuild`.
- HTTP: every request goes through `ApiHttpClient` (core/network/api_http_client.dart, `get` / `post` / … → `_send`). Socket: `IOWebSocketChannel.connect(…, headers: _headers)` (websocket_service.dart L127).
- Backend: all routes on one `mux`; wrapped at main.go L182-188 `requestLogging(metrics, requestRecovery(metrics, limitRequestBody(mux)))` → one new wrapper `versionGate(...)` there.
- 210 share: `AppShareController` stages incl. `sameWifi` (router address, no hotspot), `ApkShareServer(apkPath, apkSize, version, ownerName)`, `AppShareNative.apkInfo()` returns `version`. Battery ≤10% "Share anyway".
- Opening a URL: `MediaStorageNative.openUri(context, value, mime)` = ACTION_VIEW (MediaStorageNative.kt L176). Use with mime `text/html` for the http download link (check on phone; fallback: show the link + Copy).
- No install permission in the manifest (no REQUEST_INSTALL_PACKAGES) → the download goes through the browser (Chrome "insecure download" → Keep, as in 210).
- `BackgroundRunner` steps (background_runner.dart): 212 adds `admin_blocks`; the version rule rides on it.
- One-step frames (195c, extended in 212 by `MeshOneStep.isOneStep`): sent only to a directly linked phone, accepted on any link, never routed. 213 adds `version_rule_*` and `app_update_request` / `app_update_answer` / `app_update_offer` to that list (one line in `MeshOneStep`).
- Banners: home banner style `_offlineAccountBanner` (home_screen ~L413); chat input replacement `_blockedBar` (chat_screen ~L826); 212 adds the red admin banner + send guard, 213 reuses both.
- Version scans in old tests: `nearby_190` (version), `link_201`, `bundle178` check pubspec / version strings → bump them only as before (add the new expected version, tell you).

## 2. Files
**App, new:**
- `lib/core/config/app_build.dart`: `const int kAppBuild = 125;` + `const String kAppVersion = '3.0.54';` (a test checks they match pubspec).
- `lib/features/admin/data/models/version_rule.dart`: rule record (min_build, min_version, mode warn|stop, stop_at, very_old, seq, issued_at, by) + canonical JSON + newest-wins.
- `lib/features/admin/data/services/version_rule_service.dart`: save / verify / spread / server sync / my state (ok · warn · stopped).
- `lib/features/admin/presentation/screens/admin_min_version_screen.dart` (mock page 2).
- `lib/core/widgets/version_banner.dart`: yellow (warn) / red (stopped) banner (mock 4, 5).
- `lib/features/share_app/presentation/update_from_nearby_sheet.dart` (mock 6) + `update_offer_card.dart` (mock 8).
- `lib/features/share_app/domain/update_request_service.dart`: ask / answer / offer messages.

**App, changed:**
- `api_http_client.dart`: header `X-LinkUp-Build: kAppBuild` on every request; `426` → version state "stopped by server".
- `websocket_service.dart`: same header in `_headers`.
- 212 digest (admin_block_service.dart): adds `b` (my build) + the rule digest.
- `MeshBlockPolicy.kt` (212): `MeshOneStep.isOneStep` adds the 213 frame types (Android side, one line).
- `admin_panel_screen.dart`: "App version" card (mock 1).
- `local_store.dart` + `database_config.dart` v36: `version_rules`, `peer_builds` (peer_id, build, seen_at).
- 212 send guard: `selfRestricted` = admin-blocked OR version-stopped (one place).
- `home_screen.dart` / calls / people tabs / `chat_screen.dart`: banner + input bar text.
- `share_app_screen.dart` / `app_share_controller.dart`: start from an update request (sameWifi / Wi-Fi Direct address, or the normal QR steps).
- `link_paths_map.dart` (212): optional amber "old" tag on a node; full map filter "Old version".
- `app_dependencies.dart`, `background_runner.dart` (none new if it rides on `admin_blocks`), `pubspec.yaml`.

**Backend:**
- New: `internal/httpapi/version_gate.go` (+ `_213_test.go`), `internal/httpapi/version_rule.go`.
- Changed: `store.go` (migration 56: `version_rules`), `admin_panel.go` (web page "App version"), `cmd/server/main.go` (wrapper + routes).

## 3. Phases
### A. Build number
- [ ] A1 `kAppBuild` / `kAppVersion`; test = pubspec `version:`.
- [ ] A2 Header on HTTP + socket. Logs show `build=125` once at start.

### B. Rule record + store (DB v36)
- [ ] B1 `VersionRule` signed with the 212 admin key (offline) or the server key (web). Same checks as 212 B3 (trusted signer, owner role, cert not ended). Newest `seq` wins; "Remove rule" = record with `min_build = 0`.
- [ ] B2 `version_rules` (one current row + history), `peer_builds`.
- [ ] B3 My state: `ok` / `warn(daysLeft or none)` / `stopped`. Recomputed on start, on new rule, and every 15 min (works with the app closed).

### C. Spread + server
- [ ] C1 Rides on the 212 one-step digest / records / got-it frames (kind `version_rule`), hop to hop to every phone, also with the app closed. Digest also carries `b` = my build → `peer_builds` (only direct neighbours, which is what the Update list needs).
- [ ] C2 Server: `GET /api/v1/version-rule` (device auth) and `POST /api/v1/admin/version-rule` (admin session, owner). Sync like 212 G1: newest wins both ways.
- [ ] C3 Web panel page "App version": same fields (version box, Warn only / Stop now / Stop after X days, very-old switch), shows users by last seen build.

### D. Enforce
- [ ] D1 Old phone (≥3.0.54 but below min):
  - warn → yellow banner on Chats / Calls / People: "Update needed" or "Update needed in N days. After that this version can only read chats." + Update; × hides it until tomorrow.
  - stopped → read-only through the 212 send guard (messages, groups, calls, files, reactions, polls). Red banner "This version is stopped by admin. You can read old chats. Update to send and call." + Update. Chat input → "Old version. Update to send." + Update.
  - Notification once when it turns stopped: "This LinkUp version is stopped by admin".
- [ ] D2 Others: drop at the first hop packets from / to a peer whose announced build is below min after `stop_at` (same 212 D2 list → that phone still relays others, sealed). One-step frames are exempt, so the stopped phone can still ask for the update.
- [ ] D3 Very old switch ON:
  - Server `versionGate`: request without `X-LinkUp-Build` → `426 {"error":"update_required"}`. Not gated: web admin panel pages, `/healthz`, `/api/v1/trust`. Also gated: build < min after `stop_at` → 426.
  - Nearby: a linked peer that sent no digest with `b` within 3 min (2 rounds) = very old → 212 D2 relay-only + first-hop drop. Log `VERSION_DROP peer=… reason=very_old`.
  - Off → nothing changes for very old apps.
- [ ] D4 Admin can't stop own version (picker shows own build and lower only). The admin phone ignores rules above its own build (log).

### E. Update from a nearby phone (210)
- [ ] E1 Sheet "Get the new LinkUp" (mock 6): phones directly linked now (local Wi-Fi, Wi-Fi Direct, one mesh hop) from `peer_builds` with build ≥ min (link way + version), newest version first. Tap Ask → `app_update_request` (one-step frame, signed by my device key) → "Asking…"; 60 s timeout → "Try another". Max 1 ask per phone per 2 min. None nearby → "Ask a friend to open Settings → Share LinkUp".
- [ ] E2 Asked phone (mock 7): dialog "Ali wants the new LinkUp" / "Share your version 3.0.54 (48 MB)? …" Share / Not now. App closed → notification with Share (opens the Share screen). Battery ≤10% → 210 "Share anyway". Not now → Ali sees "Sumaira said not now".
- [ ] E3 On Share:
  - Same Wi-Fi router or same Wi-Fi Direct group (an IP path exists) → start `ApkShareServer` only (no hotspot), send `app_update_offer {url, version, size}` (one-step) → Ali's card "Sumaira is sharing LinkUp 3.0.54" + "Open download" (opens by itself once, `MediaStorageNative.openUri(url, 'text/html')`) → browser download → Keep → Install.
  - No IP path, or the link doesn't open in 20 s → Sumaira's phone opens the normal 210 Share screen (QR 1 Wi-Fi, QR 2 download); Ali's card says "Scan Sumaira's QR 1, then QR 2 with your camera" + shows the link with Copy.
  - Sharing stops after the download ends or 10 min (210 rule).
- [ ] E4 After install (new build ≥ min): banners gone, sending works, `peer_builds` updates on the next digest.

### F. Admin UI (mock 1-3)
- [ ] F1 Card "App version" under "Block users": this phone's version, "Versions seen nearby" chips with counts (from `peer_builds`, last 7 days), row "Minimum version" (current rule or "None set").
- [ ] F2 Page "Minimum version" (Admin look): version picker (own and lower), radio Warn only / Stop now / Stop after [3] days (1-30), switch "Also stop very old apps", info "Affects N users nearby", "Save rule"; current rule shows "Remove rule".
- [ ] F3 Confirm in the 212 popup style: "Stop versions below 3.0.54?" + 4 lines + "Save for everyone" / Cancel.

### G. Tests + delivery
- [ ] G1 Dart `bundle213a..f`: build constant = pubspec, header on HTTP + socket, rule sign / verify / newest wins, state warn → stopped by time (fake clock), send guard, banners, update request / offer flow with fakes, very-old detection timer.
- [ ] G2 Go: gate (no header → 426 when on, passes when off, web panel not gated), rule endpoints, owner only.
- [ ] G3 Old tests unchanged; full `flutter test`; analyze ≤ baseline; `APPLY_213.md`; app zip + backend zip; `PENDING.md`.

## 4. Phone tests (APPLY_213.md)
- [ ] 213-1 Both phones on 3.0.54. Admin sets min 3.0.54 → nothing happens (all ok).
- [ ] 213-2 ZTE acts as an old build (testers-only switch "Pretend old build" in Nearby tests; **not asked by you, say if you don't want it**). Admin sets "Stop after 1 day" offline → ZTE yellow banner within 1 min over Wi-Fi Direct.
- [ ] 213-3 "Stop now" → ZTE read-only, red banner, can't send / call, can read.
- [ ] 213-4 ZTE taps Update → sees Realme → Ask → Realme dialog → Share → ZTE download opens (same Wi-Fi).
- [ ] 213-5 Same over Wi-Fi Direct; then mesh only → QR fallback.
- [ ] 213-6 Very old switch ON with a 3.0.52 phone: server refuses it (426 in server log); 3.0.54 phones drop its messages (log `VERSION_DROP`), it still relays.
- [ ] 213-7 Web panel sets / removes the rule → phones get it online and pass it on offline.
- [ ] 213-8 App closed on ZTE: rule arrives and stop time passes → notification + read-only on open.
- [ ] 213-9 Logs from both phones (`VERSION_*`, `UPDATE_*`).

## 5. Safety
- Rules are signed; fakes are rejected (same trust as 212).
- Only the owner role; can't stop own version.
- Read-only never deletes anything; update brings everything back.
- Very old switch is OFF by default.
- Old tests pass unchanged; edits only in the files above.

## 6. Delivery
- Backend zip first (deploy), then app zip (one commit `v3 3.0.54+125 bundle 213: …`), APPLY_213.md + PowerShell.
