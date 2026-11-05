import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/data/actions/admin_action_service.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';

/// Bundle 220: the existing admin screens call this right after their own
/// action. With the server connected it does nothing (the server makes the
/// card); with no server this phone makes a signed card for all phones.
abstract final class AdminActionOffline {
  /// Null = nothing to say (online, or done quietly). Otherwise a short
  /// note for a snack: sent, or why it couldn't be sent.
  static Future<String?> ifOffline({
    required String action,
    required String userId,
    required String label,
    List<String> devices = const [],
    Map<String, dynamic> detail = const {},
    String words = '',
    SignedBlob? inner,
    AdminActionService? service,
  }) async {
    final s = service ?? AdminActionService.instance;
    if (s == null || (s.serverOnline?.call() ?? false)) return null;
    try {
      await s.make(
        action: action,
        targetUserId: userId,
        label: label,
        targetDevices: devices,
        detail: detail,
        words: words,
        inner: inner,
      );
      return 'Sent to all phones · Pending until it is done';
    } on StateError catch (e) {
      return e.message;
    } catch (e) {
      AppLogger.warning('ADMIN_ACT_OFFLINE_FAIL', detail: '$e');
      return null;
    }
  }
}
