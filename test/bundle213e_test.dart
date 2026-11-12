import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/share_app/data/app_share_channel.dart';
import 'package:locallink/features/share_app/domain/share_address_picker.dart';
import 'package:locallink/features/share_app/domain/update_request_service.dart';

import 'support/g210_fakes.dart';

/// Bundle 213 (E): Update gets the new LinkUp from a nearby phone.
/// Bundle 275: rewritten for the QUIET sharer - no question, no names, no
/// QR, no browser; shares only on the same network, battery >= 30 % or
/// charging, not in a call, one asker at a time.
class _Pair {
  late UpdateRequestService ali; // old app
  late UpdateRequestService sumaira; // new app
  final aliNative = FakeShareNative()
    ..addrs = const ShareAddresses(wifiIp: '192.168.1.20', list: [ShareAddress(iface: 'wlan0', ip: '192.168.1.20')]);
  final sumNative = FakeShareNative()
    ..addrs = const ShareAddresses(wifiIp: '192.168.1.30', list: [ShareAddress(iface: 'wlan0', ip: '192.168.1.30')]);
  final opened = <String>[];
  final served = <String>[];
  final owners = <String>[];
  final sent = <(String, String)>[];
  final frames = <Map<String, dynamic>>[];
  var now = DateTime(2026, 11, 5, 12);

  _Pair() {
    Future<void> Function(String, Map<String, dynamic>) sender(String from) => (peer, payload) async {
          sent.add((from, payload['type'].toString()));
          frames.add(Map<String, dynamic>.from(payload));
          final to = peer == 'sum' ? sumaira : ali;
          if (peer != 'sum' && peer != 'ali') return;
          unawaited(to.handleEvent({'type': 'message', 'sender_id': from, 'payload': jsonEncode(payload)}));
        };
    ali = UpdateRequestService(
      send: sender('ali'),
      events: const Stream.empty(),
      selfDeviceId: () => 'ali',
      myName: () => 'Ali',
      peerName: (_) async => 'Sumaira',
      peerBuilds: () => {
        'sum': (build: kAppBuild + 1, version: '3.0.55', at: now),
        'old': (build: kAppBuild - 3, version: '3.0.51', at: now)
      },
      native: aliNative,
      openUri: (u) async => opened.add(u),
      clock: () => now,
    );
    sumaira = UpdateRequestService(
      send: sender('sum'),
      events: const Stream.empty(),
      selfDeviceId: () => 'sum',
      myName: () => 'Sumaira',
      peerName: (_) async => 'Ali',
      peerBuilds: () => const {},
      native: sumNative,
      startServer: (apk, ip, owner) async {
        served.add(ip);
        owners.add(owner);
        return 'http://$ip:8080/';
      },
      clock: () => now,
    );
  }

  Future<void> askFrom(String who, List<String> ips) => sumaira.handleEvent({
        'type': 'message',
        'sender_id': who,
        'payload': jsonEncode({'type': 'app_update_request', 'ips': ips, 'build': kAppBuild - 1}),
      });
}

void main() {
  setUp(() {
    UpdateRequestService.resetHooksForTest();
    AppBuild.pretendOld = true; // Ali's phone is one build lower
  });
  tearDown(() {
    UpdateRequestService.resetHooksForTest();
    AppBuild.pretendOld = false;
  });

  test('only phones with a newer build; no names in the list', () async {
    final p = _Pair();
    final list = await p.ali.candidates();
    expect(list.map((c) => c.peerId), ['sum']);
    expect(list.single.name, '');
    expect(await p.ali.candidates(minBuild: kAppBuild + 2), isEmpty);
  });

  test('ask -> quiet share: offer comes, no names, no browser', () async {
    final p = _Pair();
    expect(await p.ali.ask('sum'), isTrue);
    await pumpEventQueue();
    expect(p.served, ['192.168.1.30']);
    expect(p.owners, ['']);
    expect(p.ali.offer?.url, 'http://192.168.1.30:8080/');
    expect(p.ali.offer?.name, '');
    expect(p.ali.statusOf('sum'), AskStatus.sharing);
    expect(p.opened, isEmpty);
    for (final f in p.frames) {
      expect(f.containsKey('name'), isFalse, reason: '${f['type']}');
    }
  });

  test('no same network (mesh only): quiet "not now", never the QR', () async {
    final p = _Pair();
    p.sumNative.addrs = const ShareAddresses(list: [ShareAddress(iface: 'p2p0', ip: '192.168.49.1')]);
    await p.ali.ask('sum');
    await pumpEventQueue();
    expect(p.ali.offer, isNull);
    expect(p.ali.statusOf('sum'), AskStatus.notNow);
    expect(p.served, isEmpty);
    expect(p.frames.where((f) => f['qr'] == true), isEmpty);
  });

  test('low battery: not now; charging: shares', () async {
    final p = _Pair();
    p.sumNative.batteryInfo = const ShareBattery(charging: false, level: 29);
    await p.ali.ask('sum');
    await pumpEventQueue();
    expect(p.ali.statusOf('sum'), AskStatus.notNow);
    expect(p.served, isEmpty);
    final q = _Pair();
    q.sumNative.batteryInfo = const ShareBattery(charging: true, level: 5);
    await q.ali.ask('sum');
    await pumpEventQueue();
    expect(q.served, ['192.168.1.30']);
  });

  test('in a call: not now', () async {
    final p = _Pair();
    UpdateRequestService.inCall = () => true;
    await p.ali.ask('sum');
    await pumpEventQueue();
    expect(p.ali.statusOf('sum'), AskStatus.notNow);
    expect(p.served, isEmpty);
  });

  test('one share at a time: a 2nd asker gets "not now"', () async {
    final p = _Pair();
    await p.ali.ask('sum');
    await pumpEventQueue();
    expect(p.served.length, 1);
    await p.askFrom('zed', ['192.168.1.40']);
    await pumpEventQueue();
    expect(p.served.length, 1);
    final last = p.frames.last;
    expect(last['type'], 'app_update_answer');
    expect(last['ok'], isFalse);
    expect(last['reason'], 'not_now');
  });

  test('shareRule275 order', () {
    const full = ShareBattery(charging: false, level: 80);
    expect(UpdateRequestService.shareRule275(sameNetwork: true, battery: full, inCall: false, busyWithOther: false),
        isNull);
    expect(UpdateRequestService.shareRule275(sameNetwork: true, battery: full, inCall: false, busyWithOther: true),
        'busy');
    expect(UpdateRequestService.shareRule275(sameNetwork: true, battery: full, inCall: true, busyWithOther: false),
        'in_call');
    expect(
        UpdateRequestService.shareRule275(
            sameNetwork: true,
            battery: const ShareBattery(charging: false, level: 10),
            inCall: false,
            busyWithOther: false),
        'battery');
    expect(UpdateRequestService.shareRule275(sameNetwork: false, battery: full, inCall: false, busyWithOther: false),
        'no_same_net');
  });

  test('asking the same phone again waits 2 min', () async {
    final p = _Pair();
    p.sumNative.batteryInfo = const ShareBattery(charging: false, level: 3);
    await p.ali.ask('sum');
    await pumpEventQueue();
    expect(p.ali.statusOf('sum'), AskStatus.notNow);
    expect(await p.ali.ask('sum'), isFalse);
    p.now = p.now.add(const Duration(minutes: 2));
    expect(await p.ali.ask('sum'), isTrue);
  });

  test('offers only from a phone I asked, only local http addresses', () async {
    final p = _Pair();
    await p.ali.handleEvent({
      'type': 'message',
      'sender_id': 'stranger',
      'payload': jsonEncode({'type': 'app_update_offer', 'url': 'http://192.168.1.9:8080/'}),
    });
    expect(p.ali.offer, isNull);
    p.sumNative.batteryInfo = const ShareBattery(charging: false, level: 3); // no real offer
    await p.ali.ask('sum');
    await pumpEventQueue();
    await p.ali.handleEvent({
      'type': 'message',
      'sender_id': 'sum',
      'payload': jsonEncode({'type': 'app_update_offer', 'url': 'https://evil.example/app.apk'}),
    });
    expect(p.ali.offer, isNull);
    expect(p.opened, isEmpty);
  });

  test('a phone with the same or older app is never served', () async {
    final p = _Pair();
    AppBuild.pretendOld = false;
    await p.sumaira.handleEvent({
      'type': 'message',
      'sender_id': 'ali',
      'payload': jsonEncode({
        'type': 'app_update_request',
        'ips': ['192.168.1.20'],
        'build': kAppBuild
      }),
    });
    await pumpEventQueue();
    expect(p.served, isEmpty);
    expect(p.sent.last.$2, 'app_update_answer');
  });

  test('same network address picker', () {
    expect(UpdateRequestService.sameNetworkIp(mine: ['192.168.1.30', '192.168.49.1'], theirs: ['192.168.49.7']),
        '192.168.49.1');
    expect(UpdateRequestService.sameNetworkIp(mine: ['10.0.0.5'], theirs: ['192.168.1.2']), isNull);
    expect(UpdateRequestService.sameNetworkIp(mine: ['8.8.8.8'], theirs: ['8.8.8.9']), isNull);
  });
}
