// Bundle 210: Share LinkUp - the native side (channel `locallink/app_share`).

import 'package:flutter/services.dart';

import 'package:locallink/features/share_app/domain/share_address_picker.dart';

class ApkInfo {
  final bool ok;
  final String path;
  final int size;
  final String version;
  final bool split;
  final String? reason;

  const ApkInfo({
    required this.ok,
    this.path = '',
    this.size = 0,
    this.version = '',
    this.split = false,
    this.reason,
  });

  factory ApkInfo.fromMap(Object? raw) {
    if (raw is! Map || raw['ok'] != true) {
      return ApkInfo(
          ok: false,
          reason: raw is Map ? raw['reason']?.toString() : 'apk_missing');
    }
    return ApkInfo(
      ok: true,
      path: raw['path']?.toString() ?? '',
      size: (raw['size'] as num?)?.toInt() ?? 0,
      version: raw['version_name']?.toString() ?? '',
      split: raw['split'] == true,
    );
  }
}

class ShareStart {
  final bool ok;
  final String? reason;
  final String ssid;
  final String password;
  final String qrType;
  final String? ip;
  final bool reused;
  final List<ShareAddress> addresses;

  const ShareStart({
    required this.ok,
    this.reason,
    this.ssid = '',
    this.password = '',
    this.qrType = 'WPA',
    this.ip,
    this.reused = false,
    this.addresses = const <ShareAddress>[],
  });

  factory ShareStart.fromMap(Object? raw) {
    if (raw is! Map) return const ShareStart(ok: false, reason: 'error');
    if (raw['ok'] != true) {
      return ShareStart(ok: false, reason: raw['reason']?.toString() ?? 'error');
    }
    final ip = raw['ip']?.toString();
    return ShareStart(
      ok: true,
      ssid: raw['ssid']?.toString() ?? '',
      password: raw['key']?.toString() ?? '',
      qrType: raw['qr_type']?.toString() ?? 'WPA',
      ip: (ip == null || ip.isEmpty) ? null : ip,
      reused: raw['reused'] == true,
      addresses: ShareAddress.listFrom(raw['addresses']),
    );
  }
}

class ShareAddresses {
  final List<ShareAddress> list;
  final String? wifiIp;
  const ShareAddresses(
      {this.list = const <ShareAddress>[], this.wifiIp});

  factory ShareAddresses.fromMap(Object? raw) {
    if (raw is! Map) return const ShareAddresses();
    final w = raw['wifi_ip']?.toString();
    return ShareAddresses(
      list: ShareAddress.listFrom(raw['list']),
      wifiIp: (w == null || w.isEmpty) ? null : w,
    );
  }
}

class ShareBattery {
  final bool charging;

  /// 0-100, or -1 when unknown.
  final int level;
  const ShareBattery({this.charging = false, this.level = -1});
}

/// What the Share screen needs from Android (a fake in tests).
abstract class AppShareNative {
  Future<ApkInfo> apkInfo();
  Future<ShareStart> startShare();
  Future<void> stopShare(String reason);

  /// True while the hotspot is on and Share is one of its owners.
  Future<bool> shareStillOn();
  Future<ShareAddresses> addresses();
  Future<ShareBattery> battery();
  Future<void> keepScreenOn(bool on);
  Future<bool> openHotspotSettings();
  Future<bool> openWifiSettings();
  Future<bool> openLocationSettings();
}

class MethodChannelAppShareNative implements AppShareNative {
  static const MethodChannel _channel = MethodChannel('locallink/app_share');

  const MethodChannelAppShareNative();

  Future<Object?> _call(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<ApkInfo> apkInfo() async => ApkInfo.fromMap(await _call('apkInfo'));

  @override
  Future<ShareStart> startShare() async =>
      ShareStart.fromMap(await _call('startShare'));

  @override
  Future<void> stopShare(String reason) async =>
      _call('stopShare', {'reason': reason});

  @override
  Future<bool> shareStillOn() async {
    final raw = await _call('shareStatus');
    // Unknown = keep going (never stop sharing on a channel hiccup).
    if (raw is! Map) return true;
    return raw['on'] == true && raw['share'] == true;
  }

  @override
  Future<ShareAddresses> addresses() async =>
      ShareAddresses.fromMap(await _call('addresses'));

  @override
  Future<ShareBattery> battery() async {
    final raw = await _call('battery');
    if (raw is! Map) return const ShareBattery();
    return ShareBattery(
      charging: raw['charging'] == true,
      level: (raw['level'] as num?)?.toInt() ?? -1,
    );
  }

  @override
  Future<void> keepScreenOn(bool on) async => _call('keepScreenOn', {'on': on});

  @override
  Future<bool> openHotspotSettings() async =>
      (await _call('openHotspotSettings')) == true;

  @override
  Future<bool> openWifiSettings() async =>
      (await _call('openWifiSettings')) == true;

  @override
  Future<bool> openLocationSettings() async =>
      (await _call('openLocationSettings')) == true;
}
