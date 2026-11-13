# TODO 285 - Calls tab: same person shows many rows on the same day  [BUILT 13 Nov in 3.0.90+161 - zip locallink_app_3.0.90_2026-11-14.zip, not pushed, not phone-tested]

Owner (12 Nov, screenshot `uploads/Screenshot_20261112-181753.png`): "We discussed this issue a lot of times but never fixed.
Showing duplicate rows on same day." Screen: TODAY = noshad (5), Ibrahim, noshad, Ibrahim, noshad (2), Ibrahim (2), noshad (2).

## Cause (VERIFIED in code, de70ef7) - not a data bug, it is the grouping RULE
- `lib/features/calls/presentation/call_history_groups.dart` `groupCallHistory` (Bundle 171, WhatsApp style):
  calls join only when they are BACK TO BACK with the same person (`last.peerId == call.peerId`).
  "A call with someone else in between starts a new row."
- At 1:28-1:29 PM calls went noshad, Ibrahim, noshad, Ibrahim... -> every switch = a new row.
- Bundle 255 B5 only joined back-to-back MISSED calls; it did not touch this rule. That is why it "never got fixed".
- Used only by `calls_screen.dart:234` (`_groupedList`, already split per day). Tap a row with count > 1 -> list sheet (`_openGroup` :278).

## Fix plan
- C-1 **Owner chose: ONE row per person per day, missed calls inside it.** Row position = that person's newest call that day.
  - If any call in the row was missed: row text red + "N missed" (e.g. "noshad (9) · 2 missed"); otherwise as now.
  - Replaces Bundle 171 "someone in between starts a new row" and Bundle 255 B5 "missed join only missed".
- C-2 The row shows the newest call (arrow, "No answer"/duration, time) + "(N)". Tap = existing list sheet with every call of that day.
- C-3 Tests that change (listed, not weakened): `test/calls_group_171_test.dart`
  - :44 "someone else in between starts a new row" -> expects one row per person.
  - :66 "missed calls back to back share one red row (255 B5)" -> missed + answered with the same person = ONE row.
  New test: the exact screenshot order -> 2 rows today (noshad 9, Ibrahim 4).
- Not changed: call history data, redial button, day titles.
