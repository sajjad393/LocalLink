import 'dart:convert';
import 'dart:io';

import 'dart:math' as math;

import 'package:locallink/features/share_app/presentation/qr_card_share_299.dart';
import 'package:locallink/features/share_app/presentation/qr_share_card_299.dart';
import 'package:locallink/core/theme/app_tokens.dart';

import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:locallink/core/services/qr_scan_config_232.dart';
import 'package:locallink/core/widgets/link_kit_290.dart';
import 'package:locallink/core/widgets/link_toast.dart';
import 'package:locallink/features/directory/presentation/add_contact_ui283.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/directory/data/peer_photo_book.dart';
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

  /// Bundle 283 (Q-1): "Scan instead" / the round top button = the camera.
  /// Its "My QR code" button comes back here.
  Future<void> _openScanner(BuildContext context) => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ContactQrScannerScreen(
            crypto: crypto,
            repository: repository!,
            backToMyQr: true,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Bundle 283 (mock 283 section 5): my code only - avatar, name, the QR,
    // 3 steps, "Share my QR" + "Scan instead".
    final name = profile.displayName.isNotEmpty
        ? profile.displayName
        : (profile.username.isNotEmpty ? profile.username : 'LinkUp user');
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    // Bundle 204: my picture (avatar_url is now a picture code, not a path).
    final ownPhoto = PeerPhotoBook.instance.fileFor(profile.userId) ??
        PeerPhotoBook.instance.fileFor(profile.deviceId);
    final hasAvatar = ownPhoto != null;
    final p = LinkKit.of(context);
    return Scaffold(
      backgroundColor: p.screen,
      appBar: addBar283(
        context,
        title: 'My QR code',
        actions: [
          RoundTopButton283(
            key: const ValueKey('my_qr_scan_283'),
            tooltip: 'Scan QR code',
            icon: Icons.qr_code_scanner,
            onPressed: repository == null ? null : () => _openScanner(context),
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
                child: Text('Could not create your QR code. ${snapshot.error}',
                    style: TextStyle(color: p.text)),
              ),
            );
          }
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: p.focus));
          }
          final payload = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            // Bundle 133: "Share my QR" shares a PNG of the QR CARD itself.
            child: _QrCardWithShare(
              payload: payload,
              name: name,
              username: profile.username,
              initial: initial,
              hasAvatar: hasAvatar,
              avatarPath: ownPhoto?.path ?? '',
              canScan: repository != null,
              onScan: repository == null ? null : () => _openScanner(context),
            ),
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

  /// Bundle 283 (Q-2): my profile for the "My QR code" button (it opens
  /// [MyQrScreen] in place of the camera, so Back returns to Add Contact).
  final Future<DirectoryProfile?> Function()? myProfile;

  /// Bundle 283: opened from [MyQrScreen] - "My QR code" just goes back.
  final bool backToMyQr;

  /// Bundle 283 (Q-3): picks the photo for "From photo" (tests swap it).
  final Future<String?> Function()? pickPhoto;

  const ContactQrScannerScreen({
    super.key,
    required this.crypto,
    required this.repository,
    this.onFound,
    this.myProfile,
    this.backToMyQr = false,
    this.pickPhoto,
  });

  @override
  State<ContactQrScannerScreen> createState() => _ContactQrScannerScreenState();
}

class _ContactQrScannerScreenState extends State<ContactQrScannerScreen> {
  // Bundle 232: sharper picture + QR only (see qr_scan_config_232.dart).
  final MobileScannerController scanner = linkUpQrScannerController();
  bool torchOn = false;
  bool done = false;
  bool resolving = false;
  bool _picking = false;
  String? error;

  /// Bundle 283 (Q-2): "My QR code" shows MY code (it used to only go back).
  Future<void> _openMyQr() async {
    if (widget.backToMyQr) {
      Navigator.of(context).pop();
      return;
    }
    final load = widget.myProfile;
    final me = load == null ? null : await load();
    if (!mounted) return;
    if (me == null) {
      LinkToast.show(context, 'Your profile is not ready yet.', kind: LinkToastKind.error);
      return;
    }
    AppLogger.info('QR_UI', detail: 'scanner_my_qr');
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => MyQrScreen(profile: me, crypto: widget.crypto, repository: widget.repository),
      ),
    );
  }

  static Future<String?> _galleryPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    return file?.path;
  }

  /// Bundle 283 (Q-3): a QR picture a friend sent (WhatsApp etc.) -> the
  /// same import as the camera.
  Future<void> _fromPhoto() async {
    if (_picking || done || resolving) return;
    setState(() => _picking = true);
    String? raw;
    var picked = false;
    try {
      final path = await (widget.pickPhoto ?? _galleryPhoto)();
      if (path == null || path.isEmpty) return;
      picked = true;
      final capture = await scanner.analyzeImage(path);
      for (final b in capture?.barcodes ?? const <Barcode>[]) {
        final v = b.rawValue;
        if (v != null && v.isNotEmpty) {
          raw = v;
          break;
        }
      }
    } catch (e) {
      AppLogger.warning('QR_IMPORT photo_fail', detail: 'error=$e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
    if (!mounted || !picked) return;
    AppLogger.info('QR_UI', detail: 'from_photo found=${raw == null ? 'n' : 'y'}');
    if (raw == null) {
      LinkToast.show(context, 'No QR code found in this picture', kind: LinkToastKind.error);
      return;
    }
    await _handle(raw);
  }

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
        throw const FormatException('Unsupported LinkUp QR code');
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
    // Bundle 283 (mock 283 section 5): camera straight away, a 230 dp
    // window with teal corners and a moving line, "My QR code" + "From
    // photo". "Paste code" stays as a small link under them.
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Scan QR code',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
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
          final side = math.min(230.0, math.min(constraints.maxWidth, constraints.maxHeight) * .72);
          final window = Rect.fromCenter(
            center: Offset(constraints.maxWidth / 2, constraints.maxHeight * 0.385),
            width: side,
            height: side,
          );
          final busy = done || resolving || _picking;
          return Stack(
            children: [
              MobileScanner(
                controller: scanner,
                // Bundle 232: no scanWindow. The box is only a guide; the
                // plugin filter dropped codes that were big enough to read.
                onDetect: (capture) async {
                  if (capture.barcodes.isEmpty) return;
                  final raw = capture.barcodes.first.rawValue;
                  if (raw != null && raw.isNotEmpty) await _handle(raw);
                },
              ),
              Positioned.fill(
                child: IgnorePointer(child: _ScanFrame283(window: window)),
              ),
              Positioned(
                top: window.bottom + 17,
                left: 20,
                right: 20,
                child: const Text(
                  "Point at your friend's QR code",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFE5E7EB), fontSize: 14),
                ),
              ),
              if (resolving || _picking)
                const Center(child: CircularProgressIndicator(color: AddUi283.teal)),
              if (error != null)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 140,
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
                left: 16,
                right: 16,
                bottom: 20,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(
                    children: [
                      Expanded(
                        child: _CamButton283(
                          key: const ValueKey('scan_my_qr_283'),
                          filled: true,
                          icon: Icons.qr_code_2_rounded,
                          text: 'My QR code',
                          onPressed: _openMyQr,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _CamButton283(
                          key: const ValueKey('scan_from_photo_283'),
                          filled: false,
                          icon: Icons.image_outlined,
                          text: 'From photo',
                          onPressed: busy ? null : _fromPhoto,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    key: const ValueKey('scan_paste_283'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white70),
                    onPressed: busy ? null : _pasteCode,
                    icon: const Icon(Icons.content_paste, size: 16),
                    label: const Text('Paste code', style: TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Bundle 283 (mock `.cam .a`): 50 high round camera buttons.
class _CamButton283 extends StatelessWidget {
  final bool filled;
  final IconData icon;
  final String text;
  final VoidCallback? onPressed;
  const _CamButton283({super.key, required this.filled, required this.icon, required this.text, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final fg = filled ? const Color(0xFF111111) : Colors.white;
    return Opacity(
      opacity: onPressed == null ? .5 : 1,
      child: Material(
        color: filled ? Colors.white : Colors.transparent,
        shape: StadiumBorder(
            side: filled ? BorderSide.none : const BorderSide(color: Color(0x8CFFFFFF), width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: SizedBox(
            height: 50,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Flexible(
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Bundle 283 (mock `.cam .win`): dim around a 28 radius window, teal
/// corners and a glowing line going up and down (2.4 s; still when
/// animations are off).
class _ScanFrame283 extends StatefulWidget {
  final Rect window;
  const _ScanFrame283({required this.window});

  @override
  State<_ScanFrame283> createState() => _ScanFrame283State();
}

class _ScanFrame283State extends State<_ScanFrame283> with SingleTickerProviderStateMixin, Clock283<_ScanFrame283> {
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
        valueListenable: seconds,
        builder: (context, s, _) {
          final v = (s % 2.4) / 2.4;
          final e = Curves.easeInOut.transform(v < .5 ? v * 2 : (1 - v) * 2);
          return CustomPaint(painter: ScanOverlayPainter(widget.window, line: LinkKit.calm(context) ? .5 : e));
        },
      );
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
      // Bundle 299 (Q): the card picture (recovery-card look); the caption
      // is only the code.
      await QrCardShare299.share(
        kind: QrCardKind299.contact,
        data: widget.payload,
        name: widget.name,
        sub: '@${widget.username.isNotEmpty ? widget.username : 'linkup'}',
        photoPath: widget.hasAvatar ? widget.avatarPath : null,
        made: DateTime.now(),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Bundle 283 (mock `.myqr`): one card - avatar, name, @user, the code
    // on white, 3 steps; then "Share my QR" + "Scan instead".
    final p = LinkKit.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepaintBoundary(
          key: _cardKey,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(26),
              boxShadow: p.cardShadow,
            ),
            child: Column(
              children: [
                widget.hasAvatar
                    ? CircleAvatar(
                        radius: 29,
                        backgroundImage: FileImage(File(widget.avatarPath)),
                      )
                    : Container(
                        width: 58,
                        height: 58,
                        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AddUi283.meGradient),
                        alignment: Alignment.center,
                        child: Text(widget.initial,
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                      ),
                const SizedBox(height: 8),
                Text(widget.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: p.text)),
                const SizedBox(height: 2),
                Text('@${widget.username.isNotEmpty ? widget.username : 'linkup'}',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: p.muted)),
                Container(
                  // Bundle 283: the mock box is 190; long LinkUp codes need
                  // more room to scan (Bundle 232), so the code keeps 232.
                  margin: const EdgeInsets.fromLTRB(0, 14, 0, 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                  child: QrImageView(
                    data: widget.payload,
                    size: 208,
                    padding: EdgeInsets.zero,
                    // Bundle 232: Q instead of H = 113 squares instead
                    // of 129.
                    errorCorrectionLevel: QrErrorCorrectLevel.Q,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '1. Open LinkUp on the other phone\n'
                  '2. Tap Scan QR code and point at this\n'
                  '3. You are added instantly',
                  key: const ValueKey('my_qr_steps_283'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, height: 1.6, color: p.muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: LinkKit.brandGradient, borderRadius: BorderRadius.circular(24)),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: const ValueKey('my_qr_share_283'),
                      borderRadius: BorderRadius.circular(24),
                      onTap: _sharing ? null : _shareCardAsImage,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        _sharing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.ios_share_rounded, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(_sharing ? 'Preparing…' : 'Share my QR',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  key: const ValueKey('my_qr_scan_instead_283'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.isDark ? const Color(0xFFC9CBD6) : const Color(0xFF374151),
                    side: BorderSide(color: AddUi283.chevron(p), width: 1.5),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontFamily: LocalLinkLook.fontFamily, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  onPressed: widget.canScan ? widget.onScan : null,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Scan instead'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Bundle 118 + 283: dimmed overlay with a clear 28 radius window, teal
/// corner brackets (44 dp, 4 wide) and the scan line at [line] (0 top .. 1
/// bottom; null = no line).
class ScanOverlayPainter extends CustomPainter {
  final Rect window;
  final double? line;
  const ScanOverlayPainter(this.window, {this.line});

  @override
  void paint(Canvas canvas, Size size) {
    const r = Radius.circular(28);
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final hole = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(window, r));
    canvas.drawPath(hole, dim);

    final corner = Paint()
      ..color = AddUi283.teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final w = window.inflate(2);
    const len = 44.0, cr = 24.0;
    final path = Path()
      ..moveTo(w.left, w.top + len)
      ..lineTo(w.left, w.top + cr)
      ..arcToPoint(Offset(w.left + cr, w.top), radius: const Radius.circular(cr))
      ..lineTo(w.left + len, w.top)
      ..moveTo(w.right - len, w.top)
      ..lineTo(w.right - cr, w.top)
      ..arcToPoint(Offset(w.right, w.top + cr), radius: const Radius.circular(cr))
      ..lineTo(w.right, w.top + len)
      ..moveTo(w.right, w.bottom - len)
      ..lineTo(w.right, w.bottom - cr)
      ..arcToPoint(Offset(w.right - cr, w.bottom), radius: const Radius.circular(cr))
      ..lineTo(w.right - len, w.bottom)
      ..moveTo(w.left + len, w.bottom)
      ..lineTo(w.left + cr, w.bottom)
      ..arcToPoint(Offset(w.left, w.bottom - cr), radius: const Radius.circular(cr))
      ..lineTo(w.left, w.bottom - len);
    canvas.drawPath(path, corner);

    final at = line;
    if (at == null) return;
    final y = window.top + 16 + (window.height - 24 - 16) * at.clamp(0.0, 1.0);
    final bar = Rect.fromLTWH(window.left + 14, y, window.width - 28, 3);
    final shader = const LinearGradient(colors: [Color(0x0023E0D8), AddUi283.teal, Color(0x0023E0D8)])
        .createShader(bar);
    canvas.drawRRect(RRect.fromRectAndRadius(bar.inflate(3), const Radius.circular(4)),
        Paint()
          ..shader = shader
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(2)), Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant ScanOverlayPainter oldDelegate) =>
      oldDelegate.window != window || oldDelegate.line != line;
}
