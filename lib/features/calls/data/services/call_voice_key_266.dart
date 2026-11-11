import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Bundle 266 (B1): the call voice key both phones work out alone.
///
/// key = HKDF-SHA256(pair link key [Bundle 160],
///                   info = "linkup-voice-266|" + call id), 32 bytes, base64.
/// Nothing is sent: a call that rang only through the server still talks
/// locked end to end (the server passes sealed bytes only).
///
/// The caller marks its invite with [marker] inside `supported_media_codecs`
/// (the one list the server passes on). The callee works the key out only
/// when the invite says so; a key inside a locked invite always wins.
abstract final class CallVoiceKey266 {
  /// Rides in `supported_media_codecs`; never a real codec name.
  static const String marker = 'vk266';
  static const String infoPrefix = 'linkup-voice-266|';
  static const String _salt = 'linkup-voice-266';

  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// The call key from a link key (64 hex chars) and a call id, or null.
  static Future<String?> derive(String linkKeyHex, String callId) async {
    final id = callId.trim();
    final hex = linkKeyHex.trim().toLowerCase();
    if (id.isEmpty || hex.length != 64 || !RegExp(r'^[0-9a-f]+$').hasMatch(hex)) {
      return null;
    }
    final bytes = <int>[
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
    final key = await _hkdf.deriveKey(
      secretKey: SecretKey(bytes),
      nonce: utf8.encode(_salt),
      info: utf8.encode('$infoPrefix$id'),
    );
    return base64Encode(await key.extractBytes());
  }

  /// The invite's codec list says the caller used the worked-out key.
  static bool marked(Object? codecs) =>
      codecs is List && codecs.any((c) => c?.toString().trim() == marker);
}
