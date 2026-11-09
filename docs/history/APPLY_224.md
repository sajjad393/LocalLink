# APPLY 224 - faster Wi-Fi Direct / mesh / local Wi-Fi connect, no foreign groups, quiet logs (app 3.0.64+135, app only)

**Order (after 223):** app 224 zip only. **No backend, no database, no UI change.**

**Mixed phones (D2):**
- Phones on 224 work with phones on 223.
- An **Android 9 or older** phone on 223 that hosts a group made "the old way" can't be joined by 224 phones until it updates to 224 (its tag has no `lg=1`). Update old phones too.

## PowerShell

```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force -Path "C:\Users\sajjad Ahmed\Downloads\locallink_app_224_2026-11-08.zip" -DestinationPath .
flutter pub get
flutter test -j 1
git add -A
git add -f APPLY_224.md TODO_224.md
git commit -m "v3 3.0.64+135 bundle 224: faster Wi-Fi Direct/LAN connect, never use Realme/XShare groups, beacon per address, pair waits for the endpoint, TXT re-ask, flap guard, quiet logs"
git push
```

## What changes for the user
- **Wi-Fi Direct:** LinkUp never joins or publishes a Realme Share / XShare / system group again. While the phone is in such a group, LinkUp waits and never closes it (D1). When it ends, LinkUp connects as usual.
- **Add contact over Wi-Fi Direct:** no more instant "peer is not visible yet". The app waits up to 10 s for the other phone to appear and then sends.
- **First connect:** expected about 40-60 s (it was about 2 min 12 s in the 02:10 case), because:
  - a lost TXT answer is asked for again;
  - the beacon is no longer paused 15 s when the group comes up;
  - the merge runs right after its 10 s wait.
- **Logs:** much shorter. Waiting messages, dropped relay packets and stuck files are summarised.

## How it works (short)
- **A Foreign groups:**
  - A group is LinkUp's only if its name starts with `DIRECT-LL-`, or it is this phone's own old-way group (Android < 10, tag `lg=1`), or the group our own join call went to.
  - Foreign: no name / password in the tag, `host=0 m=0`, `WD_FOREIGN_GROUP on/off`, `my_group.foreign=true`, `group plan=none reason=foreign_group`.
  - Native `disconnect` / join-with-leave refuse to close it (`WD_FOREIGN_GROUP keep why=...`).
  - Tags from 223 phones naming a foreign group are read without that group (the phone is still listed).
- **B Beacon:** one try per address. The 15 s pause only happens when **every** address is unreachable. A new Wi-Fi Direct group sends a beacon at once (`LAN_BEACON resumed why=wd_group`).
- **C Pair:**
  - No endpoint → our beacon goes out, then the app checks every 500 ms for up to 10 s (`pair-packet endpoint found after_ms=`).
  - One wait per phone; for 30 s after a give-up it fails fast as before.
  - The error text is unchanged; `PAIR_TAP stage=caught` "not visible" is INFO.
- **D Connect:**
  - Up to 3 TXT asks, 4 s apart, in the same search window (`WD_TAG txt_ask ... try=2|3`); BUSY stops them.
  - A one-shot timer re-checks the group when the 10 s merge wait ends.
  - The search timing, the tie rule and the 10 s wait are unchanged.
- **E Flap guard:**
  - 3 links that each lived < 10 s within 2 min → dialling that phone is held 30 / 60 / 120 / 300 s (`LINK_FLAP hold/free`).
  - Reset by a link of 60 s+, a network change or Pair.
  - The Wi-Fi Direct redial is delayed by the hold (`WD_REDIAL later why=flap`), never dropped. Incoming links are always answered.
- **F Logs:** `MESSAGE_ROUTE_UNAVAILABLE` / `SKIPPED` once per waiting spell per message, `MESSAGE_WAITING n= oldest_min= to=` every 10 min, `ROUTE_SELECTED_*` is INFO.
- **G Logs:**
  - `mesh_dropped` is counted in `DIRECT_EVENTS_SUMMARY ... drop=reason:n`.
  - `RELAY file stalled`: the first 20 stalls as before, then one line per 10 min.
- **H Background:** the no-screen engine binds the server gate before its steps. With no server set, `SERVER_CALL_SKIPPED why=no_server` is logged once and no calls are made.

## Phone tests (224)
1. **Realme Share:** on the C71, send a file with Realme Share while LinkUp runs. Logs show `WD_FOREIGN_GROUP on grp=DIRECT-..-XSHARE...` and no `group join` into it. After the share ends: `WD_FOREIGN_GROUP off`, and LinkUp connects again.
2. **Add contact over Wi-Fi Direct (router off):** tap Add right after the phones appear. It works without the "not visible" toast (`endpoint found after_ms=`).
3. **First connect time:** both phones fresh, router off. Note the time from app start to `group join` + link up (aim: under 60 s).
4. **Block test:** block a contact on phone A, keep both nearby 5 min. Phone B shows `LINK_FLAP hold` and no longer redials every 2 s.
5. **Logs size:** an hour with an away contact holding 2 messages gives about 6 `MESSAGE_WAITING` lines (it was 1950 lines).
