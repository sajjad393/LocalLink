# FINAL TODO LIST (11 Nov 2026)

Base: app `39f16da` (3.0.76+147), backend `2b3d9a0`.
Freeze: ON. Nothing is built until you say **"Build"**.
Rule (you, 11 Nov): **"If any thing working don't touch it."** Only things your logs showed broken are on this list.
Plan: one build = TODO 259 + TODO 260 together, version **3.0.77+148**.
- Backend zip first (one new route).
- Then ONE app zip, ONE commit.
Full details stay in `TODO_259.md` and `TODO_260.md`.

---

## PART 1: TO BUILD (on "Build")

### 1. Leave a dead Wi-Fi Direct group (TODO 260 A)
Problem: the TECNO app was killed at 22:49, but its group stayed up. Noshad and the ZTE stayed inside it, and the C71 sat alone in an empty group. Result: grey dots.
- [ ] **A1** A member phone sees no link in its group for **30 s** → it leaves (`group_dead`).
  - Safety: not during a call, not in the first 30 s after joining, not while a join is pending.
  - That group is not joined again for 10 min, unless its host comes back.
  - Files: `wifi_direct_fallback_service.dart` (new `groupPeerIds` callback from `app_dependencies.dart`), `nearby_group_planner.dart` (`groupDead` input).
  - Log: `NEARBY|group dead grp=… no_link_s=… refused=…`
- [ ] **A2** After leaving, the phone joins the friend who wants it. No new code: the existing `wanted_by_group` rule and the Bundle 158 bridge do this.
- [ ] **A3** On the router Wi-Fi, if a friend was lost in the last 30 min: search every 60 s for 5 min, then every 3 min until 30 min. Battery rules stay first.
- [ ] **A4** An empty host closes its group after 60 s if it hears a friend's group (`empty_host_yields`). Not when busy or in a call.
- [ ] **A6** A killed phone closes its old `DIRECT-LL-*` group once, when LinkUp opens again (`group leftover_closed`). Only on the owner side, and never for a group LinkUp didn't make. File: `NearbyRadio.kt`, new Kotlin test `Group260Test.kt`.
- [ ] **A5** "Keep LinkUp running" card again after the phone kills the app, at most once a day (my advice: yes). Skipped if the app already shows it. The app changes no settings by itself.

### 2. Stop the name-card storm (TODO 260 B)
Problem: in 1 hour the C71 got 2468 sync requests and saved the same cards ~2600 times. That costs battery and database writes, and slows the useful messages.
- [ ] **B1** Re-sync only when the link really goes from off to on, with at least 5 s between syncs. Everything else keeps the 20 s pause. File: `directory_repository.dart` `_handleTransportEvent`.
- [ ] **B2** Don't save a card again when its signature is the same. File: `local_store.dart` `savePublicCard233`. `_keepPublicCard` is NOT moved.
- [ ] **B3** Answer one phone's sync request at most once a minute (still pass it on).

### 3. No "Unknown user" after a reinstall (TODO 259)
- [ ] **A1** The name lookup also checks the friend's past phones (`personOfPastPhone237` in `peerDisplayName`).
- [ ] **A2** A success log `CONTACTS_SYNC_OK|n=… new=… past=…`, and the chat list refreshes the names.
- [ ] **A3** The first contacts pull right after login is never skipped (`CONTACTS_SYNC_FORCED|why=sign_in`).
- [ ] **B1 (backend)** New route `GET /api/v1/directory/device/{id}`. It answers only for contacts or for people you have chatted with; everyone else gets the same 404. New Go test.
- [ ] **B2** The app fills names that are still missing from that route (at most 50 per run, each phone asked at most once every 6 h). Log: `NAME_FILL_259`.
- [ ] **C1** Offline after a reinstall: when a friend's message can't be opened, send him my new card and ask for his (at most once per 10 min per phone, never to a blocked phone). Log: `KEY_REINSTALL_HELLO_259`.
- [ ] **C3** Check in the build: do the friend's unsent messages go out again after he gets my new card? Fix only if they don't.
- Decided (my advice, so nothing changes in what already works):
  - Q1 offline: the friend's **name** comes back, but he does not come back into People by himself. The People list comes back from the server.
  - Q2: people with directory sync OFF stay hidden (same as today).

### 4. Build checks
- [ ] New tests: `test/bundle259_test.dart`, `test/bundle260_test.dart`, `Group260Test.kt`, `directory_device_259_test.go`.
- [ ] Old tests: only the version lines change (`bundle223_logs`, `nearby_190`). Any other change gets listed in APPLY.
- [ ] Full Flutter suite + `flutter analyze` + Kotlin tests + `go test ./...`.
- [ ] Deliver: backend zip → app zip → `APPLY_app_3.0.77.md` + commit message.

---

## PART 2: YOUR STEPS (after the build)
1. Start the server (`192.168.18.27` was down) and deploy the backend zip.
2. Install 3.0.77 over the old app on all phones.
3. **Dead group test:** everyone on Wi-Fi, force-stop the TECNO. Within ~30–60 s the Note log shows `group dead`. Open the TECNO again: `group leftover_closed`.
4. **Grey-dot test:** the C71 leaves Wi-Fi with the switch ON. The friends should come back over Wi-Fi Direct within ~2 min.
5. **Storm check:** in a 1 h log, `DIRECTORY_SYNC_REQUEST` should be under ~100 (now 2468).
6. **Reinstall test:** reinstall on one phone with the server ON. Names should show within 1 min (`CONTACTS_SYNC_OK`, `NAME_FILL_259`). Then do it once with the server OFF, near a friend.
7. **TECNO:** follow the "Keep LinkUp running" card (Phone Master > App launch > LinkUp > manage manually, all ON; lock LinkUp in recent apps).
8. Send the logs + the time of anything wrong.

---

## PART 3: NOT DOING (closed or stopped)
- **Video call:** STOPPED by you. No questions, no test, no fix. The button stays as it is.
- **Video early stop:** STOPPED.
- **Mesh voice:** works. Closed; 8 hops, no change.
- **Realme slow mic:** works (starts in 1.1–1.9 s). Closed; no warm-up.
- **Group voice call:** dropped.
- **3.1 / 3.2 / D1:** skipped (my advice).
- **Wi-Fi call gaps:** no proven cause (97–99% of the audio played). Only reopened if you send a call log with gaps + the time.
- **Can't be fixed by the app:** the TECNO's own app killer, the 10% battery stop (on purpose), the server being down.
