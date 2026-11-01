# APPLY 183 - Settings, Account and the 4 tabs: one style, plain words (3.0.14+85)

182 is already on GitHub (`c39ff73`). 183 goes on top.

## Steps (PowerShell)
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$HOME\Downloads\locallink_app_fixes183_2026-11-01.zip" .
git add -A
git add -f APPLY_183.md
git reset -q -- android/local.properties
git commit -m "v3 183: Settings, Account and the 4 tabs in one style, same top bar, People filter works, plain words - 3.0.14+85"
if ($LASTEXITCODE -eq 0) { git push }
flutter clean
flutter pub get
flutter build apk --release
```

Install over the old LinkUp (no uninstall). No files to delete.

## What changed
**Settings**
1. Only the top card opens Account: "@sajjad · Account, phones, backup".
2. Groups: GENERAL (Notifications, Appearance), THIS PHONE (Keep LinkUp running, Reset setup), ADMIN (Admin panel).
3. No back arrow on Settings.

**Account**
4. Profile card with a pencil + "Tap to edit name and photo". The "My profile" row is gone.
5. Offline box: "Can't reach LinkUp. Showing saved profile." It goes away by itself when LinkUp is reached again.
6. PHONES: My phones, Move to a new phone.
7. BACKUP AND SAFETY: Backup and restore, Security key, Extra nearby safety (switch).
8. Recovery note at the bottom.
9. Inner screens use the new names: "Remove this phone?" / "Remove", "Change security key?" / "Change key".

**The 4 tabs**
10. Chats, Calls, People and Settings have the same top bar: title on the left, no arrow, no icons.
11. Chats and Calls: the Wi-Fi icon is gone. Calls: the refresh button is gone. Call rows: no change.
12. "Contacts" is now "People".
13. The sliders button works: All / Nearby / Online. A chip shows the choice, x = All again. Works with search, updates live, not remembered.
14. One style everywhere: small grey CAPS titles + the grey Settings cards.

## Phone checks (Realme and ZTE)
1. Open each tab -> the title stays in the same place, no arrow.
2. Settings -> tap the top card -> Account opens (with a back arrow).
3. Turn off Wi-Fi and data -> open Account -> grey box. Turn it on -> the box goes away by itself.
4. Tap the pencil card -> edit name and photo opens.
5. My phones -> Remove -> "Remove this phone?".
6. Security key -> "Change security key?".
7. People -> sliders -> Nearby -> only nearby friends, chip "Nearby x". Tap x -> all again.
8. People -> Online -> type a name -> both filters work together.
9. Leave People and come back -> filter is All again.
10. Chats and Calls -> no Wi-Fi icon, no refresh.

## Honest notes
- The mock was checked against the real app on a 360 dp phone (`mocks/bundle183_compare.png`). Some mock sizes were fixed to match parts of the app that did not change (top bar 56, bottom bar 72, Chats row call button + camera icon, Calls row height 84). The new design did not change.
- "Extra nearby safety": the small line uses 2 lines on a 360 dp phone (the switch needs the room). On wider phones it is 1 line.
- Left as they were: admin devices screen and the "Transfer account" words on the profile screen.
- Old files kept but no longer used: `connection_status_indicator.dart`, `messenger_section_header.dart`. The Calls screen still takes `connectivityController` but does not use it.
- Not tested on a phone yet.
