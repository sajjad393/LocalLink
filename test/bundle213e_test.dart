import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/share_app/data/app_share_channel.dart';
import 'package:locallink/features/share_app/domain/share_address_picker.dart';
import 'package:locallink/features/share_app/domain/update_request_service.dart';
import 'package:locallink/features/share_app/presentation/update_sheet.dart';

import 'support/g210_fakes.dart';

/// Bundle 213 (E): Update gets the new LinkUp from a nearby phone.
class _Pair {
  late UpdateRequestService ali; // old app
  late UpdateRequestService sumaira; // new app
  final aliNative = FakeShareNative()
    ..addrs = const ShareAddresses(wifiIp: '192.168.1.20', list: [ShareAddress(iface: 'wlan0', ip: '192.168.1.20')]);
  final sumNative = FakeShareNative()
    ..addrs = const ShareAddresses(wifiIp: '192.168.1.30', list: [ShareAddress(iface: 'wlan0', ip: '192.168.1.30')]);
  final opened = <String>[];
  final served = <String>[];
  final sent = <(String, String)>[];
  var now = DateTime(2026, 11, 5, 12);

  _Pair() {
    Future<void> Function(String, Map<String, dynamic>) sender(String from) => (peer, payload) async {
          sent.add((from, payload['type'].toString()));
          final to = peer == 'sum' ? sumaira : ali;
          // Like the link: sent, then handled on the other phone later.
          unawaited(to.handleEvent({'type': 'message', 'sender_id': from, 'payload': jsonEncode(payload)}));
        };
    ali = UpdateRequestService(
      send: sender('ali'),
      events: const Stream.empty(),
      selfDeviceId: () => 'ali',
      myName: () => 'Ali',
      peerName: (_) async => 'Sumaira',
      peerBuilds: () => {'sum': (build: kAppBuild + 1, version: '3.0.55', at: now), 'old': (build: kAppBuild - 3, version: '3.0.51', at: now)},
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
        return 'http://$ip:8080/';
      },
      clock: () => now,
    );
  }
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

  test('only phones with a newer build are offered', () async {
    final p = _Pair();
    final list = await p.ali.candidates();
    expect(list.map((c) => c.peerId), ['sum']);
    expect(list.single.name, 'Sumaira');
    expect(await p.ali.candidates(minBuild: kAppBuild + 2), isEmpty);
  });

  test('Ask → Share → the download opens by itself (once)', () async {
    final p = _Pair();
    UpdateAsk? asked;
    UpdateRequestService.confirm = (ask, apk, battery) async {
      asked = ask;
      return true;
    };
    expect(await p.ali.ask('sum'), isTrue);
    await pumpEventQueue();
    expect(asked?.name, 'Ali');
    expect(asked?.ips, contains('192.168.1.20'));
    expect(p.served, ['192.168.1.30']);
    expect(p.ali.offer?.url, 'http://192.168.1.30:8080/');
    expect(p.ali.offer?.name, 'Sumaira');
    expect(p.ali.statusOf('sum'), AskStatus.sharing);
    expect(p.opened, ['http://192.168.1.30:8080/']);
    await p.ali.openOffer();
    expect(p.opened.length, 2); // the button opens it again
  });

  test('Not now → "said not now"; asking again waits 2 min', () async {
    final p = _Pair();
    UpdateRequestService.confirm = (a, b, c) async => false;
    await p.ali.ask('sum');
    await pumpEventQueue();
    expect(p.ali.statusOf('sum'), AskStatus.notNow);
    expect(await p.ali.ask('sum'), isFalse);
    p.now = p.now.add(const Duration(minutes: 2));
    expect(await p.ali.ask('sum'), isTrue);
  });

  test('no shared Wi-Fi (mesh only): the QR way', () async {
    final p = _Pair();
    p.sumNative.addrs = const ShareAddresses(list: [ShareAddress(iface: 'p2p0', ip: '192.168.49.1')]);
    String? qrFor;
    UpdateRequestService.confirm = (a, b, c) async => true;
    UpdateRequestService.openShareScreen = (owner) => qrFor = owner;
    await p.ali.ask('sum');
    await pumpEventQueue();
    expect(p.ali.offer?.qr, isTrue);
    expect(p.ali.statusOf('sum'), AskStatus.qr);
    expect(qrFor, 'Sumaira');
    expect(p.opened, isEmpty);
  });

  test('no answer in 60 s', () async {
    final p = _Pair();
    UpdateRequestService.confirm = (a, b, c) => Completer<bool?>().future;
    await p.ali.ask('sum');
    expect(p.ali.statusOf('sum'), AskStatus.asking);
    await Future<void>.delayed(Duration.zero);
    p.ali.cancel();
    expect(p.ali.statusOf('sum'), isNull);
  }, timeout: const Timeout(Duration(seconds: 10)));

  test('offers only from a phone I asked, only local http addresses', () async {
    final p = _Pair();
    await p.ali.handleEvent({
      'type': 'message',
      'sender_id': 'stranger',
      'payload': jsonEncode({'type': 'app_update_offer', 'url': 'http://192.168.1.9:8080/'}),
    });
    expect(p.ali.offer, isNull);
    UpdateRequestService.confirm = (a, b, c) async => null; // no answer yet
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

  test('a phone with the same or older app is never asked to share', () async {
    final p = _Pair();
    AppBuild.pretendOld = false;
    var dialogs = 0;
    UpdateRequestService.confirm = (a, b, c) async {
      dialogs++;
      return true;
    };
    // Ali reports the same build as Sumaira's app.
    await p.sumaira.handleEvent({
      'type': 'message',
      'sender_id': 'ali',
      'payload': jsonEncode({'type': 'app_update_request', 'name': 'Ali', 'ips': [], 'build': kAppBuild}),
    });
    expect(dialogs, 0);
    expect(p.sent.last.$2, 'app_update_answer');
  });

  test('same network address picker', () {
    expect(UpdateRequestService.sameNetworkIp(mine: ['192.168.1.30', '192.168.49.1'], theirs: ['192.168.49.7']),
        '192.168.49.1');
    expect(UpdateRequestService.sameNetworkIp(mine: ['10.0.0.5'], theirs: ['192.168.1.2']), isNull);
    expect(UpdateRequestService.sameNetworkIp(mine: ['8.8.8.8'], theirs: ['8.8.8.9']), isNull);
  });

  testWidgets('sheet: Ask → Asking… and the waiting note', (tester) async {
    final p = _Pair();
    UpdateRequestService.confirm = (a, b, c) => Completer<bool?>().future;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: UpdateSheet(service: p.ali))));
    await tester.pump();
    await tester.pump();
    expect(find.text('Get the new LinkUp'), findsOneWidget);
    expect(find.text('Sumaira'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('update_ask_sum')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('update_asking')), findsOneWidget);
    expect(find.text('Waiting for Sumaira to tap Share (up to 1 min)…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 61));
    expect(find.text('No answer from Sumaira. Try again in 2 min.'), findsOneWidget);
  });

  testWidgets('ask dialog: Share, or Share anyway at low battery', (tester) async {
    bool? answer;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return TextButton(
        onPressed: () async => answer = await showUpdateAskDialog(
            context,
            const UpdateAsk(peerId: 'ali', name: 'Ali', ips: [], build: 124),
            const ApkInfo(ok: true, size: 48 * 1024 * 1024, version: '3.0.54'),
            const ShareBattery(level: 8)),
        child: const Text('go'),
      );
    })));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Ali wants the new LinkUp'), findsOneWidget);
    expect(find.text('Share anyway'), findsOneWidget);
    expect(find.textContaining('48 MB'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('update_ask_share')));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });

  testWidgets('offer card: Open download', (tester) async {
    final p = _Pair();
    UpdateRequestService.confirm = (a, b, c) async => true;
    await tester.runAsync(() async {
      await p.ali.ask('sum');
      await pumpEventQueue();
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: UpdateOfferCard(service: p.ali))));
    expect(find.text('Sumaira is sharing LinkUp 3.0.51'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('update_open_download')));
      await pumpEventQueue();
    });
    expect(p.opened.length, 2);
  });
}
