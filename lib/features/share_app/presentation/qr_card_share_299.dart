import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:share_plus/share_plus.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/share_app/presentation/qr_share_card_299.dart';

/// Bundle 299 (Q): shares a QR code as the card picture
/// ([QrShareCard299], the recovery-card look). The caption is only the
/// code itself (the user: "caption just show code text nothing else").
/// The temp PNG is deleted when the share sheet returns (share_plus has
/// copied it by then).
abstract final class QrCardShare299 {
  /// Tests replace the share sheet: (png path, caption).
  static Future<void> Function(String path, String text)? debugShare;

  /// The last picture's bytes (tests only).
  static Uint8List? debugLastPng;

  static Future<ui.Image?> _photo(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      final codec = await ui.instantiateImageCodec(f.readAsBytesSync(), targetWidth: 360);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  /// False when the picture could not be made or shared (logged).
  static Future<bool> share({
    required QrCardKind299 kind,
    required String data,
    required String name,
    String sub = '',
    String? photoPath,
    DateTime? made,
  }) async {
    File? file;
    try {
      final photo = await _photo(photoPath);
      final Uint8List png;
      try {
        png = await QrShareCard299.png(kind: kind, data: data, name: name, sub: sub, photo: photo, made: made);
      } finally {
        photo?.dispose();
      }
      debugLastPng = png;
      file = File('${Directory.systemTemp.path}/linkup_qr_${DateTime.now().microsecondsSinceEpoch}.png');
      await file.writeAsBytes(png, flush: true);
      final text = data.trim();
      final fake = debugShare;
      if (fake != null) {
        await fake(file.path, text);
      } else {
        await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')], text: text);
      }
      return true;
    } catch (error) {
      AppLogger.error('QR_CARD_SHARE_299_FAILED', error: error);
      return false;
    } finally {
      try {
        if (file != null && file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }
}
