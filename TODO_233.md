# TODO 233 - Offline search finds a friend's friend (app 3.0.71+142)

**Status: BUILT (go ahead 2026-11-09).** See `APPLY_233.md`. Changes made while building are marked "(built)".
Base: app 3.0.70+141 (224-232). App only. No server change. No new screen. No database version change.

---

## 1. The problem (your test)
- Yasir added Bilal **nearby**. You and Yasir are friends.
- You are offline (Wi-Fi Direct or local Wi-Fi), only Yasir is near you.
- You type "bilal" in **Add Contact** -> nothing. Searching again later -> still nothing.
- Bilal's profile is public.

## 2. Why (checked in code)

### Cause 1 (main): Yasir passes on a copy of Bilal with a broken signature
- Every profile copy is signed by its owner's phone. Your phone checks the signature and throws away any copy that fails (`_saveVerified`, `directory_repository.dart:926`, check at :945).
- Bilal's **Phone number visibility** is **Contacts** (the default, `profile.dart:28`).
- Because Yasir is Bilal's friend, Bilal's phone sends Yasir a copy **with the number inside**, signed (`_profileForRequester` :828, `revealPhoneToContact: true` :838).
- When Yasir's phone passes Bilal on to you, it **removes the number** first (`_redactForGossip` :823). This happens in 3 places:
  - sync answer `_handleSyncRequest` :886 (via `_profileForRequester` :903);
  - name answer `_handleNameQuestion` :2065 (`rows.add(_redactForGossip(...))` :2090);
  - single lookup `_handleProfileQuery` :844 (via `_profileForRequester` :867).
- The number is part of what is signed (`canonicalMap`, `directory_models.dart`, `phone_number`). Removing it breaks the signature, so your phone silently drops the copy. This happens **every time**, so searching again never helps.
- The copy works only when Bilal has no number, or his number visibility is **Everyone**.

### Cause 2: the offline search doesn't wait for friends
In `searchByName` (:1181):
- The server call has no extra limit when nothing is saved locally, so offline it waits up to **8 s** (`locallink_api.dart` `_directoryList`) before anything else happens.
- `await sync()` only **sends** "send me your lists" (`sync()` :1428). The answers come later, but the search reads the local list straight away and says "not found".
- "Does anyone know this name?" (`_askNearbyByName` :2019) goes **only to phones that are not friends** (`NameQuestionPolicy.nearbyNonFriends`, `trust == 'relay'`). Yasir is your friend, so he is never asked.
- On top of that, `sync()` has a 20 s cooldown.

---

## 3. The fix - step by step

### Part A - Yasir only passes on copies that are still whole (fixes cause 1)

**A1. New small table for each person's "safe to pass on" copy**
- File: `lib/core/services/local_store.dart`.
- In `init()` (:156), right after the database opens: `CREATE TABLE IF NOT EXISTS directory_public_cards (user_id TEXT PRIMARY KEY, card TEXT NOT NULL, profile_version INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL DEFAULT '')`.
  - There is **no DB version change** (it stays 34), so the 4 old tests that pin version 34 stay as they are.
- New methods:
  - `savePublicCard(Map row)`: keeps the newest one (higher `profile_version`; if the version is the same, the newer `updated_at`).
  - `publicCard(String userId)` returns the card or null.
- The friend-id move (`moveFriendId218` transaction, :1945): **(built)** the old id's public card is **deleted**, not moved. The card text has the old id signed inside, so it can't be reused; the next card from that person refills it.

**A2. Collect the safe copy when it arrives**
- File: `directory_repository.dart`, `_saveVerified` (:926).
- Right after the signature check passes (:945) and before the "older / same copy" returns, if the copy is **safe to pass on as it is**, save it with `savePublicCard`.
  - Safe as it is = no number inside **or** number visibility `public`.
- How Yasir gets Bilal's safe copy: Bilal's phone already sends its no-number copy to everyone on every connect and every 2 minutes (`publishOwnProfile` :490, broadcast `DIRECTORY_PROFILE`). We just keep it now. **Bilal needs no update.**
- Save my own safe copy too (`publishOwnProfile` already saves it in `directory_profiles` :507). Nothing new is needed for me: my own row is already the no-number copy.

**A3. One rule for passing a person on**
- New private helper `_shareableCard(DirectoryProfile p)`:
  1. The copy is safe as it is -> send it unchanged.
  2. Otherwise -> send the saved public card if it is the **same or a newer version**.
  3. Otherwise -> **don't send this person** (never send a broken copy). Count it for the log.
- Use it in the 3 places instead of `_redactForGossip`:
  - `_profileForRequester` (:841, the non-self branch). The own-profile branch for a friend (:838) stays as it is: my friend still gets my number.
  - `_handleSyncRequest` (:903): rows go through the helper.
  - `_handleNameQuestion` (:2090): rows go through the helper.
- Remove `_redactForGossip` once nothing uses it. Privacy stays the same or gets better: a hidden number never leaves Yasir's phone, and nothing is ever edited.

**A4. Old phones**
- A **new Yasir** gives **old phones** (3.0.70) whole copies, and they accept them. So for cause 1 **only the friend in the middle (Yasir) needs 233**.
- After the update, Yasir and Bilal must be connected **once** (about 1-2 minutes) so Yasir collects Bilal's safe copy. Until then, Yasir simply doesn't pass Bilal on (step 3 of the rule), which is no worse than today.

### Part B - the search asks friends and waits for them (fixes cause 2)

**B1. Ask friends too**
- File: `lib/features/directory/data/name_question_policy.dart`.
- New `linkedLinkUpPhones(topology)` = linked phones with trust `contact` **or** `relay`.
- `nearbyNonFriends` stays unchanged (an old test pins it).
- In `_askNearbyByName` (:2019), use the new function.
  - The question stays the same: name only, at least 3 letters, max 10 rows back, 1 question per 10 s, 1 answer per 10 s per phone.
  - Friends answer with the same limited rows as anyone else (`_handleNameQuestion` already has no friend-only rule).

**B2. Wait for the answers (already there) + read again (built)**
- `_askNearbyByName` already waits up to **4 s** or until every phone has answered (`NameQuestionPolicy.waitMs`).
- Because friends are now asked, Yasir's answer arrives inside that wait and Bilal is shown on the **first** search.
- `await sync()` stays as it is (harmless).
- **(built) Extra fix:** after asking, the saved list is now **always** read again (`if (nearby >= 0)`), not only when the name answer brought something new. Before, if a friend's sync answer saved Bilal a moment before the name answer, the name answer counted 0 new and the search still showed nothing.

**B3. No 8 s wait when the server is known to be down**
- In `searchByName`, before `api.directoryByName`: if `ServerReach.instance.shouldSkip('directory_search')` is true, don't call the server. Treat it as "server not reached" (`server = null`, so the offline hint still works).
- When the server is up or unknown, nothing changes.

**B4. Log lines**
- `FRIEND_SEARCH`: add `asked=<n>` (phones asked) at the end. This is an optional field, so the old lines pinned in tests 195a/195c stay the same when it is not set.
- `FRIEND_SEARCH_ASK`: `kind=nearby` becomes `kind=linked friends=<n> nearby=<m>`. No test pins this.
- `SERVER_CALL_SKIPPED what=directory_search why=...` (the existing line from ServerReach).
- New `DIR_PUBLIC_CARD saved to=<last 6 of id> v=<version>`: INFO, only when a new or newer card is stored.
- New `DIR_SHARE_SKIP where=sync|name|query count=<n>`: INFO, once per answer, only when n > 0, no names.

### Part C - version
- 3.0.71+142: `pubspec.yaml`, `lib/core/config/app_build.dart`.
- Version pins in old tests: `test/bundle223_logs_test.dart` (3), `test/nearby_190_test.dart` (1).

---

## 4. Safety rules for the code
- Every new store call (`savePublicCard`, `publicCard`) is wrapped in try/catch. If it fails, the old behaviour stays (13 test fakes `implements LocalStore` would throw on new methods, so old tests don't change).
- Never change `register` / `login` / `AuthenticationRepositoryContract`.
- No change to Kotlin, the transport, the message types, or the screens.
- Blocked people are never passed on (the existing `isBlocked` checks stay before the helper).

---

## 5. Files (only these)
1. `lib/core/services/local_store.dart`: table at init, 2 methods (`savePublicCard233`, `publicCard233`), id move.
2. `lib/features/directory/data/repositories/directory_repository.dart`: A2, A3, B1 call, B3, logs.
3. `lib/features/directory/data/name_question_policy.dart`: `linkedLinkUpPhones`.
4. `lib/features/directory/data/directory_search_merge.dart`: optional `asked` in the log line.
5. `pubspec.yaml`, `lib/core/config/app_build.dart`: version.
6. New test `test/friend_of_friend_233_test.dart`.
7. Old tests: version pins only (2 files).

---

## 6. New tests (`test/friend_of_friend_233_test.dart`)
1. **The broken case today:** Yasir holds Bilal's card WITH the number (visibility Contacts). Without a public card, Yasir sends **no** Bilal row (no broken copy).
2. **The fix:** Yasir also got Bilal's no-number card. In the sync answer to me, Bilal's row is that card, and **my phone accepts it** (the signature checks).
3. **Name answer:** the same as 2, through the name question.
4. **Single lookup** (`DIRECTORY_PROFILE_QUERY`): the same rule.
5. **Number "Everyone":** the card with the number is passed on unchanged.
6. **No number:** the card is passed on unchanged.
7. **Version rule:** a public card that is older than the stored card is not used. Newer or same is used.
8. **Friend is asked:** I am friends with Yasir (trust `contact`), Bilal is only on Yasir's phone. `searchByName('bilal')` returns Bilal on the **first** search.
9. Friends and strangers are both asked. Each gets one question. There is still max 1 question per 10 s.
10. **Server down:** `ServerReach` says skip, so the server isn't called and the search takes under 5 s (fake clock).
11. **Server up:** the server is called exactly as before.
12. **Blocked:** a blocked person is never in any answer, even with a public card.
13. **Store failure:** `savePublicCard` throws, the save still succeeds and nothing crashes.
14. **Id move (built):** source check that the old id's public card is deleted in the move, the table is created at open, and the DB version is still 34.
15. **Source checks:** `_redactForGossip` is no longer used, and `nearbyNonFriends` still exists.
16. **My own profile:** a friend asking me still gets my number. A stranger gets my no-number card.

The whole old suite must still pass (2376 today).

---

## 7. Phone tests (after building 3.0.71)
Update **you** and **Yasir**. Bilal can stay on the old version.
1. Bilal and Yasir connected for about 2 minutes. Yasir's log shows `DIR_PUBLIC_CARD saved`.
2. Bilal goes away. You and Yasir are on Wi-Fi Direct (no internet). You type "bilal" in Add Contact -> Bilal shows within about 4 s. Your log shows `FRIEND_SEARCH_ASK ... friends=1` and `FRIEND_SEARCH ... shown=1`.
3. The same on local Wi-Fi (same router, no server).
4. Tap Add on Bilal -> the normal add flow (the friend request goes the usual way).
5. Bilal's number must **not** be visible on your phone (his visibility is Contacts).
6. Online with the server: the search works as before.
7. Airplane mode with no one near: the "Not found. Try again when you're online or near friends." hint comes **fast** (no 8 s wait).

## 8. Who needs the update
- **Yasir (the friend in the middle):** needed for cause 1.
- **You (the one searching):** needed for cause 2 (asking friends, no 8 s wait).
- **Bilal:** not needed.

## 9. Not in this bundle
- Showing results that arrive **after** the 4 s wait without typing again. This would be a screen change and is left out to keep things stable.
- Phone-number search through friends for people whose number is "Contacts". It keeps today's result (not found), which is correct for privacy.
- Yasir's own screen sometimes switching between Bilal's card with and without the number. That is existing behaviour and not touched.

## 10. Risk and size
- Risk: **low**.
  - Only the 3 "pass on" places and the search change.
  - No new message types, no Kotlin, no screen change, no database version change.
- Size: about 120-180 lines of code + about 300 lines of tests.
- Time: about 1 working session including the full suite.
