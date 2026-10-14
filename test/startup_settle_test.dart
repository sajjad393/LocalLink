import 'dart:async';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_diagnostics.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/messaging/data/services/reliable_messaging_service.dart';

import 'support/phase5_fakes.dart';

final class _ConfiguredStore extends FakeStore {
  // A configured-but-dead server forces the initial sync branch to run.
  @override
  String? get serverAddress => 'http://127.0.0.1:1';

  // synchronize() skips work without a device token; pretend we have one.
  @override
  String? get deviceToken => 'test-device-token';
}

void main() {
  test('startup settle defers the initial sync burst past the launch window',
      () async {
    AppDiagnostics.instance.clear();
    final store = _ConfiguredStore();
    final transport = FakePeerTransport();
    final service = ReliableMessagingService(
      store,
      LocalLinkApi(store, WebSocketService()),
      WebSocketService(),
      FakeFilesRepository(),
      FakeConnectivity(),
      transport,
      startupSettle: const Duration(milliseconds: 400),
    );

    // The dead target server makes the realtime connect fail asynchronously;
    // that is the exact failure pattern being deferred, so collect instead
    // of letting the test zone treat it as an unexpected error.
    final asyncErrors = <Object>[];
    await runZonedGuarded(() async {
      service.start();

      var events = AppDiagnostics.instance.events;
      expect(events.any((e) => e.event == 'message_sync_start'), isFalse,
          reason: 'with a settle delay the initial burst must not fire immediately');
      expect(events.any((e) => e.event == 'message_startup_settle'), isTrue,
          reason: 'the settle itself is recorded');

      await Future<void>.delayed(const Duration(milliseconds: 900));

      events = AppDiagnostics.instance.events;
      expect(events.any((e) => e.event == 'message_sync_start'), isTrue,
          reason: 'the initial burst fires once the settle window passes');
    }, (error, stack) => asyncErrors.add(error));

    await service.dispose();
    await transport.dispose();
    expect(
      asyncErrors.every((e) => e is SocketException || e is WebSocketChannelException),
      isTrue,
      reason: 'the only tolerated async failure is the connected-but-dead server',
    );
  });
}
