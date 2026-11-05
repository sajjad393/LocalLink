import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/admin_crown.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';
import 'package:locallink/features/admin/presentation/screens/admin_blocked_list_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_block_confirm.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';

/// Map filter chips (E7).
enum LinkMapFilter { all, wifiDirect, mesh, localWifi, server, blocked }

bool linkMapFilterMatches(LinkMapFilter f, LinkNode n) => switch (f) {
      LinkMapFilter.all => true,
      LinkMapFilter.wifiDirect => n.tag == LinkTag.wifiDirect,
      LinkMapFilter.mesh => n.tag == LinkTag.mesh,
      LinkMapFilter.localWifi => n.tag == LinkTag.localWifi,
      LinkMapFilter.server => n.tag == LinkTag.server,
      LinkMapFilter.blocked => n.blocked,
    };

String linkMapFilterLabel(LinkMapFilter f) => switch (f) {
      LinkMapFilter.all => 'All',
      LinkMapFilter.wifiDirect => 'Wi-Fi Direct',
      LinkMapFilter.mesh => 'Mesh',
      LinkMapFilter.localWifi => 'Local Wi-Fi',
      LinkMapFilter.server => 'Server',
      LinkMapFilter.blocked => 'Blocked',
    };

/// The big map grows with the number of users so nodes never pile up.
Size linkMapCanvasSize(Size view, int users) => Size(
      math.max(view.width * 1.4, 420.0 + 26.0 * users),
      math.max(view.height * 1.3, 600.0 + 26.0 * users),
    );

/// Bundle 212 (E7, mock page 5): full-screen Link paths. Every device on
/// the link (full names), drag to scroll any way, pinch zoom 1x-4x, double
/// tap zooms in 2x (again = back), search, filters, tap a user → sheet.
class LinkPathsFullScreen extends StatefulWidget {
  const LinkPathsFullScreen({
    super.key,
    required this.nodes,
    required this.serverOnline,
    required this.targetFor,
    this.service,
    this.readHint,
    this.writeHint,
    this.selfName = 'You',
    this.selfId,
    this.selfUserId,
  });

  /// Bundle 216 (C): me in the middle (photo + 'You').
  final String selfName;
  final String? selfId;
  final String? selfUserId;

  final List<LinkNode> nodes;
  final bool serverOnline;
  final BlockTarget Function(LinkNode node) targetFor;
  final AdminBlockService? service;
  final Future<String?> Function(String key)? readHint;
  final Future<void> Function(String key, String value)? writeHint;

  static const String hintKey = 'link_map_hint_shown';

  @override
  State<LinkPathsFullScreen> createState() => _LinkPathsFullScreenState();
}

class _LinkPathsFullScreenState extends State<LinkPathsFullScreen> {
  final TransformationController _zoom = TransformationController();
  LinkMapFilter _filter = LinkMapFilter.all;
  String? _selected;
  bool _hint = false;
  // Bundle 217 (mock A-2): the first view shows the group, not the corner.
  bool _framed = false;
  Offset? _doubleTapAt;
  Size _view = Size.zero;

  @override
  void initState() {
    super.initState();
    _loadHint();
  }

  Future<void> _loadHint() async {
    var n = 0;
    try {
      n = int.tryParse(await widget.readHint?.call(LinkPathsFullScreen.hintKey) ?? '') ?? 0;
    } catch (_) {}
    if (n >= 3 || !mounted) return;
    setState(() => _hint = true);
    try {
      await widget.writeHint?.call(LinkPathsFullScreen.hintKey, '${n + 1}');
    } catch (_) {}
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  List<LinkNode> get _nodes {
    final book = AdminBlockBook.instance;
    return [
      for (final n in widget.nodes)
        n.copyWith(
            blocked: n.blocked || book.isBlocked(n.id) || book.isBlocked(n.userId)),
    ];
  }

  double get _spread {
    final c = linkMapCanvasSize(_view, widget.nodes.length);
    return (c.width / 380).clamp(1.4, 4.0);
  }

  void _setScale(double factor, {Offset? focus}) {
    final m = _zoom.value.clone();
    final current = m.getMaxScaleOnAxis();
    final next = (current * factor).clamp(1.0, 4.0);
    final f = next / current;
    final at = focus ?? Offset(_view.width / 2, _view.height / 2);
    _zoom.value = Matrix4.identity()
      ..translateByDouble(at.dx, at.dy, 0, 1)
      ..scaleByDouble(f, f, 1, 1)
      ..translateByDouble(-at.dx, -at.dy, 0, 1)
      ..multiply(m);
  }

  void _centreOn(Offset p, {double scale = 1.5}) {
    _zoom.value = Matrix4.identity()
      ..translateByDouble(
          _view.width / 2 - p.dx * scale, _view.height / 2 - p.dy * scale, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  /// Centre the first view on everyone shown (and "You"), kept inside the map.
  void _frameGroup(List<LinkNode> shown, Size canvas) {
    final place = LinkPathsCanvas.placements(shown, canvas, spread: _spread);
    final points = [
      ...place.values,
      Offset(canvas.width * 0.47, canvas.height * 0.66), // You
      Offset(canvas.width * 0.15, canvas.height * 0.18), // Server
    ];
    var minX = points.first.dx, maxX = minX, minY = points.first.dy, maxY = minY;
    for (final p in points) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    // Centre when the group fits (node + name margin); else keep the left /
    // top side (Server) in view.
    const margin = 44.0;
    double axis(double lo, double hi, double view) =>
        hi - lo + 2 * margin <= view ? view / 2 - (lo + hi) / 2 : margin - lo;
    final dx = axis(minX, maxX, _view.width)
        .clamp(math.min(0.0, _view.width - canvas.width), 0.0)
        .toDouble();
    final dy = axis(minY, maxY, _view.height)
        .clamp(math.min(0.0, _view.height - canvas.height), 0.0)
        .toDouble();
    _zoom.value = Matrix4.identity()..translateByDouble(dx, dy, 0, 1);
  }

  void _centre() {
    final canvas = linkMapCanvasSize(_view, widget.nodes.length);
    final self = Offset(canvas.width * 0.47, canvas.height * 0.66);
    _centreOn(self, scale: 1);
  }

  void _find(String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return;
    final nodes = _nodes;
    final hit = nodes.where((n) => n.label.toLowerCase().contains(t)).firstOrNull;
    if (hit == null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('No one called "$q" on the map')));
      return;
    }
    // Hidden by the chip filter: show everyone again, then find.
    if (!linkMapFilterMatches(_filter, hit)) _filter = LinkMapFilter.all;
    final shown = [for (final n in nodes) if (linkMapFilterMatches(_filter, n)) n];
    final canvas = linkMapCanvasSize(_view, widget.nodes.length);
    final place = LinkPathsCanvas.placements(shown, canvas, spread: _spread);
    setState(() => _selected = hit.id);
    final p = place[hit.id];
    if (p != null) _centreOn(p);
  }

  void _tapAt(Offset canvasPoint, List<LinkNode> shown, Size canvas) {
    // Same places as the painter, which draws only the shown nodes.
    final place = LinkPathsCanvas.placements(shown, canvas, spread: _spread);
    LinkNode? best;
    var bestD = 28.0;
    for (final n in shown) {
      final p = place[n.id];
      if (p == null) continue;
      final d = (p - canvasPoint).distance;
      if (d < bestD) {
        bestD = d;
        best = n;
      }
    }
    if (best == null) return;
    setState(() => _selected = best!.id);
    _sheet(best);
  }

  Future<void> _sheet(LinkNode node) async {
    await showAdminSheet216<void>(
      context,
      builder: (sheet) => ListenableBuilder(
        listenable: AdminBlockBook.instance,
        builder: (sheet, _) {
          final c = A216.colors(sheet);
          final t = A216Text(c);
          final target = widget.targetFor(node);
          final blocked = AdminBlockBook.instance.isBlocked(node.id) ||
              AdminBlockBook.instance.isBlocked(target.userId) ||
              node.blocked;
          final entry = widget.service?.entryFor(target.userId) ??
              widget.service?.entryFor(node.id);
          return Column(
            key: const ValueKey('link_map_sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                // Bundle 214 (D6) / 216: photo + crown A in the sheet title.
                if (node.admin || blocked)
                  AdminPersonAvatar216(
                    name: target.name,
                    userId: target.userId,
                    deviceId: node.id,
                    radius: 28,
                    admin: node.admin,
                    blocked: blocked,
                  )
                else
                  // Live crown: shows / goes when the admin card changes.
                  AdminCrown(
                    id: node.id,
                    otherId: target.userId,
                    radius: 28,
                    child: AdminPersonAvatar216(
                      name: target.name,
                      userId: target.userId,
                      deviceId: node.id,
                      radius: 28,
                      crown: false,
                    ),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(target.name, style: t.sheetTitle),
                    const SizedBox(height: 3),
                    Text(
                        [
                          if (target.username.isNotEmpty) '@${target.username}',
                          linkTagLabel(node.tag),
                          if (blocked) 'relays for others',
                        ].join(' · '),
                        style: t.cardSub),
                  ]),
                ),
                AdminTag216(blocked ? 'Blocked' : 'Active',
                    blocked ? A216Tone.red : A216Tone.green),
              ]),
              if (blocked && entry != null) ...[
                const SizedBox(height: 14),
                Text(
                    'Blocked by ${entry.record.signer == 'server' ? 'web panel' : (entry.record.by.isEmpty ? 'admin' : entry.record.by)}'
                    ' · ${blockWhen(entry.record.at)}'
                    '${entry.source == 'me' ? ' · reached ${entry.reached} phones' : ''}',
                    style: t.rowSub.copyWith(color: c.ink)),
                const SizedBox(height: 2),
                Text('Server: ${entry.serverDone ? 'done' : 'waiting'}', style: t.cardSub),
              ],
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton(
                      key: const ValueKey('link_map_sheet_action'),
                      style: FilledButton.styleFrom(
                          backgroundColor: blocked ? c.div : c.red,
                          foregroundColor: blocked ? c.ink : Colors.white,
                          shape: const StadiumBorder(),
                          textStyle: t.custom(14, FontWeight.w600, c.ink)),
                      onPressed: () => runAdminBlock(sheet,
                          service: widget.service, target: target, block: !blocked),
                      child: Text(blocked ? 'Unblock' : 'Block'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: c.ink,
                          side: BorderSide(color: c.ctrlBorder),
                          shape: const StadiumBorder(),
                          textStyle: t.custom(14, FontWeight.w600, c.ink)),
                      onPressed: () {
                        Navigator.of(sheet).push(MaterialPageRoute<void>(
                            builder: (_) => AdminBlockedListScreen(service: widget.service)));
                      },
                      child: const Text('Blocked list'),
                    ),
                  ),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(LinkMapFilter f, List<LinkNode> all) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final on = _filter == f;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: ValueKey('link_map_filter_${f.name}'),
        label: Text(
            '${linkMapFilterLabel(f)} ${all.where((n) => linkMapFilterMatches(f, n)).length}'),
        labelStyle: t.custom(12.5, on ? FontWeight.w600 : FontWeight.w500, on ? c.blue : c.ink2),
        selected: on,
        showCheckmark: false,
        backgroundColor: c.surface,
        selectedColor: c.blueSel,
        side: BorderSide(color: on ? c.blueSelBorder : c.ctrlBorder),
        shape: const StadiumBorder(),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: (_) => setState(() => _filter = f),
      ),
    );
  }

  Widget _zoomButton(Key key, String tip, IconData icon, VoidCallback onTap) => SizedBox(
        width: 44,
        height: 40,
        child: IconButton(
            key: key,
            tooltip: tip,
            padding: EdgeInsets.zero,
            iconSize: 20,
            color: A216.colors(context).ink2,
            icon: Icon(icon),
            onPressed: onTap),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AdminBlockBook.instance,
        builder: (context, _) {
          final all = _nodes;
          final shown = [for (final n in all) if (linkMapFilterMatches(_filter, n)) n];
          final blockedCount = all.where((n) => n.blocked).length;
          return AdminPage216(
            title: 'Link paths',
            subtitle:
                '${all.length} users · $blockedCount blocked · server ${widget.serverOnline ? 'online' : 'offline'}',
            right: AdminBarAction216(
              tooltip: 'Small map',
              fill: const Color(0xFFEEF3FF),
              onTap: () => Navigator.of(context).maybePop(),
              child: Icon(Icons.close_fullscreen_rounded,
                  size: 18, color: A216.colors(context).blue),
            ),
            body: Builder(builder: (context) {
              final c = A216.colors(context);
              final t = A216Text(c);
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: AdminSearch216(
                    hint: 'Find a person',
                    fieldKey: const ValueKey('link_map_search'),
                    onSubmitted: _find,
                  ),
                ),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [for (final f in LinkMapFilter.values) _chip(f, all)],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: LayoutBuilder(builder: (context, box) {
                    _view = Size(box.maxWidth, box.maxHeight);
                    final canvas = linkMapCanvasSize(_view, widget.nodes.length);
                    if (!_framed && _view.width > 0 && _view.height > 0) {
                      _framed = true;
                      _frameGroup(shown, canvas);
                    }
                    return Stack(children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: c.bgMap,
                          child: GestureDetector(
                            onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
                            onDoubleTap: () {
                              if (_zoom.value.getMaxScaleOnAxis() > 1.05) {
                                _zoom.value = Matrix4.identity();
                              } else {
                                _setScale(2, focus: _doubleTapAt);
                              }
                            },
                            child: InteractiveViewer(
                              key: const ValueKey('link_map_viewer'),
                              transformationController: _zoom,
                              constrained: false,
                              boundaryMargin: const EdgeInsets.all(80),
                              minScale: 1,
                              maxScale: 4,
                              child: GestureDetector(
                                onTapUp: (d) => _tapAt(d.localPosition, shown, canvas),
                                child: SizedBox(
                                  width: canvas.width,
                                  height: canvas.height,
                                  child: LinkPathsCanvas(
                                    nodes: shown,
                                    serverOnline: widget.serverOnline,
                                    selectedId: _selected,
                                    spread: _spread,
                                    nodeRadius: 24,
                                    selfName: widget.selfName,
                                    selfId: widget.selfId,
                                    selfUserId: widget.selfUserId,
                                    onNodeTap: (n) {
                                      setState(() => _selected = n.id);
                                      _sheet(n);
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_hint)
                        Positioned(
                          left: 76,
                          right: 12,
                          bottom: 22,
                          child: Center(
                            child: Text('Drag to scroll · pinch to zoom',
                                key: const ValueKey('link_map_hint'),
                                style: t.custom(11, FontWeight.w400, c.grey)),
                          ),
                        ),
                      Positioned(
                        left: 14,
                        bottom: 16,
                        child: Container(
                          width: 44,
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: const [A216.pillShadow],
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 0),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            _zoomButton(const ValueKey('link_map_zoom_in'), 'Zoom in',
                                Icons.add_rounded, () => _setScale(1.5)),
                            _zoomButton(const ValueKey('link_map_zoom_out'), 'Zoom out',
                                Icons.remove_rounded, () => _setScale(1 / 1.5)),
                            _zoomButton(const ValueKey('link_map_centre'), 'This phone',
                                Icons.my_location_rounded, _centre),
                          ]),
                        ),
                      ),
                    ]);
                  }),
                ),
              ]);
            }),
          );
        },
      );
}
