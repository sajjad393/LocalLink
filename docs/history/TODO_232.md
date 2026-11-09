# TODO 232 - QR scanner could not read any LinkUp code (app 3.0.70+141)

## Problem (user report)
"In our app QR scanner not working, they can't scan any of our QR codes." Camera picture shows normally, all phones, all codes.

## Cause (checked in code + ZTE log Z2453-2026-11-06-0750)
- Camera opened 07:48:59, ran 38 s, ML Kit got frames (`tflite` started), but there was **no `QR_IMPORT stage=scanned`**, so nothing was ever read.
- The log shows the reader picture was **640x480** (`Gralloc Register w:640 h:480`): the plugin default, because no `cameraResolution` was set.
- Our codes are dense:
  - contact QR: 658 characters, error level H = **129 x 129 squares** (version 28) + photo in the middle;
  - group QR: about 456 characters, level H = **109 x 109 squares** (version 23) + hole for the group photo;
  - transfer QR: about 411 characters, level L = 69 x 69 squares.
- Contact and group scanners used `scanWindow`. In mobile_scanner 5.2.3 (Android) a code is kept only if its WHOLE box is inside the window. On a 360x800 screen the window is about **190 x 190 pixels** of the 480x640 picture = **1.4 px per square** (contact), 1.6 (group). ML Kit needs about 3 or more.
- So: small enough to fit the box = too blurry to read; close enough to read = sticks out of the box and the plugin throws it away. It could never work.

## Fix (app only, no server change)
1. New `lib/core/services/qr_scan_config_232.dart`: `linkUpQrScannerController()` = QR only, `cameraResolution` 1280x720 with the new CameraX selector (picks about 1280x960, 4-5 px per square). Used by all 3 scanners.
2. `my_qr_screen.dart` (contact scanner) and `group_qr_screens.dart` (group scanner): remove `scanWindow:`. The box and corner lines stay on screen as a guide only.
3. Shown codes: contact `QrImageView` and `GroupQrPainter` error level **H -> Q** (contact 129 -> 113 squares, group 109 -> 97). Size, photo, hole and colours unchanged.
4. Version 3.0.70+141.

## Not changed
- Screen look (same size, same overlay, same texts), paste code, transfer flow, code contents (old codes still scan).

## Files
- lib/core/services/qr_scan_config_232.dart (new)
- lib/features/directory/presentation/my_qr_screen.dart
- lib/features/groups/presentation/screens/group_qr_screens.dart
- lib/features/transfer/presentation/screens/account_transfer_scan_screen.dart (one line: the controller)
- lib/core/config/app_build.dart, pubspec.yaml (version)
- test/bundle232_qr_scan_test.dart (new, 4 tests)
- Old tests: only version pins (test/bundle223_logs_test.dart 3, test/nearby_190_test.dart 1)
