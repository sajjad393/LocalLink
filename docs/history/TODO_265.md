# TODO 265 - small safety fixes from the 12 Nov review (3.0.81+152)

Status: BUILT as 3.0.81+152 (14 Nov).
Base: the pushed 3.0.80+151 commit (3.0.80 does not touch any file below,
checked against `wip_3.0.80_app.patch`). Line numbers are from `9d223ef`.
Backend: NO change. Version: 3.0.81+152.

Scope = review items C1, C2, R1. Item R4 is DROPPED (see section E).
Rule: "if anything working don't touch it" - no UI change, no new screen,
no new setting, no change to timings or retries.

---

## A. R1 - server search: the reply can't send the phone to another host

Problem: `DiscoveredServer.fromJson` takes `host` from the reply text, not
from where the reply came from. Any device on the Wi-Fi can answer and point
the phone at any host (even an internet host). On a phone that never met a
server, that host is trusted first time (`authentication_repository.dart:159`).

Real server (backend `internal/discovery/discovery.go`, `ca4f41c`):
`host` = `LOCALLINK_ADVERTISE_HOST` (often empty -> the phone uses the sender
address). In TODO 264 CI it is `10.0.2.2` (private) - still accepted.

A1. `lib/features/connectivity/data/models/discovered_server.dart` (line 19-34)
- In `fromJson`: use `rawHost` only when `rawHost == fallback.address` OR
  `rawHost` is a private IPv4 literal (10/8, 172.16/12, 192.168/16).
  Otherwise use `fallback.address` (the sender).
- Add a small `static bool privateIpv4(String)` in the model (same rule as
  `DiscoveryService.isPrivateIpv4`; that one stays untouched - no import loop).
- Add `final bool hostIgnored` (default false) so the search can log it.

A2. `lib/features/connectivity/data/services/discovery_service.dart` `onReply` (line 176-192)
- If `server.hostIgnored` -> one log line
  `SERVER_SEARCH host_ignored from=<sender>` (no other change).

A3. `lib/features/authentication/data/repositories/authentication_repository.dart`
`prepareForAuthentication` (line 102-180) - LOG ONLY
- Keep the found count in a local (`var foundCount = 0;`).
- Right before the existing `if (!isServerTrusted(info)) { await trustServer(info); }`
  add (inside that `if`, before the call):
  `AppLogger.info('SERVER_FIRST_TRUST', detail: 'found=$foundCount');`
- Do NOT change the order check -> trust -> pin (locked by `server_proof_231_test`).
- Do NOT write the text `await trustServer(info);` a second time.
- No behaviour change: the first server is still trusted (your S2 rule).

## B. C1 - server search counts packets that were never sent

Problem: `RawDatagramSocket.send()` returns 0 when nothing was sent.
`_RawDiscoverySocket.send` (line 37) throws the number away and `ask()`
(line 223-224) does `ok++` anyway -> wrong `sent=` and wrong
`reason=socket_error / no_answer` in `SERVER_SEARCH` lines.

B1. `discovery_service.dart`
- Add `@visibleForTesting static void checkSent(int bytes)` in `DiscoveryService`:
  throws `const SocketException('not sent')` when `bytes <= 0`.
- `_RawDiscoverySocket.send`: `DiscoveryService.checkSent(_socket.send(data, to, port));`
- The `DiscoverySocket` interface stays `void send(...)` (so the fake in
  `bundle256_test` is unchanged). The existing `on SocketException` catch
  in `ask()` already counts it as an error and skips `ok++`.
- Keep `on SocketException`, `onError: (Object _)`, `cancelOnError: true`
  (locked by `link_201_test` and `bundle207g_test`).

## C. C2 - account upload "BUSY" up to 90 s after opening the app

Problem: the boot/background engine holds a 90 s lease in the settings table
(`offline_account_sync_service.dart:536`, `_takeLock` 552-567). Opening the app
destroys that engine (`MainActivity.kt:126` -> `BackgroundEngine.stop`), so its
`finally { _dropLock() }` (line 742) never runs. The app then logs
`OFFLINE_ACCOUNT_BUSY` until the lease runs out.
Safe because: the background engine never starts while the app is open
(`BackgroundEngine.kt` both start paths skip on `appOpen = MainActivity.isOpen()`),
so inside the app a lease written by the background engine is always left over.

C1. `offline_account_sync_service.dart`
- `_takeLock({required bool bg})`: write `'<until>|bg'` when called from
  `autoPublish(from: 'background')`, else `'<until>'` exactly as today.
- Read: `int.tryParse(raw.split('|').first)`.
- When NOT bg and the stored value ends with `|bg` and is still in the
  future: treat it as left over -> log `offlineAccountLog216('LEASE', 'cleared=bg')`
  and take the lock (normal path).
- An untagged lease still blocks exactly as today (keeps
  `bundle216f_test` "a lease from the boot engine blocks the app" unchanged).
- The background engine keeps waiting on any lease (no change there).
- `_dropLock` unchanged.
- Do not touch the text `final back = returnSync235;` /
  `final secret = await _store.readOfflinePublishSecret();` order (locked by `bundle235_test`).

New log tag: `OFFLINE_ACCOUNT_LEASE cleared=bg`.

## D. Tests

New `test/bundle265_test.dart`:
1. `fromJson` host = sender when the reply says `203.0.113.5` and the sender is `192.168.1.22`; `hostIgnored == true`.
2. `fromJson` keeps a private host (`192.168.18.27` from sender `192.168.18.30`) and the same-as-sender host; `hostIgnored == false`.
3. `fromJson` with no host still uses the sender (as `discovery_model_test`).
4. A hostname (`evil.example`) -> sender.
5. `checkSent(0)` throws `SocketException`; `checkSent(19)` does not.
6. `discover()` with a fake socket whose `send` throws `SocketException` -> `sent=0`, `reason=socket_error`.
7. A fake reply with a public `host` -> one `SERVER_SEARCH host_ignored` line, result address = sender.
8. Lease `'<now+60s>|bg'` + `autoPublish(from: 'home')` -> publishes, log has `LEASE cleared=bg`, no `BUSY`.
9. Lease `'<now+60s>|bg'` + `autoPublish(from: 'background')` -> `BUSY` (unchanged).
10. Lease `'<now+60s>'` (untagged) + app -> `BUSY` (unchanged).
11. Background publish writes a `|bg` lease while running; app publish writes an untagged one.
12. Source: `authentication_repository.dart` has `SERVER_FIRST_TRUST` before the single `await trustServer(info);`; check < trust < pin still true.

Old tests changed: ONLY the version lines in `bundle223_logs_test` and `nearby_190_test` (-> 3.0.81+152), as in every build.
Full suite in chunks must pass (3.0.80 = 2650).

## E. Not in this TODO (and why)

- R4 (401 with no body counts as "signed out"): DROPPED. Checked the backend
  `ca4f41c`: every 401 on device routes (attachments, avatar, media, …) means
  the sign-in really failed ("unauthorized", "device authentication required",
  "invalid device token"). Login/recovery/transfer/admin 401s don't use the
  phone's own token, so they are never counted. Works today - don't touch.
- R5 (lost server answer in no-password upload): needs a server check first;
  later TODO only if a log shows it.
- R2 HTTP only, R9 debug key: your decisions - unchanged.
- R3 manifest cleartext, R6 /24, R7 log cleaning, R8 WD key: report only.

## F. Overlap

- TODO 264 (A) also edits `discovery_service.dart` (`targets264`). If both are
  approved, build 265 first; 264 goes on top (no version change there).

## G. Checks after build

- Log on a normal home Wi-Fi: `SERVER_SEARCH found addr=http://192.168.18.27:8080`
  exactly as before; no `host_ignored`.
- New phone sign-up: one `SERVER_FIRST_TRUST found=1`.
- Open the app while the background engine uploads: no 90 s `BUSY`; at most one
  `OFFLINE_ACCOUNT_LEASE cleared=bg`.

## H. Delivery

ONE app zip `locallink_app_3.0.81_<date>.zip` + `APPLY_app_3.0.81.md` +
commit message "v3 3.0.81+152 bundle 265 …". Files: `discovered_server.dart`,
`discovery_service.dart`, `authentication_repository.dart`,
`offline_account_sync_service.dart`, `app_build.dart`, `pubspec.yaml`,
`test/bundle265_test.dart`, `test/bundle223_logs_test.dart`, `test/nearby_190_test.dart`,
`docs/history/TODO_265.md`.

## I. Risks

- A2 is the only path change in the server search: a server that advertises
  a PUBLIC IP or a hostname would now be reached at its sender address instead.
  Your server is on 192.168.18.x -> no change.
- C1: only the app engine clears a `|bg` lease, and the background engine can't
  run while the app is open. Old untagged leases behave as today.
