import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/qr_scan_config_232.dart';
import 'package:locallink/core/widgets/link_toast.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/directory/data/ask_link_330.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 330: the ask by hand.
///
/// Two jobs on one screen:
/// * **mine** - the QR and the link for the ask I am making, to be read by the
///   other person when no card can travel;
/// * **theirs** - scan (or open) the same thing from the other person and this
///   phone files that ask itself, then answers when the two are near.
///
/// Nothing here touches a server, and a link never expires.
class AskQr330Screen extends StatefulWidget {
  const AskQr330Screen({
    super.key,
    required this.link,
    this.label = '',
    this.asker = '',
    this.onTake,
    this.scanner,
  });

  /// My ask, already built by [AskLink330.of].
  final String link;
  final String label;

  /// Who is asking (shown on the taking side).
  final String asker;

  /// Files the ask on this phone. Tests pass their own; the app uses the
  /// live chat request service.
  final Future<String> Function(Map<String, dynamic> chat)? onTake;

  /// Tests: replaces the camera page (returns the scanned text).
  final Future<String?> Function(BuildContext context)? scanner;

  @override
  State<AskQr330Screen> createState() => _AskQr330ScreenState();
}

class _AskQr330ScreenState extends State<AskQr330Screen> {
  bool _busy = false;

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: widget.link));
    if (mounted) {
      LinkToast.show(context, L.t.askLinkCopied330, kind: LinkToastKind.done);
    }
  }

  Future<void> _scan() async {
    final text = widget.scanner != null
        ? await widget.scanner!(context)
        : await Navigator.of(context)
            .push<String>(MaterialPageRoute<String>(builder: (_) => const _AskScanPage()));
    if (!mounted || text == null || text.isEmpty) return;
    await _take(text);
  }

  /// The other side of the deal: read their ask and file it here.
  Future<void> _take(String text) async {
    final ask = AskLink330.parse(text);
    if (ask == null) {
      LinkToast.show(context, L.t.notAnAskLink330, kind: LinkToastKind.error);
      return;
    }
    setState(() => _busy = true);
    try {
      final take = widget.onTake ?? _fileWithService;
      final id = await take(AskLink330.chatOf(ask));
      AppLogger.info('ASK_330', detail: 'took=${id.isNotEmpty}');
      if (!mounted) return;
      LinkToast.show(context, L.t.askTaken330, kind: LinkToastKind.done);
    } catch (_) {
      if (mounted) {
        LinkToast.show(context, L.t.askTakeFailed330, kind: LinkToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The real one: the same ask the LAN card would have filed.
  Future<String> _fileWithService(Map<String, dynamic> chat) async {
    final svc = ChatRequests221.instance;
    if (svc == null) throw StateError('admin actions not ready');
    final pick = ChatPick221.fromRef(chat);
    if (pick == null) throw StateError('ask names no chat');
    return svc.request(pick);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = AskLink330.codeOf(widget.link);
    return Scaffold(
      key: const Key('ask_qr_330_screen'),
      appBar: AppBar(title: Text(L.t.askByQr330)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
        children: [
          Text(
            widget.label.isEmpty ? L.t.askByQrWhat330 : L.t.askByQrWhat330,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              key: const Key('ask_qr_330_code'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: QrImageView(
                data: widget.link,
                version: QrVersions.auto,
                size: 216,
                backgroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              code.isEmpty ? '------' : '${code.substring(0, 3)} ${code.substring(3)}',
              key: const Key('ask_qr_330_words'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 4),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(L.t.askCodeRead330,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const Key('ask_qr_330_copy'),
            onPressed: _copyLink,
            icon: const Icon(Icons.link_rounded),
            label: Text(L.t.copyAskLink330),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('ask_qr_330_scan'),
            onPressed: _busy ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: Text(_busy ? L.t.askTaking330 : L.t.scanTheirAsk330),
          ),
          const SizedBox(height: 20),
          Text(L.t.askByQrHonest330,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline, height: 1.45)),
        ],
      ),
    );
  }
}

/// The camera page: one QR, then back.
class _AskScanPage extends StatefulWidget {
  const _AskScanPage();

  @override
  State<_AskScanPage> createState() => _AskScanPageState();
}

class _AskScanPageState extends State<_AskScanPage> {
  final MobileScannerController _scanner = linkUpQrScannerController();
  bool _done = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L.t.scanTheirAsk330)),
      body: MobileScanner(
        controller: _scanner,
        onDetect: (capture) {
          if (_done) return;
          for (final b in capture.barcodes) {
            final raw = b.rawValue ?? '';
            if (raw.isEmpty) continue;
            _done = true;
            Navigator.pop(context, raw);
            return;
          }
        },
      ),
    );
  }
}
