# TODO 258: names and security codes update by themselves

Status: BUILT as 3.0.76+147 (11 Nov), together with 3.0.75 (257) in one zip. Not pushed yet.
Version when built: 3.0.76+147, on top of 3.0.75+146 (TODO 257, zip built, not pushed yet). ONE app zip, ONE commit. No backend change.
Checked against: app `1eec747` + the 3.0.75 patch (`wip_3.0.75_app.patch`).

## What the user asked (11 Nov)
1. "Security code changed" must update by itself for the other users. No user action.
2. After logout / uninstall / login again, the chat list shows "Unknown user" (screenshot: "Unknown user - You: hello").
3. Some screens show the phone name (e.g. "RMX3938", "realme C71") instead of the person's name.
4. A profile change made offline must reach all users.

Decisions: my advice is used where the user did not answer (A1 trust rule, grey line, no button).

---

## A. Security code: take the new code by itself

### Today (code)
- `lib/features/directory/data/repositories/directory_repository.dart` `_saveVerified()` (~1050): a friend card with a different `signingPublicKey` -> `SecurityCode245.instance.noteCardChange(old, profile)` -> `return false`. The old card stays in use until someone taps "Accept new code".
- `lib/core/security/security_code_245.dart` keeps it in `_pending` (setting `key_change_245`). `accept()` saves it.
- Chat: `chat_screen.dart` `_keyChangeBanner245()` shows "<name>'s security code changed." + a "Check" button.
- Effects in the 10 Nov logs:
  - the old name and photo stay;
  - 75x `SEAL_OPEN_FAILED sender_key_mismatch` on the Note;
  - wrong link keys (TODO 257).

### A1 Auto-take the new card (my advice for the trust rule)
- In `_saveVerified()`, when the signing key differs, take the card at once when ANY of these is true:
  - (a) the card came from that phone itself. `message['_from'] == profile.deviceId` on `DIRECTORY_PROFILE`, `DIRECTORY_PROFILE_RESULT`, `DIRECTORY_SYNC_RESPONSE` and the name answer. Pass a new `fromOwner258` flag into `_saveVerified`.
  - (b) the server is reachable and says this user's current phone is `profile.deviceId` (`api.directoryByUserId(userId).deviceId`; 3 s timeout).
  - (c) the same phone as the old card (`old.deviceId == profile.deviceId`), and the card is signed by its own new key (already checked above). This covers reinstall / data clear / new keys on the same phone.
- Otherwise (a card relayed by someone else, for a different phone, with the server not reachable), it is kept aside as today, then:
  - auto-taken as soon as (a) or (b) happens. When the friend is next seen, send `DIRECTORY_PROFILE_QUERY` to that phone. When the server is back, check (b).
- When taken:
  - save the card, `_updates.add(profile)`;
  - remove it from `_pending`;
  - Verified -> Not verified (`clearTrust`). It does NOT become "changed", so no call warning;
  - `LinkKeyRefresh257.request('key_auto')` + forget seal keys;
  - log `KEY_AUTO_258 user=<6> phone=<6> why=owner|server|same_phone`.
- New method `SecurityCode245.autoTake258(old, incoming, why)`. `accept()` stays for the screen (manual, rarely needed).
- Risk (tell the user): someone who copies a friend's phone id and sends a fake card from another phone is NOT auto-taken by (a) or (c), because the `_from` is the sender's own id. (b) needs the server.

### A2 Grey line instead of a warning
- `chat_screen.dart` `_keyChangeBanner245()`: when the change was auto-taken, show a grey one-line note "Security code changed" for 24 h. No "Check" button, no red icon. Tapping it opens the Security code screen.
- Only when it is still held (A1 "otherwise") is the current banner shown.
- Store the auto-taken time per user in `key_change_245` (field `auto_at`).

### A3 Already waiting changes (from older builds)
- On start, for each `_pending` entry: if (c) is true (same phone), take it at once (`why=same_phone`). Otherwise ask that phone for its card when it is next seen.

### A tests
- NEW `test/key_auto_258_test.dart`:
  - same phone + new key -> taken, no pending, trust not "changed", log line;
  - relayed card for another phone -> kept aside;
  - the same card then comes from the owner -> taken;
  - the grey line shows, there is no Check button.
- OLD TESTS: `bundle245_test.dart` "source: a new key is no longer dropped" looks for `SecurityCode245.instance.noteCardChange(old, profile);` within 300 chars after `old.signingPublicKey != profile.signingPublicKey`. Keep that call in place (for the "otherwise" path) so the test stays the same. The other 245 tests call `noteCardChange()` directly: unchanged.

---

## B. "Unknown user" after a fresh login

### Today (code)
- `home_bloc.dart` `_labelsFor()` -> `home_repository.labelForDevice()` -> `local_store.peerDisplayName()`, which reads ONLY the friend's card (`directoryProfile` / `directoryProfileByDeviceId`) + custom name. No card = no label -> `home_screen.dart` shows `'Unknown user'` (lines ~817, 1274, 1291, 1495, 1507).
- A fresh install has no friend cards. They come from:
  - server: the contacts sync (`syncServerContacts()` ~1572) -> `getProfile(userId)`. `getProfile` asks the server only when there is NO local card;
  - phones: over links (refused until 3.0.75).
- The 10 Nov C71 log: 26x `CONTACTS_SYNC_FAILED` (timeouts / no route).
- The home list does NOT listen to `DirectoryRepository.profileUpdates`. A card that arrives later does not change "Unknown user" until the list reloads for another reason.

### B1 Fetch friend cards after login, until it works
- After sign-in / restore (`ADMIN_ROLE_KEPT_AFTER_SIGNIN` point / `MESSAGE_SERVICE_START`):
  - run the contacts sync now;
  - if it fails, retry every 30 s for 10 min, then every 5 min (log `CONTACTS_SYNC_RETRY in=..`).
- For each contact without a card: `getProfile` from the server. Also send `DIRECTORY_PROFILE_QUERY` to nearby / linked friends.

### B2 One name rule for a person (new `lib/core/identity/person_name_258.dart`)
- Order:
  1. custom name;
  2. card display_name;
  3. card username;
  4. last known name (new setting `name_cache_258`, deviceId -> name, saved every time 1-3 resolves; max 500);
  5. the server contact's username;
  6. "LinkUp user".
- NEVER the phone model name, and never "Unknown user" when 1-5 has anything.
- `local_store.peerDisplayName()` uses steps 1-4 (step 4 is new). The home list, chat, calls, notifications and groups all go through it.

### B3 The chat list updates when a card arrives
- `home_bloc.dart`: listen to `profileUpdates` (like `contacts_bloc.dart` line 17), debounce 1 s, and re-run `_labelsFor()` only. Cancel the subscription in `close()`.

### B4 Log
- `NAME_MISSING peer=<6> why=no_card|no_contact` once per peer per hour, when step 6 is used.

### B tests
- NEW `test/person_name_258_test.dart`:
  - the order 1-6;
  - the phone model is never returned;
  - the cache is filled and then used;
  - the home list label changes when `profileUpdates` fires;
  - after login with no cards, the retry is scheduled.

---

## C. Phone name shown instead of the person's name

### Today (code)
- `chat_screen.dart` `_peerName()` = `device.name`. The Device comes from the devices table:
  - `home_screen._chatRoute`;
  - the notification tap path in `local_link_app.dart` ~450 (`store.deviceById`).
  - `ChatBloc` (line 75) swaps in the label only when there is a card. No card = the phone name.
- `create_group_dialog.dart` (76/78) and `group_details_screen.dart` (63/64) use `device.name` (the phone model) always.
- `storage_screen.dart` 33 uses `d.name`.
- `calls_screen.dart` 62 and `call_session_manager.dart` 598 fall back to "Unknown user".

### C1
- These screens use the B2 rule:
  - the chat title, avatar letter and block banner;
  - Add member / group details;
  - Storage;
  - forward targets;
  - calls;
  - notifications.
- Admin screens that list PHONES (devices, block list, link map) keep the phone name. Where a row is about a person, it shows "Name - phone".

### C tests
- In `person_name_258_test.dart`:
  - the chat title with no card = last known name, not "RMX3938";
  - the group dialog shows names.
- Exact-string source tests to respect:
  - profile_photo_204 (chat AppBar PresenceAvatar indentation);
  - list_match_153 (calls_screen strings).
  - Change only `_peerName()`'s body and the `name:` arguments.

---

## D. A profile change made offline reaches every friend

### Today (code)
- `profile_screen.dart` 209 -> `DirectoryRepository.publishOwnProfile()` (~501):
  - ONE `transport.broadcast(DIRECTORY_PROFILE)`, only to phones linked at that moment;
  - only a PHOTO change calls `_cardToFriends()`, which sends to every friend and again when each is next seen (`_cardOwed`, `_owedCardOnSeen`).
- So a new name / username / number reaches only the phones linked right then. Friends who were away, or whose link was refused, never get it.
- `_cardToFriends()` finds each friend's phone from their card (`directoryProfile(user)['device_id']`). A friend with no card on my phone is skipped.
- `_saveServerProfile()` never replaces a signed card. So friends depend on the card coming phone to phone (fine once D1 works).

### D1
- `publishOwnProfile()`: compare a fingerprint of display name + username + phone + visibility + photo code with the last published one. If anything changed -> `_cardToFriends()` (not only the photo). Log `PEER_CARD_TO_FRIENDS count=N why=profile`.

### D2
- `_cardToFriends()`: when a friend has no card, use the contact's `device_id` (contacts table) and the 237 past phones.

### D3
- Today `cardOwedMaxSends = 5`, `cardOwedGap = 60 s` (lines 161-162): 5 tries a minute apart. Keep the gap, but count a try only when the friend is actually linked, and keep the card owed for 7 days so an away friend still gets it when next seen.

### D4
- When the server comes back, the pending profile already uploads (`syncPendingProfile`). No change.

### D tests
- NEW `test/profile_push_258_test.dart`:
  - a name change -> the card goes to every friend (even one not linked now) and again when seen;
  - no change -> nothing sent;
  - a friend with no card -> uses the contact's phone id.

---

## Scope (files)
- `lib/features/directory/data/repositories/directory_repository.dart` (A1, A3, B1, D1-D3)
- `lib/core/security/security_code_245.dart` (A1-A3)
- `lib/features/messaging/presentation/screens/chat_screen.dart` (A2, C1)
- `lib/core/identity/person_name_258.dart` NEW (B2)
- `lib/core/services/local_store.dart` (B2 step 4, `peerDisplayName`)
- `lib/features/home/bloc/home_bloc.dart` (B3)
- `lib/features/home/presentation/screens/home_screen.dart` (B2 fallback text only)
- `lib/features/groups/presentation/widgets/create_group_dialog.dart`, `lib/features/groups/presentation/screens/group_details_screen.dart` (C1)
- `lib/features/storage/presentation/storage_screen.dart`, `lib/features/calls/presentation/screens/calls_screen.dart`, `lib/features/calls/data/services/call_session_manager.dart`, `lib/app/local_link_app.dart` (C1)
- `lib/app/app_dependencies.dart` (B1 retry after login, A1 server check binding)
- Version files + tests. No Kotlin. No backend.

## Not touched
- The admin phone lists, the map (222 lock), the seal code, the link check (257).

## How to check after install
1. Reinstall one phone (or clear data) and log in: friends show their real names within about 1 minute. No "Unknown user", no phone model names.
2. On the other phones: no "Check" banner. Only a grey "Security code changed" line. Logs: `KEY_AUTO_258 ... why=same_phone|owner|server`.
3. Change your name with the server off: the friends' phones show it as soon as they are linked (`PEER_CARD_TO_FRIENDS ... why=profile`). A friend who was away gets it when next seen.
4. Logs: `NAME_MISSING` lines (if any) say which friend still has no name and why.

---

## Build notes (3.0.76+147)

What was built, and where it differs from the plan above:

- **A1, rule (c) dropped.** "Same phone id + signed by its own new key" is not a proof: anyone can write a card with a friend's phone id and sign it with their own key. So only two proofs take a new code by itself:
  - **owner**: the card was handed over by that phone itself (`sender_id` from the link layer or the server == the card's phone id);
  - **server**: the server says the account's phone is this phone AND its key there is the card's key (`/directory/user/<id>` + `/device-keys`).
- **New for A1:** after a reinstall, the friend's locked messages can't be opened (my copy of his card has the old key, `SEAL_OPEN_FAILED sender_key_mismatch`). That failure now asks his phone for its card (`DIRECTORY_CARD_ASK_258`). His phone answers with its PUBLIC card in the open (`DIRECTORY_OWN_CARD_258`; no number unless it is public; contacts only; at most once a minute). An open card counts only when it comes from its own phone. Asks are sent at most once in 10 min per phone.
- **A3:** held cards are checked again at start, after every good contacts sync (server back), and when that phone connects (it is asked for its card).
- **A2:** grey line `chat_key_auto_258` for 24 h, with no button. Tapping it opens the Security code screen, and the line goes away. A held card still shows the old banner with "Check".
- **B1:** contacts sync retries in 30 s, up to 10 times (`CONTACTS_SYNC_RETRY`), then the normal 2-min cycle takes over.
- **B2:** step 5 (the server contact's username) isn't possible: the server contact list has no names. Names still come from the server through `getProfile`. Also new: when there's no card for that phone, the name comes from the card of the contact kept with that phone.
- **C1:** `create_group_dialog.dart` and `group_details_screen.dart` are not used anywhere in the app, so they are not changed. Admin screens are unchanged (they list phones).
- **D3:** a try counts only when the card could be sent. The owed list is kept for 7 days and survives a restart (`card_owed_258`). A change made before a restart is found at the next start (`card_print_258`).

Files changed (258): `person_name_258.dart` (new), `security_code_245.dart`, `directory_repository.dart`, `local_store.dart`, `message_seal_service.dart`, `sealing_peer_transport.dart`, `app_dependencies.dart`, `home_bloc.dart`, `home_screen.dart`, `chat_screen.dart`, `messaging_repository.dart`, `local_link_app.dart`, `calls_screen.dart`, `call_session_manager.dart`, `notification_identity_resolver.dart`, `storage_screen.dart`, `app_build.dart`, `pubspec.yaml`.

Tests: new `test/bundle258_test.dart` (20 tests). Old tests: only the version bump (`bundle223_logs`, `nearby_190`). `bundle245` source check kept as it was (the held path still calls `noteCardChange`).

Security note: a new code is taken with no tap only when the friend's own phone or the server proves it. A card passed on by someone else is never taken alone.
