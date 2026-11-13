import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/presentation/widgets/link_apart_291.dart';
import 'package:locallink/core/widgets/admin_crown.dart';
import 'package:locallink/features/admin/data/services/admin_badge_book.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Which link one map edge represents. Drives colour + placement sector.
enum LinkTag { server, wifiDirect, mesh, localWifi }

/// One device on the link map.
class LinkNode {
  final String id;
  final String label;
  final LinkTag tag;

  /// Bundle 212: blocked by admin - grey node, red ring, red badge, grey
  /// dashed line (it relays others' sealed messages only).
  final bool blocked;

  /// Bundle 216 (C): the account behind the phone ('' = unknown). Used for
  /// the photo, the crown and one-node-per-person.
  final String userId;

  /// Bundle 216: admin known from the data itself (UI check data, link map).
  final bool admin;

  /// TODO 290: the admin level from the data ('' = from the admin cards).
  final String adminRole;

  /// Bundle 273: a phone that passes messages but is not a contact - drawn
  /// as the LinkUp logo, no name, no photo ([hiddenMore] = "+N" phones).
  final bool relay;
  final int hiddenMore;

  /// Bundle 273: a contact that is offline now - grey, no line.
  final bool offline;

  /// Bundle 272 / 273: no default line from You / the server (its lines
  /// come from the extra edges only).
  final bool noLine;

  const LinkNode({
    required this.id,
    required this.label,
    required this.tag,
    this.blocked = false,
    this.userId = '',
    this.admin = false,
    this.relay = false,
    this.hiddenMore = 0,
    this.offline = false,
    this.noLine = false,
    this.adminRole = '',
  });

  LinkNode copyWith({bool? blocked}) => LinkNode(
      id: id,
      label: label,
      tag: tag,
      blocked: blocked ?? this.blocked,
      userId: userId,
      admin: admin,
      relay: relay,
      hiddenMore: hiddenMore,
      offline: offline,
      noLine: noLine,
      adminRole: adminRole);
}

/// Bundle 272 (B-3): one extra line on the map, between any two ends.
/// [from] / [to] are node ids, or [self] (this phone) / [server].
class LinkEdge {
  const LinkEdge(this.from, this.to, this.tag, {this.blocked = false});

  static const String self = '#self';
  static const String server = '#server';

  final String from;
  final String to;
  final LinkTag tag;
  final bool blocked;

  /// Same line either way round.
  String get key {
    final a = from.compareTo(to) <= 0 ? from : to;
    final b = identical(a, from) ? to : from;
    return '$a|$b|${tag.name}${blocked ? '|b' : ''}';
  }

  @override
  bool operator ==(Object other) => other is LinkEdge && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Bundle 272 / 274: what the full-screen map shows while it is open (live).
class LinkMapLive272 {
  const LinkMapLive272(this.nodes, this.edges);
  final List<LinkNode> nodes;
  final List<LinkEdge> edges;
}

/// Bundle 216 (C): one map node per phone / person. Rules:
/// 1. removed (revoked) phones are dropped;
/// 2. two records of the same account → only the newest one stays;
/// 3. same phone name, one live (< 4 min) and one stale → the stale one
///    goes (an old account on the same phone);
/// 4. this phone's own ids ([ownIds]) never show as another phone.
({List<T> kept, int hidden}) dedupeNodes<T>(
  List<T> items, {
  required String Function(T) deviceId,
  required String Function(T) userId,
  required String Function(T) phoneName,
  required DateTime? Function(T) seenAt,
  bool Function(T)? revoked,
  Set<String> ownIds = const {},
  DateTime? now,
}) {
  final at = (now ?? DateTime.now()).toUtc();
  bool live(T x) {
    final t = seenAt(x);
    return t != null && at.difference(t.toUtc()).inMinutes < 4;
  }

  var list = [
    for (final x in items)
      if (!(revoked?.call(x) ?? false) && !ownIds.contains(deviceId(x))) x,
  ];
  // Rule 2: newest per account.
  final byUser = <String, T>{};
  for (final x in list) {
    final u = userId(x).trim();
    if (u.isEmpty) continue;
    final old = byUser[u];
    if (old == null) {
      byUser[u] = x;
      continue;
    }
    final a = seenAt(x)?.millisecondsSinceEpoch ?? 0;
    final b = seenAt(old)?.millisecondsSinceEpoch ?? 0;
    if (a > b) byUser[u] = x;
  }
  list = [
    for (final x in list)
      if (userId(x).trim().isEmpty || identical(byUser[userId(x).trim()], x)) x,
  ];
  // Rule 3: same phone name, live beats stale.
  final liveNames = <String>{
    for (final x in list)
      if (live(x) && phoneName(x).trim().isNotEmpty) phoneName(x).trim().toLowerCase(),
  };
  list = [
    for (final x in list)
      if (live(x) ||
          phoneName(x).trim().isEmpty ||
          !liveNames.contains(phoneName(x).trim().toLowerCase()))
        x,
  ];
  return (kept: list, hidden: items.length - list.length);
}

/// Bundle 216: `MAP_NODES shown= hidden_dupes=` once per map open.
void logMapNodes216(int shown, int hidden) =>
    AppLogger.info('MAP_NODES', detail: 'shown=$shown hidden_dupes=$hidden');

/// Bundle 212: blocked node colours.
const Color kLinkBlockedGrey = Color(0xFF9CA3AF);
const Color kLinkBlockedRed = Color(0xFFD92D20);

/// Tints matching the app’s transport language (chips / dividers).
/// Bundle 216: the UI_SPEC_216 link colours.
const kLinkTagColors = <LinkTag, Color>{
  LinkTag.server: Color(0xFF3B82C4), // Bundle 272 (A-1): server = blue
  LinkTag.wifiDirect: Color(0xFFE8A317),
  LinkTag.mesh: Color(0xFF7C5CDB),
  LinkTag.localWifi: Color(0xFF14A3A0),
};

A216Link linkOfTag216(LinkTag t) => switch (t) {
      LinkTag.server => A216Link.server,
      LinkTag.wifiDirect => A216Link.wifiDirect,
      LinkTag.mesh => A216Link.mesh,
      LinkTag.localWifi => A216Link.lan,
    };

String linkTagLabel(LinkTag tag) => switch (tag) {
      LinkTag.server => 'Server',
      LinkTag.wifiDirect => 'Wi-Fi Direct',
      LinkTag.mesh => 'Mesh',
      LinkTag.localWifi => 'Local Wi-Fi',
    };

/// Bundle 134 / 216: “Link paths” — the offline admin link map. This phone
/// in the middle, the server cloud, and every known phone as its round
/// profile photo with the name under it (216 C), joined by coloured lines
/// by link. Deterministic placement (sorted by id) so it never reshuffles.
class LinkPathsMap extends StatelessWidget {
  final List<LinkNode> nodes;
  final bool serverOnline;

  /// Bundle 212 (E6): the expand button (full-screen map); none when null.
  final VoidCallback? onExpand;

  /// Bundle 216: canvas height (the admin home card uses 104).
  final double height;

  /// Bundle 216: this phone ("You") photo.
  final String selfName;
  final String? selfId;
  final String? selfUserId;
  final ValueChanged<LinkNode>? onNodeTap;

  /// Bundle 216: card head ('Link paths' / 'Who is linked to whom, live').
  final String? title;
  final String? subtitle;

  /// Bundle 272 (B-3): lines between other phones / server -> phone.
  final List<LinkEdge> extraEdges;

  /// Bundle 273: the grey note with nobody on the map.
  final String emptyText;

  const LinkPathsMap({
    this.title,
    this.subtitle,
    super.key,
    required this.nodes,
    required this.serverOnline,
    this.onExpand,
    this.height = 300,
    this.selfName = 'You',
    this.selfId,
    this.selfUserId,
    this.onNodeTap,
    this.extraEdges = const [],
    this.emptyText = 'No other phones linked',
  });

  static Set<A216Link> linksOf(List<LinkNode> nodes, bool serverOnline,
          [List<LinkEdge> extraEdges = const []]) =>
      {
        if (serverOnline) A216Link.server,
        for (final n in nodes)
          if (!n.blocked && !n.offline) linkOfTag216(n.tag),
        for (final e in extraEdges)
          if (!e.blocked) linkOfTag216(e.tag),
      };

  @override
  Widget build(BuildContext context) {
    AdminPersonAvatar216.noteYouName(selfName); // Bundle 254 (21.5)
    final c = A216.colors(context);
    final links = linksOf(nodes, serverOnline, extraEdges);
    final t = A216Text(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null || onExpand != null)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) Text(title!, style: t.cardTitle),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: t.cardSub),
                  ],
                ],
              ),
            ),
            if (onExpand != null)
              Material(
                color: c.div,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const ValueKey('link_paths_expand'),
                  onTap: onExpand,
                  child: Tooltip(
                    message: 'Full screen',
                    child: SizedBox(
                        width: 30,
                        height: 30,
                        child: Icon(Icons.open_in_full_rounded,
                            size: 15, color: c.ink2)),
                  ),
                ),
              ),
          ]),
        // Bundle 216 (page 3): room for the crowns under the subtitle.
        // Bundle 217: 16 so the bigger crowns stay under the subtitle.
        if (title != null) const SizedBox(height: 16),
        SizedBox(
          height: height,
          child: Stack(clipBehavior: Clip.none, children: [
            // Bundle 222 (mock M-1): always You + Server, like the full map;
            // with nobody else a small grey note sits on the right.
            Positioned.fill(
              child: LinkPathsCanvas(
                      nodes: nodes,
                      serverOnline: serverOnline,
                      nodeRadius: 14,
                      small: true,
                      selfName: selfName,
                      selfId: selfId,
                      selfUserId: selfUserId,
                      onNodeTap: onNodeTap,
                      extraEdges: extraEdges,
                    ),
            ),
            if (linkMapUserCount(nodes) == 0)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Text(emptyText,
                      key: const ValueKey('link_paths_empty'),
                      style: A216Text(c).note),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            LinkLegend216(links: links),
            if (nodes.any((n) => n.blocked)) const LinkBlockedLegend(),
          ],
        ),
      ],
    );
  }
}

/// Bundle 222: the one count both maps use (other phones on the map; You
/// and the Server are not counted), so they can never differ.
int linkMapUserCount(List<LinkNode> nodes) => nodes.length;

/// Bundle 212: "Blocked · relays only" in the legend.
class LinkBlockedLegend extends StatelessWidget {
  const LinkBlockedLegend({super.key});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: kLinkBlockedGrey,
                  shape: BoxShape.circle,
                  border: Border.all(color: kLinkBlockedRed, width: 1.4))),
          const SizedBox(width: 5),
          Text('Blocked · relays only', style: A216Text.of(context).legend),
        ],
      );
}

/// Bundle 217: when the map lines may move (TODO_217 §2.2). Off with
/// Android "Remove animations", battery saver, or the app paused.
class LinkMotion217 {
  static final ValueNotifier<bool> powerSave = ValueNotifier(false);

  /// Tests: true / false forces motion on / off; null = the real rules.
  static bool? debugForce;

  /// UI check only: draw the dots frozen at this phase (0..1); null = live.
  @visibleForTesting
  static double? debugPhase;

  /// Tests: under `flutter test` motion stays off (old tests use
  /// pumpAndSettle) unless this is true.
  @visibleForTesting
  static bool motionInTests = false;

  static final bool _underTest =
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  static const _ch = MethodChannel('locallink/device');
  static String? _lastLog;

  static Future<void> refresh() async {
    if (_underTest) return;
    try {
      powerSave.value = (await _ch
              .invokeMethod<bool>('powerSave')
              .timeout(const Duration(milliseconds: 300))) ??
          false;
    } catch (_) {
      powerSave.value = false;
    }
  }

  /// Null = motion allowed, else why not (anim / saver / test).
  static String? whyOff(BuildContext c) {
    if (debugForce != null) return debugForce! ? null : 'test';
    if (_underTest && !motionInTests) return 'test';
    if (MediaQuery.maybeOf(c)?.disableAnimations ?? false) return 'anim';
    if (powerSave.value) return 'saver';
    return null;
  }

  static bool allowed(BuildContext c) => whyOff(c) == null;

  static void log(bool on, String? why) {
    final line = on ? 'on' : 'off why=${why ?? 'paused'}';
    if (line == _lastLog) return;
    _lastLog = line;
    AppLogger.info('LINK_MOTION', detail: line);
  }

  @visibleForTesting
  static void resetForTest() {
    debugForce = null;
    debugPhase = null;
    motionInTests = false;
    powerSave.value = false;
    _lastLog = null;
  }
}

/// Bundle 212 / 216 / 217: the map drawing (the small card and the full
/// screen): aerial moving lines + server painted, people as photo widgets
/// on top.
class LinkPathsCanvas extends StatefulWidget {
  final List<LinkNode> nodes;
  final bool serverOnline;
  final String? selectedId;
  final double spread;
  final double nodeRadius;
  final bool small;
  final String selfName;
  final String? selfId;
  final String? selfUserId;
  final ValueChanged<LinkNode>? onNodeTap;

  /// Bundle 272 (B-3): extra lines (other phones, server -> phone).
  final List<LinkEdge> extraEdges;

  const LinkPathsCanvas(
      {super.key,
      required this.nodes,
      required this.serverOnline,
      this.selectedId,
      this.spread = 1.0,
      this.nodeRadius = 24,
      this.small = false,
      this.selfName = 'You',
      this.selfId,
      this.selfUserId,
      this.onNodeTap,
      this.extraEdges = const []});

  @override
  State<LinkPathsCanvas> createState() => LinkPathsCanvasState();

  /// Bundle 217 (§2.1): control point of the aerial line p → q, bowing away
  /// from [centre]; k = 0.60 (full map) or 0.36 ([small] card).
  @visibleForTesting
  static Offset aerialControl(Offset p, Offset q, Offset centre, {bool small = false, double? bow}) {
    final k = bow ?? (small ? 0.36 : 0.60); // Bundle 272 (M-3): phone<->phone 0.25
    final d = q - p;
    final len = math.max(1.0, d.distance);
    final mid = Offset((p.dx + q.dx) / 2, (p.dy + q.dy) / 2);
    var n = Offset(-d.dy / len, d.dx / len);
    final o = mid - centre;
    if (o.distance < 1) {
      if (n.dy > 0) n = -n;
    } else if (o.dx * n.dx + o.dy * n.dy < 0) {
      n = -n;
    }
    return mid + n * (k * len);
  }

  Widget _buildWith(BuildContext context, Animation<double> flow, bool motion) {
    final c = A216.colors(context);
    final t = A216Text(c);
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      final painter = _LinkPathsPainter(
        nodes: nodes,
        serverOnline: serverOnline,
        labelColor: c.ink2,
        selectedId: selectedId,
        spread: spread,
        drawNodes: false,
        nodeR: nodeRadius,
        dotColor: c.mapDot,
        grid: !small,
        flow: flow,
        motion: motion,
        dark: c.dark,
        small: small,
        extraEdges: extraEdges,
      );
      final place = painter._placements(size);
      final self = painter._self(size);
      final bg = small ? c.surface : c.bgMap;
      Widget person(Offset at, {required String id, String userId = '', required String name,
          bool blocked = false, bool admin = false, bool me = false, LinkNode? node}) {
        final r = nodeRadius;
        // Bundle 273: a non-contact relay = the LinkUp logo (no name/photo);
        // an offline contact = grey.
        final Widget avatar = node != null && node.relay
            ? LinkRelayAvatar273(radius: r, more: node.hiddenMore, background: bg)
            : node != null && node.offline
                ? Opacity(
                    opacity: 0.45,
                    child: ColorFiltered(
                      colorFilter: kLinkGreyFilter273,
                      child: AdminPersonAvatar216(
                          name: name,
                          deviceId: id.isEmpty ? null : id,
                          userId: userId.isEmpty ? null : userId,
                          radius: r,
                          background: bg),
                    ))
                : AdminPersonAvatar216(
                    name: name,
                    deviceId: id.isEmpty ? null : id,
                    userId: userId.isEmpty ? null : userId,
                    radius: r,
                    admin: admin,
                    blocked: blocked,
                    background: bg,
                  );
        final noLabel = node != null && node.relay && name.trim().isEmpty;
        final label = noLabel
            ? const SizedBox.shrink()
            : small
            ? Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.miniMapName)
            : Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: c.dark ? null : const [A216.pillShadow],
                ),
                // Bundle 217 (mock A-2): pill as wide as the name.
                child: Center(
                  widthFactor: 1,
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.mapName),
                ),
              );
        final w = small ? 76.0 : 110.0;
        return Positioned(
          key: ValueKey('link_node_${me ? 'self' : id}'),
          left: at.dx - w / 2,
          top: at.dy - r,
          width: w,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: node == null || onNodeTap == null ? null : () => onNodeTap!(node),
            child: IgnorePointer(
              ignoring: onNodeTap == null || node == null,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                  if (node != null && node.id == selectedId)
                    Positioned(
                      left: -5,
                      top: -5,
                      right: -5,
                      bottom: -5,
                      child: Container(
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: c.blue.withValues(alpha: 0.16))),
                    ),
                  avatar,
                ]),
                SizedBox(height: small ? 3 : 6),
                label,
                if (blocked && !small) ...[
                  const SizedBox(height: 4),
                  const AdminTag216('Blocked', A216Tone.red),
                ],
              ]),
            ),
          ),
        );
      }

      return Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: CustomPaint(painter: painter)),
        for (final n in nodes)
          if (place[n.id] != null)
            person(place[n.id]!,
                id: n.id,
                userId: n.userId,
                name: n.label,
                blocked: n.blocked,
                admin: n.admin,
                node: n),
        person(self,
            id: selfId ?? '',
            userId: selfUserId ?? '',
            name: 'You',
            me: true,
            admin: AdminBadgeBook.instance.selfAdmin),
      ]);
    });
  }

  /// Where each node sits on a canvas of [size] (tap test on full screen).
  /// Bundle 291: [nodeRadius] = the photo size the map draws (24 on the
  /// full screen), so taps find the same (pushed apart) spots.
  static Map<String, Offset> placements(List<LinkNode> nodes, Size size,
          {double spread = 1.0, double nodeRadius = 24}) =>
      _LinkPathsPainter(
              nodes: nodes,
              serverOnline: true,
              labelColor: Colors.black,
              spread: spread,
              drawNodes: false,
              nodeR: nodeRadius)
          ._placements(size);
}

/// Bundle 217: runs the line motion (one 6 s cycle = 3 dash loops + 2 dot
/// trips) and stops it per [LinkMotion217].
class LinkPathsCanvasState extends State<LinkPathsCanvas>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _flow =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));
  bool _paused = false;
  static bool _refreshed = false;

  @visibleForTesting
  bool get debugAnimating => _flow.isAnimating;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LinkMotion217.powerSave.addListener(_onSaver);
    if (!_refreshed) {
      _refreshed = true;
      unawaited(LinkMotion217.refresh());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion(rebuild: false);
  }

  void _onSaver() {
    if (mounted) _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _paused = true;
      _syncMotion();
    } else if (state == AppLifecycleState.resumed) {
      _paused = false;
      _syncMotion();
      unawaited(LinkMotion217.refresh());
    }
  }

  void _syncMotion({bool rebuild = true}) {
    final why = _paused ? 'paused' : LinkMotion217.whyOff(context);
    final on = why == null;
    var changed = false;
    if (on && !_flow.isAnimating) {
      _flow.repeat();
      changed = true;
    } else if (!on && _flow.isAnimating) {
      _flow.stop();
      _flow.value = 0;
      changed = true;
    }
    LinkMotion217.log(on, why);
    if (changed && rebuild && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LinkMotion217.powerSave.removeListener(_onSaver);
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget._buildWith(context, _flow, _flow.isAnimating);
}

class _LinkPathsPainter extends CustomPainter {
  final List<LinkNode> nodes;
  final bool serverOnline;
  final Color labelColor;
  final String? selectedId;

  _LinkPathsPainter({
    required this.nodes,
    required this.serverOnline,
    required this.labelColor,
    this.selectedId,
    this.spread = 1.0,
    this.drawNodes = true,
    this.nodeR = 11,
    this.dotColor,
    this.grid = true,
    this.flow,
    this.motion = false,
    this.dark = false,
    this.small = false,
    this.extraEdges = const [],
  })  : crownKey = [
          for (final n in nodes)
            if (!n.blocked && AdminCrown.showFor(n.id)) n.id,
          if (AdminBadgeBook.instance.selfAdmin) 'self',
        ].join(','),
        super(repaint: flow);

  /// Bundle 217: the motion clock (repaints only the canvas), whether it
  /// runs, the theme and the small card (k 0.36 instead of 0.60).
  final Animation<double>? flow;
  final bool motion;
  final bool dark;
  final bool small;

  /// Bundle 272 (B-3): extra lines drawn after the default ones.
  final List<LinkEdge> extraEdges;

  /// Bundle 214 (D6): who gets a crown 👑 above the node (snapshot).
  final String crownKey;

  /// Bundle 212: 1 on the card; bigger on the full-screen map.
  final double spread;

  /// Bundle 216: people are photo widgets on top; the painter draws only
  /// the grid, the lines and the server.
  final bool drawNodes;
  final double nodeR;
  final Color? dotColor;
  final bool grid;

  /// Bundle 216: line width (2.2 small map, 2.4 full map).
  double get _lw => drawNodes ? 1.8 : (nodeR < 20 ? 2.2 : 2.4);

  static const _selfRadius = 24.0;
  static const _nodeRadius = 11.0;

  Offset _self(Size size) => Offset(size.width * 0.47, size.height * 0.66);
  Offset _server(Size size) => Offset(size.width * 0.15, size.height * 0.18);

  /// Deterministic placement: yellow WD fan to the left, purple mesh chains
  /// up-right, teal LAN down-right, green cloud near the server.
  /// Bundle 291 (B-4): photo radius the people are drawn with.
  double get _r291 => drawNodes ? _nodeRadius : nodeR;

  /// Bundle 291 (B-4): what the spots depend on (cache key).
  String _key291(Size size) => '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}'
      '|$spread|$_r291|$small|${[for (final n in nodes) '${n.id}:${n.tag.index}:${n.offline ? 1 : 0}'].join(',')}';

  /// Bundle 291 (B-4): the 212 spots, then pushed apart so no two people
  /// (photo + name) and nobody and me / the server sit on top of each other.
  Map<String, Offset> _placements(Size size) => LinkApart291.cached(
      _key291(size),
      () => LinkApart291.apart(_placements212(size), size,
          r: _r291, fixed: [_self(size), _server(size)], small: small));

  Map<String, Offset> _placements212(Size size) {
    final sorted = [...nodes]..sort((a, b) => a.id.compareTo(b.id));
    final byTag = <LinkTag, List<LinkNode>>{
      for (final tag in LinkTag.values)
        tag: [for (final n in sorted) if (n.tag == tag && !n.offline) n],
    };
    final result = <String, Offset>{};
    final s = _self(size);
    final sv = _server(size);
    // Bundle 273: offline contacts sit on an upper arc, grey, no line.
    final off = [for (final n in sorted) if (n.offline) n];
    for (var i = 0; i < off.length; i++) {
      final f = off.length == 1 ? 0.5 : i / (off.length - 1);
      final angle = (200 + 140 * f) * math.pi / 180;
      final r = (118.0 + 22 * (i % 2)) * spread;
      final x = s.dx + math.cos(angle) * r * 1.25;
      final y = s.dy + math.sin(angle) * r * 0.82;
      result[off[i].id] = Offset(x.clamp(16.0, size.width - 16.0), y.clamp(16.0, size.height - 34.0));
    }

    // sector definitions: (startAngleDeg, endAngleDeg) with screen coords
    // (0deg = right, 90deg = down, 180deg = left, 270deg = up).
    const sectors = <LinkTag, (double, double)>{
      LinkTag.wifiDirect: (150, 245),
      LinkTag.mesh: (295, 348),
      LinkTag.localWifi: (18, 68),
      LinkTag.server: (0, 0), // placed around the cloud instead
    };
    for (final tag in LinkTag.values) {
      final list = byTag[tag]!;
      if (list.isEmpty) continue;
      for (var i = 0; i < list.length; i++) {
        if (tag == LinkTag.server) {
          // Small fan hugging the cloud edge.
          final angle = (-55 + (88 / math.max(1, list.length - 1)) * i) *
              math.pi /
              180;
          final ring = (62 + 18 * (i % 3)) * spread;
          result[list[i].id] =
              Offset(sv.dx + math.cos(angle) * ring, sv.dy + math.sin(angle) * ring * 0.75 + 4);
          continue;
        }
        final (startDeg, endDeg) = sectors[tag]!;
        final span = (endDeg - startDeg) / math.max(1, list.length - 1);
        final jitter = ((list[i].id.hashCode % 21) - 10) / 10.0;
        final angleDeg = startDeg + span * i + jitter * 4;
        final angle = angleDeg * math.pi / 180;
        // Bundle 212: more rings and wider ones on the big map ([spread]).
        final rings = (tag == LinkTag.mesh ? 3 : 2) +
            (spread > 1 ? (list.length ~/ 6) : 0);
        final ringBase = (tag == LinkTag.mesh ? 74.0 : 92.0) * spread;
        final ringStep = (tag == LinkTag.mesh ? 30.0 : 44.0) * spread;
        final r = ringBase + ringStep * (i % rings) + jitter * 6;
        final x = s.dx + math.cos(angle) * r;
        final y = s.dy + math.sin(angle) * r * 0.82;
        result[list[i].id] = Offset(
            x.clamp(16.0, size.width - 16.0), y.clamp(16.0, size.height - 34.0));
      }
    }
    return result;
  }

  /// Bundle 217 (§2.1): quadratic aerial path p → q bowing away from [centre].
  Path _aerial(Offset p, Offset q, Offset centre, [LinkRoute291? route]) {
    // Bundle 291 (B-4): the router keeps the line off third photos / lines.
    final ctrl = route == null
        ? LinkPathsCanvas.aerialControl(p, q, centre, small: small)
        : route.pick(p, q, centre, small ? 0.36 : 0.60);
    return Path()
      ..moveTo(p.dx, p.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, q.dx, q.dy);
  }

  /// Bundle 217: centre of everything on the map (self, server, nodes).
  Offset _centre(Offset s, Offset sv, Map<String, Offset> place) {
    var x = s.dx + sv.dx, y = s.dy + sv.dy;
    for (final o in place.values) {
      x += o.dx;
      y += o.dy;
    }
    final n = place.length + 2;
    return Offset(x / n, y / n);
  }

  /// Bundle 217 (§2.1 layers 1-4): glow, base, moving dashes, glow dot.
  void _flowLine(Canvas canvas, Path path, Color color, int index) {
    final lw = _lw;
    canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: dark ? 0.45 : 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = lw + 6
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    _stroke(canvas, path, color.withValues(alpha: 0.55), lw);
    final dash = dark
        ? Color.lerp(color, Colors.white, 0.5)!
        : Color.lerp(color, Colors.black, 0.12)!;
    final phase = LinkMotion217.debugPhase;
    final moving = motion || phase != null;
    final v = phase ?? (motion ? (flow?.value ?? 0.0) : 0.0);
    final offset = ((v * 3) % 1) * 20;
    for (final m in path.computeMetrics()) {
      final len = m.length;
      for (var d = offset - 20; d < len; d += 20) {
        final a = math.max(0.0, d), b = math.min(len, d + 6);
        if (b > a) _stroke(canvas, m.extractPath(a, b), dash, lw);
      }
      if (!moving || len < 1) continue;
      final at = (((v * 2) + index * 0.23) % 1) * len;
      const parts = 6;
      final tail = len * 0.14;
      final tailColor = dark ? Colors.white : color;
      for (var j = 0; j < parts; j++) {
        final b = at - tail * j / parts;
        final a = at - tail * (j + 1) / parts;
        if (b <= 0) break;
        _stroke(canvas, m.extractPath(math.max(0.0, a), b),
            tailColor.withValues(alpha: 0.9 * (1 - j / parts)), lw);
      }
      final tan = m.getTangentForOffset(at);
      if (tan == null) continue;
      canvas.drawCircle(tan.position, 5.5, Paint()..color = color.withValues(alpha: 0.35));
      canvas.drawCircle(tan.position, 2.6, Paint()..color = Colors.white);
      if (!dark) {
        canvas.drawCircle(
            tan.position,
            2.6,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4);
      }
    }
  }

  void _stroke(Canvas canvas, Path path, Color color, double width) {
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round);
  }

  void _dashedServerLink(Canvas canvas, Offset from, Offset to, Offset centre) {
    // Offline server: alternating grey / red dashes, unmistakable (217: on
    // the aerial path, no motion).
    final path = _aerial(from, to, centre);
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      final total = metric.length;
      const seg = 9.0;
      var d = 0.0;
      var red = false;
      while (d < total) {
        final end = math.min(total, d + seg);
        _stroke(canvas, metric.extractPath(d, end),
            red ? const Color(0xFFD6453B) : const Color(0xFF9AA7B8), 2.6);
        d = end + 5.5;
        red = !red;
      }
    }
  }

  void _dashed(Canvas canvas, Path path, Color color) {
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = math.min(metric.length, d + 7.0);
        _stroke(canvas, metric.extractPath(d, end), color, 1.8);
        d = end + 5.0;
      }
    }
  }

  void _grid(Canvas canvas, Size size) {
    if (!grid) return;
    // Bundle 216: map dots r 0.7 every 20.
    final paint = Paint()
      ..color = dotColor ?? labelColor.withValues(alpha: 0.06);
    const gap = 20.0;
    for (var y = gap; y < size.height; y += gap) {
      for (var x = gap; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 0.7, paint);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    _grid(canvas, size);
    final s = _self(size);
    final sv = _server(size);
    final place = _placements(size);

    // ---- edges (Bundle 217: aerial moving lines) -------------------------
    final centre = _centre(s, sv, place);
    // Bundle 291 (B-4): one router per picture (same bows every frame).
    final route = LinkRoute291.of(
        '${_key291(size)}|$serverOnline|$small|'
        '${[for (final n in nodes) '${n.noLine ? 1 : 0}${n.blocked ? 1 : 0}'].join()}|'
        '${[for (final e in extraEdges) '${e.from}>${e.to}:${e.tag.index}:${e.blocked ? 1 : 0}'].join(',')}',
        obstacles: [s, sv, ...place.values],
        clear: _r291 + 10,
        midGap: small ? 12 : 16);
    var index = 0;
    // Server link from self (dashed red/grey when down, green when up).
    if (serverOnline) {
      _flowLine(canvas, _aerial(s, sv, centre, route), kLinkTagColors[LinkTag.server]!, index++);
    } else {
      _dashedServerLink(canvas, s, sv, centre);
      index++;
    }

    // Green arcs: server → the devices it reaches.
    for (final n in nodes) {
      if (n.tag != LinkTag.server || n.noLine || n.offline) continue;
      final pos = place[n.id]!;
      if (n.blocked) {
        _dashed(canvas, _aerial(sv, pos, centre, route), kLinkBlockedGrey);
        continue;
      }
      _flowLine(canvas, _aerial(sv, pos, centre, route), kLinkTagColors[LinkTag.server]!, index++);
    }

    // Purple mesh CHAINS: sorted links node→node marching inward to self.
    final meshNodes = [
      for (final n in nodes)
        if (n.tag == LinkTag.mesh && !n.noLine && !n.offline) place[n.id]!
    ];
    if (meshNodes.isNotEmpty) {
      meshNodes.sort((a, b) => (b - s).distance.compareTo((a - s).distance));
      var from = meshNodes.first;
      for (var i = 1; i < meshNodes.length; i++) {
        _flowLine(canvas, _aerial(from, meshNodes[i], centre, route),
            kLinkTagColors[LinkTag.mesh]!, index++);
        from = meshNodes[i];
      }
      _flowLine(canvas, _aerial(from, s, centre, route), kLinkTagColors[LinkTag.mesh]!, index++);
    }

    // Yellow / teal: self → device.
    for (final n in nodes) {
      if (n.tag == LinkTag.mesh || n.tag == LinkTag.server) continue;
      if (n.noLine || n.offline) continue; // Bundle 272 / 273
      if (n.blocked) {
        // Bundle 212: grey dashed = relays others' messages only (no motion).
        _dashed(canvas, _aerial(s, place[n.id]!, centre, route), kLinkBlockedGrey);
        continue;
      }
      _flowLine(canvas, _aerial(s, place[n.id]!, centre, route), kLinkTagColors[n.tag]!, index++);
    }

    // Bundle 272 (B-3 / M-3): extra lines. Phone<->phone lines bow away
    // from the centre of the phones only, a smaller bow (0.25); server lines
    // use the normal centre. Blocked = grey dashed.
    if (extraEdges.isNotEmpty) {
      final phones = <Offset>[s, ...place.values];
      var px = 0.0, py = 0.0;
      for (final o in phones) {
        px += o.dx;
        py += o.dy;
      }
      final phoneCentre = Offset(px / phones.length, py / phones.length);
      Offset? at(String id) => id == LinkEdge.self ? s : (id == LinkEdge.server ? sv : place[id]);
      for (final e in extraEdges) {
        final a = at(e.from), b = at(e.to);
        if (a == null || b == null || a == b) continue;
        final viaServer = e.from == LinkEdge.server || e.to == LinkEdge.server;
        final ctrl = viaServer
            ? route.pick(a, b, centre, small ? 0.36 : 0.60)
            : route.pick(a, b, phoneCentre, 0.25); // Bundle 291 (B-4)
        final path = Path()
          ..moveTo(a.dx, a.dy)
          ..quadraticBezierTo(ctrl.dx, ctrl.dy, b.dx, b.dy);
        if (e.blocked) {
          _dashed(canvas, path, kLinkBlockedGrey);
        } else {
          _flowLine(canvas, path, kLinkTagColors[e.tag]!, index++);
        }
      }
    }

    // ---- server cloud --------------------------------------------------
    if (!drawNodes) {
      // Bundle 216: white circle, light blue border, blue cloud, "Server".
      final r = nodeR;
      // Bundle 217: dark map = dark circle with a blue border.
      canvas.drawCircle(sv, r, Paint()..color = dark ? const Color(0xFF161B22) : Colors.white);
      canvas.drawCircle(
          sv,
          r,
          Paint()
            ..color = dark ? const Color(0xFF2F6BFF) : const Color(0xFFB2CCFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      _text(canvas, Icons.cloud_outlined, sv,
          size: r, color: const Color(0xFF1E5BFF));
      _plainLabel(canvas, sv + Offset(0, r + 10), 'Server', r < 20 ? 10.5 : 11.5);
      return;
    }
    _glassyCircle(canvas, sv, 26, const Color(0xFFE6F1FF),
        const Color(0xFF3B82C4));
    _text(canvas, Icons.cloud_outlined, sv,
        size: 26, color: const Color(0xFF3B82C4));
    _label(canvas, sv + const Offset(0, 30), 'Server',
        strong: true);
    _label(canvas, sv + const Offset(0, 46), serverOnline ? 'online' : 'offline',
        strong: false, tiny: true);

    // ---- device nodes + labels ----------------------------------------
    for (final n in nodes) {
      final pos = place[n.id]!;
      if (n.id == selectedId) {
        canvas.drawCircle(pos, _nodeRadius + 7,
            Paint()..color = const Color(0xFF2F6BFF).withValues(alpha: 0.22));
      }
      if (n.blocked) {
        // Bundle 212: grey node, red ring, small red badge, red label.
        _glassyCircle(canvas, pos, _nodeRadius,
            kLinkBlockedGrey.withValues(alpha: 0.35), kLinkBlockedRed);
        _text(canvas, Icons.person, pos, size: 12, color: const Color(0xFF6B7280));
        final badge = pos + const Offset(_nodeRadius - 1, -_nodeRadius + 1);
        canvas.drawCircle(badge, 6, Paint()..color = Colors.white);
        canvas.drawCircle(badge, 5, Paint()..color = kLinkBlockedRed);
        _text(canvas, Icons.block, badge, size: 8, color: Colors.white);
        _label(canvas, pos + const Offset(0, _nodeRadius + 11),
            '${n.label} · Blocked',
            color: kLinkBlockedRed);
        continue;
      }
      final color = kLinkTagColors[n.tag]!;
      _glassyCircle(canvas, pos, _nodeRadius, color.withValues(alpha: 0.25),
          color.withValues(alpha: 0.9));
      _text(canvas, Icons.person, pos,
          size: 12, color: Color.lerp(color, Colors.black, 0.25)!);
      _label(canvas, pos + const Offset(0, _nodeRadius + 11), n.label);
      if (crownKey.split(',').contains(n.id)) {
        _crown(canvas, pos - const Offset(0, _nodeRadius + 7), 12);
      }
    }

    // ---- self hub ------------------------------------------------------
    final hub = Paint()..color = const Color(0xFF2F6BFF);
    canvas.drawCircle(s, _selfRadius + 5, Paint()..color = Colors.white);
    canvas.drawCircle(s, _selfRadius, hub);
    _text(canvas, Icons.person, s, size: 26, color: Colors.white);
    _label(canvas, s + const Offset(0, _selfRadius + 14), 'This phone',
        strong: true);
    if (crownKey.split(',').contains('self')) {
      _crown(canvas, s - const Offset(0, _selfRadius + 9), 18);
    }
  }

  /// Bundle 214 (D6) / 217: the admin crown above a node (the painted crown).
  void _crown(Canvas canvas, Offset center, double size) {
    paintCrown217(canvas, center - Offset(0, CrownPainter216.heightFor(size) / 2), size);
  }

  void _glassyCircle(Canvas canvas, Offset c, double r, Color fill, Color ring) {
    canvas.drawCircle(c, r + 2.5, Paint()..color = Colors.white);
    canvas.drawCircle(c, r, Paint()..color = fill);
    canvas.drawCircle(c, r, Paint()..color = ring..style = PaintingStyle.stroke..strokeWidth = 1.6);
  }

  void _text(Canvas canvas, IconData icon, Offset center,
      {required double size, required Color color}) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
            inherit: false,
            fontSize: size,
            color: color,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _plainLabel(Canvas canvas, Offset center, String text, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            inherit: false,
            fontFamily: 'Roboto216',
            fontSize: size,
            fontWeight: FontWeight.w600,
            color: labelColor),
      ),
      textDirection: TextDirection.ltr,
      // Bundle 217: pill as wide as the name (not the 92 px limit).
      textWidthBasis: TextWidthBasis.longestLine,
    )..layout(maxWidth: 92);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _label(Canvas canvas, Offset center, String text,
      {bool strong = false, bool tiny = false, Color? color}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            inherit: false,
            fontSize: tiny ? 8.5 : (strong ? 11.5 : 9.5),
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            color: color ?? labelColor.withValues(alpha: strong ? 0.9 : 0.75)),
      ),
      textDirection: TextDirection.ltr,
      // Bundle 217: pill as wide as the name (not the 92 px limit).
      textWidthBasis: TextWidthBasis.longestLine,
    )..layout(maxWidth: 92);
    const pad = const EdgeInsets.symmetric(horizontal: 6, vertical: 2);
    final pill = Rect.fromCenter(
        center: center,
        width: tp.width + pad.horizontal,
        height: tp.height + pad.vertical);
    canvas.drawRRect(
        RRect.fromRectAndRadius(pill, const Radius.circular(6)),
        Paint()
          ..color = color == null
              ? Colors.white.withValues(alpha: 0.85)
              : const Color(0xFFFDEBE9));
    tp.paint(
        canvas,
        center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_LinkPathsPainter old) =>
      old.nodes.length != nodes.length ||
      old.serverOnline != serverOnline ||
      old.nodes.map((e) => e.tag).join(',') != nodes.map((e) => e.tag).join(',') ||
      // Bundle 212
      old.selectedId != selectedId ||
      old.spread != spread ||
      old.drawNodes != drawNodes ||
      old.nodeR != nodeR ||
      old.crownKey != crownKey || // Bundle 214
      old.motion != motion || old.dark != dark || old.small != small || // Bundle 217
      old.nodes.map((e) => '${e.id}${e.blocked}${e.offline}${e.noLine}').join(',') !=
          nodes.map((e) => '${e.id}${e.blocked}${e.offline}${e.noLine}').join(',') ||
      old.extraEdges.map((e) => e.key).join(',') != extraEdges.map((e) => e.key).join(','); // Bundle 272
}

/// Bundle 273: grey for an offline contact's photo.
const ColorFilter kLinkGreyFilter273 = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// Bundle 273: a LinkUp phone that passes messages (not a contact): the
/// LinkUp logo, no name, no photo; "+N" when more phones are in between.
class LinkRelayAvatar273 extends StatelessWidget {
  const LinkRelayAvatar273({super.key, required this.radius, this.more = 0, this.background});

  final double radius;
  final int more;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final d = radius * 2;
    return SizedBox(
      key: const ValueKey('link_relay_logo'),
      width: d,
      height: d,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: background ?? Colors.white,
            border: Border.all(color: kLinkTagColors[LinkTag.mesh]!, width: 1.6),
          ),
          child: ClipOval(
            child: Padding(
              padding: EdgeInsets.all(radius * 0.22),
              child: Image.asset('assets/brand/splash_logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.hub_rounded, size: radius, color: kLinkTagColors[LinkTag.mesh])),
            ),
          ),
        ),
        if (more > 0)
          Positioned(
            right: -6,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                  color: kLinkTagColors[LinkTag.mesh], borderRadius: BorderRadius.circular(8)),
              child: Text('+$more',
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
            ),
          ),
      ]),
    );
  }
}
