# APPLY 177 - Nearby while LocalLink is closed + Add friend with no box (3.0.8+79)

Apply 173, 174, 175 and 176 first. Then:

```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes177_2026-11-01.zip" .
git add -A
git add -f APPLY_177.md
git reset -q -- "%SystemDrive%" android/local.properties
git commit -m "v3 177: Nearby keeps working when the app is closed (search, join and start groups, battery rules), silent Nearby connections only, Add friend saves both phones with no accept box, added-you notice with Remove / Block, one-time Location ask on Android 10-12, Nearby line on STATUS card - 3.0.8+79"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter build apk --release
```

Install the new app on BOTH phones (old versions can't connect by Nearby any more).
You said you can reinstall - that is fine, nothing else is needed.

## What changed (simple)
1. **Nearby works when LocalLink is closed.** Messages arrive and calls ring with no Wi-Fi router, also after you swipe the app away.
2. A closed phone can **find, join and start** a Nearby group by itself (slow search: every 3 min).
3. **Battery:** under 20% it searches every 10 min. At 10% or less it stops searching (charging = normal).
4. **Never the Android "Accept invitation?" pop-up** any more - in the open app too. Only silent joins.
5. Button **"Pair" is now "Add friend"**. No accept box: both phones save each other at once.
6. The other phone gets a notice **"X added you as a friend"** with **Remove** and **Block**.
7. Online search **Add** also shows that notice on the other phone.
8. **Blocked people are ignored** (no answer, no contact, no notice).
9. **STATUS card** has a new line: "Nearby while closed: On" (or Needs permission / Needs location / Battery low / Off by admin).
10. **Android 10, 11, 12 only:** one orange card asks once for Location "All the time". After one answer only a small "Turn on" link stays.
11. If the admin switched Wi-Fi off for the phone, Nearby does nothing.

## Phone tests (each one separately; 2 phones; NO Wi-Fi router unless written)
Log on A: `adb logcat -s NEARBY LocalLinkBoot LocalLinkCall LocalLinkPair flutter`

| # | Do this on A | Then | Pass |
|---|---|---|---|
| 1 | A and B in a Nearby group, app open. Swipe A away | B sends a message | A gets the notification. Log `NEARBY_BG_STATE when=close` |
| 2 | Same as 1 | B calls A | A rings. Accept connects |
| 3 | A closed, not in a group. B opens LocalLink near A | B sends a message | Within ~3 min A joins B's group silently and gets the message |
| 4 | Same as 3 | B calls A | A rings after joining. Accept connects |
| 5 | A closed in a group, then open A | - | The group stays (no leave / join again in the log) |
| 6 | A and B BOTH closed, B has a message waiting for A | - | One starts a group, the other joins, the message arrives |
| 7 | B taps "Add friend" on A (A open) | - | No box on A. Both phones list each other. A gets "B added you as a friend" |
| 8 | Same as 7 but A closed | - | Same as 7. The notice shows on A |
| 9 | On A's notice tap Remove | - | B removed from A's contacts |
| 10 | On A's notice tap Block | - | B removed + blocked. B adds again: nothing happens on A. Log `PAIR_BLOCKED_IGNORED` |
| 11 | Online: B searches A and taps Add | - | A lists B + gets the notice |
| 12 | Anywhere, any time | - | Never an "Accept invitation?" pop-up from Android |
| 13 | A battery under 20% / 10% or less, closed, not charging | - | Search every 10 min / log `NEARBY_BG_BATTERY_STOP` |
| 14 | Android 10-12 phone: open Keep LocalLink running | - | Orange Location card once; Allow opens Android's page; then only "Turn on" stays |
| 15 | Remove the Nearby permission, close A | - | Nothing happens, no pop-up. STATUS line "Needs permission" |
| 16 | A locked 1 hour in a group | - | Battery 4%/h or less |
| 17 | Same Wi-Fi router (175/176 tests) | - | Same as before |
| 18 | Force Stop A | - | Nothing works until A is opened (Android rule) |

## Android limits (honest)
- **Force Stop:** nothing works until the app is opened again.
- **Android 7, 8, 9:** can't join a group silently (Android needs 10+). These phones can only start a group that others join.
- **Android 10, 11, 12:** searching while closed needs Location "All the time" + the Location switch ON. If you say no, it works only when already in a group.
- **Android 13+:** uses "Nearby devices". Expected to work while closed. Not yet confirmed on a phone.
- **Deep sleep (Doze):** Android may pause the search for a while. Messages on an existing link should still arrive.
- **Xiaomi / Oppo / Vivo / ZTE:** may kill the closed app or switch Wi-Fi Direct off. Set battery to "No restrictions".
- Some phones drop a Wi-Fi Direct group after a few minutes of silence.
- **Old LocalLink versions** can't connect by Nearby any more. Install the new app on both phones.
- **Add friend with no box:** anyone near you with LocalLink can add you. That is why you get the notice with **Block**.
- Remove / Block tapped while LocalLink is fully stopped is done the next time the app starts.
- Nothing here is tested on real phones yet: only compile + automatic tests.
