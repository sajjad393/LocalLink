import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';

/// Bundle 197a: one chat or group the user can forward to.
class ForwardTarget {
  final String id;
  final String name;
  final String subtitle;
  final bool isGroup;
  final DateTime? lastAt;

  const ForwardTarget({
    required this.id,
    required this.name,
    this.subtitle = '',
    this.isGroup = false,
    this.lastAt,
  });

  String get key => isGroup ? 'g:$id' : 'd:$id';
}

/// One message to forward (text and / or its files).
class ForwardItem {
  final String text;
  final List<Attachment> attachments;
  const ForwardItem({required this.text, this.attachments = const []});
  bool get isEmpty => text.trim().isEmpty && attachments.isEmpty;
}

/// Thrown when a photo / file to forward is no longer on this phone.
class ForwardFileMissing implements Exception {
  const ForwardFileMissing();
  @override
  String toString() => 'This file is no longer on your phone';
}

/// Bundle 197a: the Home screen registers how to list chats and send, so
/// the 1-to-1 chat and the group chat can both forward to anyone.
class ForwardHub {
  static ForwardHub? instance;

  final Future<List<ForwardTarget>> Function() targets;
  final Future<void> Function(
      ForwardTarget target, String body, List<PickedFile> files) send;
  final FileTransferRepositoryContract files;

  /// Route that opens a chat (used when exactly one chat was picked).
  final Route<void>? Function(ForwardTarget target)? routeFor;

  ForwardHub({
    required this.targets,
    required this.send,
    required this.files,
    this.routeFor,
  });

  /// A sendable copy of each attachment (protected files are decrypted to a
  /// view copy first). Throws [ForwardFileMissing].
  Future<List<PickedFile>> filesFor(ForwardItem item) async {
    final out = <PickedFile>[];
    for (final a in item.attachments) {
      final path = a.localPath ?? '';
      if (path.isEmpty || !await File(path).exists()) {
        throw const ForwardFileMissing();
      }
      var usable = path;
      try {
        if (await files.isProtectedLocalFile(path)) {
          final dot = a.originalName.lastIndexOf('.');
          final ext = dot >= 0 ? a.originalName.substring(dot) : '.bin';
          usable = await files.materializeForDisplay(path, extension: ext);
        }
      } catch (_) {
        throw const ForwardFileMissing();
      }
      out.add(PickedFile(
        path: usable,
        name: a.originalName,
        contentType: a.contentType,
        size: a.size,
      ));
    }
    return out;
  }

  /// Send every item to every target, one after another. Returns how many
  /// chats got at least one message.
  Future<int> forward(List<ForwardItem> items, List<ForwardTarget> to) async {
    final prepared = <(String, List<PickedFile>)>[];
    var fileCount = 0;
    for (final item in items) {
      if (item.isEmpty) continue;
      final picked = await filesFor(item);
      fileCount += picked.length;
      prepared.add((
        MessageEnvelope.build(text: item.text.trim(), forwarded: true),
        picked,
      ));
    }
    var chats = 0;
    for (final target in to) {
      var sent = false;
      for (final (body, picked) in prepared) {
        await send(target, body, picked);
        sent = true;
      }
      if (sent) chats++;
    }
    AppLogger.info('MESSAGE_FORWARD',
        detail: 'count=${prepared.length} chats=$chats files=$fileCount');
    return chats;
  }
}
