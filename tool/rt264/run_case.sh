#!/bin/bash
# Bundle 264: run one run-time test case on an emulator.
# usage: run_case.sh <case> [serial] [side]
# Needs: server_ctl.py already running, an emulator booted, flutter on PATH.
set -u
CASE="$1"
SERIAL="${2:-emulator-5554}"
SIDE="${3:-a}"
PKG=com.sajjad.linkup
OUT="${RT264_OUT:-out}"
TAG="${CASE}_${SIDE}"
mkdir -p "$OUT"

adb -s "$SERIAL" logcat -c || true
adb -s "$SERIAL" logcat -v time > "$OUT/logcat_${TAG}.txt" 2>&1 &
LOGCAT=$!

# The same Allow taps a person would do, once the app is installed
# (only on the emulator).
(
  for i in $(seq 1 600); do
    if adb -s "$SERIAL" shell pm path "$PKG" >/dev/null 2>&1; then
      for p in POST_NOTIFICATIONS NEARBY_WIFI_DEVICES ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION \
               BLUETOOTH_SCAN BLUETOOTH_CONNECT BLUETOOTH_ADVERTISE CAMERA RECORD_AUDIO; do
        adb -s "$SERIAL" shell pm grant "$PKG" "android.permission.$p" >/dev/null 2>&1 || true
      done
    fi
    sleep 2
  done
) &
GRANT=$!

START=$(date +%s)
flutter test integration_test/rt264_server_flows_test.dart -d "$SERIAL" \
  --dart-define=LINKUP_TEST_SERVER_IP=10.0.2.2 \
  --dart-define=RT264_CASE="$CASE" \
  --dart-define=RT264_SIDE="$SIDE" > "$OUT/flutter_${TAG}.txt" 2>&1
CODE=$?
END=$(date +%s)

kill $GRANT $LOGCAT 2>/dev/null || true

{
  echo "case=$CASE side=$SIDE serial=$SERIAL exit=$CODE seconds=$((END - START))"
  grep -o 'RT264_STEP .*' "$OUT/flutter_${TAG}.txt" || echo "RT264_STEP FAIL no steps (app did not start? see flutter_${TAG}.txt)"
  grep -o 'RT264_RESULT .*' "$OUT/flutter_${TAG}.txt" || true
  FIRST=$(grep -o 'RT264_STEP FAIL .*' "$OUT/flutter_${TAG}.txt" | head -1)
  echo "first_fail=${FIRST:-none}"
} > "$OUT/summary_${TAG}.txt"
# The app log printed by the test (same as Send logs).
sed -n 's/.*RT264_LOG \(.*\)/\1/p' "$OUT/flutter_${TAG}.txt" > "$OUT/applog_${TAG}.txt"
cat "$OUT/summary_${TAG}.txt"
exit $CODE
