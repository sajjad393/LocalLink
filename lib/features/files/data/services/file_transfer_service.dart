import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/io_client.dart' as http_io;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/security/security_policy.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/files/data/models/file_transfer_models.dart';
import 'package:locallink/core/security/sensitive_file_protection_service.dart';

class FileTransferService {
  static const _channel = MethodChannel('locallink/files');
  final LocalStore store;

  /// HTTP client with a bounded TCP connect phase. The surrounding
  /// `.timeout()` calls bound the whole transfer, but a dead or unreachable
  /// server can otherwise stall that entire budget inside OS-level connect
  /// retries — which made attachment taps look frozen when the server is off.
  /// 8 s connects fail fast; transfer throughput is unaffected.
 http.Client _newHttpClient() {
  final inner = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  return http_io.IOClient(inner);
}
  final ConnectivityRepositoryContract? connectivity;
  final Map<String, http.Client> _activeClients = {};
  final Set<String> _cancelledTransfers = {};
  final SensitiveFileProtectionService sensitiveFiles;

  FileTransferService(this.store,
      {this.connectivity,
      SensitiveFileProtectionService? sensitiveFiles})
      : sensitiveFiles = sensitiveFiles ?? SensitiveFileProtectionService();

  String get baseUrl =>
      SecurityPolicy.normalizeServerAddress(store.serverAddress ?? '');

  Future<List<PickedFile>> pickFiles(
      {String mimeType = '*/*', bool allowMultiple = false}) async {
    final result = await _channel.invokeMethod<dynamic>('pickFile', {
      'mimeType': mimeType,
      'allowMultiple': allowMultiple,
    });
    if (result == null) return [];
    final values = result is List ? result : [result];
    return values
        .map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return PickedFile(
            path: m['path']?.toString() ?? '',
            name: m['name']?.toString() ?? 'attachment',
            contentType:
                m['content_type']?.toString() ?? 'application/octet-stream',
            size: int.tryParse(m['size']?.toString() ?? '') ?? 0,
          );
        })
        .where((f) => f.path.isNotEmpty)
        .toList();
  }

  Future<Attachment> upload(PickedFile file,
      {String? clientFileId,
      String? transferId,
      void Function(TransferProgress progress)? onProgress}) async {
    // Standard multipart path. The previous hand-rolled StreamedRequest pump
    // pushed chunks into the sink without backpressure and stalled after the
    // first chunk on Android — the server only responded to requests that
    // somehow completed, which is exactly why 200s kept arriving AFTER the
    // 45s timeouts. This version is bounded end-to-end, and retries are safe:
    // the server de-duplicates via X-Client-File-ID.
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/api/v1/files'));
    request.headers.addAll(_headers());
    if (clientFileId != null && clientFileId.trim().isNotEmpty) {
      request.headers['X-Client-File-ID'] = clientFileId.trim();
    }
    request.files.add(await http.MultipartFile.fromPath('file', file.path,
        filename: file.name));
    final contentLength = request.contentLength;

    AppLogger.info(
      'FILE_UPLOAD_SEND_START',
      detail: 'bytes=$contentLength name=${file.name}',
    );
    onProgress?.call(TransferProgress(
      operationId: transferId ?? 'untracked-upload',
      direction: FileTransferDirection.upload,
      completed: 0,
      total: contentLength,
      status: FileTransferStatus.running,
    ));

    final client = _newHttpClient();
    if (transferId != null && transferId.isNotEmpty)
      _activeClients[transferId] = client;
    try {
      final streamed =
          await client.send(request).timeout(const Duration(seconds: 40));
      AppLogger.info(
        'FILE_UPLOAD_RESPONSE_HEADERS',
        detail: 'status=${streamed.statusCode}',
      );
      final body = await streamed.stream
          .bytesToString()
          .timeout(const Duration(seconds: 30));
      AppLogger.info('FILE_UPLOAD_RESPONSE_BODY', detail: 'len=${body.length}');
      if (streamed.statusCode != 200 && streamed.statusCode != 201) {
        throw Exception(_errorBody(body, streamed.statusCode));
      }
      onProgress?.call(TransferProgress(
        operationId: transferId ?? 'untracked-upload',
        direction: FileTransferDirection.upload,
        completed: contentLength,
        total: contentLength,
        status: FileTransferStatus.completed,
      ));
      final payload = jsonDecode(body) as Map<String, dynamic>;
      if (transferId != null && _cancelledTransfers.remove(transferId)) {
        throw const FileTransferCancelledException();
      }
      return Attachment.fromJson(
          Map<String, dynamic>.from(payload['file'] as Map));
    } catch (_) {
      if (transferId != null && _cancelledTransfers.remove(transferId)) {
        throw const FileTransferCancelledException();
      }
      rethrow;
    } finally {
      _activeClients.remove(transferId);
      client.close();
    }
  }

  Future<Attachment> uploadForMessage(
    PickedFile file, {
    required String recipientId,
    required String messageId,
    required String createdAt,
    required String clientFileId,
    String? transferId,
    void Function(TransferProgress progress)? onProgress,
  }) => upload(file, clientFileId: clientFileId, transferId: transferId, onProgress: onProgress);

  Future<Attachment> uploadForGroupMessage(
    PickedFile file, {
    required String groupId,
    required String messageId,
    required String createdAt,
    required String clientFileId,
    String? transferId,
    void Function(TransferProgress progress)? onProgress,
  }) => upload(file, clientFileId: clientFileId, transferId: transferId, onProgress: onProgress);

  Future<String> downloadForMessage(
    String messageId,
    Attachment attachment, {
    String? transferId,
    void Function(TransferProgress progress)? onProgress,
  }) async {
    final message = await store.messageById(messageId);
    if (message == null) throw StateError('message not found');
    final path = await _downloadAndMaybeDecrypt(
      attachment,
      senderId: message.senderId,
      recipientId: message.recipientId,
      groupId: '',
      messageId: message.id,
      createdAt: message.createdAt.toUtc().toIso8601String(),
      transferId: transferId,
      onProgress: onProgress,
    );
    await store.setMessageAttachmentLocalPath(messageId, attachment.id, path);
    return path;
  }

  Future<String> downloadForGroupMessage(
    String messageId,
    Attachment attachment, {
    String? transferId,
    void Function(TransferProgress progress)? onProgress,
  }) async {
    final message = await store.groupMessageById(messageId);
    if (message == null) throw StateError('group message not found');
    final path = await _downloadAndMaybeDecrypt(
      attachment,
      senderId: message.senderId,
      recipientId: '',
      groupId: message.groupId,
      messageId: message.id,
      createdAt: message.createdAt,
      transferId: transferId,
      onProgress: onProgress,
    );
    await store.setGroupAttachmentLocalPath(messageId, attachment.id, path);
    return path;
  }

  Future<String> _downloadAndMaybeDecrypt(
    Attachment attachment, {
    required String senderId,
    required String recipientId,
    required String groupId,
    required String messageId,
    required String createdAt,
    String? transferId,
    void Function(TransferProgress progress)? onProgress,
  }) => download(attachment, transferId: transferId, onProgress: onProgress);

  Future<void> sendDirectFile({
    required String recipientId,
    required String messageId,
    required String fileId,
    required PickedFile file,
  }) async {
    if (recipientId.trim().isEmpty ||
        messageId.trim().isEmpty ||
        fileId.trim().isEmpty) {
      throw const FormatException(
          'Direct file transfer identifiers are required');
    }
    if (file.path.trim().isEmpty || !await File(file.path).exists()) {
      throw StateError('Selected file is no longer available');
    }
    final boundary = connectivity;
    if (boundary == null || !(await boundary.isWifiDirectTransportStarted())) {
      throw StateError('Wi-Fi Direct transport is unavailable');
    }
    await boundary.sendDirectFile(
      recipientId: recipientId,
      filePath: file.path,
      fileId: fileId,
      messageId: messageId,
      fileName: file.name,
      contentType: file.contentType,
    );
  }

  Future<String> stageOutgoingFile({
    required PickedFile file,
    required String fileId,
  }) async {
    // Bundle 106: give every outgoing attachment a durable home in the
    // app-private attachments dir. image_picker returns CACHE paths the OS
    // can reclaim; when that copy vanished while the outbox waited offline,
    // the direct send aborted before the message left (no delivery) and the
    // sender's own bubble had no file to render (no preview). Staged copies
    // fix both, and server uploads stay byte-identical.
    try {
      if (fileId.trim().isEmpty) return file.path;
      final source = File(file.path);
      if (file.path.trim().isEmpty || !await source.exists()) return file.path;
      final root = await getDatabasesPath();
      final dir = Directory('$root/attachments');
      await dir.create(recursive: true);
      final target =
          '${dir.path}/outbox-${_safeAttachmentId(fileId)}${_safeExtension(file.name, file.contentType, false)}';
      if (FileSystemEntity.typeSync(target) != FileSystemEntityType.notFound) {
        return target; // already staged (retry flush re-resolves it)
      }
      await source.copy(target);
      AppLogger.info('FILE_STAGED_OUTBOX',
          detail: 'file=$fileId size=${file.size}');
      return target;
    } catch (error, stackTrace) {
      AppLogger.error('FILE_STAGE_OUTBOX_FAILED',
          error: error, stackTrace: stackTrace, detail: 'file=$fileId');
      return file.path; // fall back: keep today's behavior rather than fail
    }
  }

  Future<void> cancelDirectFile(String fileId) async {
    final id = fileId.trim();
    if (id.isEmpty) return;
    final boundary = connectivity;
    if (boundary == null) return;
    await boundary.cancelDirectFile(id);
  }

  Future<String> download(Attachment attachment,
      {String? transferId,
      void Function(TransferProgress progress)? onProgress,
      bool thumbnail = false}) async {
    final relative =
        thumbnail ? attachment.thumbnailUrl : attachment.downloadUrl;
    if (relative == null || relative.isEmpty)
      throw Exception('Attachment download URL is missing');
    final uri =
        SecurityPolicy.resolveLocalResource(relative, baseAddress: baseUrl);
    final root = await getDatabasesPath();
    final dir = Directory('$root/attachments');
    await dir.create(recursive: true);
    final safeAttachmentId = _safeAttachmentId(attachment.id);
    final extension = _safeExtension(
        attachment.originalName, attachment.contentType, thumbnail);
    final target =
        '${dir.path}/$safeAttachmentId${thumbnail ? '-thumb' : ''}$extension';
    final protectedTarget = '$target.enc';
    final output = File(protectedTarget);
    if (await output.exists() && await output.length() > 0) return output.path;

    final part =
        File('$target${SensitiveFileProtectionService.plaintextPartSuffix}');
    var offset = await part.exists() ? await part.length() : 0;
    if (offset > 0 && offset > attachment.size + 2 * 1024 * 1024) {
      await part.delete();
      offset = 0;
    }

    final request = http.Request('GET', uri);
    request.headers.addAll(_headers());
    if (offset > 0) request.headers['Range'] = 'bytes=$offset-';
    final client = _newHttpClient();
    if (transferId != null && transferId.isNotEmpty)
      _activeClients[transferId] = client;
    try {
      final response =
          await client.send(request).timeout(const Duration(minutes: 3));
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('Download failed (${response.statusCode})');
      }
      final append = offset > 0 && response.statusCode == 206;
      if (!append) {
        offset = 0;
        if (await part.exists()) await part.delete();
      }
      final sink =
          part.openWrite(mode: append ? FileMode.append : FileMode.write);
      var received = offset;
      final total = response.contentLength != null
          ? offset + response.contentLength!
          : attachment.size;
      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          final hardLimit = math.max(attachment.size + 2 * 1024 * 1024, total);
          if (received > hardLimit)
            throw StateError('download exceeds expected bounds');
          sink.add(chunk);
          onProgress?.call(TransferProgress(
            operationId: transferId ?? 'untracked-download',
            direction: FileTransferDirection.download,
            completed: received,
            total: total,
            status: FileTransferStatus.running,
          ));
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (transferId != null && _cancelledTransfers.remove(transferId)) {
        throw const FileTransferCancelledException();
      }
      await sensitiveFiles.protectFile(part.path, protectedTarget);
      await part.delete();
      return protectedTarget;
    } catch (_) {
      // Bundle 168: a failed delete must not hide the real error.
      try {
        await part.delete();
      } catch (_) {}
      if (transferId != null && _cancelledTransfers.remove(transferId)) {
        throw const FileTransferCancelledException();
      }
      rethrow;
    } finally {
      _activeClients.remove(transferId);
      client.close();
    }
  }

  Future<String> materializeForDisplay(String protectedPath,
          {String extension = '.bin'}) =>
      sensitiveFiles.materializeForView(protectedPath, extension: extension);

  Future<bool> isProtectedLocalFile(String path) =>
      sensitiveFiles.isProtected(path);

  Future<String> protectLegacyLocalFile(String plaintextPath) async {
    final file = File(plaintextPath);
    if (!await file.exists()) {
      // Bundle 144: the plaintext was already protected on an earlier pass (send
      // or first view) but the row still names it. Use that '.enc' copy: this
      // was the sender's OWN photo/video/voice note stuck behind a download icon.
      final protectedPath = '$plaintextPath.enc';
      if (await File(protectedPath).exists() &&
          await sensitiveFiles.isProtected(protectedPath)) {
        return protectedPath;
      }
      throw StateError('local file does not exist');
    }
    if (await sensitiveFiles.isProtected(plaintextPath)) return plaintextPath;
    final protectedPath = '$plaintextPath.enc';
    await sensitiveFiles.protectFile(plaintextPath, protectedPath);
    await file.delete();
    return protectedPath;
  }

  Future<void> cancel(String transferId) async {
    final id = transferId.trim();
    if (id.isEmpty) return;
    _cancelledTransfers.add(id);
    _activeClients.remove(id)?.close();
  }

  Future<void> deleteLocalFile(String path) async {
    final value = path.trim();
    if (value.isEmpty) return;
    try {
      final root = await getDatabasesPath();
      final attachmentDir = Directory('$root/attachments');
      final appDir = Directory(Directory(root).parent.path);
      final directDir =
          Directory('${appDir.path}/files/locallink_direct_files');
      final file = File(value);
      final candidate = await file.parent.resolveSymbolicLinks();
      final attachmentRoot = await attachmentDir.resolveSymbolicLinks();
      var allowedRoot = attachmentRoot;
      if (await directDir.exists()) {
        final directRoot = await directDir.resolveSymbolicLinks();
        if (candidate == directRoot ||
            candidate.startsWith('$directRoot${Platform.pathSeparator}')) {
          allowedRoot = directRoot;
        }
      }
      if (candidate != allowedRoot &&
          !candidate.startsWith('$allowedRoot${Platform.pathSeparator}'))
        return;
      await file.delete();
    } catch (_) {}
  }

  Future<void> cleanupSensitiveViewCopies() async {
    try {
      final root = await getDatabasesPath();
      await sensitiveFiles
          .cleanupSensitiveArtifacts(Directory('$root/attachments'));
    } catch (_) {}
  }

  Future<void> cleanupSensitiveArtifacts() => cleanupSensitiveViewCopies();

  Future<void> clearLocalCache() async {
    for (final client in _activeClients.values) {
      try {
        client.close();
      } catch (_) {}
    }
    _activeClients.clear();
    _cancelledTransfers.clear();
    try {
      final root = await getDatabasesPath();
      final dir = Directory('$root/attachments');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  Map<String, String> _headers() => {
        'Authorization': 'Bearer ${store.deviceToken ?? ''}',
        'X-Device-ID': store.deviceId ?? '',
      };

  String _safeAttachmentId(String value) {
    final id = value.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
      throw StateError('Invalid attachment id');
    }
    return id;
  }

  String _safeExtension(String name, String contentType, bool thumbnail) {
    if (thumbnail) return '.png';
    final clean = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
    final dot = clean.lastIndexOf('.');
    if (dot >= 0 && dot < clean.length - 1) return clean.substring(dot);
    switch (contentType) {
      case 'image/jpeg':
        return '.jpg';
      case 'image/png':
        return '.png';
      case 'image/gif':
        return '.gif';
      case 'application/pdf':
        return '.pdf';
      default:
        return '.bin';
    }
  }

  String _errorBody(String body, int status) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['error']?.toString() ?? 'File upload failed ($status)';
    } catch (_) {
      return 'File upload failed ($status)';
    }
  }
}
