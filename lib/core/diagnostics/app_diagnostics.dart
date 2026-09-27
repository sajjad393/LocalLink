import 'dart:convert';

/// Bounded, in-memory operational diagnostics for the local client.
///
/// Diagnostics are deliberately aggregate-only. Event fields use an allowlist
/// and no message bodies, credentials, phone numbers, file paths, device IDs,
/// usernames, ciphertext or request payloads are retained.
final class AppDiagnosticsEvent {
  final DateTime at;
  final String category;
  final String event;
  final Map<String, Object?> data;

  const AppDiagnosticsEvent({
    required this.at,
    required this.category,
    required this.event,
    required this.data,
  });

  Map<String, Object?> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'category': category,
        'event': event,
        if (data.isNotEmpty) 'data': data,
      };
}

final class AppDiagnostics {
  AppDiagnostics._();

  static final AppDiagnostics instance = AppDiagnostics._();

  static const int maxEvents = 300;
  static const int maxCounters = 96;
  static const int maxStringLength = 64;

  static const Set<String> _allowedKeys = {
    'status',
    'state',
    'transport',
    'quality',
    'reason_code',
    'error_type',
    'failure_class',
    'app_state',
    'connected',
    'ready',
    'enabled',
    'attempt',
    'count',
    'bytes',
    'duration_ms',
    'queue_packets',
    'queue_bytes',
    'peer_count',
    'route_count',
    'send_failures',
    'packets_sent',
    'packets_received',
    'active_transfers',
    'completed_transfers',
    'failed_transfers',
    'cancelled_transfers',
    'request_status',
  };

  final List<AppDiagnosticsEvent> _events = <AppDiagnosticsEvent>[];
  final Map<String, int> _counters = <String, int>{};
  int _droppedEvents = 0;

  List<AppDiagnosticsEvent> get events => List.unmodifiable(_events);

  Map<String, int> get counters => Map.unmodifiable(_counters);

  int get droppedEvents => _droppedEvents;

  void record(
    String category,
    String event, {
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    final safeCategory = _key(category);
    final safeEvent = _key(event);
    if (safeCategory.isEmpty || safeEvent.isEmpty) return;

    final safeData = _sanitizeData(data);
    final counterKey = '$safeCategory.$safeEvent';
    if (_counters.containsKey(counterKey) || _counters.length < maxCounters) {
      _counters[counterKey] = (_counters[counterKey] ?? 0) + 1;
    }

    if (_events.length >= maxEvents) {
      _events.removeAt(0);
      _droppedEvents++;
    }
    _events.add(
      AppDiagnosticsEvent(
        at: DateTime.now().toUtc(),
        category: safeCategory,
        event: safeEvent,
        data: safeData,
      ),
    );
  }

  void recordException(
    String category,
    String event,
    Object error, {
    String reasonCode = 'exception',
  }) {
    record(
      category,
      event,
      data: <String, Object?>{
        'error_type': error.runtimeType.toString(),
        'reason_code': reasonCode,
      },
    );
  }

  Map<String, Object?> snapshot() {
    return <String, Object?>{
      'schema': 1,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'retention': <String, Object?>{
        'max_events': maxEvents,
        'max_counters': maxCounters,
      },
      'dropped_events': _droppedEvents,
      'counters': Map<String, int>.from(_counters),
      'recent_events': _events.map((event) => event.toJson()).toList(growable: false),
    };
  }

  String exportJson({bool pretty = true}) {
    const encoder = JsonEncoder.withIndent('  ');
    return pretty ? encoder.convert(snapshot()) : jsonEncode(snapshot());
  }

  void clear() {
    _events.clear();
    _counters.clear();
    _droppedEvents = 0;
  }

  Map<String, Object?> _sanitizeData(Map<String, Object?> input) {
    final out = <String, Object?>{};
    for (final entry in input.entries) {
      if (!_allowedKeys.contains(entry.key) || out.length >= 16) continue;
      final value = entry.value;
      if (value is bool || value is int) {
        out[entry.key] = value;
      } else if (value is double && value.isFinite) {
        out[entry.key] = value.clamp(-1000000000, 1000000000);
      } else if (value is String) {
        final token = _token(value);
        if (token.isNotEmpty) out[entry.key] = token;
      }
    }
    return out;
  }

  String _key(String value) {
    final compact = value.trim().toLowerCase();
    if (compact.isEmpty || compact.length > maxStringLength) return '';
    if (!RegExp(r'^[a-z0-9][a-z0-9_.-]*$').hasMatch(compact)) return '';
    return compact;
  }

  String _token(String value) {
    final compact = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.length <= maxStringLength) return compact;
    return '${compact.substring(0, maxStringLength)}…';
  }
}
