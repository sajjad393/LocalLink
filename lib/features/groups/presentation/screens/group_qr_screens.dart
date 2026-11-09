import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart'
    show QrCode, QrErrorCorrectLevel, QrImage;
import 'package:share_plus/share_plus.dart';

import 'package:locallink/core/models/group_join_code.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/qr_scan_config_232.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/error_toast.dart';
import 'package:locallink/core/widgets/group_avatar.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/features/directory/presentation/my_qr_screen.dart'
    show ScanOverlayPainter;
import 'package:locallink/features/groups/data/group_change_hub.dart';
import 'package:locallink/features/groups/presentation/screens/new_group_screen.dart'
    show NewGroupTitle;
import 'package:locallink/features/groups/presentation/widgets/group_nearby_widgets.dart';

/// Bundle G4: Join with QR (approved mock G0).
///
/// * [GroupInviteQrScreen] mock 36 - the group code (admins, Nearby groups).
/// * [GroupScanScreen]     mock 2 "Join group with QR" - the camera.
/// * [JoinGroupScreen]     mock 38 - the scanner's phone ("Requested ✓").

const Color _qrDark = Color(0xFF1B1B1F);
const Color _qrBlue = Color(0xFF1E5BFF);

/// Mock 36 QR look: round dots, round corner squares with a blue middle.
class GroupQrPainter extends CustomPainter {
  GroupQrPainter(String data)
      : _image = QrImage(QrCode.fromData(
            // Bundle 232: Q instead of H (fewer squares, easier to scan).
            data: data, errorCorrectLevel: QrErrorCorrectLevel.Q));

  final QrImage _image;

  bool _finder(int r, int c, int n) =>
      (r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7);

  @override
  void paint(Canvas canvas, Size size) {
    final n = _image.moduleCount;
    final cell = size.width / n;
    final dark = Paint()..color = _qrDark;
    final white = Paint()..color = Colors.white;
    final blue = Paint()..color = _qrBlue;
    // Keep the middle free for the group photo (error level Q is enough).
    final hole = (n * 0.22).round();
    final lo = (n - hole) ~/ 2;
    final hi = lo + hole;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (_finder(r, c, n)) continue;
        if (r >= lo && r < hi && c >= lo && c < hi) continue;
        if (!_image.isDark(r, c)) continue;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(c * cell, r * cell, cell, cell),
                Radius.circular(cell * .3)),
            dark);
      }
    }
    void finder(int r, int c) {
      final x = c * cell, y = r * cell;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, y, 7 * cell, 7 * cell),
              Radius.circular(cell * 1.6)),
          dark);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x + cell, y + cell, 5 * cell, 5 * cell),
              Radius.circular(cell * 1.1)),
          white);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x + 2 * cell, y + 2 * cell, 3 * cell, 3 * cell),
              Radius.circular(cell * .8)),
          blue);
    }

    finder(0, 0);
    finder(0, n - 7);
    finder(n - 7, 0);
  }

  @override
  bool shouldRepaint(covariant GroupQrPainter old) => old._image != _image;
}

// ---------------------------------------------------------------- mock 36

class GroupInviteQrScreen extends StatefulWidget {
  const GroupInviteQrScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    this.photoVersion = 0,
  });

  final String groupId;
  final String groupName;
  final int photoVersion;

  @override
  State<GroupInviteQrScreen> createState() => _GroupInviteQrScreenState();
}

class _GroupInviteQrScreenState extends State<GroupInviteQrScreen> {
  final GlobalKey _cardKey = GlobalKey();
  GroupJoinCode? _code;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load(false));
  }

  Future<void> _load(bool reset) async {
    final make = GroupNearbyHub.inviteCode;
    if (make == null || _busy) return;
    setState(() => _busy = true);
    try {
      final code = await make(widget.groupId, reset);
      if (mounted) setState(() => _code = code);
    } catch (error) {
      if (mounted) showErrorToast(context, error: error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    try {
      final boundary = _cardKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return;
      final file = File(
          '${Directory.systemTemp.path}/linkup_group_qr_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')],
          text: 'Scan this code in LinkUp to join "${widget.groupName}"');
    } catch (error) {
      AppLogger.error('GROUP_QR_SHARE_FAILED', error: error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final code = _code;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title:
            NewGroupTitle(title: 'Invite with QR', subtitle: widget.groupName),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SizedBox(height: 6),
          Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
              child: RepaintBoundary(
                key: _cardKey,
                child: Container(
                  key: const ValueKey('group_qr_box'),
                  width: 210,
                  height: 210,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 10,
                          offset: Offset(0, 2)),
                    ],
                  ),
                  child: code == null
                      ? const Center(child: CircularProgressIndicator())
                      : Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox.expand(
                              child: CustomPaint(
                                  painter: GroupQrPainter(code.encode())),
                            ),
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: Colors.white, width: 3),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: _SquareGroupPhoto(
                                      groupId: widget.groupId,
                                      photoVersion: widget.photoVersion),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(widget.groupName,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 4, 30, 0),
            child: Text.rich(
              const TextSpan(children: [
                TextSpan(
                    text:
                        'Anyone who scans this near a member can ask to join. '
                        'It works without internet.\n'),
                TextSpan(
                    text: 'Expires in 24 hours.',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ]),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, height: 1.4, color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 10),
          MessengerListGroup(
            dividerIndent: 58,
            children: [
              _QrRow(
                key: const ValueKey('group_qr_share'),
                icon: Icons.share_outlined,
                title: 'Share code',
                subtitle: 'Send the picture to a friend',
                onTap: code == null ? null : _share,
              ),
              _QrRow(
                key: const ValueKey('group_qr_reset'),
                icon: Icons.restart_alt_rounded,
                title: 'Reset code',
                subtitle: 'The old code stops working',
                red: true,
                onTap: _busy ? null : () => _load(true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The group photo as a square (the QR middle, mock 36 "qrlogo").
class _SquareGroupPhoto extends StatelessWidget {
  const _SquareGroupPhoto({required this.groupId, required this.photoVersion});
  final String groupId;
  final int photoVersion;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 38,
        height: 38,
        child: ClipRect(
          child: OverflowBox(
            maxWidth: 54,
            maxHeight: 54,
            child: GroupAvatar(
                radius: 27, groupId: groupId, photoVersion: photoVersion),
          ),
        ),
      );
}

class _QrRow extends StatelessWidget {
  const _QrRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.red = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool red;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fg = red ? colors.error : colors.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(icon,
                size: 22, color: red ? colors.error : colors.onSurfaceVariant),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: fg)),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12.5, color: colors.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------- mock 2 "Join with QR"

/// The camera for a group code (same look as "Scan contact QR").
class GroupScanScreen extends StatefulWidget {
  const GroupScanScreen({super.key});

  @override
  State<GroupScanScreen> createState() => _GroupScanScreenState();
}

class _GroupScanScreenState extends State<GroupScanScreen> {
  // Bundle 232: sharper picture + QR only (see qr_scan_config_232.dart).
  final MobileScannerController _scanner = linkUpQrScannerController();
  bool _torch = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _handle(String raw) async {
    if (_done) return;
    final code = GroupJoinCode.parse(raw);
    if (code == null) {
      if (mounted) setState(() => _error = 'This is not a LinkUp group code.');
      return;
    }
    _done = true;
    AppLogger.info('GROUP_JOIN_QR', detail: 'scanned');
    await Navigator.pushReplacement<void, void>(
      context,
      MaterialPageRoute(
          builder: (_) => JoinGroupScreen(code: code, autoAsk: true)),
    );
  }

  Future<void> _paste() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Paste group code'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          minLines: 2,
          decoration: const InputDecoration(hintText: 'llgq1:…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value.isNotEmpty) await _handle(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Join group with QR'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Flashlight',
            icon: Icon(_torch ? Icons.flash_on : Icons.flash_off_outlined),
            onPressed: () {
              _scanner.toggleTorch();
              setState(() => _torch = !_torch);
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final side =
              math.min(constraints.maxWidth, constraints.maxHeight) * 0.66;
          final window = Rect.fromCenter(
            center:
                Offset(constraints.maxWidth / 2, constraints.maxHeight * 0.40),
            width: side,
            height: side,
          );
          return Stack(
            children: [
              MobileScanner(
                controller: _scanner,
                // Bundle 232: no scanWindow (the box is only a guide).
                onDetect: (capture) async {
                  if (capture.barcodes.isEmpty) return;
                  final raw = capture.barcodes.first.rawValue;
                  if (raw != null && raw.isNotEmpty) await _handle(raw);
                },
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: ScanOverlayPainter(window)),
                ),
              ),
              Positioned(
                top: window.bottom + 14,
                left: 24,
                right: 24,
                child: const Text(
                  'Scan a group code',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
              if (_error != null)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 96,
                  child: Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer)),
                    ),
                  ),
                ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 28,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54)),
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste, size: 18),
                  label: const Text('Paste code'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- mock 38

/// The scanner's phone: the group from the code; scanning asks at once
/// ("Ask to join" stays only if that failed), then
/// "Requested ✓" for 24 hours. Closes when "… added you" arrives.
class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen(
      {super.key, required this.code, this.nowMs, this.autoAsk = false});

  final GroupJoinCode code;
  final int Function()? nowMs;

  /// Scanning = asking (mock 38 shows "Requested ✓" right away).
  final bool autoAsk;

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  String _state = 'none';
  bool _busy = false;
  StreamSubscription<String>? _changes;

  int get _now => widget.nowMs?.call() ?? DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _changes = GroupChangeHub.instance.changes.listen((id) {
      if (id == widget.code.gid) unawaited(_reload());
    });
    if (widget.code.expired(_now)) _state = 'expired';
    unawaited(_reload().then((_) {
      if (widget.autoAsk && mounted && _state == 'none') return _ask();
    }));
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      if (await GroupNearbyHub.inGroup?.call(widget.code.gid) ?? false) {
        if (mounted) Navigator.of(context).maybePop();
        return;
      }
      final s = await GroupNearbyHub.joinState?.call(widget.code.gid) ?? 'none';
      if (!mounted) return;
      setState(() {
        if (s != 'none' || !widget.code.expired(_now)) _state = s;
      });
    } catch (_) {}
  }

  Future<void> _ask() async {
    final ask = GroupNearbyHub.askToJoin;
    if (ask == null || _busy) return;
    setState(() => _busy = true);
    try {
      await ask(widget.code);
      if (mounted) setState(() => _state = 'asked');
    } catch (error) {
      if (!mounted) return;
      if (error.toString().contains(GroupJoinCode.expiredText) ||
          widget.code.expired(_now)) {
        setState(() => _state = 'expired');
      } else {
        showErrorToast(context, error: error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final code = widget.code;
    final from = code.issuerName.isEmpty ? 'an admin' : code.issuerName;
    final hint =
        TextStyle(fontSize: 13, height: 1.4, color: colors.onSurfaceVariant);
    final names = code.names.isEmpty ? [from] : code.names;
    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: const Text('Join group')),
      body: ListView(
        padding: const EdgeInsets.only(top: 30, bottom: 24),
        children: [
          const Center(child: GroupAvatar(radius: 48)),
          const SizedBox(height: 12),
          Text(code.name.isEmpty ? 'Group' : code.name,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          Text("Group · ${code.count} members · from $from's code",
              key: const ValueKey('join_group_line'),
              textAlign: TextAlign.center,
              style: hint),
          const SizedBox(height: 10),
          Center(
            child: SizedBox(
              height: 38,
              width: 38.0 + (names.length - 1) * 26,
              child: Stack(
                children: [
                  for (var i = 0; i < names.length; i++)
                    Positioned(
                      left: i * 26.0,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2),
                        ),
                        child: AccountAvatar(name: names[i], radius: 17),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: switch (_state) {
              'asked' => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Opacity(
                      opacity: .9,
                      child: OutlinedButton(
                        key: const ValueKey('join_requested'),
                        onPressed: null,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: const StadiumBorder(),
                          side: BorderSide(color: colors.outlineVariant),
                          disabledForegroundColor: colors.onSurface,
                          textStyle: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w700),
                        ),
                        child: const Text('Requested ✓'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                        'An admin must add you. This stays for 24 hours. '
                        'You get "$from added you" when it is done.',
                        textAlign: TextAlign.center,
                        style: hint),
                  ],
                ),
              'expired' => Text(GroupJoinCode.expiredText,
                  key: const ValueKey('join_expired'),
                  textAlign: TextAlign.center,
                  style: hint.copyWith(color: colors.error)),
              _ => FilledButton(
                  key: const ValueKey('join_ask'),
                  onPressed: _busy ? null : _ask,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Ask to join'),
                ),
            },
          ),
        ],
      ),
    );
  }
}
