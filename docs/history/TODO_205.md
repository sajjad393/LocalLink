# TODO 205: smooth switching between Wi-Fi, Wi-Fi Direct, Mesh and Online (PLAN ONLY, freeze on)

> **Status (2026-11-04):** P1–P8 BUILT in app 3.0.46+117 (`locallink_app_205_2026-11-04.zip`, see `APPLY_205.md`). Waiting for phone tests 205-1..11. P9 (online calls) not started, needs its own go-ahead.
> Changed from the plan: the search window stays 20 s (not 15 s); the online-backup "once" memory is in the app (not the outbox row); "mesh spare 60 s" and "group owned only by the background service" were not changed (the new `WD_GROUP_LOST why=` log will show if app close still drops the group).

Code checked at `ec30fe3` (3.0.45), backend at `b17f935`. Logs: `uploads/LinkUp-logs-RMX5303-2026-11-04-2120.txt` (Realme, 3.0.41) and
`uploads/LinkUp-logs-Z2453-2026-11-04-2119.txt` (ZTE, 3.0.38).

---------------------------------------------------------------------------------------------------

## 0. The two open questions, checked in code

### 0.1 Online backup for a nearby message with no ✓✓ → **CAN BE DONE (no server change)**
- **The server keeps our id.**
  - In `LocalLinkBackend/internal/httpapi/messaging.go` `insertMessageAt`, the app's id is used as the message id.
  - If the same id comes again with the same sender, friend, words and time, the server returns the stored message and makes **no second copy**.
  - The app sends `'id': id` and the same `created_at` in `send_message` (`reliable_messaging_service.dart`, server path).
- **The friend's phone keeps one copy.**
  - Every arrival path checks `store.messageExists(id)` first (nearby ~2628, server ~1987, sync ~833).
  - `saveMessage` updates the same row, and the bubble and notification only come for a **new** id. So a message that comes by both ways shows **once**, with one notification.
- **Limits:**
  1. **Words only.** A message with photos/files would need the files uploaded to the server over the internet. Those keep the nearby road (203 continue). If the nearby road is lost, today's normal server road (upload) already takes over.
  2. Same words and same time on both roads, so the server never says "id belongs to different message". Today both roads use the same outbox `body` and `created_at`, which is fine.
  3. Today, "nearby available" always wins (`canUseDirect`), so a message can wait on a nearby road that looks alive but is dead. The backup fixes exactly this.

### 0.2 Moving a running call from nearby to online → **NOT POSSIBLE TODAY (calls are nearby-only)**
- `call_transport_mode.dart`: `isLocalOnly => true`.
- `call_transport_selection_policy.dart`: no local way → error "No local LAN, Wi-Fi Direct, or mesh route is available".
- `call_transport_factory.dart`: always `NativeMeshCallTransport`.
- The server (`websocket.go`) only passes **call messages** (invite / accept / end / busy). It carries **no voice**. There is no online voice road to move to, so a call can never start or continue over the internet today.
- **So:**
  1. **In 205 (Phase 7):** a call moves between **nearby ways only** (Wi-Fi ↔ Wi-Fi Direct ↔ Mesh). If every nearby way is lost: "Reconnecting…" for up to 20 s, then "Call ended: no nearby connection".
  2. **Online calls** (start or continue a voice call over the internet) are a **new feature**: the server passes voice packets, and the app reuses the Opus voice already in `CallOpusCodec`. It needs its own bundle and a backend change. This is **Phase 9 (separate go-ahead)**.

### 0.3 Every problem in the logs → the phase that fixes it

| # | Log problem (time) | Phase |
|---|--------------------|-------|
| L1 | Realme: link died 21:00:51, Wi-Fi off 21:00:53, still "Nearby · Wi-Fi" until 21:01:14 | P1 |
| L2 | ZTE: Wi-Fi off 21:01:02, no Offline / Connecting written until the app was opened at 21:09:47 | P1 + P2 |
| L3 | Router off, but the link inside Wi-Fi Direct was called `lan` → "Nearby · Wi-Fi" (21:10–21:14 both phones); call `path=lan` at 21:14 | P1 |
| L4 | Right after joining, the Wi-Fi Direct link dies within milliseconds and a 2nd `lan` link replaces it (21:10:10, 21:12:22: two links racing) | P1 |
| L5 | 1st switch took **3 min** (21:00:53 → 21:03:57); ZTE did not search 21:01:17–21:03:54 | P2 |
| L6 | 2nd break: **5 min** with no link until the ZTE app was opened (21:04:54 → 21:10:10). Realme searched 15 times and saw 0 phones; ZTE stayed host and did not search | P2 |
| L7 | **Closing the app drops the Wi-Fi Direct group** on Realme (member): close 21:04:44 → group lost 21:04:55; close 21:14:47 → group lost 21:14:53 | P2 |
| L8 | False `router_back` at 21:09:50 (router still off) closed a good group | P3 |
| L9 | The group dropped by itself at 21:11:58 / 21:12:04 and came back in about 20 s | P2 (faster rejoin) + P6 (log the reason) |

---------------------------------------------------------------------------------------------------

## 1. The 4 ways (best first)

| # | Way | What it is | Words under the name | Needs |
|---|-----|------------|----------------------|-------|
| 1 | **Wi-Fi** | Both phones on the same router or hotspot | `Nearby · Wi-Fi` | A router (internet not needed) |
| 2 | **Wi-Fi Direct** | Phone to phone, no router (our own group, or the friend's group joined like a Wi-Fi) | `Nearby · Wi-Fi Direct` | Nothing |
| 3 | **Mesh** | Through 1 or more other LinkUp phones in between | `Nearby · Mesh, via 1 phone` | A phone in between |
| 4 | **Online** | Through the server | `Online` | Internet on both phones |
| – | (switching) | The old way just broke and a new one is being tried | `Connecting…` (at most 20 s) | – |
| – | (none) | Nothing works | `Offline` | – |

**Main rule:** always use the **best way that is working right now**. A **better** way takes over only after it has been checked (link verified, plus 5 s steady). A **worse** way takes over at once when the current one breaks.

Today in code: `PresenceWay` order is `wifi, wifiDirect, mesh, nearby, connecting, online, offline` (`presence_hub.dart`). Messages pick local first (`reliable_messaging_service` `canUseDirect`), else the server.

---------------------------------------------------------------------------------------------------

## 2. One picture of the flow (per friend)

```
                 better way checked + steady 5 s
        +--------------------------------------------------+
        |                                                  |
   [CONNECTED: way X] --link breaks / my Wi-Fi off--> [CONNECTING ≤20 s]
        ^                                                  |
        |   any way works                                  | nothing found in 20 s
        +---------------------------------- [SEARCHING] <--+
                                               |   (shows Online if the server works,
                                               |    else Offline; keeps searching
                                               |    in the background, app closed)
```

- **CONNECTED:** the label shows the real way (section 4).
- **CONNECTING:** it starts at once when the link dies, when this phone's Wi-Fi goes off, or when the friend's route is withdrawn. Messages wait in the queue during this time and are not lost.
- **SEARCHING:**
  - Wi-Fi Direct search and mesh routes run in the **native background service** (app closed, screen off).
  - Online is used at once if both phones have internet.
  - Local search continues behind it, because local is preferred when it comes back.

---------------------------------------------------------------------------------------------------

## 3. Every switch, step by step

### A. Wi-Fi → Wi-Fi Direct (router off, or a phone walks out of the router)
1. 0 s:
   - The link dies (`transport_link_died transport=lan`) or `NET_CHANGE wifi_down=true`.
   - The label changes to **Connecting…** at once (never "Wi-Fi" again while Wi-Fi is off).
2. 0–2 s: both phones start the **friend Wi-Fi Direct plan at once** (no 20 s wait when the cause is "my Wi-Fi went off").
3. Search windows are **lined up by the clock** on both phones: search at second :00 and :30 of every minute for 15 s.
   - Wi-Fi Direct only finds phones that are searching **at the same time**.
   - Today the 20 s windows start at random times every 25 s to 3 min, so the two phones often miss each other.
4. The smaller id opens the pair's group and the bigger id joins it silently. This is the 200 rule and is kept.
5. Linked: `LINK_AUTH verified`, then the label becomes **Nearby · Wi-Fi Direct**.
6. Queued messages go at once (route change → flush). Files **continue** (203).
7. Goal: **under 30 s** (today 3 min in the logs).

### B. Wi-Fi Direct → Wi-Fi (router back)
1. The router comes back (`NET_CHANGE wifi_up=true`, a real router network). Keep the Wi-Fi Direct group.
2. Wait until the friend is seen and verified on the router (`peer_connected transport=lan`, not inside our group), and steady for 5 s.
3. Then move to Wi-Fi: the label becomes **Nearby · Wi-Fi**. Close the empty friend group (`router_back`).
4. Never close the group during a call or a file transfer. Close it after they end.
5. **Fix:** `router_back` must count only a real router.
   - The logs showed `router_back` at 21:09:50 while the router was still off.
   - `onWifiNetwork()` in `NearbyRadio.kt` counts any `TRANSPORT_WIFI` network. To check: networks from Wi-Fi Direct and the local net must not count.

### C. Direct (Wi-Fi / Wi-Fi Direct) → Mesh (friend walks away, a 3rd phone is in between)
1. The direct link dies. Is there a mesh route through another phone (route map)?
   - Yes → switch at once. The label becomes **Nearby · Mesh, via 1 phone**.
   - No → step A (Wi-Fi Direct search) and Online at the same time.
2. Messages, files and call voice go through the middle phone (sealed, as today).

### D. Mesh → Direct (friend comes close again)
1. A direct link to the friend comes up and is verified, then steady 5 s → use it. The label becomes Wi-Fi / Wi-Fi Direct.
2. The mesh route stays as a spare for 60 s and is used again if the direct link dies.
3. **No flapping:** after a switch, don't switch to another *better* way for 30 s, unless the current way breaks.

### E. Local → Online (no local way, both have internet)
1. CONNECTING ends without a local way, and the server says the friend is connected → **Online**.
2. Queued messages go through the server at once.
3. Local search continues in the background, with the same windows as A.

### F. Online → Local (friend found nearby)
1. A local way is verified and steady 5 s → the label becomes **Nearby · …**. New messages use local.
2. The server stays connected as a spare.
3. **Safety (new, checked in 0.1):** a **words-only** message sent nearby with no ✓✓ after 15 s, while the server is up, is **also sent through the server** with the same id. The server makes no second copy, and the friend's phone shows it once.

### G. Internet goes off while Online
1. The server drops. If a local way exists, show it. Otherwise **Offline** after 20 s, and keep searching locally in the background.
2. Messages stay queued and go on the first way that works.

### H. App closed / phone locked (all switches above)
- All switching must work **without opening the app**:
  - native service: search windows, group open/join, links, routes;
  - background engine: the friend plan and the queue.
- Logs show the 2nd break waited **5 min** until the ZTE app was opened. When it was opened, the phones linked in 16 s.
- Fixes:
  1. Search windows lined up by the clock (A3) in the background too: every 30 s for the first 5 min after a break, then every 60 s for 30 min, then every 3 min.
  2. A phone that is **host** keeps searching too. In the logs, Realme searched 15 times and saw 0 phones while ZTE was host.
  3. The battery rule stays: below 10 %, stop unless charging. No WorkManager. Only `connectedDevice` FGS from boot.
  4. ZTE: keep the existing "App protection / screen-lock cleaning" guide. No silent setting changes.

---------------------------------------------------------------------------------------------------

## 4. Labels: always the real way

| What the phone knows | Today | New |
|----------------------|-------|-----|
| Link `lan` but my Wi-Fi is **off** (the link runs on the Wi-Fi Direct network 192.168.49.x / `p2p-*`) | `Nearby · Wi-Fi` ❌ (logs 21:10–21:14) | `Nearby · Wi-Fi Direct` |
| Link `local_net` (friend's group joined like a Wi-Fi) | `Nearby` (falls to the default) | `Nearby · Wi-Fi Direct` |
| Link just died, grace time | `Nearby · Wi-Fi` for up to 20 s | `Connecting…` |
| My Wi-Fi went off | waits for the 20 s timer | `Connecting…` at once |
| Nothing for 20 s, server up | `Online` | `Online` (same) |
| Call path | `path=lan` inside Wi-Fi Direct ❌ | `path=wifi_direct` |

Native fix: when a link is made, look at the address/interface. `192.168.49.x` or `p2p-*` means report `wifi_direct`.

---------------------------------------------------------------------------------------------------

## 5. What happens to things in progress during a switch

| Thing | During the switch | After |
|-------|-------------------|-------|
| Text message | Waits in the queue (clock icon) | Sent at once on the new way; ✓✓ when the friend gets it |
| Photo / video / file | Pauses (ring stays) | **Continues** from where it stopped (203 resume, same `.send-` copy); never from 0 |
| Voice call (local) | Up to ~2 s quiet | Voice moves to the new local way (`CALL_PATH at=change`) |
| Voice call, every nearby way lost | "Reconnecting…" up to 20 s | Comes back on any nearby way, else "Call ended: no nearby connection". **Calls never use the internet today (checked in 0.2)**; online calls are Phase 9 |
| Group message | Same as a text (G7 rules) | Same |
| Status / presence | `Connecting…` | Real way |

---------------------------------------------------------------------------------------------------

## 6. Timers (one place, `SwitchRules`)

| Timer | Value |
|-------|-------|
| Connecting… max | 20 s (`pathGrace`, kept) |
| A better way must be steady | 5 s |
| No flapping after a switch | 30 s |
| Mesh spare kept after direct returns | 60 s |
| Search window (background and foreground) | 15 s, starting at :00 and :30 |
| Back-off | every 30 s for 5 min → every 60 s for 30 min → every 3 min |
| Local send with no ✓✓ → also via the server | 15 s |
| Empty friend group closes | 3 min (kept), never during a call or file |

---------------------------------------------------------------------------------------------------

## 7. Phases (for the go-ahead)

1. **P1 Labels + one link (L1, L2, L3, L4):**
   - Wi-Fi off → Connecting… at once.
   - `lan` on 192.168.49.x / `p2p-*` → Wi-Fi Direct; `local_net` → Wi-Fi Direct; the call path the same.
   - **One link per friend:** when 2 links come up together, keep one (the older verified one) and don't close it for a newer one within 5 s. The label follows the link that stays.
2. **P2 Fast background switch (L2, L5, L6, L7, L9):**
   - Start the friend plan at once on Wi-Fi off or link death.
   - Search windows lined up by the clock; the host keeps searching; back-off timers. All of it in the native service + background engine.
   - **App close must not drop the group (L7):** the Wi-Fi Direct channel and group belong to the background service only. Closing the app screen never closes or re-creates them (today `bg_start` re-inits, and the group is lost 5–10 s later).
   - After the group drops by itself: rejoin in under 10 s.
3. **P3 `router_back` fix (L8):** only a real router counts; make-before-break back to Wi-Fi.
4. **P4 Mesh ↔ direct:** steady 5 s, no flapping for 30 s, mesh spare for 60 s.
5. **P5 Online backup (checked in 0.1, no server change):**
   - **Who:** words-only messages (no files) that were sent nearby, have no ✓✓ after 15 s, while the server socket is connected.
   - **What:** also send `send_message` with the **same id, words and time**. Log `ONLINE_BACKUP_SEND id=… after_s=15`.
   - **Once:** at most 1 backup per message (remember it in the outbox row). The first ✓✓ from either road wins, and the other is ignored.
   - **Not for:** messages with photos/files (they keep the nearby road and continue), control messages (read / delete / reaction keep their own rules), groups (G7 rules; a later phase may add them).
   - **Tests:** a fake socket gets exactly 1 backup after 15 s; none when ✓✓ comes in time; none for files; the friend side shows 1 bubble and 1 notification when both roads deliver.
6. **P6 Logs (L9 reason):** `WD_GROUP_LOST` with who closed it (app close / system / other phone), plus `SWITCH from=wifi to=connecting why=wifi_off`, `SWITCH from=connecting to=wifi_direct after_s=…`, `LINK_KIND_FIXED was=lan now=wifi_direct`, `WD_SEARCH aligned slot=:30`, `ONLINE_BACKUP_SEND id=…`.
7. **P7 Calls while switching (nearby only, checked in 0.2):**
   - The voice moves between Wi-Fi / Wi-Fi Direct / Mesh during a call.
   - The call screen shows the real way.
   - Every nearby way lost → "Reconnecting…" up to 20 s → "Call ended: no nearby connection" (clear words, no silent hang).
8. **P8 Tests:** unit tests for `SwitchRules`, labels, the friend plan inputs and the online backup, then the phone tests below.
9. **P9 Online calls (NEW FEATURE, separate bundle + backend, own go-ahead):**
   - Start a voice call over the internet when there's no nearby way.
   - During a call, move nearby ↔ online.
   - Needs: a server voice relay (WebSocket or UDP), reuse of the Opus voice (`CallOpusCodec`), and the same rules as section 3 (better way steady 5 s, no flapping).
   - Not part of 205.

---------------------------------------------------------------------------------------------------

## 8. Phone tests (newest build on both phones, both apps CLOSED unless the test says otherwise)

1. **205-1 Router off:** Within 5 s the chat shows `Connecting…`, never "Wi-Fi". Within 30 s it shows `Nearby · Wi-Fi Direct` without opening the app. A message from the other phone arrives.
2. **205-2 Router back:** Stays on Wi-Fi Direct until Wi-Fi is checked, then shows `Nearby · Wi-Fi`, and the group closes. During a call it waits until the call ends.
3. **205-3 Walk away with a 3rd phone in the middle:** Shows `Nearby · Mesh, via 1 phone`. Messages still arrive.
4. **205-4 Come back:** Within ~10 s shows Wi-Fi / Wi-Fi Direct again, with no flapping back and forth.
5. **205-5 No local way, internet ON on both:** Shows `Online` after ≤20 s. Messages go through the server.
6. **205-6 Local comes back while Online:** Shows `Nearby · …`. A message with no ✓✓ in 15 s is still delivered (via the server) and never shows twice.
7. **205-7 Wi-Fi Direct breaks with the app closed:** Links again by itself within 1 min (logs: `WD_SEARCH aligned`, `SWITCH … after_s`).
8. **205-8 File during a switch:** Send a 30 MB video, then turn the router off. It **continues** on Wi-Fi Direct and does not restart.
9. **205-9 Call during a switch:** Call on Wi-Fi, then turn the router off. The voice comes back on Wi-Fi Direct within a few seconds. The call screen shows the right way. Walk fully out of range: "Reconnecting…", then "Call ended: no nearby connection" after 20 s.
10. **205-10 Battery:** Below 10 % and not charging, background search stops (a log line says why). On the charger it starts again.
11. **205-11 Online backup:** both phones have internet, and the nearby road looks up but is dead (e.g., the friend's Wi-Fi Direct is frozen). Send a text. ✓✓ comes within ~20 s through the server, and the friend sees it **once**. With a photo: no backup, and the photo waits for nearby.
