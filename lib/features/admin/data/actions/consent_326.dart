import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Bundle 326: "the answering phone gets a say".
///
/// Today the phone that HAS the chat starts pushing a file the moment somebody
/// asks - the owner finds out afterwards. With 326 the answering phone asks its
/// owner first ("Ali asks for this file · 61 MB") and only then do the bytes
/// leave the phone.
///
/// Everything here is on this phone: no server, no internet. Nothing expires -
/// an ask that is never answered simply stays waiting, and Stop removes the
/// request on the other side as it always did.
enum Consent326Verdict {
  /// Go ahead: either it is small enough to not be worth asking about, or the
  /// owner already said Send (or Wi-Fi only, and we are on Wi-Fi).
  go,

  /// Asked, not answered yet. The answer waits and is tried again later - it
  /// is never thrown away.
  waiting,

  /// The owner said no. The asking phone's card says so, in grey.
  no,
}

/// One question waiting for the owner of THIS phone.
class ConsentAsk326 {
  const ConsentAsk326({
    required this.id,
    required this.requestId,
    required this.madeAt,
    this.label = '',
    this.name = '',
    this.kind = '',
    this.bytes = 0,
  });

  /// `requestId:file` - one question per request and file.
  final String id;
  final String requestId;

  /// Who is asking (the chat label), the file, its kind and its size.
  final String label;
  final String name;
  final String kind;
  final int bytes;
  final String madeAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'request_id': requestId,
        'label': label,
        'name': name,
        'kind': kind,
        'bytes': bytes,
        'made_at': madeAt,
      };

  static ConsentAsk326? fromJson(Object? x) {
    if (x is! Map) return null;
    final id = x['id']?.toString() ?? '';
    final req = x['request_id']?.toString() ?? '';
    if (id.isEmpty || req.isEmpty) return null;
    return ConsentAsk326(
      id: id,
      requestId: req,
      label: x['label']?.toString() ?? '',
      name: x['name']?.toString() ?? '',
      kind: x['kind']?.toString() ?? '',
      bytes: switch (x['bytes']) {
        final int n => n,
        final Object n => int.tryParse('$n') ?? 0,
        _ => 0,
      },
      madeAt: x['made_at']?.toString() ?? '',
    );
  }
}

/// The decisions of the owner of this phone, and the questions still waiting.
abstract final class Consent326 {
  static const String go = 'go';
  static const String wifi = 'wifi';
  static const String no = 'no';

  /// Under this size nobody is asked: a 200 KB photo is not worth a tap.
  static const int minAskBytes = 5 * 1024 * 1024;

  /// This phone's own store (prefs), wired in `app_dependencies.dart`.
  static const String storeKey = 'consent_326';
  static const String asksKey = 'consent_asks_326';
  static Future<String?> Function(String key)? read;
  static Future<void> Function(String key, String value)? write;

  /// True while this phone is on Wi-Fi / LAN (the Wi-Fi-only answer).
  static bool Function()? onWifi;

  /// The questions waiting for the owner, newest last. The app shows them.
  static final ValueNotifier<List<ConsentAsk326>> asks = ValueNotifier(const []);

  /// requestId -> go | wifi | no
  static final Map<String, String> _decided = {};

  static bool _loaded = false;

  /// One answer per request while the app runs; the store keeps it anyway.
  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await read?.call(storeKey);
      if (raw != null && raw.isNotEmpty) {
        final d = jsonDecode(raw);
        if (d is Map) {
          for (final e in d.entries) {
            final v = e.value?.toString() ?? '';
            if (v == go || v == wifi || v == no) _decided[e.key.toString()] = v;
          }
        }
      }
    } catch (_) {
      // A broken store means "ask again", never "answer for them".
    }
    try {
      final raw = await read?.call(asksKey);
      if (raw != null && raw.isNotEmpty) {
        final d = jsonDecode(raw);
        final list = [
          for (final x in (d is List ? d : const []))
            if (ConsentAsk326.fromJson(x) case final a?) a,
        ];
        if (list.isNotEmpty) asks.value = list;
      }
    } catch (_) {}
  }

  static Future<void> _save() async {
    try {
      await write?.call(storeKey, jsonEncode(_decided));
      await write?.call(
          asksKey, jsonEncode([for (final a in asks.value) a.toJson()]));
    } catch (_) {}
  }

  /// What to do with an answer of [bytes] for [requestId] - before one byte
  /// leaves this phone.
  ///
  /// * small (under [minAskBytes]) -> go, nobody is asked;
  /// * the owner already decided -> that decision (Wi-Fi only waits off Wi-Fi);
  /// * otherwise the question is put in [asks] once and this answer waits.
  static Future<Consent326Verdict> verdict({
    required String requestId,
    required int bytes,
    String label = '',
    String name = '',
    String kind = '',
    String fileKey = '',
    DateTime Function()? clock,
  }) async {
    if (bytes < minAskBytes) return Consent326Verdict.go;
    await _ensureLoaded();
    final d = _decided[requestId];
    if (d == no) return Consent326Verdict.no;
    if (d == go) return Consent326Verdict.go;
    if (d == wifi) {
      return (onWifi?.call() ?? true)
          ? Consent326Verdict.go
          : Consent326Verdict.waiting; // 325 rule: it waits, it never expires
    }
    final id = fileKey.isEmpty ? requestId : '$requestId:$fileKey';
    if (!asks.value.any((a) => a.id == id)) {
      asks.value = [
        ...asks.value,
        ConsentAsk326(
          id: id,
          requestId: requestId,
          label: label,
          name: name,
          kind: kind,
          bytes: bytes,
          madeAt: (clock ?? DateTime.now)().toUtc().toIso8601String(),
        ),
      ];
      await _save();
    }
    return Consent326Verdict.waiting;
  }

  /// The owner tapped Send / Wi-Fi only / No on [id].
  static Future<void> decide(String id, String decision) async {
    await _ensureLoaded();
    final ask = asks.value.where((a) => a.id == id).firstOrNull;
    if (ask == null) return;
    if (decision == go || decision == wifi || decision == no) {
      _decided[ask.requestId] = decision;
    }
    asks.value = [
      for (final a in asks.value)
        if (a.id != id) a,
    ];
    await _save();
  }

  /// "61 MB" / "800 KB" - the same shape the rest of the app uses.
  static String sizeWords(int bytes) {
    if (bytes >= 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return '${mb >= 100 ? mb.round() : mb.toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }

  @visibleForTesting
  static void resetForTest() {
    _decided.clear();
    _loaded = false;
    asks.value = const [];
  }
}
