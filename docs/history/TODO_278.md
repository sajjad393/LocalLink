# TODO 278 - offline sign-in says "username and password do not match" when the phone has no saved sign-in

Status: BUILT (12 Nov "Build") in 3.0.87+158. Was: WRITTEN, waiting for "Build". Code checked on 3.0.85 (`a42e416`) + 277.
User (ask_user): signed in online on this phone before? "Not sure". Version: separate **3.0.87+158**,
own zip + commit on top of 3.0.86 (277).

## What the user sees
Server off, sign in: always "That username and password do not match."

## Code facts
- Offline sign-in only works with a sign-in copy saved on THIS phone (one slot):
  - written after every online sign-in / create (`authentication_bloc.dart` `_mirror`), after an
    offline account is published (`offline_account_sync_service.dart:422`), on reset with code
    (`recovery_repository.dart:257/:332`), and on the 235 return (`account_return_235.dart:135`);
  - removed by Settings > Reset (`local_link_app.dart:599` `_resetAccount` ->
    `local_store.dart:1662` `clearConfiguration` -> `:1677` `clearOfflineLoginMirror`).
    Sign out keeps it.
- `authentication_repository.dart:350` `verifyOfflineLoginAsync`: if the typed username is not
  the saved one (or nothing is saved) it returns false BEFORE the password check.
- `authentication_bloc.dart:177-205` `_offlineFallback`: every false = the same text
  "That username and password do not match." (line 204) and log `AUTH_OFFLINE_LOGIN bad`.
- Password maths (`password_kdf.dart`) are the same for save and check: no bug there.

## Log evidence (RMX5303, 3.0.63)
- 6 Nov 19:36:30 `AUTH_OFFLINE_LOGIN bad` x2 with NO `KDF ... verify` line before it =
  stopped before the password check (no copy for that username).
- 7 Nov 02:13:51 `KDF ms=2702 verify` then `AUTH_OFFLINE_LOGIN ok via=password`.
- The user's latest failing try is NOT in any uploaded log: cause for that try NOT VERIFIED.

## Likely causes (one of)
1. The username typed is not the last account that signed in online on this phone (one slot).
2. Nothing saved: Settings > Reset was used, app data cleared / fresh install, or this account
   never signed in online on this phone.
3. Wrong password (only then is the message right).

## Fix (smallest)
- F-1: `verifyOfflineLoginAsync` tells WHY (repository-only helper, contract unchanged):
  `ok` / `no_copy` / `other_user` / `bad_password`.
- F-2: `_offlineFallback` text by reason (no names of other accounts shown):
  - `bad_password`: "That username and password do not match." (unchanged)
  - `no_copy`: "This phone has no saved sign-in yet. Turn the server on and sign in once."
  - `other_user`: "This phone can sign in offline only with the last account used on it."
- F-3: log `AUTH_OFFLINE_LOGIN bad reason=<no_copy|other_user|bad_password>` (no username).
- No change to: saving, Reset, password maths, server login, 235 rule.

## Tests
- New: each reason gives its text + log; right password still signs in; recovery code still works.
- Old test `bundle214g_test.dart` uses the "do not match" text - keep it passing (wrong-password
  case); change only if it covers a no-copy case (list it then).
- Full suite, analyze, release build, aapt2. Version 3.0.87+158 (user choice), 4 anchors:
  `app_build.dart:7-8`, `pubspec.yaml:4`, `bundle223_logs_test.dart:32-34`, `nearby_190_test.dart:291`.
