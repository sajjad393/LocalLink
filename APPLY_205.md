# APPLY 205: smooth switching between Wi-Fi, Wi-Fi Direct, Mesh and Online (app 3.0.46+117)

Base: app `ec30fe3` (203, 3.0.45+116). Plan: `TODO_205.md` (phases P1–P8 approved; P9 online calls NOT in this bundle).
Zip: `locallink_app_205_2026-11-04.zip` (app only, no backend change, the server does not need a new deploy for 205).

---------------------------------------------------------------------------------------------------

## What changed, phase by phase

### P1 The words show the real way (logs L1, L2, L3, L4)
- A link found on the router beacons but running **inside the Wi-Fi Direct group** (192.168.49.x / `p2p-*`) now shows **"Nearby · Wi-Fi Direct"**, not "Wi-Fi". The same for a linked group (`local_net`). The call log path says `wifi_direct` too.
  - Native: new `LinkKindPolicy` (`SwitchPolicy205.kt`); `path_kind` is added to the topology and to `peer_connected`; one log line `LINK_KIND_FIXED peer=… was=lan now=wifi_direct`.
  - Dart: `LocalRoutePolicyService.select()` reads `path_kind`; `PresenceHub` maps `local_net` → Wi-Fi Direct. The call screen chip uses the same hub, so it is fixed too.
- **Router off → "Connecting…" at once:** when Wi-Fi goes off, the router links are closed right away (`SWITCH router_links_closed n=… why=wifi_off`). Links inside the Wi-Fi Direct group stay.
- **A late "not connected" note no longer kills a fresh Wi-Fi Direct link** (logs 21:10:10, closed 24 ms after it was made). A note within 5 s of a new link is checked again 5.5 s later (`WD_DISCONNECT_NOTE_LATER` / `WD_DISCONNECT_NOTE_RECHECK`).
- **Wi-Fi Direct link died but the group is still there → dial the host again after 1 s** (`WD_REDIAL why=link_died`), not after the next system note (which may never come).

### P2 Switching with the app closed (L5, L6, L7, L9)
- **Short wake lock after a break** (`locallink:reconnect`): when the last link to a contact breaks, or Wi-Fi goes off, the phone stays awake **up to 5 min** so the search / friend group / queue run with the screen off. It ends at once when a link is back.
  - After a 5 min hold that found nobody: no new hold for 10 min. Never at 10 % battery or less unless charging.
  - Logs: `RECONNECT_WAKE on why=link_died|wifi_off hold_s=300`, `RECONNECT_WAKE off why=linked|timeout after_s=…`, `RECONNECT_WAKE skip why=… reason=rest|battery`.
- **Search timing (`NearbySearchCadence`):**
  1. battery rules first (unchanged);
  2. urgent (pairing / pending / host left) every 25 s (unchanged);
  3. **linked in a group and nobody waiting → no search with the app closed, every 5 min with it open** (a search sometimes dropped the group, L7);
  4. **a friend lost lately → every 30 s for 5 min, then every 60 s until 30 min**;
  5. then the old rules (60 s waiting, 3 min idle).
- **Searches line up with the clock:** a search starts in the first 6 s of its slot (:00 / :30 …), so two phones with the app closed search at the same moment and see each other (logs: Realme searched ~15 times with `peers=0` while the ZTE slept). A missed slot (phone asleep) searches at the next tick.
  - Search at once (`why=soon`) when the group ends or the router goes away.
  - Log: `WD_SEARCH_SLOT every_s=30 why=slot|late|soon|first role=… linked=… fg=…`.
- **No extra search window while linked** (native `onPeersChanged` skips it for a member, or a host with members).
- The search **window stays 20 s** (Bundle 200 value), not the 15 s from the plan: 20 s was tested and works on both phones.

### P3 `router_back` only for a real router (L8)
- Only a real, unrestricted Wi-Fi network counts (`RouterNetworkPolicy`): not the phone's own Wi-Fi Direct group (`p2p-*`, 192.168.49.x, restricted), not the LocalLink hotspot. That gave the false `router_back` at 21:09:50 while `wifi=false`.
- The friend group closes for `router_back` only after the Wi-Fi has been up **5 s** (`router_settling` until then).

### P4 No back-and-forth in the words (`SwitchRules`, new `lib/core/presence/switch_rules.dart`)
- A **worse** way shows at once (Wi-Fi → Wi-Fi Direct → Mesh → Connecting…).
- A **better** way shows at once after "Connecting…"; otherwise it must stay up **5 s**, or **10 s** when the way got worse less than **30 s** ago.
- The 5 s tick shows a better way by itself once it is steady. Log: `SWITCH peer=… from=mesh to=wifiDirect`.

### P5 Online backup for words (no server change)
- A words-only message sent over a nearby way that is **still "sending" after 15 s** is ALSO sent through the server, **once**, with the **same id, words and time**. The server keeps one copy per id and the friend's phone saves an id once, so it never shows twice.
- Only when the server socket is up and "Internet only" is off. Not for photos / files (they keep the nearby road and continue).
- Log: `ONLINE_BACKUP_SEND id=… waited_s=… sent=true recipient=…`.
- The "once" memory is in the app (up to 500 ids); after an app restart a still-unanswered message may get one more backup (still shown once).

### P6 Logs
- `WD_GROUP_LOST … why=p2p_off|self|after_search|app_close|other_or_system` (best guess of who ended the group). The old part of the line is unchanged.
- New lines: `LINK_KIND_FIXED`, `SWITCH`, `SWITCH router_links_closed`, `WD_SEARCH_SLOT`, `WD_REDIAL`, `WD_DISCONNECT_NOTE_*`, `RECONNECT_WAKE`, `ONLINE_BACKUP_SEND`, `CALL_NO_NEARBY_WAIT`, `CALL_NO_NEARBY_END`.

### P7 Calls (nearby only)
- The voice still moves between Wi-Fi / Wi-Fi Direct / Mesh during a call (unchanged), and the chip shows the real way (P1).
- Answered call in "Reconnecting…" with **no nearby way for 20 s** → `CALL_NO_NEARBY_END` and the screen says **"Call ended: no nearby connection"** for 2 s, then closes. If a nearby way exists but the voice is not back yet, it waits another 20 s (`CALL_NO_NEARBY_WAIT`).
- Calls over the internet are P9 (separate bundle + backend change, needs its own go-ahead).

### Not in 205 (on purpose)
- "Mesh spare kept 60 s after direct returns": the native mesh routes keep their own timers (unchanged).
- Making the Wi-Fi Direct group belong only to the background service (app close re-init): not changed. The new `why=app_close` on `WD_GROUP_LOST` will show on the next test whether it still happens.

---------------------------------------------------------------------------------------------------

## Files (26 in the zip, with APPLY_205.md and TODO_205.md)

New:
- `android/app/src/main/kotlin/com/sajjad/locallink/SwitchPolicy205.kt` (LinkKindPolicy, RouterNetworkPolicy, ReconnectWakePolicy)
- `lib/core/presence/switch_rules.dart`
- `lib/features/messaging/data/services/online_backup_rule.dart`
- `lib/features/calls/presentation/call_end_words.dart`
- `test/bundle205_switch_test.dart` (24 tests)
- `android/app/src/test/kotlin/com/sajjad/locallink/Switch205Test.kt` (8 tests)

Changed:
- Kotlin: `LocalLinkTransportService.kt`, `NearbyRadio.kt`, `NearbyTagManager.kt`, `SearchWindowPolicy.kt`, `WdGroupLost.kt`, `CallPathPolicy.kt`
- Dart: `presence_hub.dart`, `local_route_policy_service.dart`, `nearby_group_planner.dart`, `nearby_friend_link.dart`, `wifi_direct_fallback_service.dart`, `reliable_messaging_service.dart`, `call_session_manager.dart`, `call_screen.dart`, `local_link_app.dart` (version stamp)
- `pubspec.yaml` 3.0.46+117, `test/nearby_190_test.dart` (version scan), `test/link_201_test.dart` (log line scan)
- `APPLY_205.md`, `TODO_205.md`

## Checks done here (no phone)
- Kotlin compile check: clean.
- Kotlin JUnit: 27 / 27 (8 new + the older tests on the same files).
- Flutter tests: 1525 / 1525 pass (149 files, run in chunks of 8; 24 new). One old source check (`link_201_test`) was updated for the new `WD_GROUP_LOST … why` call.
- `flutter analyze`: no new issues compared with 203 (same 169 old infos/warnings).
- These are compile and unit checks only. The radio, wake lock and background parts need the phone tests below.

---------------------------------------------------------------------------------------------------

## Before testing (both phones)
- Install the new build on BOTH phones (Realme and ZTE). Keep-running ON. Battery: "No restrictions" / allowlist for LinkUp (ZTE: App protection list ON and "Allow screen-lock cleaning" OFF).
- Close both apps unless the test says otherwise. Extended RAM OFF on the ZTE.

## Phone tests (from TODO_205 §8)
1. **205-1 Router off:** within 5 s `Connecting…` (never "Wi-Fi"); within ~30–60 s `Nearby · Wi-Fi Direct` without opening the app; a message arrives. Logs: `SWITCH router_links_closed`, `RECONNECT_WAKE on why=wifi_off`, `WD_SEARCH_SLOT … why=soon`.
2. **205-2 Router back:** stays Wi-Fi Direct until Wi-Fi is up 5 s, then `Nearby · Wi-Fi`; the group closes (`router_back`). During a call it waits for the call to end. No `router_back` while `wifi=false`.
3. **205-3 Walk away, 3rd phone in the middle:** `Nearby · Mesh, via 1 phone`; messages arrive.
4. **205-4 Come back:** Wi-Fi / Wi-Fi Direct again after ~5–10 s, no flapping (`SWITCH from=mesh to=…` once).
5. **205-5 No local way, internet on both:** `Online` after ≤20 s; messages go via the server.
6. **205-6 Local comes back while Online:** `Nearby · …`; a message with no ✓✓ in 15 s is still delivered and shows once.
7. **205-7 Wi-Fi Direct breaks with the apps closed:** links again by itself within ~1 min (`RECONNECT_WAKE on`, `WD_SEARCH_SLOT`, then `RECONNECT_WAKE off why=linked`).
8. **205-8 File during a switch:** 30 MB video, then router off: it continues on Wi-Fi Direct (does not restart).
9. **205-9 Call during a switch:** call on Wi-Fi, router off: voice back on Wi-Fi Direct in a few seconds, chip shows Wi-Fi Direct. Walk fully away: "Reconnecting…", then "Call ended: no nearby connection" after ~20 s.
10. **205-10 Battery:** under 10 % and not charging: no background search (`NEARBY_BG_BATTERY_STOP`), no wake (`RECONNECT_WAKE skip reason=battery`). On the charger it starts again.
11. **205-11 Online backup:** both online, nearby road dead: send a text: ✓✓ within ~20–30 s via the server (`ONLINE_BACKUP_SEND`), shown once. With a photo: no backup.

After the tests: 5 taps on "Chats" → send both log files.
