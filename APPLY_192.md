# Bundle 192 – detailed call path logs (logs only) (3.0.23+94)

Includes Bundle 191 (echo cancel + `CALL_MIC_EFFECTS`), see APPLY_191.md.

## Why
- Before testing Wi-Fi Direct and Mesh calls we need to see which way the voice went,
  if it changed during the call, and what the middle phone did.
- `CALL_VOICE_HEALTH` already had `link=lan|wifi_direct|relay`, but no hops, no middle phone,
  no path changes, no middle-phone counts, no Wi-Fi Direct link details.

## New log lines (no behaviour change)
1. `CALL_PATH call=<id> at=start|change|end path=<p> hops=<n> via=<id6> udp=y|n`
   - path: `lan` (same router), `wifi_direct` (phone to phone), `local_net`, `mesh` (through a middle phone), `none`.
   - checked every 2 s, logged only when it changes; `!` when a direct path moves to a middle phone or is lost.
2. `CALL_VOICE_HEALTH ... hops_rx=<n> via=<id6>` (added at the end of the existing 10 s line).
3. Middle phone: `RELAY_VOICE_HEALTH stream=<6> src=<6> dst=<6> passed=<n> per_s=<n> dropped=<n> gap_max_ms=<n> at=run|end`
   - every 10 s per call passing through, and `at=end` after 8 s without voice. ~50 per_s is normal.
   - dropped = call budget full, or no way onward.
4. `WD_LINK at=call_start|call_end|drop_in_call|up_in_call group=y|n role=owner|client members=<n> freq=<MHz> band=2.4|5|6`
   - `drop_in_call` (with `!`) = the Wi-Fi Direct link was lost while a call was on.

## Files
- New: `CallPathPolicy.kt` (CallPathPolicy + WdLinkPolicy), `mesh/RelayVoiceHealth.kt`, test `Path192Test.kt`.
- Changed: `LocalLinkTransportService.kt`, `NearbyRadio.kt`, `CallVoiceHealth.kt` (2 fields at the end).
- Version 3.0.23+94, stamp `v3 · 3.0.23 · bundles 104-192 (2026-11-02)`.

## Not changed
- No change to how calls connect, route, sound, or how Nearby searches.

## Checks here
- Kotlin compile clean; Kotlin tests 327 passed (Mic191Test 8 + Path192Test 14 new).
- flutter analyze 0 errors; `nearby_190_test` passes (version group now 192).
- Real Wi-Fi Direct / Mesh behaviour can only be checked on phones.
