import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/security/security_policy.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/files/data/models/file_transfer_models.dart';
import 'package:locallink/features/files/data/services/attachment_crypto_service.dart';
import 'package:locallink/features/groups/data/services/group_crypto_service.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/security/sensitive_file_protection_service.dart';

class FileTransferService {
  static const _channel = MethodChannel('locallink/files');
  final LocalStore store;
  final ConnectivityRepositoryContract? connectivity;
  final Map<String, http.Client> _activeClients = {};
  final Set<String> _cancelledTransfers = {};
  final IdentityCryptoService crypto;
  final GroupCryptoService? groupCrypto;
  final AttachmentCryptoService attachmentCrypto;
  final SensitiveFileProtectionService sensitiveFiles;

  FileTransferService(this.store,
      {this.connectivity,
      IdentityCryptoService? crypto,
      this.groupCrypto,
      AttachmentCryptoService? attachmentCrypto,
      SensitiveFileProtectionService? sensitiveFiles})
      : crypto = crypto ?? IdentityCryptoService(),
        attachmentCrypto = attachmentCrypto ?? AttachmentCryptoService(),
        sensitiveFiles = sensitiveFiles ?? SensitiveFileProtectionService();

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
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/api/v1/files'));
    request.headers.addAll(_headers());
    if (clientFileId != null && clientFileId.trim().isNotEmpty) {
      request.headers['X-Client-File-ID'] = clientFileId.trim();
    }
    request.files.add(await http.MultipartFile.fromPath('file', file.path,
        filename: file.name));
    final finalized = request.finalize();
    final contentLength = request.contentLength;
    final streamed = http.StreamedRequest(request.method, request.url);
    streamed.headers.addAll(request.headers);
    streamed.contentLength = contentLength;
    var sent = 0;
    final pump = finalized.listen(
      (chunk) {
        sent += chunk.length;
        streamed.sink.add(chunk);
        onProgress?.call(TransferProgress(
          operationId: transferId ?? 'untracked-upload',
          direction: FileTransferDirection.upload,
          completed: sent,
          total: contentLength,
          status: FileTransferStatus.running,
        ));
      },
      onError: streamed.sink.addError,
      onDone: streamed.sink.close,
      cancelOnError: true,
    );
    final client = http.Client();
    if (transferId != null && transferId.isNotEmpty)
      _activeClients[transferId] = client;
    try {
      final response =
          await client.send(streamed).timeout(const Duration(minutes: 3));
      await pump.asFuture<void>().catchError((_) {});
      final body = await response.stream.bytesToString();
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(_errorBody(body, response.statusCode));
      }
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
      await pump.cancel();
      client.close();
    }
  }

  Future<Attachment> uploadE2eForMessage(
    PickedFile file, {
    required String recipientId,
    required String messageId,
    required String createdAt,
    required String clientFileId,
    String? transferId,
    void Function(TransferProgress progress)? onProgress,
  }) async {
    final senderId = store.deviceId?.trim() ?? '';
    if (senderId.isEmpty ||
        recipientId.trim().isEmpty ||
        messageId.trim().isEmpty ||
        createdAt.trim().isEmpty) {
      throw const FormatException(
          'direct E2E attachment identity metadata is required');
    }
    final peerKeys = await crypto.cachedPeerPublicKeys();
    final peerPublic = peerKeys[recipientId];
    if (peerPublic == null || peerPublic.isEmpty)
      throw StateError('recipient identity key is unavailable');
    final shared = await crypto.deriveSharedKey(recipientId, peerPublic);
    return _uploadEncrypted(
      file,
      baseKey: shared,
      scope: 'direct',
      keyVersion: crypto.keyVersion,
      senderId: senderId,
      recipientId: recipientId,
      groupId: '',
      messageId: messageId,
      createdAt: createdAt,
      clientFileId: clientFileId,
      transferId: transferId,
      onProgress: onProgress,
    );
  }

  Future<Attachment> uploadE2eForGroupMessage(
    PickedFile file, {
    required String groupId,
    required String messageId,
    required String createdAt,
    required String clientFileId,
    String? transferId,
    void Function(TransferProgress progress)? onProgress,
  }) async {
    final senderId = store.deviceId?.trim() ?? '';
    final groupService = groupCrypto;
    if (senderId.isEmpty || groupService == null)
      throw StateError('group E2E attachment dependencies are unavailable');
    final group = await store.groupById(groupId);
    if (group == null) throw StateError('group not found');
    final version = await groupService.ensureCurrentKey(group);
    final groupKey = await groupService.keyForVersion(groupId, version);
    if (groupKey == null) throw StateError('current group key is unavailable');
    return _uploadEncrypted(
      file,
      baseKey: groupKey,
      scope: 'group',
      keyVersion: version,
      senderId: senderId,
      recipientId: '',
      groupId: groupId,
      messageId: messageId,
      createdAt: createdAt,
      clientFileId: clientFileId,
      transferId: transferId,
      onProgress: onProgress,
    );
  }

  Future<Attachment> _uploadEncrypted(
    PickedFile file, {
    required String baseKey,
    required String scope,
    required int keyVersion,
    required String senderId,
    required String recipientId,
    required String groupId,
    required String messageId,
    required String createdAt,
    required String clientFileId,
    String? transferId,
    void Function(TransferProgress progress)? onProgress,
  }) async {
    final bytes = await File(file.path).readAsBytes();
    final size = bytes.length;
    final sha = await attachmentCrypto.sha256Hex(bytes);
    var width = 0;
    var height = 0;
    var isImage = file.contentType.toLowerCase().startsWith('image/');
    if (isImage) {
      try {
        final codec = await ui.instantiateImageCodec(bytes,
            targetWidth: 320, targetHeight: 320);
        final frame = await codec.getNextFrame();
        width = frame.image.width;
        height = frame.image.height;
        codec.dispose();
      } catch (_) {
        isImage = false;
      }
    }
    final encrypted = await attachmentCrypto.encrypt(
      plaintext: bytes,
      baseKey: baseKey,
      scope: scope,
      keyVersion: keyVersion,
      senderId: senderId,
      recipientId: recipientId,
      groupId: groupId,
      messageId: messageId,
      fileId: clientFileId,
      originalName: file.name,
      contentType: file.contentType,
      size: size,
      sha256: sha,
    );
    AttachmentCryptoResult? encryptedThumb;
    if (isImage) {
      try {
        final codec = await ui.instantiateImageCodec(bytes,
            targetWidth: 320, targetHeight: 320);
        final frame = await codec.getNextFrame();
        final data =
            await frame.image.toByteData(format: ui.ImageByteFormat.png);
        codec.dispose();
        if (data != null) {
          encryptedThumb = await attachmentCrypto.encrypt(
            plaintext: data.buffer.asUint8List(),
            baseKey: baseKey,
            scope: scope,
            keyVersion: keyVersion,
            senderId: senderId,
            recipientId: recipientId,
            groupId: groupId,
            messageId: messageId,
            fileId: clientFileId,
            originalName: file.name,
            contentType: file.contentType,
            size: size,
            sha256: sha,
            purpose: 'thumbnail',
          );
        }
      } catch (_) {}
    }
    final req =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/api/v1/files'));
    req.headers.addAll(_headers());
    req.headers.addAll({
      'X-Client-File-ID': clientFileId,
      'X-File-Crypto-Version': AttachmentCryptoService.cryptoVersion,
      'X-File-E2E-Scope': scope,
      'X-File-Key-Version': keyVersion.toString(),
      'X-File-Original-Name': file.name,
      'X-File-Content-Type': file.contentType,
      'X-File-Plaintext-Size': size.toString(),
      'X-File-Plaintext-SHA256': sha,
      'X-File-Width': width.toString(),
      'X-File-Height': height.toString(),
      'X-File-Is-Image': isImage.toString(),
      'X-File-Nonce': encrypted.nonce,
      'X-File-Mac': encrypted.mac,
    });
    req.files.add(http.MultipartFile.fromBytes('file', encrypted.ciphertext,
        filename: 'encrypted.bin'));
    if (encryptedThumb != null) {
      req.headers['X-File-Thumbnail-Nonce'] = encryptedThumb.nonce;
      req.headers['X-File-Thumbnail-Mac'] = encryptedThumb.mac;
      req.files.add(http.MultipartFile.fromBytes(
          'thumbnail', encryptedThumb.ciphertext,
          filename: 'encrypted-thumb.bin'));
    }
    final streamedRequest = http.StreamedRequest(req.method, req.url);
    streamedRequest.headers.addAll(req.headers);
    streamedRequest.contentLength = req.contentLength;
    final finalized = req.finalize();
    var sent = 0;
    final pump = finalized.listen((chunk) {
      sent += chunk.length;
      streamedRequest.sink.add(chunk);
      onProgress?.call(TransferProgress(
          operationId: transferId ?? clientFileId,
          direction: FileTransferDirection.upload,
          completed: sent,
          total: req.contentLength,
          status: FileTransferStatus.running));
    },
        onError: streamedRequest.sink.addError,
        onDone: streamedRequest.sink.close,
        cancelOnError: true);
    final client = http.Client();
    if (transferId != null && transferId.isNotEmpty)
      _activeClients[transferId] = client;
    try {
      final response = await client
          .send(streamedRequest)
          .timeout(const Duration(minutes: 3));
      await pump.asFuture<void>().catchError((_) {});
      final body = await response.stream.bytesToString();
      if (response.statusCode != 200 && response.statusCode != 201)
        throw Exception(_errorBody(body, response.statusCode));
      final payload = jsonDecode(body) as Map<String, dynamic>;
      final attachment = Attachment.fromJson(
          Map<String, dynamic>.from(payload['file'] as Map));
      if (attachment.cryptoVersion != AttachmentCryptoService.cryptoVersion ||
          attachment.cryptoScope != scope ||
          attachment.cryptoKeyVersion != keyVersion ||
          attachment.cryptoNonce != encrypted.nonce ||
          attachment.cryptoMac != encrypted.mac) {
        throw StateError(
            'server returned inconsistent E2E attachment metadata');
      }
      return attachment;
    } finally {
      _activeClients.remove(transferId);
      await pump.cancel();
      client.close();
    }
  }

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
  }) async {
    if (attachment.cryptoVersion.isEmpty) {
      return download(attachment,
          transferId: transferId, onProgress: onProgress);
    }
    if (attachment.cryptoVersion != AttachmentCryptoService.cryptoVersion)
      throw StateError('unsupported attachment crypto version');
    final relative = attachment.downloadUrl;
    if (relative == null || relative.isEmpty)
      throw StateError('encrypted attachment download URL is missing');
    final ciphertext = await _downloadBytes(relative,
        transferId: transferId,
        onProgress: onProgress,
        expectedSize: attachment.size);
    final target = await _attachmentTargetPath(attachment, false);
    final temp =
        File('$target${SensitiveFileProtectionService.plaintextPartSuffix}');
    try {
      final baseKeys = <String>[];
      if (attachment.cryptoScope == 'group') {
        final groupService = groupCrypto;
        if (groupService == null)
          throw StateError('group crypto service unavailable');
        final key = await groupService.keyForVersion(
            groupId, attachment.cryptoKeyVersion);
        if (key == null) throw StateError('group key version is unavailable');
        baseKeys.add(key);
      } else {
        if (senderId.isEmpty || recipientId.isEmpty)
          throw StateError('direct attachment participants are missing');
        final peerKeys = await crypto.cachedPeerPublicKeys();
        final history = await crypto.cachedPeerIdentityHistory();
        final candidates = <String>{};
        final current = peerKeys[senderId];
        if (current != null) candidates.add(current);
        candidates.addAll(history[senderId]?.values ?? const <String>[]);
        final localVersions = await crypto.availableKeyVersions();
        for (final peerKey in candidates) {
          for (final localVersion in localVersions) {
            try {
              baseKeys.add(await crypto.deriveSharedKey(senderId, peerKey,
                  selfKeyVersion: localVersion));
            } catch (_) {}
          }
        }
      }
      List<int>? plain;
      final nonce = attachment.cryptoNonce;
      final mac = attachment.cryptoMac;
      if (nonce == null || mac == null) {
        throw StateError('attachment authentication metadata missing');
      }
      for (final base in baseKeys) {
        try {
          plain = await attachmentCrypto.decrypt(
            ciphertext: ciphertext,
            baseKey: base,
            scope: attachment.cryptoScope,
            keyVersion: attachment.cryptoKeyVersion,
            senderId: senderId,
            recipientId: recipientId,
            groupId: groupId,
            messageId: messageId,
            fileId: attachment.id,
            originalName: attachment.originalName,
            contentType: attachment.contentType,
            size: attachment.size,
            sha256: attachment.sha256,
            nonce: nonce,
            mac: mac,
          );
          break;
        } catch (_) {}
      }
      if (plain == null) throw StateError('attachment decryption failed');
      if (plain.length != attachment.size ||
          await attachmentCrypto.sha256Hex(plain) !=
              attachment.sha256.toLowerCase()) {
        throw StateError('attachment plaintext integrity check failed');
      }
      final protectedTarget = '$target.enc';
      await temp.writeAsBytes(plain, flush: true);
      await sensitiveFiles.protectFile(temp.path, protectedTarget);
      await temp.delete();
      return protectedTarget;
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  Future<List<int>> _downloadBytes(String relative,
      {String? transferId,
      void Function(TransferProgress progress)? onProgress,
      required int expectedSize}) async {
    final uri =
        SecurityPolicy.resolveLocalResource(relative, baseAddress: baseUrl);
    final request = http.Request('GET', uri);
    request.headers.addAll(_headers());
    final client = http.Client();
    if (transferId != null && transferId.isNotEmpty)
      _activeClients[transferId] = client;
    try {
      final response =
          await client.send(request).timeout(const Duration(minutes: 3));
      if (response.statusCode != 200)
        throw Exception('Download failed (${response.statusCode})');
      final buffer = <int>[];
      var received = 0;
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > expectedSize + 1024 * 1024)
          throw StateError('encrypted download exceeds expected bounds');
        buffer.addAll(chunk);
        onProgress?.call(TransferProgress(
            operationId: transferId ?? 'untracked-download',
            direction: FileTransferDirection.download,
            completed: received,
            total: response.contentLength ?? 0,
            status: FileTransferStatus.running));
      }
      return buffer;
    } finally {
      _activeClients.remove(transferId);
      client.close();
    }
  }

  Future<String> _attachmentTargetPath(
      Attachment attachment, bool thumbnail) async {
    final root = await getDatabasesPath();
    final dir = Directory('$root/attachments');
    await dir.create(recursive: true);
    final safe = _safeAttachmentId(attachment.id);
    final ext = _safeExtension(
        attachment.originalName, attachment.contentType, thumbnail);
    return '${dir.path}/$safe${thumbnail ? '-thumb' : ''}$ext';
  }

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
    final client = http.Client();
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
            throw StateError('encrypted download exceeds expected bounds');
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
      await part.delete().catchError((_) {});
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
    if (!await file.exists()) throw StateError('local file does not exist');
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
