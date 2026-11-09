# APPLY 232 - QR scanner reads LinkUp codes again (app 3.0.70+141)

App only. No backend change. This comes inside the new app zip `locallink_app_224-232_2026-11-09.zip` (224, 225, 226, 227, 229, 231, 232). It replaces the 224-231 app zip. The backend zip `locallink_backend_230-231_2026-11-09.zip` is unchanged; still deploy it first.

## PowerShell (app)
```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force -Path "C:\Users\sajjad Ahmed\Downloads\locallink_app_224-232_2026-11-09.zip" -DestinationPath .
flutter pub get
flutter test -j 1
git add -A
git add -f APPLY_224.md APPLY_225.md APPLY_226.md APPLY_227.md APPLY_229.md APPLY_231.md APPLY_232.md TODO_224.md TODO_225.md TODO_226.md TODO_227.md TODO_229.md TODO_231.md TODO_232.md
git commit -m "v3 3.0.70+141 bundles 224-227 + 229 + 231 + 232: faster Wi-Fi Direct/LAN connect and never use Realme/XShare groups (224), a call wakes Wi-Fi Direct with Waiting for <name> to connect (225), Bluetooth LE finds friends with Allow and Bluetooth off cards in Add Contact Nearby (226), no jump to Welcome while logged in and the call screen closes once (227), size limits on nearby socket lines so no phone nearby can fill the memory (229), the server proves its key at sign in and one pinned server key is shared with the admin trust key (231), QR scanner reads LinkUp codes again with a sharper camera picture and no scan box filter (232)"
git push
```
Then build the APK as usual.

## What users see
- The scanner screens look the same. Now the code is read once it is anywhere in the camera picture; it doesn't have to fit inside the box.
- The contact and group QR codes have slightly bigger squares (fewer of them). Same size, same photo.

## Important
- **Both phones need 3.0.70.** The new scanner also reads codes from older app versions. An old scanner still can't read reliably.

## Phone tests
1. **Contact QR:** Phone A opens My QR, Phone B opens Add Contact -> Scan. Hold B about 20-30 cm away. It should read within 1-2 seconds. The log shows `QR_IMPORT stage=scanned`, then `stage=done`.
2. **Close up:** hold B close, so the code is bigger than the box -> still reads.
3. **Group QR:** an admin shows the group code, the other phone scans it -> the join screen opens.
4. **Account transfer QR:** old phone shows the code, new phone scans it -> "Transfer request detected".
5. **ZTE (2 GB):** test 1 on the ZTE as the scanner. The camera picture should stay smooth.
6. **Old code:** a phone still on 3.0.69 shows My QR, the 3.0.70 phone scans it -> reads.

If a scan still fails, send the log from the scanning phone. Look for `QR_IMPORT` lines and `Gralloc Register w:` sizes.

## Files
See `TODO_232.md`.

**Old tests changed:** only the version pins (`test/bundle223_logs_test.dart` 3, `test/nearby_190_test.dart` 1).

## Tests
- New: 4 in `test/bundle232_qr_scan_test.dart`.
- Full Flutter suite (9 chunks): **2376 passed, 0 failed**.
- No camera in my test machine, so the real scan must be checked on the phones (tests above).
