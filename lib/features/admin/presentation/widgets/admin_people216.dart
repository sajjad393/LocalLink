import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/domain/admin_repository_contract.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';

/// Bundle 216 (E): small helpers shared by the tool pages.

// ------------------------------------------------------------ Wi-Fi rule
/// Server value → shown words (WORDS_216). null / '' = Default.
String wifiRuleLabel216(Object? v) => switch ((v ?? '').toString()) {
      'allowed' => 'Allowed',
      'forced_on' => 'Always on',
      'forced_off' => 'Always off',
      _ => 'Default',
    };

const wifiRuleValues216 = <String?>[null, 'allowed', 'forced_on', 'forced_off'];

/// The stored rule of a person / phone (empty = Default). The effective
/// `wifi_radio_policy` is 'allowed' when nothing is set, so read the own
/// field first.
String? wifiRuleOf216(Map<String, dynamic>? policy, {required bool device}) {
  if (policy == null) return null;
  final own = policy[device ? 'device_wifi_radio_policy' : 'user_wifi_radio_policy'];
  final s = (own ?? '').toString().trim();
  return s.isEmpty ? null : s;
}

/// Sheet with the 4 Wi-Fi rule cards. Returns `(picked: value)` or null
/// when closed without a pick.
Future<({String? picked})?> pickWifiRule216(BuildContext context,
    {required String? current, required String title, String? note}) {
  return showAdminSheet216<({String? picked})>(context, builder: (sheet) {
    final t = A216Text.of(sheet);
    const subs = {
      null: 'Follow the account or phone setting',
      'allowed': 'The phone decides',
      'forced_on': 'Wi-Fi stays on',
      'forced_off': 'Wi-Fi stays off',
    };
    return Column(
      key: const ValueKey('a216_wifi_sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: t.sheetTitle),
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(note, style: t.cardSub),
        ],
        const SizedBox(height: 14),
        for (final v in wifiRuleValues216) ...[
          AdminRadioCard216(
            key: ValueKey('a216_wifi_${v ?? 'default'}'),
            title: wifiRuleLabel216(v),
            subtitle: subs[v]!,
            selected: current == v,
            height: 54,
            sheet: true,
            onTap: () => Navigator.of(sheet).pop((picked: v)),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  });
}

// ---------------------------------------------------------- status words
({String text, A216Tone tone}) userStatus216(Object? status) => switch ('$status') {
      'suspended' => (text: 'Suspended', tone: A216Tone.orange),
      'disabled' => (text: 'Off', tone: A216Tone.red),
      _ => (text: 'Active', tone: A216Tone.green),
    };

// ------------------------------------------------------------ links
({String text, A216Tone tone}) deviceLink216(Map<String, dynamic> d) {
  if ('${d['status']}' == 'revoked' || (d['revoked_at'] ?? '').toString().isNotEmpty) {
    return (text: 'Removed', tone: A216Tone.red);
  }
  if (d['online'] == false &&
      d['server_connected'] != true &&
      d['wifi_direct_connected'] != true &&
      d['mesh_available'] != true &&
      d['lan_available'] != true) {
    return (text: 'Offline', tone: A216Tone.grey);
  }
  if (d['server_connected'] == true) return (text: 'Server', tone: A216Tone.green);
  if (d['wifi_direct_connected'] == true) return (text: 'Wi-Fi Direct', tone: A216Tone.amber);
  if (d['mesh_available'] == true) return (text: 'Mesh', tone: A216Tone.purple);
  if (d['lan_available'] == true) return (text: 'Local Wi-Fi', tone: A216Tone.teal);
  // Bundle 255 B9: online with no link flag is NOT a server link (noshad's
  // phone said "Server" before it ever reached the server).
  return d['online'] == true
      ? (text: 'Online', tone: A216Tone.grey)
      : (text: 'Offline', tone: A216Tone.grey);
}

/// Bundle 255 B9: ALL links of a phone (same flags as the Network tiles),
/// so a row and the tiles never disagree. No flag = grey Online / Offline.
List<({String text, A216Tone tone})> deviceLinks255(Map<String, dynamic> d) {
  final one = deviceLink216(d);
  if (one.text == 'Removed') return [one];
  final all = <({String text, A216Tone tone})>[
    if (d['server_connected'] == true) (text: 'Server', tone: A216Tone.green),
    if (d['wifi_direct_connected'] == true) (text: 'Wi-Fi Direct', tone: A216Tone.amber),
    if (d['mesh_available'] == true) (text: 'Mesh', tone: A216Tone.purple),
    if (d['lan_available'] == true) (text: 'Local Wi-Fi', tone: A216Tone.teal),
  ];
  return all.isEmpty ? [one] : all;
}

String linkWord216(Object? link) => switch ('$link') {
      'server' => 'Server',
      'wifi_direct' || 'wifiDirect' => 'Wi-Fi Direct',
      'mesh' => 'Mesh',
      'lan' || 'local_wifi' || 'localWifi' => 'Local Wi-Fi',
      _ => '$link',
    };

/// The other end of a phone's link from link-map edges ('' = none / server).
({String link, String other}) edgeOf216(Map<String, dynamic>? linkMap, String deviceId) {
  final edges = linkMap?['edges'];
  final nodes = linkMap?['nodes'];
  if (edges is! List) return (link: '', other: '');
  String nameOf(String id) {
    if (nodes is List) {
      for (final n in nodes) {
        if (n is Map && '${n['device_id']}' == id) {
          return personName216(Map<String, dynamic>.from(n), fallback: '${n['device_name'] ?? ''}');
        }
      }
    }
    return '';
  }

  for (final e in edges) {
    if (e is! Map) continue;
    final from = '${e['from']}';
    final to = '${e['to']}';
    if (from != deviceId && to != deviceId) continue;
    final other = from == deviceId ? to : from;
    return (link: '${e['link'] ?? ''}', other: other == 'server' ? '' : nameOf(other));
  }
  return (link: '', other: '');
}

// --------------------------------------------------------- server photos
/// Bundle 216 (H): admin photos from `/api/v1/admin/users/{id}/avatar`,
/// kept in memory for this app run (never on disk).
abstract final class AdminAvatarCache216 {
  static final Map<String, Uint8List?> _bytes = {};
  static final Map<String, Future<Uint8List?>> _busy = {};

  static Uint8List? peek(String userId) => _bytes[userId];
  static bool has(String userId) => _bytes.containsKey(userId);

  static Future<Uint8List?> load(AdminRepositoryContract repo, String userId) {
    if (_bytes.containsKey(userId)) return Future.value(_bytes[userId]);
    if (repo is! AdminExtraReads216) return Future.value(null);
    return _busy[userId] ??= (repo as AdminExtraReads216).userAvatar(userId).then((b) {
      _bytes[userId] = b;
      _busy.remove(userId);
      return b;
    }).catchError((Object e) {
      AppLogger.info('ADMIN_AVATAR_FAIL', detail: '$e');
      _bytes[userId] = null;
      _busy.remove(userId);
      return null;
    });
  }

  static void clearForTest() {
    _bytes.clear();
    _busy.clear();
  }
}

/// [AdminPersonAvatar216] that uses the server photo when the person has
/// one (`has_avatar`) — the phone's own photo cache stays first.
class ServerPersonAvatar216 extends StatefulWidget {
  const ServerPersonAvatar216({
    super.key,
    required this.name,
    required this.userId,
    this.deviceId,
    this.hasAvatar = false,
    this.radius = 20,
    this.admin = false,
    this.blocked = false,
    this.online = false,
    this.grey = false,
  });

  final String name;
  final String userId;
  final String? deviceId;
  final bool hasAvatar;
  final double radius;
  final bool admin;
  final bool blocked;
  final bool online;

  /// Not active (suspended / off): grey photo without the red ring.
  final bool grey;

  @override
  State<ServerPersonAvatar216> createState() => _ServerPersonAvatar216State();
}

class _ServerPersonAvatar216State extends State<ServerPersonAvatar216> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = AdminAvatarCache216.peek(widget.userId);
    if (widget.hasAvatar && _bytes == null && !AdminAvatarCache216.has(widget.userId)) {
      AdminRepositoryContract? repo;
      try {
        repo = context.read<AdminBloc>().repository;
      } catch (_) {}
      if (repo != null) {
        AdminAvatarCache216.load(repo, widget.userId).then((b) {
          if (mounted && b != null) setState(() => _bytes = b);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    Widget a = AdminPersonAvatar216(
      name: widget.name,
      userId: widget.userId,
      deviceId: widget.deviceId,
      radius: widget.radius,
      admin: widget.admin,
      blocked: widget.blocked,
      online: widget.online,
      photo: b == null ? null : MemoryImage(b),
    );
    if (widget.grey && !widget.blocked) {
      a = Opacity(opacity: 0.55, child: a);
    }
    return a;
  }
}
