# TODO 280 - adding a friend from / to a phone-only account (made offline) is one-sided until the server is back

Status: BUILT (12 Nov "Build") in 3.0.89+160. Fact 2 (search rows=0) is a different cause (the answering phone searches only the people it saved; no `accountId` there) - not changed. Was: WRITTEN. Code checked: app `de70ef7` (3.0.86); same code in
3.0.84 `6bf30bd` (no diff in these files). Logs: `uploads/LinkUp-logs-*-2026-11-12-201*.txt`
(all four phones on 3.0.84+155, not 3.0.85/3.0.86).

## Setup in the logs
- C71 (RMX5303) account made with the server 19:33:54 (id ..1b561f); Note (RMX3938) with the server
  19:35:44 (id ..a5bee3).
- Server off after that. ZTE made a phone-only account 19:41:01 (offline id ..457370); TECNO a
  phone-only account 19:53:04 (offline id ..b6d2d4).
- Server back about 19:56: ZTE published 19:56:18 (-> ..45fa14), TECNO 19:57:54 (-> ..399a00).

## What went wrong (log facts)
1. ZTE added C71 (19:46:12) and Note (19:47:22) from search: `FRIEND_ADD_TAP`, `FRIEND_HELLO sent`,
   but NO `CONTACT_EDGE_SENT` (no friend link). C71 got ZTE's hello at 19:46:15 and dropped it:
   `SEAL_OPEN_FAILED reason=not_a_contact` (18 such lines on C71, 19 on Note).
   C71 saw ZTE as a friend only at 19:58:30 (`CONTACT_AUTO_ADDED`, server path) = 12 min late.
2. Note searched for the ZTE (19:49:04-11): ZTE answered `rows=0 kind=friend`, nothing shown; Note had to
   use Nearby pairing (19:49:18, worked).
3. Note's friend link to ZTE's offline id (19:49:25, 19:53:00, 19:56:15, `to=457370`) was never applied on
   ZTE (no `CONTACT_EDGE_APPLIED` and no log at all) until after ZTE's id moved (19:56:28).
- Adds between two server accounts worked at once (Note -> C71 19:48:05: `CONTACT_EDGE_APPLIED notice=y`).
  Nearby pairing worked for every pair.

## Cause (verified in code)
A phone-only account has NO `store.accountId` (`local_store.dart:1492` `saveOfflineAccount` never sets
it; only `saveConfiguration` at `:1479` does). Its id lives only in the profile (`offline_...`,
`authentication_repository.dart:261`). The friend-link code uses `store.accountId`:
- send: `directory_repository.dart:2402` `publishContactEdge` -> `ContactEdge.isValid` needs
  `fromUserId` -> silent return (no link, no log) - fact 1.
- receive: `directory_repository.dart:3006-3016` `_handleContactEdge`: `me.isEmpty` -> "not addressed to
  us", silent - fact 3. Same in `_handleContactEdgeAck` (`:2810`).
- name question `origin_user_id` (`:2872`) is empty too.
- Fact 2 (search answer 0): ZTE's own card / share rules for a phone-only account NOT VERIFIED; will be
  checked when building, fixed only if the same cause.

## Fix (smallest)
- F-1: one helper `_myUserId()` in `directory_repository.dart` = `store.accountId`, else the profile's
  `offline_...` id (phone-only account). Use it in `publishContactEdge`, `_handleContactEdge`,
  `_handleContactEdgeAck`, and the name question `origin_user_id`. Nothing else changes.
- F-2: log `CONTACT_EDGE_SKIP reason=no_self_id` / `CONTACT_EDGE_NOT_MINE` once per link (no ids) so a
  silent drop shows in logs.
- After publish the existing 218 id move already re-sends waiting links for the new id (`:1711`).
- No change to: sealing rules (strangers still only send friend links), pairing, server contacts.

## Tests
- Phone-only account: add -> friend link sent with the offline id; a link to my offline id is applied
  and acked; server account unchanged; empty id still never sends.
- Full suite, analyze, release build, aapt2. Kotlin/Go not touched.
