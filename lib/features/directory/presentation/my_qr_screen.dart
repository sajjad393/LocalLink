import 'dart:convert';
import 'dart:io';

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter/material.dart';

import 'package:locallink/core/widgets/error_toast.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';

class MyQrScreen extends StatelessWidget {
  final DirectoryProfile profile;
  final IdentityCryptoService crypto;
  final DirectoryRepositoryContract? repository;

  const MyQrScreen({
    super.key,
    required this.profile,
    required this.crypto,
    this.repository,
  });

  Future<String> _payload() async {
    final signingPublicKey = await crypto.signingPublicKey();
    final identityPublicKey = await crypto.publicKey();
    final unsigned = profile.copyWith(
      deviceId: profile.deviceId,
      phoneNumber: '',
      avatarUrl: '',
      signingPublicKey: signingPublicKey,
      identityPublicKey: identityPublicKey,
      signature: '',
      source: 'qr',
      syncedAt: '',
    );
    final signature = await crypto.signDirectoryProfile(unsigned.canonical());
    return jsonEncode({
      'v': 1,
      'profile': unsigned.toMap(),
      'signature': signature,
    });
  }

  @override
  Widget build(BuildContext context) {
    // Bundle 118: card-based layout, avatar in the QR centre (error
    // correction H leaves 30% headroom so the overlay never breaks scans),
    // 3 short icon steps instead of prose, and copy/scan actions.
    final name = profile.displayName.isNotEmpty
        ? profile.displayName
        : (profile.username.isNotEmpty ? profile.username : 'LocalLink user');
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final hasAvatar =
        profile.avatarUrl.isNotEmpty && File(profile.avatarUrl).existsSync();
    return Scaffold(
      appBar: AppBar(
        title: const Text('My QR Code'),
        actions: [
          IconButton(
            tooltip: 'Scan QR Code',
            onPressed: repository == null
                ? null
                : () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ContactQrScannerScreen(
                          crypto: crypto,
                          repository: repository!,
                        ),
                      ),
                    ),
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _payload(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not create your QR code. ${snapshot.error}'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final payload = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              // Bundle 133: "Share code" now shares a PNG of the QR CARD
              // itself (this wrapper renders the card into an image) instead
              // of copying the raw JSON payload text. Clipboard copy remains
              // one tap deeper via the paste-code dialog.
              _QrCardWithShare(
                payload: payload,
                name: name,
                username: profile.username,
                initial: initial,
                hasAvatar: hasAvatar,
                avatarPath: profile.avatarUrl,
                canScan: repository != null,
                onScan: repository == null
                    ? null
                    : () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ContactQrScannerScreen(
                              crypto: crypto,
                              repository: repository!,
                            ),
                          ),
                        ),
              ),
            ],
          );
        },
      ),
    );
  }

}

class ContactQrScannerScreen extends StatefulWidget {
  final IdentityCryptoService crypto;
  final DirectoryRepositoryContract repository;
  final void Function(DirectoryProfile)? onFound;

  const ContactQrScannerScreen({
    super.key,
    required this.crypto,
    required this.repository,
    this.onFound,
  });

  @override
  State<ContactQrScannerScreen> createState() => _ContactQrScannerScreenState();
}

class _ContactQrScannerScreenState extends State<ContactQrScannerScreen> {
  final MobileScannerController scanner = MobileScannerController();
  bool torchOn = false;
  bool done = false;
  bool resolving = false;
  String? error;

  @override
  void dispose() {
    scanner.dispose();
    super.dispose();
  }

  Future<void> _handle(String raw) async {
    if (done || resolving) return;
    setState(() {
      resolving = true;
      error = null;
    });

    // Bundle 116: staged QR import diagnostics. cleanBlocError() flattens
    // every typed failure (FormatException/StateError/...) into a generic
    // sentence, so these AppLogger.warning lines + a verbatim error card are
    // the only way to see WHERE and WHY a scan failed.
    var stage = 'scanned';
    AppLogger.warning('QR_IMPORT stage=scanned',
        detail: 'len=${raw.length} head=${raw.substring(0, raw.length < 32 ? raw.length : 32)}');
    try {
      stage = 'decode';
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['v']?.toString() != '1') {
        throw const FormatException('Unsupported LocalLink QR code');
      }
      final payload = Map<String, dynamic>.from(decoded);
      final profileMap = payload['profile'];
      final signature = payload['signature']?.toString() ?? '';
      if (profileMap is! Map || signature.isEmpty) {
        throw const FormatException('QR code is incomplete');
      }

      final profile = DirectoryProfile.fromMap(
        Map<String, dynamic>.from(profileMap),
      ).copyWith(
        signature: signature,
        source: 'qr',
        syncedAt: DateTime.now().toUtc().toIso8601String(),
      );
      AppLogger.warning('QR_IMPORT stage=decoded',
          detail: 'uid=${profile.userId} v=${profile.profileVersion} '
              'device=${profile.deviceId}');

      stage = 'verify';
      if (!profile.isSigned ||
          !await widget.crypto.verifyDirectoryProfile(
            canonicalPayload: profile.canonical(),
            signature: profile.signature,
            signingPublicKey: profile.signingPublicKey,
          )) {
        throw const FormatException('QR signature verification failed');
      }
      AppLogger.warning('QR_IMPORT stage=verified');

      stage = 'import';
      final resolved = await widget.repository.importQrProfile(payload);
      if (resolved == null) {
        AppLogger.warning('QR_IMPORT stage=import_null',
            detail: 'repository returned null '
                '(self-scan, blocked contact, or unavailable profile)');
        throw StateError('This contact is unavailable or blocked');
      }

      AppLogger.warning('QR_IMPORT stage=done',
          detail: 'uid=${resolved.userId} name=${resolved.displayName}');
      setState(() => done = true);
      widget.onFound?.call(resolved);
      if (widget.onFound == null && mounted) {
        Navigator.pop(context, resolved);
      }
    } catch (e) {
      AppLogger.warning('QR_IMPORT fail', detail: 'stage=$stage error=$e');
      if (!mounted) return;
      // Bundle 116: verbatim reason — cleanBlocError() would squash this into
      // "Something went wrong" / a server sentence and hide the real cause.
      setState(() {
        error = 'QR import failed ($stage): $e';
      });
    } finally {
      if (mounted) setState(() => resolving = false);
    }
  }

  Future<void> _pasteCode() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Paste contact code'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          minLines: 2,
          decoration: const InputDecoration(
            hintText: 'Paste the shared code text here',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value.isNotEmpty) await _handle(value);
  }

  @override
  Widget build(BuildContext context) {
    // Bundle 118: dark viewfinder with corner brackets + torch toggle + a
    // single helper line; paste/manual entry stays one tap away.
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Scan contact QR'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Flashlight',
            icon: Icon(torchOn ? Icons.flash_on : Icons.flash_off_outlined),
            onPressed: () {
              scanner.toggleTorch();
              setState(() => torchOn = !torchOn);
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
                controller: scanner,
                scanWindow: window,
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
                  "Point at the other phone's code",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
              if (resolving)
                const Center(child: CircularProgressIndicator()),
              if (error != null)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 96,
                  child: Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        error ?? '',
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 28,
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black87),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.qr_code, size: 18),
                        label: const Text('My code'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54)),
                        onPressed: done || resolving ? null : _pasteCode,
                        icon: const Icon(Icons.content_paste, size: 18),
                        label: const Text('Paste code'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}


/// Bundle 118: one icon + one short line — replaces the old instruction
/// paragraph under the QR card.
class _QrStep extends StatelessWidget {
  final IconData icon;
  final String text;
  const _QrStep({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: scheme.primaryContainer,
            child: Icon(icon, size: 17, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
              child:
                  Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Bundle 133: the QR card + action row, with the card wrapped in a
/// RepaintBoundary so "Share code" can snapshot it into a PNG and open the
/// system share sheet — a picture the other phone can scan, instead of the
/// raw JSON payload text it used to send.
class _QrCardWithShare extends StatefulWidget {
  final String payload;
  final String name;
  final String username;
  final String initial;
  final bool hasAvatar;
  final String avatarPath;
  final bool canScan;
  final VoidCallback? onScan;

  const _QrCardWithShare({
    required this.payload,
    required this.name,
    required this.username,
    required this.initial,
    required this.hasAvatar,
    required this.avatarPath,
    required this.canScan,
    required this.onScan,
  });

  @override
  State<_QrCardWithShare> createState() => _QrCardWithShareState();
}

class _QrCardWithShareState extends State<_QrCardWithShare> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _shareCardAsImage() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundaryContext = _cardKey.currentContext;
      final boundary = boundaryContext?.findRenderObject();
      if (boundaryContext == null || boundary is! RenderRepaintBoundary) {
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return;
      final file = File(
          '${Directory.systemTemp.path}/locallink_qr_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'Scan this code to add me on LocalLink',
      );
    } catch (error) {
      AppLogger.error('QR_SHARE_IMAGE_FAILED', error: error);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        RepaintBoundary(
          key: _cardKey,
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      QrImageView(
                        data: widget.payload,
                        size: 232,
                        errorCorrectionLevel: QrErrorCorrectLevel.H,
                        backgroundColor: Colors.white,
                      ),
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 5),
                        ),
                        child: widget.hasAvatar
                            ? CircleAvatar(
                                radius: 28,
                                backgroundImage:
                                    FileImage(File(widget.avatarPath)),
                              )
                            : CircleAvatar(
                                radius: 28,
                                backgroundColor: scheme.primary,
                                child: Text(
                                  widget.initial,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.name,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${widget.username.isNotEmpty ? widget.username : 'locallink'} · LocalLink',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const _QrStep(
          icon: Icons.smartphone_outlined,
          text: 'Open LocalLink on the other phone',
        ),
        const _QrStep(
          icon: Icons.center_focus_strong_outlined,
          text: 'Point its camera at this code',
        ),
        const _QrStep(
          icon: Icons.check_circle_outline,
          text: 'Contact is added instantly',
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _sharing ? null : _shareCardAsImage,
                icon: _sharing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.share_outlined, size: 18),
                label: Text(_sharing ? 'Preparing…' : 'Share code'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.canScan ? widget.onScan : null,
                icon: const Icon(Icons.qr_code_scanner_outlined, size: 18),
                label: const Text('Scan instead'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Bundle 118: dimmed overlay with a clear rounded window and bold corner
/// brackets — gives the scanner frame its focused look.
class ScanOverlayPainter extends CustomPainter {
  final Rect window;
  const ScanOverlayPainter(this.window);

  @override
  void paint(Canvas canvas, Size size) {
    const r = Radius.circular(20);
    final dim = Paint()..color = Colors.black.withOpacity(0.55);
    final hole = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(window, r));
    canvas.drawPath(hole, dim);

    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const len = 26.0;
    final path = Path()
      ..moveTo(window.left, window.top + len)
      ..lineTo(window.left, window.top + r.y)
      ..arcToPoint(Offset(window.left + r.x, window.top), radius: r)
      ..lineTo(window.left + len, window.top)
      ..moveTo(window.right - len, window.top)
      ..lineTo(window.right - r.x, window.top)
      ..arcToPoint(Offset(window.right, window.top + r.y), radius: r)
      ..lineTo(window.right, window.top + len)
      ..moveTo(window.right, window.bottom - len)
      ..lineTo(window.right, window.bottom - r.y)
      ..arcToPoint(Offset(window.right - r.x, window.bottom), radius: r)
      ..lineTo(window.right - len, window.bottom)
      ..moveTo(window.left + len, window.bottom)
      ..lineTo(window.left + r.x, window.bottom)
      ..arcToPoint(Offset(window.left, window.bottom - r.y), radius: r)
      ..lineTo(window.left, window.bottom - len);
    canvas.drawPath(path, corner);
  }

  @override
  bool shouldRepaint(covariant ScanOverlayPainter oldDelegate) =>
      oldDelegate.window != window;
}
