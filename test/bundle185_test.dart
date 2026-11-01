// Bundle 185: ZTE problems - killed in the background, slow open,
// SEAL not_ready. See TODO_185.md (A-D).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/startup_timer.dart';
import 'package:locallink/core/security/secure_storage_service.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/memory_trim.dart';
import 'package:locallink/core/services/message_seal_service.dart';
import 'package:locallink/features/connectivity/data/services/sealing_peer_transport.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_controller.dart';
import 'package:locallink/features/home/domain/background_brand_guide.dart';

String _read(String path) => File(path).readAsStringSync();

class _Watch implements Stopwatch {
  int ms = 0;
  @override
  int get elapsedMilliseconds => ms;
  @override
  void start() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<SealKeyPair> _pair(int seed) async => SealKeyPair.from(
      await X25519().newKeyPairFromSeed(List<int>.filled(32, seed)),
    );

class _Inner implements PeerTransportContract {
  final StreamController<Map<String, dynamic>> controller =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<(String, Map<String, dynamic>)> sent = [];

  @override
  Stream<Map<String, dynamic>> get events => controller.stream;

  @override
  Future<void> send({
    required String recipientId,
    required Map<String, dynamic> payload,
  }) async {
    sent.add((recipientId, payload));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Keys implements SealKeySource {
  _Keys(this.selfId, this.own, this.contacts);
  @override
  final String? selfId;
  final List<SealKeyPair> own;
  final Map<String, List<int>> contacts;
  final Map<String, String> settings = {};

  @override
  Future<List<SealKeyPair>> ownKeys() async => own;
  @override
  Future<List<int>?> contactPublicKey(String peerId) async => contacts[peerId];
  @override
  Future<Set<String>> blockedPeerIds() async => const {};
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async =>
      settings[key] = value;
}

Map<String, dynamic> _messageEvent(
        String sender, String self, Map<String, dynamic> payload, String id) =>
    {
      'type': 'message',
      'sender_id': sender,
      'mesh_final_recipient': true,
      'mesh_destination_id': self,
      'payload': jsonEncode({
        ...payload,
        'sender_id': sender,
        'recipient_id': self,
        'mesh_packet_id': id,
        'mesh_path': [sender],
      }),
    };

class _CountingSecure implements SecureStorageService {
  final Map<String, String> data = {};
  int writes = 0;
  @override
  Future<String?> read({required String key}) async => data[key];
  @override
  Future<void> write({required String key, required String value}) async {
    writes++;
    data[key] = value;
  }

  @override
  Future<void> delete({required String key}) async => data.remove(key);
  @override
  Future<Map<String, String>> readAll() async => Map.of(data);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bundle 185 A4 start timer', () {
    test('steps, total and the slowest step', () {
      final w = _Watch();
      final t = StartupTimer(watch: w, log: false);
      w.ms = 120;
      t.step('database');
      w.ms = 150;
      t.step('settings');
      w.ms = 900;
      t.step('keys');
      expect(t.steps.map((s) => s.ms), [120, 30, 750]);
      expect(t.summary(),
          'total_ms=900 slowest=keys:750 steps=database:120,settings:30,keys:750');
    });

    test('no steps still gives a line', () {
      final t = StartupTimer(watch: _Watch(), log: false);
      expect(t.summary(), 'total_ms=0 slowest=- steps=');
    });
  });

  group('Bundle 185 D2 start order', () {
    test('first screen shows before the services start', () async {
      final order = <String>[];
      final t = StartupTimer(watch: _Watch(), log: false);
      await StartupSequence.run(
        timer: t,
        core: () async => order.add('core'),
        showFirstScreen: () => order.add('screen'),
        firstFrame: () async => order.add('frame'),
        rest: () async => order.add('services'),
        servicesReady: () => order.add('ready'),
      );
      expect(order, ['core', 'screen', 'frame', 'services', 'ready']);
      expect(t.steps.map((s) => s.name),
          ['first_screen', 'first_frame', 'services']);
    });

    test('a failing service start is passed up (error screen)', () async {
      var ready = false;
      await expectLater(
        StartupSequence.run(
          timer: StartupTimer(watch: _Watch(), log: false),
          core: () async {},
          showFirstScreen: () {},
          firstFrame: () async {},
          rest: () async => throw StateError('boom'),
          servicesReady: () => ready = true,
        ),
        throwsStateError,
      );
      expect(ready, isFalse);
    });

    test('the app uses the new order and waits for services on taps', () {
      final app = _read('lib/app/local_link_app.dart');
      expect(app, contains('StartupSequence.run('));
      expect(app, contains('firstFrame: () => WidgetsBinding.instance.endOfFrame'));
      expect(app,
          contains('.timeout(const Duration(milliseconds: 1500), onTimeout: () {})'));
      expect(app,
          contains('if (!_ready || !_servicesReady || !_configured || navigator == null)'));
      expect(app, contains("_deps.initializeConfiguredServices(coreDone: true)"));
      expect(app, contains("_deps.initializeLocalOnlyServices(coreDone: true)"));
      final deps = _read('lib/app/app_dependencies.dart');
      expect(deps, contains('if (!coreDone) await initializeCore(localOnly: false);'));
      expect(deps, contains('if (!coreDone) await initializeCore(localOnly: true);'));
    });
  });

  group('Bundle 185 D3 keys start', () {
    test('a second start writes nothing to secure storage', () async {
      final secure = _CountingSecure();
      await IdentityCryptoService(secureStorage: secure).init('dev-1');
      final first = secure.writes;
      expect(first, greaterThan(0));
      secure.writes = 0;
      final again = IdentityCryptoService(secureStorage: secure);
      await again.init('dev-1');
      expect(secure.writes, 0);
      expect(again.keyVersion, 1);
    });
  });

  group('Bundle 185 C held locked messages', () {
    late SealKeyPair yKeys;
    late SealKeyPair zKeys;
    late _Inner yInner;
    late _Inner zInner;
    late SealingPeerTransport yasir;
    late DateTime now;
    late SealingPeerTransport zulfqar;

    setUp(() async {
      yKeys = await _pair(21);
      zKeys = await _pair(22);
      yInner = _Inner();
      zInner = _Inner();
      now = DateTime(2026, 11, 1, 21, 7, 56);
      yasir = SealingPeerTransport(yInner)
        ..bind(_Keys('yasir', [yKeys], {'zulfqar': zKeys.publicKey}));
      // Zulfqar's phone is still starting: no keys yet.
      zulfqar = SealingPeerTransport(zInner, clock: () => now);
      await Future<void>.delayed(Duration.zero);
      final sub = yasir.events.listen((_) {});
      yInner.controller.add({'type': 'peer_connected', 'peer_id': 'zulfqar', 'seal': true});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
    });

    Future<Map<String, dynamic>> sealed(String body) async {
      yInner.sent.clear();
      await yasir.send(
          recipientId: 'zulfqar',
          payload: {'type': 'direct_message', 'body': body});
      final out = yInner.sent.single.$2;
      expect(out['type'], 'sealed');
      return out;
    }

    test('a message before the keys is held, then opened in order', () async {
      final got = <Map<String, dynamic>>[];
      final sub = zulfqar.events.listen(got.add);
      zInner.controller.add(_messageEvent('yasir', 'zulfqar', await sealed('one'), 'p1'));
      zInner.controller.add(_messageEvent('yasir', 'zulfqar', await sealed('two'), 'p2'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(got, isEmpty);
      expect(zulfqar.heldCount, 2);

      now = now.add(const Duration(seconds: 1));
      zulfqar.bind(_Keys('zulfqar', [zKeys], {'yasir': yKeys.publicKey}));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(zulfqar.heldCount, 0);
      final bodies = got
          .map((e) => (jsonDecode(e['payload'] as String) as Map)['body'])
          .toList();
      expect(bodies, ['one', 'two']);
    });

    test('held longer than 30 s is dropped, not opened', () async {
      final got = <Map<String, dynamic>>[];
      final sub = zulfqar.events.listen(got.add);
      zInner.controller.add(_messageEvent('yasir', 'zulfqar', await sealed('old'), 'p3'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      now = now.add(const Duration(seconds: 31));
      zulfqar.bind(_Keys('zulfqar', [zKeys], {'yasir': yKeys.publicKey}));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();
      expect(got, isEmpty);
      expect(zulfqar.heldCount, 0);
    });

    test('at most 50 are held', () async {
      final sub = zulfqar.events.listen((_) {});
      final one = await sealed('x');
      for (var i = 0; i < SealingPeerTransport.maxHeld + 5; i++) {
        zInner.controller.add(_messageEvent('yasir', 'zulfqar', one, 'q$i'));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(zulfqar.heldCount, SealingPeerTransport.maxHeld);
    });

    test('plain events are not held', () async {
      final got = <Map<String, dynamic>>[];
      final sub = zulfqar.events.listen(got.add);
      zInner.controller.add({'type': 'peer_connected', 'peer_id': 'yasir'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      expect(got.single['type'], 'peer_connected');
      expect(zulfqar.heldCount, 0);
    });
  });

  group('Bundle 185 B1 memory', () {
    const channel = MethodChannel('locallink/voice_notes');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      VideoInfoCache.resetForTest();
    });

    test('on screen: keep everything', () {
      expect(MemoryTrim.onPressure(AppLifecycleState.resumed, cache: ImageCache()),
          isFalse);
    });

    test('hidden: video thumbnails and pictures are dropped', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        return <String, dynamic>{
          'thumbnail': Uint8List.fromList([1, 2, 3]),
          'duration_ms': 1000,
          'display_width': 10,
          'display_height': 10,
        };
      });
      await VideoInfoCache.load('/x.mp4', 'k1');
      expect(VideoInfoCache.peek('k1'), isNotNull);
      expect(MemoryTrim.onPressure(AppLifecycleState.paused, cache: ImageCache()),
          isTrue);
      expect(VideoInfoCache.peek('k1'), isNull);
    });

    test('the app listens for memory pressure', () {
      expect(_read('lib/app/local_link_app.dart'),
          contains('MemoryTrim.onPressure(_lifecycleState)'));
    });
  });

  group('Bundle 185 B2 ZTE help', () {
    test('3 simple ZTE steps', () {
      final g = backgroundBrandFor('ZTE Z2453');
      expect(g.key, 'zte');
      expect(g.steps.first, 'Tap Open settings');
      expect(g.steps[1], contains('Unrestricted'));
      expect(g.steps[2], contains('screen-lock cleaning'));
      expect(g.steps[3], contains('Lock'));
    });
  });
}
