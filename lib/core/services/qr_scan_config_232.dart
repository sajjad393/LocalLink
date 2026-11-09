import 'dart:ui' show Size;

import 'package:mobile_scanner/mobile_scanner.dart';

/// Bundle 232: one scanner setup for every LinkUp QR scanner.
///
/// Before 232 the scanners used the plugin default, a 640x480 picture.
/// Our contact and group codes have 109-129 squares per side, so each
/// square got only 1-2 pixels and ML Kit could not read them.
///
/// * [kQrScanResolution] asks CameraX for about 1280x960 (4:3, the
///   closest size at or above 1280x720). That gives 4-5 pixels per square
///   when the code fills half of the frame, and it is still light for
///   2 GB phones.
/// * Only QR codes are searched, so ML Kit skips the bar code readers.
/// * The scan window filter is NOT used any more (see the scanners): the
///   plugin dropped every code that was not fully inside the small box,
///   so a code close enough to read was always thrown away.
const Size kQrScanResolution = Size(1280, 720);

MobileScannerController linkUpQrScannerController() => MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      cameraResolution: kQrScanResolution,
      useNewCameraSelector: true,
    );
