import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:locallink/core/services/app_logger.dart';
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
    AppLogger.info(
      'WS_CONNECT_REQUEST',
      detail: _safeUrl(url),
    );

    if (_channel != null && _url == url && !_manualDisconnect) {
      if (_ready) {
        AppLogger.info(
          'WS_ALREADY_CONNECTED',
          detail: _safeUrl(url),
        );
        return;
      }

      final pending = _readyCompleter;

      if (pending != null) {
        try {
          await pending.future.timeout(_readyTimeout);
        } catch (error, stackTrace) {
          AppLogger.error(
            'WS_WAIT_READY_FAILED',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }

      return;
    }

    if (_channel != null && _url != url) {
      AppLogger.info(
        'WS_URL_CHANGED',
        detail: _safeUrl(url),
      );

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

    AppLogger.info(
      'WS_OPEN_START',
      detail: 'generation=$generation ${_safeUrl(url)}',
    );

    try {
      await _subscription?.cancel();
      _subscription = null;

      final channel = IOWebSocketChannel.connect(
        Uri.parse(url),
        headers: _headers,
      );

      _channel = channel;

      AppLogger.info(
        'WS_SOCKET_CREATED',
        detail: 'generation=$generation',
      );

      _subscription = channel.stream.listen(
            (event) => _handleEvent(generation, event),
        onDone: () {
          AppLogger.warning(
            'WS_STREAM_DONE',
            detail: 'generation=$generation',
          );

          _handleClosed(generation);
        },
        onError: (Object error, StackTrace stackTrace) {
          AppLogger.error(
            'WS_STREAM_ERROR',
            error: error,
            stackTrace: stackTrace,
            detail: 'generation=$generation',
          );

          _handleClosed(
            generation,
            error: error,
          );
        },
        cancelOnError: true,
      );
    } catch (error, stackTrace) {
      _opening = false;

      AppLogger.error(
        'WS_OPEN_FAILED',
        error: error,
        stackTrace: stackTrace,
        detail: 'generation=$generation ${_safeUrl(url)}',
      );

      _handleClosed(
        generation,
        error: error,
      );

      if (waitForReady) {
        final pending = _readyCompleter;

        if (pending != null && !pending.isCompleted) {
          try {
            await pending.future;
          } catch (_) {
            // The original connection error has already been logged.
          }
        }
      }

      return;
    }

    _opening = false;

    AppLogger.info(
      'WS_OPENED_WAITING_READY',
      detail: 'generation=$generation',
    );

    if (waitForReady) {
      final pending = _readyCompleter;

      if (pending != null) {
        try {
          await pending.future.timeout(_readyTimeout);
        } on TimeoutException catch (error, stackTrace) {
          AppLogger.error(
            'WS_READY_TIMEOUT',
            error: error,
            stackTrace: stackTrace,
            detail: 'generation=$generation',
          );

          if (generation == _generation) {
            _handleClosed(
              generation,
              error: StateError('WebSocket ready timeout'),
            );
          }

          rethrow;
        } catch (error, stackTrace) {
          AppLogger.error(
            'WS_READY_FAILED',
            error: error,
            stackTrace: stackTrace,
            detail: 'generation=$generation',
          );

          rethrow;
        }
      }
    }
  }

  void _handleEvent(
      int generation,
      dynamic event,
      ) {
    if (generation != _generation) {
      AppLogger.warning(
        'WS_STALE_EVENT_IGNORED',
        detail:
        'eventGeneration=$generation currentGeneration=$_generation',
      );
      return;
    }

    if (event is! String) {
      AppLogger.warning(
        'WS_NON_STRING_FRAME',
        detail: 'type=${event.runtimeType}',
      );
      return;
    }

    AppLogger.info(
      'WS_FRAME_RECEIVED',
      detail: 'bytes=${utf8.encode(event).length}',
    );

    try {
      final decoded = jsonDecode(event);

      if (decoded is! Map) {
        AppLogger.warning(
          'WS_INVALID_FRAME_TYPE',
          detail: 'decoded=${decoded.runtimeType}',
        );
        return;
      }

      final value = Map<String, dynamic>.from(decoded);

      final type = value['type']?.toString() ?? 'unknown';
      final id = value['id']?.toString();

      AppLogger.info(
        'WS_MESSAGE_RECEIVED',
        detail:
        'type=$type'
            '${id == null || id.isEmpty ? '' : ' id=$id'}',
      );

      if (type == 'ready') {
        _markReady(generation);
        return;
      }

      _messages.add(value);
    } catch (error, stackTrace) {
      AppLogger.error(
        'WS_FRAME_DECODE_FAILED',
        error: error,
        stackTrace: stackTrace,
        detail: 'bytes=${utf8.encode(event).length}',
      );

      // Malformed server frames are ignored; the transport remains alive.
    }
  }

  void _markReady(int generation) {
    if (
    generation != _generation ||
        _manualDisconnect ||
        _channel == null) {
      return;
    }

    final wasReady = _ready;

    _ready = true;

    AppLogger.info(
      'WS_READY',
      detail:
      'generation=$generation '
          'wasReady=$wasReady '
          'queued=${_durableQueue.length}',
    );

    if (!wasReady) {
      _state.add(true);
    }

    final pending = _readyCompleter;

    _readyCompleter = null;

    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }

    _stabilityTimer?.cancel();

    _stabilityTimer = Timer(
      _stableConnectionWindow,
          () {
        if (generation == _generation && _ready) {
          _reconnectAttempt = 0;

          AppLogger.info(
            'WS_CONNECTION_STABLE',
            detail: 'generation=$generation',
          );
        }
      },
    );

    _flushDurableQueue();
  }

  bool send(
      Map<String, dynamic> payload, {
        bool durable = false,
      }) {
    final type = payload['type']?.toString() ?? 'unknown';
    final id = payload['id']?.toString();

    AppLogger.info(
      'WS_SEND_REQUEST',
      detail:
      'type=$type'
          '${id == null || id.isEmpty ? '' : ' id=$id'} '
          'durable=$durable '
          'connected=$_ready',
    );

    late final String encoded;

    try {
      encoded = jsonEncode(payload);
    } catch (error, stackTrace) {
      AppLogger.error(
        'WS_SEND_ENCODE_FAILED',
        error: error,
        stackTrace: stackTrace,
        detail: 'type=$type',
      );

      return false;
    }

    final payloadBytes = utf8.encode(encoded).length;

    if (payloadBytes > _maxPayloadBytes) {
      AppLogger.warning(
        'WS_SEND_PAYLOAD_TOO_LARGE',
        detail:
        'type=$type bytes=$payloadBytes '
            'max=$_maxPayloadBytes',
      );

      return false;
    }

    final channel = _channel;

    if (!_ready || channel == null) {
      if (!durable) {
        AppLogger.warning(
          'WS_SEND_REJECTED_NOT_CONNECTED',
          detail:
          'type=$type '
              '${id == null || id.isEmpty ? '' : 'id=$id'}',
        );

        return false;
      }

      _enqueueDurable(payload);

      AppLogger.info(
        'WS_SEND_QUEUED',
        detail:
        'type=$type '
            '${id == null || id.isEmpty ? '' : 'id=$id'} '
            'queue=${_durableQueue.length}',
      );

      return true;
    }

    try {
      channel.sink.add(encoded);

      AppLogger.info(
        'WS_SEND_SUCCESS',
        detail:
        'type=$type '
            '${id == null || id.isEmpty ? '' : 'id=$id'} '
            'bytes=$payloadBytes',
      );

      return true;
    } catch (error, stackTrace) {
      AppLogger.error(
        'WS_SEND_FAILED',
        error: error,
        stackTrace: stackTrace,
        detail:
        'type=$type '
            '${id == null || id.isEmpty ? '' : 'id=$id'}',
      );

      if (durable) {
        _enqueueDurable(payload);

        AppLogger.info(
          'WS_SEND_REQUEUED',
          detail:
          'type=$type '
              '${id == null || id.isEmpty ? '' : 'id=$id'}',
        );
      }

      _handleClosed(
        _generation,
        error: error,
      );

      return durable;
    }
  }

  void _enqueueDurable(
      Map<String, dynamic> payload,
      ) {
    if (_durableQueue.length >= _maxQueuedDurableMessages) {
      final removed = _durableQueue.removeAt(0);

      AppLogger.warning(
        'WS_DURABLE_QUEUE_DROPPED_OLDEST',
        detail:
        'type=${removed['type']?.toString() ?? 'unknown'} '
            'id=${removed['id']?.toString() ?? ''}',
      );
    }

    _durableQueue.add(
      Map<String, dynamic>.from(payload),
    );

    AppLogger.info(
      'WS_DURABLE_QUEUE_ADD',
      detail:
      'type=${payload['type']?.toString() ?? 'unknown'} '
          'id=${payload['id']?.toString() ?? ''} '
          'size=${_durableQueue.length}',
    );
  }

  void _flushDurableQueue() {
    final channel = _channel;

    if (!_ready || channel == null || _durableQueue.isEmpty) {
      return;
    }

    AppLogger.info(
      'WS_DURABLE_QUEUE_FLUSH_START',
      detail: 'count=${_durableQueue.length}',
    );

    while (_ready && _durableQueue.isNotEmpty) {
      final payload = _durableQueue.first;

      late final String encoded;

      try {
        encoded = jsonEncode(payload);
      } catch (error, stackTrace) {
        AppLogger.error(
          'WS_QUEUE_ENCODE_FAILED',
          error: error,
          stackTrace: stackTrace,
          detail:
          'type=${payload['type']?.toString() ?? 'unknown'} '
              'id=${payload['id']?.toString() ?? ''}',
        );

        _durableQueue.removeAt(0);
        continue;
      }

      try {
        channel.sink.add(encoded);

        _durableQueue.removeAt(0);

        AppLogger.info(
          'WS_QUEUE_MESSAGE_SENT',
          detail:
          'type=${payload['type']?.toString() ?? 'unknown'} '
              'id=${payload['id']?.toString() ?? ''} '
              'remaining=${_durableQueue.length}',
        );
      } catch (error, stackTrace) {
        AppLogger.error(
          'WS_QUEUE_SEND_FAILED',
          error: error,
          stackTrace: stackTrace,
          detail:
          'type=${payload['type']?.toString() ?? 'unknown'} '
              'id=${payload['id']?.toString() ?? ''}',
        );

        _handleClosed(
          _generation,
          error: error,
        );

        return;
      }
    }

    AppLogger.info(
      'WS_DURABLE_QUEUE_FLUSH_COMPLETE',
      detail: 'remaining=${_durableQueue.length}',
    );
  }

  void _handleClosed(
      int generation, {
        Object? error,
      }) {
    if (generation != _generation) {
      return;
    }

    AppLogger.warning(
      'WS_CLOSED',
      detail:
      'generation=$generation '
          'error=${error == null ? 'none' : error.runtimeType}',
    );

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

    unawaited(
      oldSubscription?.cancel(),
    );

    unawaited(
      oldChannel?.sink.close(),
    );

    if (wasActive) {
      _state.add(false);

      AppLogger.info(
        'WS_CONNECTION_STATE',
        detail: 'connected=false',
      );
    }

    if (_manualDisconnect) {
      AppLogger.info(
        'WS_NO_RECONNECT_MANUAL_DISCONNECT',
      );
      return;
    }

    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (
    _manualDisconnect ||
        _url == null ||
        _reconnectTimer != null) {
      return;
    }

    final exponent = min(_reconnectAttempt, 4);
    final baseSeconds = min(
      30,
      3 * (1 << exponent),
    );

    _reconnectAttempt++;

    final jitterMillis = _random.nextInt(2001);

    final delay = Duration(
      seconds: baseSeconds,
      milliseconds: jitterMillis,
    );

    AppLogger.info(
      'WS_RECONNECT_SCHEDULED',
      detail:
      'attempt=$_reconnectAttempt '
          'delayMs=${delay.inMilliseconds}',
    );

    _reconnectTimer = Timer(
      delay,
          () {
        _reconnectTimer = null;

        AppLogger.info(
          'WS_RECONNECT_ATTEMPT',
          detail: 'attempt=$_reconnectAttempt',
        );

        unawaited(
          _open(waitForReady: false),
        );
      },
    );
  }

  Future<void> disconnect() async {
    AppLogger.info(
      'WS_DISCONNECT_REQUEST',
    );

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
      pending.completeError(
        StateError('WebSocket disconnected'),
      );
    }

    final oldSubscription = _subscription;
    final oldChannel = _channel;

    _subscription = null;
    _channel = null;

    await oldSubscription?.cancel();
    await oldChannel?.sink.close();

    _state.add(false);

    AppLogger.info(
      'WS_DISCONNECTED',
    );
  }

  void dispose() {
    AppLogger.info(
      'WS_DISPOSE',
    );

    _manualDisconnect = true;

    _reconnectTimer?.cancel();
    _stabilityTimer?.cancel();

    _reconnectTimer = null;
    _stabilityTimer = null;

    _generation++;

    unawaited(
      _subscription?.cancel(),
    );

    unawaited(
      _channel?.sink.close(),
    );

    _subscription = null;
    _channel = null;
    _ready = false;

    final pending = _readyCompleter;

    _readyCompleter = null;

    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        StateError('WebSocket service disposed'),
      );
    }

    _messages.close();
    _state.close();
  }

  String _safeUrl(String value) {
    try {
      final uri = Uri.parse(value);

      return Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path,
      ).toString();
    } catch (_) {
      return '<invalid-url>';
    }
  }
}