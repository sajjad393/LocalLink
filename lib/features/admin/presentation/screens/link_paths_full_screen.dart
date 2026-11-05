import 'dart:math' as math;

import 'package:locallink/core/widgets/admin_crown.dart';
import 'package:flutter/material.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';
import 'package:locallink/features/admin/presentation/screens/admin_blocked_list_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_block_confirm.dart';
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
  });

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
        LinkNode(
            id: n.id,
            label: n.label,
            tag: n.tag,
            blocked: n.blocked || book.isBlocked(n.id)),
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
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheet) => ListenableBuilder(
        listenable: AdminBlockBook.instance,
        builder: (sheet, _) {
          final target = widget.targetFor(node);
          final blocked = AdminBlockBook.instance.isBlocked(node.id) ||
              AdminBlockBook.instance.isBlocked(target.userId) ||
              node.blocked;
          final entry = widget.service?.entryFor(target.userId) ??
              widget.service?.entryFor(node.id);
          return SafeArea(
            child: Padding(
              key: const ValueKey('link_map_sheet'),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    // Bundle 214 (D6): crown in the node sheet title.
                    AdminCrown(
                      id: node.id,
                      otherId: target.userId,
                      radius: 24,
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFFE5E7EB),
                        child: Text(target.initials,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF6B7280))),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(target.name,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w800)),
                            Text(
                                [
                                  if (target.username.isNotEmpty) '@${target.username}',
                                  linkTagLabel(node.tag),
                                  if (blocked) 'relays for others',
                                ].join(' · '),
                                style: const TextStyle(
                                    fontSize: 12.5, color: Color(0xFF5B6472))),
                          ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: blocked ? kBlockRedTint : kUnblockGreenTint,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(blocked ? 'Blocked' : 'Active',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: blocked ? kBlockRed : kUnblockGreen)),
                    ),
                  ]),
                  if (blocked && entry != null) ...[
                    const SizedBox(height: 12),
                    Text(
                        'Blocked by ${entry.record.signer == 'server' ? 'web panel' : (entry.record.by.isEmpty ? 'admin' : entry.record.by)}'
                        ' · ${blockWhen(entry.record.at)}'
                        '${entry.source == 'me' ? ' · reached ${entry.reached} phones' : ''}',
                        style: const TextStyle(fontSize: 13.5)),
                    Text('Server: ${entry.serverDone ? 'done' : 'waiting'}',
                        style: const TextStyle(
                            fontSize: 12.5, color: Color(0xFF5B6472))),
                  ],
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('link_map_sheet_action'),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            shape: const StadiumBorder()),
                        onPressed: () => runAdminBlock(sheet,
                            service: widget.service,
                            target: target,
                            block: !blocked),
                        child: Text(blocked ? 'Unblock' : 'Block',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: blocked ? const Color(0xFF1E5BFF) : kBlockRed)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            shape: const StadiumBorder()),
                        onPressed: () {
                          Navigator.of(sheet).push(MaterialPageRoute<void>(
                              builder: (_) => AdminBlockedListScreen(
                                  service: widget.service)));
                        },
                        child: const Text('Blocked list',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AdminBlockBook.instance,
        builder: (context, _) {
          final all = _nodes;
          final shown = [for (final n in all) if (linkMapFilterMatches(_filter, n)) n];
          final blockedCount = all.where((n) => n.blocked).length;
          return Scaffold(
            backgroundColor: const Color(0xFFF5F6F8),
            appBar: AppBar(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              titleSpacing: 0,
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Link paths',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                Text(
                    '${all.length} users · $blockedCount blocked · server ${widget.serverOnline ? 'online' : 'offline'}',
                    key: const ValueKey('link_map_counts'),
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B6472))),
              ]),
              actions: [
                IconButton.filledTonal(
                  tooltip: 'Small map',
                  icon: const Icon(Icons.close_fullscreen_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: Column(children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(children: [
                  TextField(
                    key: const ValueKey('link_map_search'),
                    textInputAction: TextInputAction.search,
                    onSubmitted: _find,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      hintText: 'Find a user on the map',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 34,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      for (final f in LinkMapFilter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            key: ValueKey('link_map_filter_${f.name}'),
                            label: Text(
                                '${linkMapFilterLabel(f)} ${all.where((n) => linkMapFilterMatches(f, n)).length}'),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ]),
                  ),
                ]),
              ),
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  _view = Size(box.maxWidth, box.maxHeight);
                  final canvas = linkMapCanvasSize(_view, widget.nodes.length);
                  return Stack(children: [
                    Positioned.fill(
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
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_hint)
                      Positioned(
                        top: 8,
                        right: 12,
                        child: Container(
                          key: const ValueKey('link_map_hint'),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E6EC))),
                          child: const Text('Drag to scroll · pinch to zoom',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF5B6472))),
                        ),
                      ),
                    Positioned(
                      left: 12,
                      bottom: 16,
                      child: Material(
                        color: Colors.white,
                        elevation: 1,
                        borderRadius: BorderRadius.circular(12),
                        child: Column(children: [
                          IconButton(
                              key: const ValueKey('link_map_zoom_in'),
                              tooltip: 'Zoom in',
                              icon: const Icon(Icons.add),
                              onPressed: () => _setScale(1.5)),
                          IconButton(
                              key: const ValueKey('link_map_zoom_out'),
                              tooltip: 'Zoom out',
                              icon: const Icon(Icons.remove),
                              onPressed: () => _setScale(1 / 1.5)),
                          IconButton(
                              key: const ValueKey('link_map_centre'),
                              tooltip: 'This phone',
                              icon: const Icon(Icons.my_location),
                              onPressed: _centre),
                        ]),
                      ),
                    ),
                  ]);
                }),
              ),
            ]),
          );
        },
      );
}
