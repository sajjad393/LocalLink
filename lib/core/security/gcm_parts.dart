// Bundle 208 (D1): AES-256-GCM on a file in parts, with progress.
//
// Same result, byte for byte, as `AesGcm.with256bits()` of the
// `cryptography` package (tests check this on many sizes and against the
// NIST vectors), so files locked before and after this bundle open the
// same way. Two differences:
//  * the file is read and written in parts (1 MB), so a progress number
//    can be sent after each part and a 30 MB video never sits in memory
//    twice;
//  * GHASH uses a 4-bit table (Shoup's method, as in OpenSSL's
//    gcm_gmult_4bit) instead of the package's bit-by-bit loop, which was
//    most of the 14-21 s "Preparing" wait on the slow phone.
// The AES blocks come from the package's own AES-CTR (public API).
//
// Needs 64-bit integers (Android / desktop VM). Not for the web.

import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Called after each part: bytes done of total.
typedef GcmProgress = void Function(int done, int total);

/// GHASH over GF(2^128) with a 16-entry table of H multiples.
class GcmHash {
  GcmHash(Uint8List h) {
    assert(h.length == 16);
    var vh = _u64(h, 0), vl = _u64(h, 8);
    _hi[8] = vh;
    _lo[8] = vl;
    for (final i in const [4, 2, 1]) {
      final t = (vl & 1) != 0 ? _r : 0;
      vl = (vh << 63) | (vl >>> 1);
      vh = (vh >>> 1) ^ t;
      _hi[i] = vh;
      _lo[i] = vl;
    }
    for (var i = 2; i < 16; i <<= 1) {
      for (var j = 1; j < i; j++) {
        _hi[i + j] = _hi[i] ^ _hi[j];
        _lo[i + j] = _lo[i] ^ _lo[j];
      }
    }
  }

  // ignore: avoid_js_rounded_ints
  static const int _r = 0xE100000000000000;
  static const List<int> _rem4 = <int>[
    0x0000 << 48, 0x1C20 << 48, 0x3840 << 48, 0x2460 << 48, //
    0x7080 << 48, 0x6CA0 << 48, 0x48C0 << 48, 0x54E0 << 48, //
    0xE100 << 48, 0xFD20 << 48, 0xD940 << 48, 0xC560 << 48, //
    0x9180 << 48, 0x8DA0 << 48, 0xA9C0 << 48, 0xB5E0 << 48, //
  ];

  final List<int> _hi = List<int>.filled(16, 0);
  final List<int> _lo = List<int>.filled(16, 0);
  final Uint8List _x = Uint8List(16);
  final Uint8List _pend = Uint8List(16);
  int _pendLen = 0;

  static int _u64(Uint8List b, int o) =>
      (b[o] << 56) | (b[o + 1] << 48) | (b[o + 2] << 40) | (b[o + 3] << 32) |
      (b[o + 4] << 24) | (b[o + 5] << 16) | (b[o + 6] << 8) | b[o + 7];

  void _mult() {
    final x = _x;
    final hi = _hi, lo = _lo, rem4 = _rem4;
    var nlo = x[15];
    var nhi = nlo >>> 4;
    nlo &= 0xf;
    var zh = hi[nlo], zl = lo[nlo];
    var cnt = 15;
    while (true) {
      var rem = zl & 0xf;
      zl = (zh << 60) | (zl >>> 4);
      zh = (zh >>> 4) ^ rem4[rem];
      zh ^= hi[nhi];
      zl ^= lo[nhi];
      if (--cnt < 0) break;
      nlo = x[cnt];
      nhi = nlo >>> 4;
      nlo &= 0xf;
      rem = zl & 0xf;
      zl = (zh << 60) | (zl >>> 4);
      zh = (zh >>> 4) ^ rem4[rem];
      zh ^= hi[nlo];
      zl ^= lo[nlo];
    }
    for (var i = 0; i < 8; i++) {
      x[i] = (zh >>> (56 - 8 * i)) & 0xff;
      x[8 + i] = (zl >>> (56 - 8 * i)) & 0xff;
    }
  }

  /// Adds [data] as one zero-padded section (AAD).
  void addPadded(List<int> data) {
    flushSection();
    add(data, 0, data.length);
    flushSection();
  }

  /// Adds bytes of the current section (any length; blocks continue
  /// across calls).
  void add(List<int> data, int start, int end) {
    var i = start;
    final x = _x;
    if (_pendLen > 0) {
      while (_pendLen < 16 && i < end) {
        _pend[_pendLen++] = data[i++];
      }
      if (_pendLen < 16) return;
      for (var j = 0; j < 16; j++) {
        x[j] ^= _pend[j];
      }
      _mult();
      _pendLen = 0;
    }
    while (i + 16 <= end) {
      for (var j = 0; j < 16; j++) {
        x[j] ^= data[i + j];
      }
      _mult();
      i += 16;
    }
    while (i < end) {
      _pend[_pendLen++] = data[i++];
    }
  }

  /// Ends the current section: the last part block is zero-padded.
  void flushSection() {
    if (_pendLen == 0) return;
    for (var j = 0; j < _pendLen; j++) {
      _x[j] ^= _pend[j];
    }
    _mult();
    _pendLen = 0;
  }

  /// Lengths block; returns the GHASH value.
  Uint8List finish(int aadBytes, int dataBytes) {
    flushSection();
    final len = ByteData(16)
      ..setUint64(0, aadBytes * 8)
      ..setUint64(8, dataBytes * 8);
    add(len.buffer.asUint8List(), 0, 16);
    return Uint8List.fromList(_x);
  }
}

class GcmParts {
  GcmParts._();

  static const int partBytes = 1024 * 1024;
  static const int nonceLength = 12;
  static const int macLength = 16;

  static const DartAesCtr _ctr =
      DartAesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);

  /// AES-CTR state starting at counter block nonce||ctr (big endian).
  static Future<DartCipherState> _stream(
      List<int> key, List<int> nonce, int ctr, {required bool encrypt}) async {
    final iv = Uint8List(16)..setAll(0, nonce);
    iv[12] = (ctr >>> 24) & 0xff;
    iv[13] = (ctr >>> 16) & 0xff;
    iv[14] = (ctr >>> 8) & 0xff;
    iv[15] = ctr & 0xff;
    final state = _ctr.newState();
    await state.initialize(
        isEncrypting: encrypt, secretKey: SecretKeyData(key), nonce: iv);
    return state;
  }

  /// H = AES(key, 0^128) and E(J0) = AES(key, nonce||1).
  static Future<(Uint8List, Uint8List)> _hAndJ0(
      List<int> key, List<int> nonce) async {
    final hState = await _stream(key, Uint8List(12), 0, encrypt: true);
    final h = Uint8List.fromList(hState.convertChunkSync(Uint8List(16)));
    final jState = await _stream(key, nonce, 1, encrypt: true);
    final ej0 = Uint8List.fromList(jState.convertChunkSync(Uint8List(16)));
    return (h, ej0);
  }

  static Uint8List _xor16(Uint8List a, Uint8List b) =>
      Uint8List.fromList(List<int>.generate(16, (i) => a[i] ^ b[i]));

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }

  /// In-memory AES-256-GCM (tests + the start-up self check).
  static Future<SecretBox> encryptBytes(List<int> clear,
      {required List<int> key, required List<int> nonce, List<int> aad = const []}) async {
    final (h, ej0) = await _hAndJ0(key, nonce);
    final ctr = await _stream(key, nonce, 2, encrypt: true);
    final out = Uint8List.fromList(
        ctr.convertChunkSync(Uint8List.fromList(clear)));
    final g = GcmHash(h)..addPadded(aad);
    g.add(out, 0, out.length);
    final tag = _xor16(g.finish(aad.length, out.length), ej0);
    return SecretBox(out, nonce: nonce, mac: Mac(tag));
  }

  static Future<List<int>> decryptBytes(SecretBox box,
      {required List<int> key, List<int> aad = const []}) async {
    final (h, ej0) = await _hAndJ0(key, box.nonce);
    final g = GcmHash(h)..addPadded(aad);
    g.add(box.cipherText, 0, box.cipherText.length);
    final tag = _xor16(g.finish(aad.length, box.cipherText.length), ej0);
    if (!_same(tag, box.mac.bytes)) throw SecretBoxAuthenticationError();
    final ctr = await _stream(key, box.nonce, 2, encrypt: false);
    return Uint8List.fromList(
        ctr.convertChunkSync(Uint8List.fromList(box.cipherText)));
  }

  /// Unlocks [protectedPath] (magic | nonce len | mac len | nonce | mac |
  /// cipher text) into [viewPath]. The plain part is written as it goes;
  /// a wrong check sum deletes it and throws [SecretBoxAuthenticationError].
  static Future<void> decryptFile(String protectedPath, String viewPath,
      List<int> key, List<int> magic, {GcmProgress? progress}) async {
    final input = await File(protectedPath).open();
    RandomAccessFile? output;
    var ok = false;
    try {
      final total = await input.length();
      final head = await input.read(magic.length + 2);
      if (head.length < magic.length + 2) {
        throw const FormatException('invalid protected local file');
      }
      for (var i = 0; i < magic.length; i++) {
        if (head[i] != magic[i]) {
          throw const FormatException('invalid protected local file');
        }
      }
      final nonceLen = head[magic.length];
      final macLen = head[magic.length + 1];
      final start = magic.length + 2 + nonceLen + macLen;
      if (nonceLen < 8 || macLen < 12 || total <= start) {
        throw const FormatException('invalid protected local file envelope');
      }
      if (nonceLen != nonceLength || macLen != macLength) {
        throw UnsupportedError('parts: nonce $nonceLen mac $macLen');
      }
      final nonce = await input.read(nonceLen);
      final mac = await input.read(macLen);
      final cipherLen = total - start;
      final (h, ej0) = await _hAndJ0(key, nonce);
      final g = GcmHash(h)..addPadded(magic);
      final ctr = await _stream(key, nonce, 2, encrypt: false);
      output = await File(viewPath).open(mode: FileMode.writeOnly);
      var done = 0;
      progress?.call(0, cipherLen);
      while (done < cipherLen) {
        final want = cipherLen - done < partBytes ? cipherLen - done : partBytes;
        final part = await input.read(want);
        if (part.length != want) throw const FileSystemException('short read');
        g.add(part, 0, part.length);
        final plain = ctr.convertChunkSync(part, possibleBuffer: part);
        await output.writeFrom(plain);
        done += want;
        progress?.call(done, cipherLen);
      }
      final tag = _xor16(g.finish(magic.length, cipherLen), ej0);
      if (!_same(tag, mac)) throw SecretBoxAuthenticationError();
      await output.flush();
      ok = true;
    } finally {
      await input.close();
      await output?.close();
      if (!ok) {
        try {
          await File(viewPath).delete();
        } catch (_) {}
      }
    }
  }

  /// Locks [sourcePath] into [partPath] in the same format.
  static Future<void> encryptFile(String sourcePath, String partPath,
      List<int> key, List<int> magic, List<int> nonce,
      {GcmProgress? progress}) async {
    if (nonce.length != nonceLength) throw ArgumentError('nonce');
    final input = await File(sourcePath).open();
    final output = await File(partPath).open(mode: FileMode.writeOnly);
    try {
      final total = await input.length();
      final (h, ej0) = await _hAndJ0(key, nonce);
      final g = GcmHash(h)..addPadded(magic);
      final ctr = await _stream(key, nonce, 2, encrypt: true);
      // Header with a zero mac first; the real mac is written at the end.
      await output.writeFrom(magic);
      await output.writeFrom([nonceLength, macLength]);
      await output.writeFrom(nonce);
      final macAt = await output.position();
      await output.writeFrom(Uint8List(macLength));
      var done = 0;
      progress?.call(0, total);
      while (done < total) {
        final want = total - done < partBytes ? total - done : partBytes;
        final part = await input.read(want);
        if (part.length != want) throw const FileSystemException('short read');
        final cipher = ctr.convertChunkSync(part, possibleBuffer: part);
        g.add(cipher, 0, cipher.length);
        await output.writeFrom(cipher);
        done += want;
        progress?.call(done, total);
      }
      final tag = _xor16(g.finish(magic.length, total), ej0);
      await output.setPosition(macAt);
      await output.writeFrom(tag);
      await output.flush();
    } finally {
      await input.close();
      await output.close();
    }
  }
}
