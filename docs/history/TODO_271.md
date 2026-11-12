# TODO 271 - Cycle 3 log findings (3.0.84+155, logs 12 Nov 13:15-13:33)

Status: BUILT as bundle 271 (user chose "Bundle 271: fix D-271-1 + save the Cycle 3 report"). No version change.

## D-271-1 (P3) Startup error after an update: LateInitializationError in group file pump
Evidence (RMX3938, first open after install over 3.0.78):
- 13:14:43 APP_OPEN; 13:14:49 MAIN_STALL 6551 ms; 13:14:51.169 ERROR uncaught_async_error
  LateInitializationError '_db' at LocalStore.purgeGroupFileSends <- GroupFileSender._pumpOnce
  <- GroupFileSender.pump <- app_dependencies.dart:367
- 13:14:51.391 STARTUP_STEP database ms=8232 (DB opened 0.2 s AFTER the error)
Root cause (code, origin 390de01):
- lib/app/app_dependencies.dart:365-368 starts a fixed 8 s Timer that calls fileSender.pump().
- The timer starts when the deps are built, not when LocalStore.init() finishes
  (lib/app/local_link_app.dart:275). On an upgrade the DB open took 8.2 s, so the timer won.
- LocalStore.purgeGroupFileSends (local_store.dart:1080) uses late _db with no guard
  (touchDevicePresence at ~3668 already has the `!_databaseOpened` guard pattern).
User impact: none seen. One red log line; pump runs again on events and the 30 s check timer.
Fix (done): LocalStore.purgeGroupFileSends returns and LocalStore.groupFileSends returns [] while
!_databaseOpened (same pattern as touchDevicePresence). Nothing else changed.
Regression test: LocalStore without init -> purgeGroupFileSends and the sends read do not throw.
Files: lib/core/services/local_store.dart, test/bundle271_store_guard_test.dart (new).

## Environment (not app defects)
- E-1 Server PC clock is ~79 min slow: SERVER_CLOCK_WRONG offset_s=-4757..-4759 on all 3 phones;
  MESSAGE_CLOCK_CLAMPED drift=4759s on RMX5303. Fix: Windows time Sync now.
- E-2 Server says "recipient device not found" for ZTE android-c891ac8ded16a834 (RMX5303 13:18:08).
  ZTE was not in this test. NOT VERIFIED.

## Not defects
- Short calls (2-4 s, state=missed on callee): callee rang + sent invite_ack; caller pressed end.
- CALL_VIDEO_START_FAIL x2: video is STOPPED (rule) - ignored.
- mali_gralloc / MediaCodec / ExtLoader errors: vendor system lines.
- WS reconnect attempts 13:19-13:33: server was off (expected).
