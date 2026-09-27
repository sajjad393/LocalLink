import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class AttachmentCryptoResult {
  final List<int> ciphertext;
  final String nonce;
  final String mac;
  final String cryptoVersion;
  final String scope;
  final int keyVersion;
  const AttachmentCryptoResult({
    required this.ciphertext,
    required this.nonce,
    required this.mac,
    required this.cryptoVersion,
    required this.scope,
    required this.keyVersion,
  });
}

class AttachmentCryptoService {
  static const cryptoVersion = 'e2e:v1';
  final AesGcm _aes = AesGcm.with256bits();
  final Hmac _hmac = Hmac.sha256();

  String _encode(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');

  List<int> _decode(String value) {
    var v = value;
    while (v.length % 4 != 0) v += '=';
    return base64Url.decode(v);
  }

  String context({
    required String scope,
    required int keyVersion,
    required String senderId,
    required String recipientId,
    required String groupId,
    required String messageId,
    required String fileId,
    required String originalName,
    required String contentType,
    required int size,
    required String sha256,
    required String purpose,
  }) => jsonEncode(<String, Object>{
        'domain': 'locallink-attachment-e2e-v1',
        'version': 1,
        'scope': scope,
        'key_version': keyVersion,
        'sender_id': senderId,
        'recipient_id': recipientId,
        'group_id': groupId,
        'message_id': messageId,
        'file_id': fileId,
        'original_name': originalName,
        'content_type': contentType,
        'size': size,
        'sha256': sha256,
        'purpose': purpose,
      });

  Future<SecretKey> _deriveFileKey(String baseKey, String canonicalContext) async {
    final base = _decode(baseKey);
    if (base.length != 32) throw const FormatException('invalid attachment base key');
    final mac = await _hmac.calculateMac(
      utf8.encode('locallink-attachment-key-v1|$canonicalContext'),
      secretKey: SecretKey(base),
    );
    return SecretKey(mac.bytes.sublist(0, 32));
  }

  Future<AttachmentCryptoResult> encrypt({
    required List<int> plaintext,
    required String baseKey,
    required String scope,
    required int keyVersion,
    required String senderId,
    required String recipientId,
    required String groupId,
    required String messageId,
    required String fileId,
    required String originalName,
    required String contentType,
    required int size,
    required String sha256,
    String purpose = 'file',
  }) async {
    final canonical = context(
      scope: scope,
      keyVersion: keyVersion,
      senderId: senderId,
      recipientId: recipientId,
      groupId: groupId,
      messageId: messageId,
      fileId: fileId,
      originalName: originalName,
      contentType: contentType,
      size: size,
      sha256: sha256,
      purpose: purpose,
    );
    final key = await _deriveFileKey(baseKey, canonical);
    final box = await _aes.encrypt(
      plaintext,
      secretKey: key,
      aad: utf8.encode(canonical),
    );
    return AttachmentCryptoResult(
      ciphertext: box.cipherText,
      nonce: _encode(box.nonce),
      mac: _encode(box.mac.bytes),
      cryptoVersion: cryptoVersion,
      scope: scope,
      keyVersion: keyVersion,
    );
  }

  Future<List<int>> decrypt({
    required List<int> ciphertext,
    required String baseKey,
    required String scope,
    required int keyVersion,
    required String senderId,
    required String recipientId,
    required String groupId,
    required String messageId,
    required String fileId,
    required String originalName,
    required String contentType,
    required int size,
    required String sha256,
    required String nonce,
    required String mac,
    String purpose = 'file',
  }) async {
    if (nonce.isEmpty || mac.isEmpty) throw const FormatException('attachment authentication metadata missing');
    final canonical = context(
      scope: scope,
      keyVersion: keyVersion,
      senderId: senderId,
      recipientId: recipientId,
      groupId: groupId,
      messageId: messageId,
      fileId: fileId,
      originalName: originalName,
      contentType: contentType,
      size: size,
      sha256: sha256,
      purpose: purpose,
    );
    final key = await _deriveFileKey(baseKey, canonical);
    return _aes.decrypt(
      SecretBox(
        ciphertext,
        nonce: _decode(nonce),
        mac: Mac(_decode(mac)),
      ),
      secretKey: key,
      aad: utf8.encode(canonical),
    );
  }

  Future<String> sha256Hex(List<int> bytes) async {
    final digest = await Sha256().hash(bytes);
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Uint8List asBytes(List<int> data) => Uint8List.fromList(data);
}
