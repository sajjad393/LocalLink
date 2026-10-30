// Bundle 148: one live status for every screen (PresenceHub).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/widgets/device_status_indicator.dart';
import 'package:locallink/core/widgets/messenger_conversation_tile.dart';
import 'package:locallink/features/home/bloc/home_bloc.dart';
import 'package:locallink/features/home/domain/home_repository_contract.dart';

class _Clock {
  DateTime now = DateTime(2026, 10, 30, 12);
  void advance(Duration d) => now = now.add(d);
}

Device _dev(String id, {bool server = false, bool lan = false, bool mesh = false}) =>
    Device(
      id: id,
      name: 'Device $id',
      platform: 'android',
      createdAt: '2026-01-01T00:00:00Z',
      lastSeenAt: '2026-01-01T00:00:00Z',
      serverConnected: server,
      lanAvailable: lan,
      meshAvailable: mesh,
    );

final class _Repo implements HomeRepositoryContract {
  _Repo(this.list, [this.users = const {}]);
  final List<Device> list;
  final Map<String, String> users;
  @override
  String? get localDeviceId => 'me';
  @override
  Stream<Map<String, dynamic>> get presenceEvents => const Stream.empty();
  @override
  Stream<Map<String, dynamic>> get directPresenceEvents => const Stream.empty();
  @override
  Future<List<Device>> devices() async => list;
  @override
  Future<List<LocalGroup>> groups() async => const <LocalGroup>[];
  @override
  Future<List<Device>> localDevices() async => list;
  @override
  Future<List<LocalGroup>> localGroups() async => const <LocalGroup>[];
  @override
  Future<LocalGroup> createGroup(String name, List<String> memberIds) =>
      throw UnimplementedError();
  @override
  Future<void> cacheDevice(Device device) async {}
  @override
  Future<void> markDeviceSeen(String deviceId) async {}
  @override
  Future<String?> userIdForDevice(String deviceId) async => users[deviceId];
  @override
  Future<String?> labelForDevice(String deviceId) async => null;
}

Map<String, dynamic> _directMsg(String from) =>
    {'type': 'message', 'sender_id': from, 'payload': '{}'};

Map<String, dynamic> _serverPresence(String id,
        {required bool server, bool lan = false, bool mesh = false}) =>
    {
      'type': 'presence_update',
      'device_id': id,
      'server_connected': server,
      'lan_available': lan,
      'mesh_available': mesh,
      'wifi_direct_connected': lan,
    };

void main() {
  late _Clock clock;
  late PresenceHub hub;

  setUp(() {
    clock = _Clock();
    hub = PresenceHub(clock: () => clock.now)..localDeviceId = () => 'me';
  });

  test('a packet over the direct link = Nearby', () {
    expect(hub.statusOf('bob'), PresenceStatus.offline);
    hub.onDirectEvent(_directMsg('bob'));
    expect(hub.statusOf('bob'), PresenceStatus.nearby);
    expect(hub.labelOf('bob'), 'Nearby');
    expect(hub.channelOf('bob'), 'nearby');
  });

  test('far person reachable only via the server = Online', () {
    hub.onServerMessage(_serverPresence('far', server: true));
    expect(hub.statusOf('far'), PresenceStatus.online);
    expect(hub.labelOf('far'), 'Online');
  });

  test("the other phone's own claim (lan/mesh flags) never means Nearby", () {
    hub.onServerMessage(_serverPresence('far', server: true, lan: true, mesh: true));
    expect(hub.statusOf('far'), PresenceStatus.online);
  });

  test('their server disconnect keeps a nearby person Nearby', () {
    hub.onDirectEvent(_directMsg('bob'));
    hub.onServerMessage(_serverPresence('bob', server: true));
    hub.onServerMessage(_serverPresence('bob', server: false)); // all flags false
    expect(hub.statusOf('bob'), PresenceStatus.nearby);
  });

  test('their server disconnect turns a far person Offline at once', () {
    hub.onServerMessage(_serverPresence('far', server: true));
    hub.onServerMessage(_serverPresence('far', server: false));
    expect(hub.statusOf('far'), PresenceStatus.offline);
  });

  test('OUR server drop: nearby stays Nearby, server-only goes Offline', () {
    hub.onDirectEvent(_directMsg('bob'));
    hub.onServerMessage(_serverPresence('bob', server: true));
    hub.onServerMessage(_serverPresence('far', server: true));
    hub.serverLinkLost();
    expect(hub.statusOf('bob'), PresenceStatus.nearby);
    expect(hub.statusOf('far'), PresenceStatus.offline);
  });

  test('Nearby falls back to Online when the direct proof gets old', () {
    hub.noteNearby('bob');
    clock.advance(const Duration(seconds: 40));
    hub.noteServer('bob');
    clock.advance(const Duration(seconds: 35)); // nearby proof 75 s old
    expect(hub.statusOf('bob'), PresenceStatus.online);
  });

  test('one lost 30 s beat does not flicker; ~70 s of silence = Offline', () {
    hub.noteNearby('bob');
    clock.advance(const Duration(seconds: 62));
    expect(hub.statusOf('bob'), PresenceStatus.nearby);
    clock.advance(const Duration(seconds: 9)); // 71 s
    expect(hub.statusOf('bob'), PresenceStatus.offline);
  });

  test('the 5 s tick tells every screen when someone expires', () async {
    var notified = 0;
    hub.addListener(() => notified++);
    hub.noteNearby('bob');
    await Future<void>.delayed(Duration.zero);
    expect(notified, 1);
    hub.checkExpiry(); // nothing changed
    await Future<void>.delayed(Duration.zero);
    expect(notified, 1);
    clock.advance(const Duration(seconds: 75));
    hub.checkExpiry();
    await Future<void>.delayed(Duration.zero);
    expect(notified, 2);
  });

  test('our own device id is ignored', () {
    hub.onDirectEvent(_directMsg('me'));
    hub.noteServer('me');
    expect(hub.statusOf('me'), PresenceStatus.offline);
  });

  test('peer_connected on the direct link counts as Nearby proof', () {
    hub.onDirectEvent({'type': 'peer_connected', 'peer_id': 'bob'});
    expect(hub.statusOf('bob'), PresenceStatus.nearby);
  });

  test('two devices of one person share the best status', () async {
    hub.userResolver = (id) async => const {'old': 'u1', 'new': 'u1'}[id];
    hub.noteNearby('new');
    hub.statusOf('old');
    hub.statusOf('new');
    await Future<void>.delayed(Duration.zero);
    expect(hub.statusOf('old'), PresenceStatus.nearby);
    expect(hub.statusOfDevice('old'), PresenceStatus.offline);
  });

  test('names resolve once and notify listeners', () async {
    var calls = 0;
    hub.nameResolver = (id) async {
      calls++;
      return 'Ayesha';
    };
    var notified = 0;
    hub.addListener(() => notified++);
    expect(hub.nameOf('bob'), isNull);
    expect(hub.nameOf('bob'), isNull);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(hub.nameOf('bob'), 'Ayesha');
    expect(calls, 1);
    expect(notified, greaterThan(0));
  });

  test('attach listens to direct + server streams and our server link', () async {
    final direct = StreamController<Map<String, dynamic>>.broadcast();
    final server = StreamController<Map<String, dynamic>>.broadcast();
    final link = StreamController<bool>.broadcast();
    hub.attach(
        directEvents: direct.stream,
        serverMessages: server.stream,
        serverConnection: link.stream);
    direct.add(_directMsg('bob'));
    server.add(_serverPresence('far', server: true));
    await Future<void>.delayed(Duration.zero);
    expect(hub.statusOf('bob'), PresenceStatus.nearby);
    expect(hub.statusOf('far'), PresenceStatus.online);
    link.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(hub.statusOf('far'), PresenceStatus.offline);
    expect(hub.statusOf('bob'), PresenceStatus.nearby);
    hub.resetForTest();
    await direct.close();
    await server.close();
    await link.close();
  });

  group('HomeBloc', () {
    test('server list sets Online only — its lan flag is not Nearby', () async {
      final bloc = HomeBloc(
        repository: _Repo([_dev('far', server: true, lan: true, mesh: true), _dev('gone')]),
        presence: hub,
      );
      await bloc.load();
      expect(hub.statusOf('far'), PresenceStatus.online);
      expect(hub.statusOf('gone'), PresenceStatus.offline);
      await bloc.close();
    });

    test('server list never wipes a nearby person', () async {
      hub.noteNearby('bob');
      final bloc = HomeBloc(repository: _Repo([_dev('bob')]), presence: hub);
      await bloc.load();
      expect(hub.statusOf('bob'), PresenceStatus.nearby);
      await bloc.close();
    });

    test('duplicate devices: the live one represents the person', () async {
      hub.noteNearby('phone-b');
      final bloc = HomeBloc(
        repository: _Repo([_dev('phone-a'), _dev('phone-b')],
            {'phone-a': 'u1', 'phone-b': 'u1'}),
        presence: hub,
      );
      await bloc.load();
      expect(bloc.state.devices.map((d) => d.id), ['phone-b']);
      await bloc.close();
    });
  });

  group('screens read the same hub', () {
    setUp(() => PresenceHub.instance.resetForTest());
    tearDown(() => PresenceHub.instance.resetForTest());

    Widget host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

    testWidgets('avatar badge + status badge agree and update live', (tester) async {
      final device = _dev('bob'); // flags all false: hub decides
      await tester.pumpWidget(host(Column(children: [
        PresenceAvatar(avatar: const CircleAvatar(), device: device),
        DeviceStatusIndicator(device: device),
        ListenableBuilder(
          listenable: PresenceHub.instance,
          builder: (_, __) => Text('label:${PresenceHub.instance.labelOf('bob')}'),
        ),
      ])));
      expect(find.text('label:Offline'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_rounded), findsNothing);

      PresenceHub.instance.noteNearby('bob');
      await tester.pump();
      expect(find.text('label:Nearby'), findsOneWidget);
      expect(find.text('Nearby'), findsOneWidget); // status badge
      expect(find.byIcon(Icons.wifi_rounded), findsNWidgets(2));

      PresenceHub.instance.serverLinkLost(); // server drop: still Nearby
      await tester.pump();
      expect(find.text('label:Nearby'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Calls tab style avatar (bare id, no flags) shows Online', (tester) async {
      PresenceHub.instance.noteServer('far');
      await tester.pumpWidget(host(const PresenceAvatar(
        avatar: CircleAvatar(),
        device: Device(
            id: 'far', name: 'Far', platform: 'android', createdAt: '', lastSeenAt: ''),
      )));
      await tester.pump();
      expect(find.byIcon(Icons.public_rounded), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
