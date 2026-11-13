import 'package:locallink/core/widgets/link_toast.dart';
import 'package:flutter/material.dart';

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/services/media_book.dart';
import 'package:locallink/features/storage/data/media_storage_service.dart';
import 'package:locallink/features/storage/domain/media_clean_policy.dart';

/// Bundle 197b: hold-sheet rules for media (V6, P1) shared by the 1-to-1
/// and the group chat screens.
class MediaMessageActions {
  MediaMessageActions._();

  static MediaKind kindOf(Attachment a) =>
      mediaKindOf(contentType: a.contentType, name: a.originalName, isImage: a.isImage);

  /// V6: a message whose media was removed can't be forwarded or saved.
  static bool hasRemoved(Iterable<Attachment> attachments, {MediaBook? book}) {
    final b = book ?? MediaBook.instance;
    return attachments.any((a) => b.isRemoved(a.id));
  }

  /// P1: received photo / video / document, file present, Android 10+.
  static List<Attachment> savable(
    Iterable<Attachment> attachments, {
    required bool mine,
    MediaBook? book,
    bool? androidOk,
    bool Function(Attachment a)? present,
  }) {
    if (mine) return const [];
    if (!(androidOk ?? MediaStorageService.instance.canSaveToPhone)) return const [];
    final b = book ?? MediaBook.instance;
    final has = present ??
        (Attachment a) => MediaStorageService.diskPathOf(a.localPath ?? '') != null;
    return [
      for (final a in attachments)
        if (kindOf(a) != MediaKind.voice && !b.isRemoved(a.id) && (a.localPath ?? '').isNotEmpty && has(a)) a,
    ];
  }

  static Future<void> save(BuildContext context, List<Attachment> attachments) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    String? text;
    for (final a in attachments) {
      text = await MediaStorageService.instance.saveToPhone(a);
    }
    if (text != null) LinkToast.maybeOn(messenger, text, kind: LinkToast.guess(text));
  }

  /// K4: forwarding counts as opening.
  static void markOpened(Iterable<Attachment> attachments) {
    for (final a in attachments) {
      MediaBook.instance.markOpened(a.id);
    }
  }
}
