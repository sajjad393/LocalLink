import 'dart:async';

import 'package:locallink/core/widgets/link_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:locallink/core/identity/person_name_276.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/features/admin/presentation/screens/link_paths_full_screen.dart';
import 'package:locallink/features/contacts/presentation/widgets/mini_map_zoom_298.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_block_confirm.dart' show BlockTarget;
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';

/// Bundle 273: "My links" - a small map at the top of Chats for EVERY user:
/// You in the middle, only your contacts around you, a line per contact by
/// how it is reached now (Wi-Fi teal, Wi-Fi Direct yellow, Mesh purple,
/// server blue through the cloud). Offline contacts are grey, no line.
///
/// Mesh with a relay: You -> relay -> contact. A relay that is one of your
/// contacts shows as that contact; any other phone is the LinkUp logo (no
/// name, no photo, no id). 2+ phones in between = one logo with "+N".
/// Never shown: links between other people, server map data, phone names.
/// Drawn only from PresenceHub (local, live) - no network, no background work.

class MyLinkContact273 {
  const MyLinkContact273({required this.deviceId, required this.userId, required this.name});
  final String deviceId;
  final String userId;
  final String name;
}

class MyLinks273 {
  const MyLinks273({
    required this.nodes,
    required this.edges,
    required this.live,
    required this.offline,
    required this.relaysKnown,
    required this.relaysLogo,
  });

  final List<LinkNode> nodes;
  final List<LinkEdge> edges;
  final int live, offline, relaysKnown, relaysLogo;

  static const String relayPrefix = 'relay:';

  /// Pure: contacts + their live ways -> map nodes and lines.
  static MyLinks273 build({
    required List<MyLinkContact273> contacts,
    required PresenceWayInfo Function(String deviceId) wayOf,
    String? Function(String deviceId)? userOf,
  }) {
    final byDevice = <String, MyLinkContact273>{};
    final byUser = <String, MyLinkContact273>{};
    final list = <MyLinkContact273>[];
    for (final c in contacts) {
      if (c.deviceId.isEmpty || byDevice.containsKey(c.deviceId)) continue;
      if (c.userId.isNotEmpty && byUser.containsKey(c.userId)) continue;
      byDevice[c.deviceId] = c;
      if (c.userId.isNotEmpty) byUser[c.userId] = c;
      list.add(c);
    }
    MyLinkContact273? contactOf(String device) {
      final direct = byDevice[device];
      if (direct != null) return direct;
      final u = userOf?.call(device) ?? '';
      return u.isEmpty ? null : byUser[u];
    }

    final nodes = <LinkNode>[];
    final edges = <LinkEdge>[];
    final relayNodes = <String, LinkNode>{};
    final ownLine = <String>{}; // contacts with a line of their own from You
    var live = 0, off = 0, known = 0, logo = 0;
    final ways = {for (final c in list) c.deviceId: wayOf(c.deviceId)};
    // Live first, then offline (upper grey arc).
    list.sort((a, b) {
      final ao = ways[a.deviceId]!.way == PresenceWay.offline ? 1 : 0;
      final bo = ways[b.deviceId]!.way == PresenceWay.offline ? 1 : 0;
      if (ao != bo) return ao - bo;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    for (final c in list) {
      final info = ways[c.deviceId]!;
      final name = personName276(c.name);
      switch (info.way) {
        case PresenceWay.offline:
          off++;
          nodes.add(
              LinkNode(id: c.deviceId, label: name, tag: LinkTag.mesh, userId: c.userId, offline: true, noLine: true));
        case PresenceWay.online:
          live++;
          nodes.add(LinkNode(id: c.deviceId, label: name, tag: LinkTag.server, userId: c.userId));
        case PresenceWay.wifi:
          live++;
          ownLine.add(c.deviceId);
          nodes.add(LinkNode(id: c.deviceId, label: name, tag: LinkTag.localWifi, userId: c.userId));
        case PresenceWay.wifiDirect:
          live++;
          ownLine.add(c.deviceId);
          nodes.add(LinkNode(id: c.deviceId, label: name, tag: LinkTag.wifiDirect, userId: c.userId));
        case PresenceWay.connecting:
          live++;
          nodes.add(LinkNode(id: c.deviceId, label: name, tag: LinkTag.localWifi, userId: c.userId, noLine: true));
          edges.add(LinkEdge(LinkEdge.self, c.deviceId, LinkTag.localWifi, blocked: true)); // grey dashed
        case PresenceWay.mesh:
        case PresenceWay.nearby:
          live++;
          nodes.add(LinkNode(id: c.deviceId, label: name, tag: LinkTag.mesh, userId: c.userId, noLine: true));
          final via = (info.via ?? '').trim();
          if (info.way != PresenceWay.mesh || via.isEmpty || via == c.deviceId) {
            edges.add(LinkEdge(LinkEdge.self, c.deviceId, LinkTag.mesh));
            continue;
          }
          final between = info.phonesBetween ?? 1;
          final friend = contactOf(via);
          if (friend != null && friend.deviceId != c.deviceId) {
            known++;
            edges.add(LinkEdge(friend.deviceId, c.deviceId, LinkTag.mesh));
            edges.add(LinkEdge(LinkEdge.self, friend.deviceId, LinkTag.mesh));
          } else {
            final id = '$relayPrefix$via';
            if (!relayNodes.containsKey(id)) {
              logo++;
              relayNodes[id] = LinkNode(
                  id: id,
                  label: '',
                  tag: LinkTag.mesh,
                  relay: true,
                  noLine: true,
                  hiddenMore: between >= 2 ? between - 1 : 0);
              edges.add(LinkEdge(LinkEdge.self, id, LinkTag.mesh));
            }
            edges.add(LinkEdge(id, c.deviceId, LinkTag.mesh));
          }
      }
    }
    nodes.addAll(relayNodes.values);
    // A friend relay with its own line from You needs no second one.
    final seen = <String>{};
    final clean = <LinkEdge>[
      for (final e in edges)
        if (!(e.from == LinkEdge.self && ownLine.contains(e.to)) && seen.add(e.key)) e,
    ];
    return MyLinks273(nodes: nodes, edges: clean, live: live, offline: off, relaysKnown: known, relaysLogo: logo);
  }

  String get summary => '$live live · $offline offline';
}

/// Bundle 273: Settings › Privacy › "Show My links map" (on by default).
class MyLinksSetting273 extends ChangeNotifier {
  MyLinksSetting273._();
  static final MyLinksSetting273 instance = MyLinksSetting273._();
  static const String key = 'my_links_card_273';

  bool _on = true;
  Future<void> Function(String key, String value)? _write;
  bool get on => _on;

  Future<void> load({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
  }) async {
    _write = write;
    try {
      final next = (await read(key) ?? '1') != '0';
      if (next != _on) {
        _on = next;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> set(bool value) async {
    if (value == _on) return;
    _on = value;
    notifyListeners();
    AppLogger.info('MYMAP_273', detail: value ? 'shown' : 'hidden');
    try {
      await _write?.call(key, value ? '1' : '0');
    } catch (_) {}
  }

  @visibleForTesting
  void debugSet(bool value) {
    _on = value;
    _write = null;
    notifyListeners();
  }
}

/// Bundle 273: the card at the top of Chats.
class MyLinksCard273 extends StatefulWidget {
  const MyLinksCard273({
    super.key,
    required this.loadContacts,
    required this.serverOnline,
    required this.onOpenChat,
    this.selfId,
    this.selfUserId,
    this.selfName = 'You',
    this.hub,
  });

  final Future<List<MyLinkContact273>> Function() loadContacts;
  final ValueListenable<bool> serverOnline;
  final void Function(String deviceId) onOpenChat;
  final String? selfId;
  final String? selfUserId;
  final String selfName;
  final PresenceHub? hub;

  @override
  State<MyLinksCard273> createState() => _MyLinksCard273State();
}

class _MyLinksCard273State extends State<MyLinksCard273> {
  List<MyLinkContact273> _contacts = const [];
  bool _logged = false;
  Timer? _reload;

  PresenceHub get _hub => widget.hub ?? PresenceHub.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // New / removed contacts show within a minute (local DB only).
    _reload = Timer.periodic(const Duration(seconds: 60), (_) => unawaited(_load()));
  }

  Future<void> _load() async {
    try {
      final list = await widget.loadContacts();
      if (mounted) setState(() => _contacts = list);
    } catch (_) {}
  }

  /// Bundle 298 (D): pinch zoom of the small map ("Reset" shows when moved).
  final TransformationController _zoom298 = TransformationController();

  @override
  void dispose() {
    _reload?.cancel();
    _zoom298.dispose();
    super.dispose();
  }

  MyLinks273 _build() => MyLinks273.build(contacts: _contacts, wayOf: _hub.wayInfoOf, userOf: _hub.userOf);

  void _relayNote() => LinkToast.show(context, "A LinkUp phone helping to pass your messages. It can't read them.", kind: LinkToastKind.info);

  void _openFull(bool online) {
    AppLogger.info('MYMAP_273', detail: 'full_open');
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ListenableBuilder(
        listenable: _hub,
        builder: (context, _) {
          final now = _build();
          return LinkPathsFullScreen(
            nodes: now.nodes,
            extraEdges: now.edges,
            serverOnline: online,
            userMode: true,
            title: 'My links',
            userSubtitle: now.summary,
            onUserTap: (n) {
              Navigator.of(context).maybePop();
              widget.onOpenChat(n.id);
            },
            targetFor: (n) => BlockTarget(userId: n.userId, deviceIds: [n.id], name: n.label),
            selfName: widget.selfName,
            selfId: widget.selfId,
            selfUserId: widget.selfUserId,
          );
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([MyLinksSetting273.instance, _hub, widget.serverOnline]),
      builder: (context, _) {
        if (!MyLinksSetting273.instance.on || _contacts.isEmpty) return const SizedBox.shrink();
        final m = _build();
        if (!_logged) {
          _logged = true;
          AppLogger.info('MYMAP_273',
              detail:
                  'contacts=${_contacts.length} live=${m.live} relays_known=${m.relaysKnown} relays_logo=${m.relaysLogo}');
        }
        final online = widget.serverOnline.value;
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          key: const ValueKey('my_links_card_273'),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _openFull(online),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                child: Stack(children: [
                  LinkPathsMap(
                    title: 'My links',
                    subtitle: m.summary,
                    height: 110,
                    nodes: m.nodes,
                    extraEdges: m.edges,
                    serverOnline: online,
                    selfName: widget.selfName,
                    selfId: widget.selfId,
                    selfUserId: widget.selfUserId,
                    emptyText: 'No contacts yet',
                    onNodeTap: (n) => n.relay ? _relayNote() : widget.onOpenChat(n.id),
                    wrapCanvas: (canvas) => MiniMapZoomBox298(controller: _zoom298, child: canvas),
                    legendEnd: MiniMapReset298(controller: _zoom298),
                  ),
                  Positioned(
                    right: 0,
                    top: -6,
                    child: PopupMenuButton<String>(
                      key: const ValueKey('my_links_menu_273'),
                      tooltip: 'More',
                      icon: Icon(Icons.more_vert_rounded, size: 18, color: scheme.onSurfaceVariant),
                      onSelected: (v) {
                        if (v == 'hide') unawaited(MyLinksSetting273.instance.set(false));
                        if (v == 'open') _openFull(online);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'open', child: Text('Full map')),
                        PopupMenuItem(value: 'hide', child: Text('Hide map')),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Bundle 273: Settings › Privacy › "Show My links map".
class MyLinksRow273 extends StatelessWidget {
  const MyLinksRow273({super.key});

  @override
  Widget build(BuildContext context) {
    final s = MyLinksSetting273.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => MessengerSettingsRow(
        key: const ValueKey('settings_my_links'),
        icon: Icons.hub_outlined,
        title: 'Show My links map',
        subtitle: 'A small map of your contacts at the top of Chats',
        onTap: () => s.set(!s.on),
        trailing: Switch(key: const ValueKey('settings_my_links_switch'), value: s.on, onChanged: s.set),
      ),
    );
  }
}
