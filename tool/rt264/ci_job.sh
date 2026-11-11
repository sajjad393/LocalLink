#!/bin/bash
# Bundle 264: what one GitHub job runs inside the emulator runner.
# usage: ci_job.sh <case>      (one emulator, emulator-5554)
#        ci_job.sh key_note    (starts a 2nd emulator, A and B at once)
set -u
CASE="$1"
export RT264_OUT="${RT264_OUT:-$PWD/out}"
mkdir -p "$RT264_OUT"
export RT264_ADMIN_PASS="$(head -c 18 /dev/urandom | base64 | tr -d '/+=' | head -c 24)"

if [ "$CASE" != "key_note" ]; then
  export RT264_SERIALS=emulator-5554
  python3 tool/rt264/server_ctl.py > "$RT264_OUT/server_ctl.txt" 2>&1 &
  CTL=$!
  sleep 2
  bash tool/rt264/run_case.sh "$CASE" emulator-5554 a
  CODE=$?
  kill $CTL 2>/dev/null || true
  exit $CODE
fi

# key_note: second emulator from the same AVD (read-only copy).
"$ANDROID_HOME/emulator/emulator" -avd test -port 5556 -read-only -no-window \
  -gpu swiftshader_indirect -noaudio -no-boot-anim -camera-back none \
  > "$RT264_OUT/emulator_5556.txt" 2>&1 &
adb -s emulator-5556 wait-for-device
for i in $(seq 1 180); do
  [ "$(adb -s emulator-5556 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break
  sleep 2
done
adb -s emulator-5556 shell settings put global window_animation_scale 0 || true
adb -s emulator-5556 shell settings put global transition_animation_scale 0 || true
adb -s emulator-5556 shell settings put global animator_duration_scale 0 || true

export RT264_SERIALS=emulator-5554,emulator-5556
python3 tool/rt264/server_ctl.py > "$RT264_OUT/server_ctl.txt" 2>&1 &
CTL=$!
sleep 2
# B builds in its own copy so the two builds don't share one build folder.
rm -rf ../app_b && cp -r . ../app_b
bash tool/rt264/run_case.sh key_note emulator-5554 a &
A=$!
(
  cd ../app_b
  bash tool/rt264/run_case.sh key_note emulator-5556 b
  adb -s emulator-5556 shell pm clear com.sajjad.linkup || true
  bash tool/rt264/run_case.sh key_note emulator-5556 b2
)
wait $A
CODE=$?
kill $CTL 2>/dev/null || true
exit $CODE
