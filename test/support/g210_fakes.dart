// Bundle 210: fakes for the Share LinkUp tests.

import 'dart:async';
import 'dart:io';

import 'package:locallink/features/share_app/data/apk_share_server.dart';
import 'package:locallink/features/share_app/data/app_share_channel.dart';
import 'package:locallink/features/share_app/domain/share_address_picker.dart';

class FakeShareNative implements AppShareNative {
  ApkInfo apk = const ApkInfo(
      ok: true, path: '/data/app/base.apk', size: 62 * 1024 * 1024,
      version: '3.0.51');
  ShareBattery batteryInfo = const ShareBattery(charging: false, level: 80);
  ShareStart start = const ShareStart(
      ok: true,
      ssid: 'AndroidShare_4821',
      password: 'k7m2x9qp',
      ip: '192.168.43.1');
  ShareAddresses addrs = const ShareAddresses();
  bool stillOn = true;

  /// When set, startShare waits for it.
  Completer<void>? holdStart;
  final List<String> calls = <String>[];

  @override
  Future<ApkInfo> apkInfo() async {
    calls.add('apk');
    return apk;
  }

  @override
  Future<ShareStart> startShare() async {
    calls.add('start');
    if (holdStart != null) await holdStart!.future;
    return start;
  }

  @override
  Future<void> stopShare(String reason) async => calls.add('stop $reason');

  @override
  Future<bool> shareStillOn() async {
    calls.add('status');
    return stillOn;
  }

  @override
  Future<ShareAddresses> addresses() async {
    calls.add('addresses');
    return addrs;
  }

  @override
  Future<ShareBattery> battery() async {
    calls.add('battery');
    return batteryInfo;
  }

  @override
  Future<void> keepScreenOn(bool on) async => calls.add('screen $on');

  @override
  Future<bool> openHotspotSettings() async {
    calls.add('open_hotspot');
    return true;
  }

  @override
  Future<bool> openWifiSettings() async {
    calls.add('open_wifi');
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    calls.add('open_location');
    return true;
  }
}

/// A server that opens no socket.
class FakeShareServer extends ApkShareServer {
  bool failStart = false;
  bool started = false;
  bool stopped = false;
  final List<SharePhone> fakePhones = <SharePhone>[];

  FakeShareServer()
      : super(
            apkPath: '/data/app/base.apk',
            apkSize: 62 * 1024 * 1024,
            version: '3.0.51',
            ownerName: 'Sajjad');

  @override
  Future<int> start(
      {int from = 8080, int to = 8089, InternetAddress? address}) async {
    if (failStart) throw const ShareServerException('port_busy');
    started = true;
    return 8080;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    started = false;
  }

  @override
  bool get running => started;

  @override
  int? get port => started ? 8080 : null;

  @override
  List<SharePhone> get phones => List.unmodifiable(fakePhones);

  /// A phone starts downloading.
  void addPhone({int upTo = 0}) {
    fakePhones.add(SharePhone(
        number: fakePhones.length + 1,
        address: '192.168.43.${20 + fakePhones.length}',
        total: apkSize,
        startedAt: DateTime(2026, 11, 5, 10))
      ..upTo = upTo);
    onChange?.call();
  }
}

const List<ShareAddress> kHotspotAddrs = <ShareAddress>[
  ShareAddress(iface: 'wlan0', ip: '192.168.1.7'),
  ShareAddress(iface: 'ap0', ip: '192.168.43.1', hotspot: true),
];
