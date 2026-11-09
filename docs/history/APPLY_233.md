# APPLY 233 - offline search finds a friend's friend (app 3.0.71+142)

App only. No backend change.

This bundle comes inside the new app zip `locallink_app_224-233_2026-11-09.zip` (224, 225, 226, 227, 229, 231, 232, 233). It replaces the 224-232 app zip.

The backend zip `locallink_backend_230-231_2026-11-09.zip` is unchanged. Still deploy it first.

## PowerShell (app)
```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force -Path "C:\Users\sajjad Ahmed\Downloads\locallink_app_224-233_2026-11-09.zip" -DestinationPath .
flutter pub get
flutter test -j 1
git add -A
git add -f APPLY_224.md APPLY_225.md APPLY_226.md APPLY_227.md APPLY_229.md APPLY_231.md APPLY_232.md APPLY_233.md TODO_224.md TODO_225.md TODO_226.md TODO_227.md TODO_229.md TODO_231.md TODO_232.md TODO_233.md
git commit -m "v3 3.0.71+142 bundles 224-227 + 229 + 231 + 232 + 233: faster Wi-Fi Direct/LAN connect and never use Realme/XShare groups (224), a call wakes Wi-Fi Direct with Waiting for <name> to connect (225), Bluetooth LE finds friends with Allow and Bluetooth off cards in Add Contact Nearby (226), no jump to Welcome while logged in and the call screen closes once (227), size limits on nearby socket lines so no phone nearby can fill the memory (229), the server proves its key at sign in and one pinned server key is shared with the admin trust key (231), QR scanner reads LinkUp codes again with a sharper camera picture and no scan box filter (232), offline search finds a friend's friend: only whole signed copies are passed on and friends are asked too (233)"
git push
```
Then build the APK as usual.

## What users see
- No screen changes.
- In Add Contact, offline (Wi-Fi Direct or the same Wi-Fi), searching for a friend's friend now finds them within about 4 seconds.
- Their phone number stays hidden unless they set "Everyone".
- With no network, the "Not found..." hint comes quickly. There is no 8-second wait any more once the app knows the server is down.

## Who needs the update
- **Yasir (the friend in the middle):** needed. Without it he still sends broken copies.
- **You (the one searching):** needed for asking friends and the faster search.
- **Bilal:** not needed.

## Important
- After the update, **Yasir and Bilal must be connected once** (about 1-2 minutes). That way Yasir keeps Bilal's copy without the number.
- Until then, Yasir simply doesn't pass Bilal on. That is no worse than today.
- No database version change (it stays 34). The new table is created by itself when the app opens.

## Phone tests (after building 3.0.71)
1. Bilal and Yasir connected for about 2 minutes. Yasir's log shows `DIR_PUBLIC_CARD saved to=...`.
2. Bilal goes away. You and Yasir on **Wi-Fi Direct**, no internet. Type "bilal" in Add Contact -> Bilal shows within about 4 s.
   - Your log shows `FRIEND_SEARCH_ASK ... kind=linked friends=1` and `FRIEND_SEARCH ... shown=1 ... asked=1`.
3. The same on **local Wi-Fi** (same router, no server).
4. Tap Add on Bilal -> the normal add flow.
5. Bilal's number is **not** shown on your phone (his visibility is Contacts).
6. Online with the server: the search works as before.
7. Airplane mode with no one near: search twice. The second time the "Not found" hint comes fast, and the log shows `SERVER_CALL_SKIPPED what=directory_search`.

If Bilal still doesn't show, send the logs from **both** you and Yasir. Look for:
- `DIR_SHARE_SKIP` on Yasir's phone. This means Yasir has no number-free copy of Bilal yet, so Bilal and Yasir must meet once.
- `FRIEND_SEARCH_ANSWER ... rows=` on Yasir's phone.
- `FRIEND_SEARCH` on yours.

## Log lines (new / changed)
- `DIR_PUBLIC_CARD saved to=<last 6> v=<version>`: a copy that is safe to pass on was kept.
- `DIR_SHARE_SKIP where=sync|name|query count=<n>`: people left out because there is no safe copy yet (never sent broken).
- `FRIEND_SEARCH_ASK len=.. peers=.. kind=linked friends=<n> nearby=<m>` (was `kind=nearby`).
- `FRIEND_SEARCH ... asked=<n>`: added at the end when phones were asked.
- `SERVER_CALL_SKIPPED what=directory_search why=no_network|server_down|no_server`.

## Files
See `TODO_233.md` part 5.

**Old tests changed:** only the version pins (`test/bundle223_logs_test.dart` 3, `test/nearby_190_test.dart` 1).

## Tests
- New: 19 in `test/friend_of_friend_233_test.dart`. That includes an end-to-end test with 3 phones: Yasir meets Bilal, Bilal leaves, I search with only Yasir near, and Bilal is found on the **first** search with his number hidden.
- Proof: with the old "remove the number" step put back, 8 of the new tests fail, including the end-to-end one (your bug). With the fix, all pass.
- Full Flutter suite (9 chunks): **2395 passed, 0 failed**.
- Not tested on real phones yet (phone tests above).
