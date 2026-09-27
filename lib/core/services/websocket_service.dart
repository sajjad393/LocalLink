import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  static const _readyTimeout = Duration(seconds: 8);
  static const _stableConnectionWindow = Duration(seconds: 10);
  static const _maxQueuedDurableMessages = 256;
  static const _maxPayloadBytes = 64 * 1024;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _state = StreamController<bool>.broadcast();
  Timer? _reconnectTimer;
  Timer? _stabilityTimer;
  Completer<void>? _readyCompleter;
  String? _url;
  Map<String, String> _headers = const {};
  bool _manualDisconnect = false;
  bool _opening = false;
  bool _ready = false;
  int _reconnectAttempt = 0;
  int _generation = 0;
  final List<Map<String, dynamic>> _durableQueue = [];
  final Random _random = Random();

  Stream<Map<String, dynamic>> get messages => _messages.stream;
  Stream<bool> get connectionState => _state.stream;
  bool get isConnected => _ready;

  Future<void> connect(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    if (_channel != null && _url == url && !_manualDisconnect) {
      if (_ready) return;
      final pending = _readyCompleter;
      if (pending != null) {
        await pending.future.timeout(_readyTimeout);
      }
      return;
    }

    if (_channel != null && _url != url) {
      await disconnect();
    }

    _manualDisconnect = false;
    _url = url;
    _headers = Map<String, String>.from(headers);
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _open(waitForReady: true);
  }

  Future<void> _open({required bool waitForReady}) async {
    final url = _url;
    if (url == null || _manualDisconnect || _opening || _channel != null) {
      return;
    }

    _opening = true;
    _ready = false;
    _readyCompleter = waitForReady ? Completer<void>() : null;
    final generation = ++_generation;

    try {
      await _subscription?.cancel();
      _subscription = null;
      final channel = IOWebSocketChannel.connect(
        Uri.parse(url),
        headers: _headers,
      );
      _channel = channel;
      _subscription = channel.stream.listen(
        (event) => _handleEvent(generation, event),
        onDone: () => _handleClosed(generation),
        onError: (_) => _handleClosed(generation),
        cancelOnError: true,
      );
    } catch (error) {
      _opening = false;
      _handleClosed(generation, error: error);
      if (waitForReady) {
        final pending = _readyCompleter;
        if (pending != null && !pending.isCompleted) {
          await pending.future;
        }
      }
      return;
    }

    _opening = false;

    if (waitForReady) {
      final pending = _readyCompleter;
      if (pending != null) {
        try {
          await pending.future.timeout(_readyTimeout);
        } on TimeoutException {
          if (generation == _generation) {
            _handleClosed(generation,
                error: StateError('WebSocket ready timeout'));
          }
          rethrow;
        }
      }
    }
  }

  void _handleEvent(int generation, dynamic event) {
    if (generation != _generation) return;
    if (event is! String) return;

    try {
      final value = jsonDecode(event);
      if (value is! Map<String, dynamic>) return;

      if (value['type'] == 'ready') {
        _markReady(generation);
        return;
      }

      _messages.add(value);
    } catch (_) {
      // Malformed server frames are ignored; the transport remains alive.
    }
  }

  void _markReady(int generation) {
    if (generation != _generation || _manualDisconnect || _channel == null) {
      return;
    }

    final wasReady = _ready;
    _ready = true;
    if (!wasReady) _state.add(true);

    final pending = _readyCompleter;
    _readyCompleter = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }

    _stabilityTimer?.cancel();
    _stabilityTimer = Timer(_stableConnectionWindow, () {
      if (generation == _generation && _ready) {
        _reconnectAttempt = 0;
      }
    });

    _flushDurableQueue();
  }

  bool send(
    Map<String, dynamic> payload, {
    bool durable = false,
  }) {
    late final String encoded;
    try {
      encoded = jsonEncode(payload);
    } catch (_) {
      return false;
    }
    if (utf8.encode(encoded).length > _maxPayloadBytes) {
      return false;
    }

    final channel = _channel;
    if (!_ready || channel == null) {
      if (!durable) return false;
      _enqueueDurable(payload);
      return true;
    }

    try {
      channel.sink.add(encoded);
      return true;
    } catch (_) {
      if (durable) _enqueueDurable(payload);
      _handleClosed(_generation);
      return durable;
    }
  }

  void _enqueueDurable(Map<String, dynamic> payload) {
    if (_durableQueue.length >= _maxQueuedDurableMessages) {
      _durableQueue.removeAt(0);
    }
    _durableQueue.add(Map<String, dynamic>.from(payload));
  }

  void _flushDurableQueue() {
    final channel = _channel;
    if (!_ready || channel == null || _durableQueue.isEmpty) return;

    while (_ready && _durableQueue.isNotEmpty) {
      final payload = _durableQueue.first;
      final encoded = jsonEncode(payload);
      try {
        channel.sink.add(encoded);
        _durableQueue.removeAt(0);
      } catch (_) {
        _handleClosed(_generation);
        return;
      }
    }
  }

  void _handleClosed(int generation, {Object? error}) {
    if (generation != _generation) return;

    final wasActive = _channel != null || _ready;
    _ready = false;
    _opening = false;
    _stabilityTimer?.cancel();
    _stabilityTimer = null;

    final pending = _readyCompleter;
    _readyCompleter = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        error ?? StateError('WebSocket connection closed'),
      );
    }

    final oldSubscription = _subscription;
    final oldChannel = _channel;
    _subscription = null;
    _channel = null;
    unawaited(oldSubscription?.cancel());
    unawaited(oldChannel?.sink.close());

    if (wasActive) _state.add(false);
    if (_manualDisconnect) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _url == null || _reconnectTimer != null) return;

    final exponent = min(_reconnectAttempt, 4);
    final baseSeconds = min(30, 3 * (1 << exponent));
    _reconnectAttempt++;
    final jitterMillis = _random.nextInt(2001);
    _reconnectTimer = Timer(
      Duration(seconds: baseSeconds, milliseconds: jitterMillis),
      () {
        _reconnectTimer = null;
        unawaited(_open(waitForReady: false));
      },
    );
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stabilityTimer?.cancel();
    _stabilityTimer = null;
    _generation++;
    _ready = false;
    _opening = false;

    final pending = _readyCompleter;
    _readyCompleter = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('WebSocket disconnected'));
    }

    final oldSubscription = _subscription;
    final oldChannel = _channel;
    _subscription = null;
    _channel = null;
    await oldSubscription?.cancel();
    await oldChannel?.sink.close();
    _state.add(false);
  }

  void dispose() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _stabilityTimer?.cancel();
    _reconnectTimer = null;
    _stabilityTimer = null;
    _generation++;
    unawaited(_subscription?.cancel());
    unawaited(_channel?.sink.close());
    _subscription = null;
    _channel = null;
    _ready = false;
    final pending = _readyCompleter;
    _readyCompleter = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('WebSocket service disposed'));
    }
    _messages.close();
    _state.close();
  }
}
