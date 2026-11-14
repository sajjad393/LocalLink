import 'package:locallink/core/widgets/link_toast.dart';
import 'package:flutter/material.dart';

import 'package:locallink/core/diagnostics/log_share_service.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 180: "Preparing logs..." (Cancel), then the Android share sheet.
/// [prepare] / [share] can be swapped in tests.
Future<void> runLogShare(
  BuildContext context, {
  Future<String?> Function()? prepare,
  Future<void> Function(String path)? share,
}) async {
  final doPrepare = prepare ?? () => LogShareService.prepare();
  final doShare = share ?? LogShareService.share;
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.maybeOf(context);
  var cancelled = false;
  var open = true;
  AppLogger.info('LOG_SHARE_START');
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        key: const ValueKey('log_share_dialog'),
        content: Row(
          children: [
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L.t.preparingLogs, style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text(L.t.last1Hour),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const ValueKey('log_share_cancel'),
            onPressed: () {
              cancelled = true;
              open = false;
              Navigator.of(ctx).pop();
            },
            child: Text(L.t.cancel),
          ),
        ],
      ),
    ),
  );
  String? path;
  Object? failure;
  try {
    path = await doPrepare();
  } catch (e) {
    failure = e;
  }
  if (open) {
    open = false;
    navigator.pop();
  }
  await dialog;
  if (cancelled) {
    AppLogger.info('LOG_SHARE_CANCELLED');
    return;
  }
  if (path == null) {
    AppLogger.warning('LOG_SHARE_FAILED', detail: 'error=${failure ?? 'no_file'}');
    LinkToast.maybeOn(messenger, L.t.couldNotPrepareLogs, kind: LinkToastKind.error);
    return;
  }
  try {
    await doShare(path);
    AppLogger.info('LOG_SHARE_OPENED');
  } catch (e) {
    AppLogger.warning('LOG_SHARE_FAILED', detail: 'error=$e');
    LinkToast.maybeOn(messenger, L.t.couldNotShareLogs, kind: LinkToastKind.error);
  }
}
