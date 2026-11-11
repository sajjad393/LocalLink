# APPLY app 3.0.77+148 (TODO 259 + TODO 260)

Zip: `locallink_app_3.0.77_2026-11-11.zip`, on top of GitHub `39f16da` (3.0.76+147).
Deploy the backend FIRST: `APPLY_backend_259.md` (one new route). The app also works with the old server (it then just keeps the old names).

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_3.0.77_2026-11-11.zip" .
flutter pub get
flutter test
git add -A
git add -f docs/history/TODO_259.md docs/history/TODO_260.md docs/history/TODO_FINAL.md docs/history/APPLY_app_3.0.77.md
git commit -m "v3 3.0.77+148 bundles 259-260: a member leaves a Wi-Fi Direct group whose host app is gone after 30 s with no link and does not rejoin that host for 10 min, a force-stopped phone closes its own leftover group when LinkUp starts again, faster search on the router Wi-Fi when a friend walked off it (260 A), directory card storm stopped: re-sync only on a real new link with 5 s minimum, the same signed card is not saved again, the same sync answer goes to one phone at most once a minute (260 B), no Unknown user: a friend's old phone shows his name, contacts pull logs CONTACTS_SYNC_OK and is never skipped at start, chats without a name ask the server who owns that phone, after an offline reinstall my new card goes to a friend whose message I can't open (259)"
git push
flutter build apk --release
```

## Install
Install on ALL phones over the old app. Do NOT clear data.

## What is in it
Dead Wi-Fi Direct group (260 A):
- A1: a member phone with no link inside its group for 30 s leaves it (`group_dead`). Not during a call, not in the first 30 s after joining, not while a join/leave is still running, not in another app's group, not in the friend backup group. On the router Wi-Fi a mate that still sends Wi-Fi beacons counts as a link. That host is not joined again for 10 min (also not by the friend link), unless it sends a new tag (its app runs again).
  Log: `NEARBY|group dead grp=DIRECT-LL-.. no_link_s=.. in_group_s=..` (once per group).
- A2: no new code (the existing `wanted_by_group` rule and the bridge do the re-join).
- A3: on the router Wi-Fi with the app closed, when a friend's link died lately: search every 60 s for 5 min, then every 3 min until 30 min. Battery rules stay first.
- A6: when LinkUp starts again after a force stop, it closes its own old `DIRECT-LL-` group once (only if this phone is the owner, never another app's group).
  Log: `NEARBY group leftover_closed grp=.. members=..`.
- NOT done: A4 (`empty_host_yields`): the existing D3 `merge_into_bigger` rule already moves an empty host into the bigger group, so no new rule (less risk). A5 (keep-alive card again after a force stop): there is no home-screen keep-alive card that could be shown again; it would be new UI + a mock, so it is left out of this build.

Name-card storm (260 B):
- B1: a re-sync only when the link really goes from off to on, and at least 5 s after the last one (was: at once on every `state` event, ~1000 an hour). Skipped syncs: one log line a minute `DIR_SYNC_SKIP|why=cooldown n=..`.
- B2: the same signed card (same version + signature) is not saved again.
- B3: the SAME answer to one phone's sync request goes at most once a minute; a changed answer (a new or newer card) goes at once. The request is still passed on. (Built this way so the old test `friend_of_friend_233` "7. an OLDER pass-on copy..." stays unchanged: it asks twice in a row and expects the newer card.)

No "Unknown user" (259):
- A1: a friend's OLD phone shows his name (the old-phone list from the server).
- A2: `CONTACTS_SYNC_OK|n=.. new=.. past=..` after a good contacts pull; the chat list reads the names again.
- A3: the first contacts pull after app start / sign-in is never skipped because a call failed just before: `CONTACTS_SYNC_FORCED|why=start`. (A phone-only account with no server never calls.)
- B2: chats that still have no name ask the server "who owns this phone" (max 50 per run, each phone once in 6 h, stops at the first network error): `NAME_FILL_259|asked=.. found=.. none=..`.
- C1: after an offline reinstall, when a friend's locked message can't be opened, my new card goes to that phone and I ask for his (once per 10 min per phone, max 20 an hour, never to a blocked phone, never for group packets): `KEY_REINSTALL_HELLO_259|to=.. why=not_a_contact` (or `why=unknown_recipient_key`). On the friend's phone: `KEY_CARD_IN_258 ... saved=y` and `KEY_AUTO_258 ... why=owner`.
- C3 (checked in code, no change): the friend's messages that I could not open are not acknowledged, so his phone sends them again (retry every 15 s, wait at most 64 s between tries). Each new try is locked with the card he has at that moment, so after he takes my new card I can open them. NOT VERIFIED on phones. Messages that already went through the server are not sent again by this path.
- Q1/Q2 as decided: the name comes back, the person does not come back into People by himself; directory sync OFF stays hidden.

## What to check (your steps)
1. Start the server and deploy the backend zip first.
2. Dead group: everyone on Wi-Fi, force-stop the TECNO. Within about 30 to 60 s the Note log shows `group dead`. Open the TECNO again: `group leftover_closed`.
3. Grey dots: the C71 leaves Wi-Fi with the switch ON. Friends should come back over Wi-Fi Direct within about 2 min.
4. Storm: in a 1 h log, `DIRECTORY_SYNC_REQUEST` should be under about 100 (was 2468).
5. Reinstall with the server ON: names within 1 min (`CONTACTS_SYNC_FORCED`, `CONTACTS_SYNC_OK`, `NAME_FILL_259`). Then once with the server OFF, near a friend (`KEY_REINSTALL_HELLO_259`).
6. Send the logs + the time of anything wrong.

## Tests
- New: `test/bundle259_test.dart` (14), `test/bundle260_test.dart` (16), `android/app/src/test/kotlin/com/sajjad/locallink/Group260Test.kt` (3).
- Old tests changed: only the version lines in `test/bundle223_logs_test.dart` and `test/nearby_190_test.dart` (3.0.77+148).
- Here: `flutter analyze` no new issues; full Flutter suite 2592 passed (11 chunks, all EXIT=0); Kotlin JVM tests OK (455); backend `go vet` + `go test -p 1 ./...` EXIT=0.
- Compile and unit tests only: nothing here was tried on a phone.
