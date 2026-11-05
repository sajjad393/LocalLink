// Bundle 210 (C): the Share LinkUp web server (page + APK only).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/share_app/data/apk_share_server.dart';

void main() {
  late Directory dir;
  late File apk;
  late Uint8List bytes;
  late ApkShareServer server;
  late int port;
  var fakeNow = DateTime(2026, 11, 5, 10);
  final client = HttpClient()..autoUncompress = false;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('share210');
    apk = File('${dir.path}/base.apk');
    bytes = Uint8List.fromList(List<int>.generate(300 * 1024, (i) => i % 251));
    await apk.writeAsBytes(bytes);
  });

  tearDownAll(() async {
    client.close(force: true);
    await dir.delete(recursive: true);
  });

  setUp(() async {
    fakeNow = DateTime(2026, 11, 5, 10);
    server = ApkShareServer(
      apkPath: apk.path,
      apkSize: bytes.length,
      version: '3.0.51',
      ownerName: 'Saj<b>jad',
      now: () => fakeNow,
      tick: const Duration(hours: 1),
    );
    port = await server.start(
        from: 18080, to: 18099, address: InternetAddress.loopbackIPv4);
  });

  tearDown(() async => server.stop());

  Future<(HttpClientResponse, List<int>)> get(String path,
      {String method = 'GET', Map<String, String> headers = const {}}) async {
    final req = await client.openUrl(
        method, Uri.parse('http://127.0.0.1:$port$path'));
    req.followRedirects = false;
    headers.forEach(req.headers.set);
    final res = await req.close();
    final body = <int>[];
    await for (final c in res) {
      body.addAll(c);
    }
    return (res, body);
  }

  test('page: English + Urdu, name escaped, no outside files', () async {
    final (res, body) = await get('/');
    expect(res.statusCode, 200);
    expect(res.headers.contentType?.mimeType, 'text/html');
    final html = utf8.decode(body);
    expect(html, contains('Download LinkUp'));
    expect(html, contains('لنک اپ ڈاؤن لوڈ کریں'));
    expect(html, contains('How to install'));
    expect(html, contains('Keep / Download anyway'));
    expect(html, contains('Saj&lt;b&gt;jad'));
    expect(html, isNot(contains('Saj<b>jad')));
    expect(html, contains('href="/LinkUp.apk"'));
    expect(html, isNot(contains('https://')));
    expect(html, isNot(contains('<script')));
  });

  test('APK: whole file, right headers, phone marked done', () async {
    final (res, body) = await get('/LinkUp.apk');
    expect(res.statusCode, 200);
    expect(res.headers.value('content-type'),
        'application/vnd.android.package-archive');
    expect(res.headers.value('content-disposition'),
        'attachment; filename="LinkUp-3.0.51.apk"');
    expect(res.headers.value('accept-ranges'), 'bytes');
    expect(res.contentLength, bytes.length);
    expect(body, bytes);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(server.phones, hasLength(1));
    expect(server.phones.single.done, isTrue);
    expect(server.phones.single.progress, 1.0);
    expect(server.activeDownloads, 0);
  });

  test('Range: 100-199, 100-, last 50 → 206 with the right bytes', () async {
    var (res, body) = await get('/LinkUp.apk', headers: {'range': 'bytes=100-199'});
    expect(res.statusCode, 206);
    expect(res.headers.value('content-range'), 'bytes 100-199/${bytes.length}');
    expect(body, bytes.sublist(100, 200));
    (res, body) = await get('/LinkUp.apk', headers: {'range': 'bytes=100-'});
    expect(res.statusCode, 206);
    expect(body, bytes.sublist(100));
    (res, body) = await get('/LinkUp.apk', headers: {'range': 'bytes=-50'});
    expect(res.statusCode, 206);
    expect(body, bytes.sublist(bytes.length - 50));
  });

  test('resume from the same phone = one phone, done at the end', () async {
    await get('/LinkUp.apk', headers: {'range': 'bytes=0-1023'});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(server.phones.single.done, isFalse);
    expect(server.phones.single.progress, closeTo(1024 / bytes.length, 1e-9));
    await get('/LinkUp.apk', headers: {'range': 'bytes=1024-'});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(server.phones, hasLength(1));
    expect(server.phones.single.done, isTrue);
  });

  test('bad range → 416', () async {
    final (res, _) = await get('/LinkUp.apk',
        headers: {'range': 'bytes=${bytes.length + 5}-'});
    expect(res.statusCode, 416);
    expect(res.headers.value('content-range'), 'bytes */${bytes.length}');
  });

  test('other paths → back to /; POST → 405; HEAD has no body', () async {
    var (res, body) = await get('/secret/chats.db');
    expect(res.statusCode, 302);
    expect(res.headers.value('location'), '/');
    (res, body) = await get('/generate_204');
    expect(res.statusCode, 302);
    (res, body) = await get('/LinkUp.apk', method: 'POST');
    expect(res.statusCode, 405);
    (res, body) = await get('/LinkUp.apk', method: 'HEAD');
    expect(res.statusCode, 200);
    expect(res.contentLength, bytes.length);
    expect(body, isEmpty);
    expect(server.phones, isEmpty);
  });

  test('a 4th phone waits while 3 download (503 busy page)', () async {
    server.activeDownloadsForTest = ApkShareServer.maxDownloads;
    final (res, body) = await get('/LinkUp.apk');
    expect(res.statusCode, 503);
    expect(res.headers.value('retry-after'), '60');
    expect(utf8.decode(body), contains('Try again in a minute'));
    expect(server.phones, isEmpty);
    server.activeDownloadsForTest = 0;
  });

  test('idle: 10 min with nothing → onIdle once; a download keeps it alive',
      () async {
    var idle = 0;
    server.onIdle = () => idle++;
    fakeNow = fakeNow.add(const Duration(minutes: 9, seconds: 59));
    expect(server.checkIdle(), isFalse);
    server.activeDownloadsForTest = 1;
    fakeNow = fakeNow.add(const Duration(minutes: 5));
    expect(server.checkIdle(), isFalse);
    server.activeDownloadsForTest = 0;
    expect(server.checkIdle(), isTrue);
    expect(server.checkIdle(), isFalse);
    expect(idle, 1);
  });

  test('a page visit counts as activity', () async {
    fakeNow = fakeNow.add(const Duration(minutes: 8));
    await get('/');
    fakeNow = fakeNow.add(const Duration(minutes: 8));
    expect(server.checkIdle(), isFalse);
  });

  test('all ports busy → port_busy', () async {
    final other = ApkShareServer(
        apkPath: apk.path, apkSize: bytes.length, version: '1', ownerName: '');
    await expectLater(
        other.start(from: port, to: port, address: InternetAddress.loopbackIPv4),
        throwsA(isA<ShareServerException>()
            .having((e) => e.reason, 'reason', 'port_busy')));
    await other.stop();
  });

  test('stop closes the port', () async {
    await server.stop();
    expect(server.running, isFalse);
    await expectLater(
        client.getUrl(Uri.parse('http://127.0.0.1:$port/')).then((r) => r.close()),
        throwsA(anything));
  });

  group('parseRange', () {
    test('cases', () {
      expect(parseRange(null, 10), isNull);
      expect(parseRange('items=1-2', 10), isNull);
      final r = parseRange('bytes=2-5', 10)!;
      expect([r.start, r.end, r.length], [2, 5, 4]);
      expect(parseRange('bytes=2-', 10)!.end, 9);
      expect(parseRange('bytes=2-99', 10)!.end, 9);
      expect(parseRange('bytes=-3', 10)!.start, 7);
      expect(parseRange('bytes=-30', 10)!.start, 0);
      expect(() => parseRange('bytes=10-', 10), throwsRangeError);
      expect(() => parseRange('bytes=5-2', 10), throwsRangeError);
      expect(() => parseRange('bytes=x', 10), throwsRangeError);
      expect(() => parseRange('bytes=-0', 10), throwsRangeError);
    });
  });
}
