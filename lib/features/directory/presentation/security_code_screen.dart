import 'dart:async';

import 'package:locallink/core/widgets/link_toast.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:locallink/core/security/identity_trust_service.dart';
import 'package:locallink/core/security/security_code_245.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/qr_scan_config_232.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 245 (audit S7): chat ⋮ › Conversation info › Security code.
///
/// Both phones show the same 12 groups of 5 digits. Compare them in person
/// (or scan the other phone's code), then "Mark as verified".
/// A waiting key change shows "<name>'s security code changed" with
/// "Accept new code" - nothing is taken automatically.
class SecurityCodeScreen extends StatefulWidget {
  const SecurityCodeScreen({
    super.key,
    required this.deviceId,
    required this.name,
    SecurityCode245? hub,
    this.scanner,
  }) : _hub = hub;

  final String deviceId;
  final String name;
  final SecurityCode245? _hub;

  /// Tests: replaces the camera page (returns the scanned text).
  final Future<String?> Function(BuildContext context)? scanner;

  static const String qrPrefix = 'linkup-sc-v1:';

  @override
  State<SecurityCodeScreen> createState() => _SecurityCodeScreenState();
}

class _SecurityCodeScreenState extends State<SecurityCodeScreen> {
  SecurityCode245 get hub => widget._hub ?? SecurityCode245.instance;
  SecurityCodeView245? _view;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    hub.addListener(_reload);
    unawaited(_reload());
  }

  @override
  void dispose() {
    hub.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    SecurityCodeView245? v;
    try {
      v = await hub.view(widget.deviceId);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _view = v;
      _loading = false;
    });
  }

  void _snack(String text) => LinkToast.show(context, text, kind: LinkToast.guess(text));

  Future<void> _setVerified(bool on) async {
    final v = _view;
    if (v == null || _busy) return;
    setState(() => _busy = true);
    await hub.setVerified(v.deviceId, on);
    if (mounted) setState(() => _busy = false);
    if (on) _snack(L.t.isVerified(widget.name));
  }

  Future<void> _accept() async {
    final p = _view?.pending;
    if (p == null || _busy) return;
    setState(() => _busy = true);
    final ok = await hub.accept(p.profile.userId);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(ok ? L.t.newSecurityCodeAccepted : L.t.couldNotAcceptTheNewCode);
  }

  Future<void> _scan() async {
    final v = _view;
    if (v == null) return;
    final raw = widget.scanner != null
        ? await widget.scanner!(context)
        : await Navigator.push<String>(
            context, MaterialPageRoute(builder: (_) => const _CodeScanPage()));
    if (!mounted || raw == null) return;
    final text = raw.trim();
    final digits = text.startsWith(SecurityCodeScreen.qrPrefix)
        ? text.substring(SecurityCodeScreen.qrPrefix.length)
        : '';
    final match = digits == v.digits;
    AppLogger.info('SECURITY_CODE_245', detail: 'scan=${match ? 'match' : 'no_match'}');
    if (match) {
      await _setVerified(true);
    } else {
      _snack(L.t.theCodesDonTMatchAsk(widget.name));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final v = _view;
    return Scaffold(
      key: const Key('security_code_screen'),
      appBar: AppBar(title: Text(L.t.securityCode)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : v == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      L.t.sSecurityCodeIsNotReady(widget.name),
                      key: const Key('security_code_not_ready'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    if (v.pending != null) _changedCard(context, v),
                    _stateChip(context, v.state),
                    const SizedBox(height: 14),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: QrImageView(
                          key: const Key('security_code_qr'),
                          data: '${SecurityCodeScreen.qrPrefix}${v.digits}',
                          size: 180,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _digits(context, v.groups),
                    const SizedBox(height: 16),
                    Text(
                      L.t.compareThisCodeWithTheOne(widget.name),
                      key: const Key('security_code_help'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, height: 1.35, color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.tonalIcon(
                      key: const Key('security_code_scan'),
                      onPressed: _busy ? null : _scan,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(L.t.scanSCode(widget.name)),
                    ),
                    const SizedBox(height: 10),
                    if (v.state == IdentityTrustState.verified)
                      OutlinedButton(
                        key: const Key('security_code_unverify'),
                        onPressed: _busy ? null : () => _setVerified(false),
                        child: Text(L.t.removeVerifiedMark),
                      )
                    else
                      FilledButton.icon(
                        key: const Key('security_code_verify'),
                        onPressed: _busy || v.pending != null ? null : () => _setVerified(true),
                        icon: const Icon(Icons.verified_user_outlined),
                        label: Text(L.t.markAsVerified),
                      ),
                  ],
                ),
    );
  }

  Widget _changedCard(BuildContext context, SecurityCodeView245 v) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('security_code_changed_card'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.gpp_maybe_outlined, size: 20, color: colors.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(L.t.sSecurityCodeChanged(widget.name),
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15, color: colors.onErrorContainer)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            L.t.thisHappensWhenReinstallsLinkupOr(widget.name, widget.name),
            style: TextStyle(fontSize: 13.5, height: 1.3, color: colors.onErrorContainer),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('security_code_accept'),
              onPressed: _busy ? null : _accept,
              child: Text(L.t.acceptNewCode),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stateChip(BuildContext context, IdentityTrustState state) {
    final colors = Theme.of(context).colorScheme;
    final (IconData icon, String text, Color fg) = switch (state) {
      IdentityTrustState.verified => (Icons.verified_user, L.t.verified, const Color(0xFF1E8E3E)),
      IdentityTrustState.changed => (Icons.gpp_maybe_outlined, L.t.codeChanged, colors.error),
      IdentityTrustState.revoked => (Icons.block, L.t.revoked, colors.error),
      IdentityTrustState.unverified => (Icons.shield_outlined, L.t.notVerified, colors.onSurfaceVariant),
    };
    return Center(
      child: Container(
        key: Key('security_code_state_${state.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: fg)),
        ]),
      ),
    );
  }

  Widget _digits(BuildContext context, List<String> groups) {
    final colors = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var r = 0; r < groups.length; r += 4) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final g in groups.skip(r).take(4))
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(g,
                        style: TextStyle(
                          fontSize: 20,
                          letterSpacing: 1.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        )),
                  ),
                ),
              ),
          ],
        ),
      ));
    }
    return Container(
      key: const Key('security_code_digits'),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: rows),
    );
  }
}

class _CodeScanPage extends StatefulWidget {
  const _CodeScanPage();
  @override
  State<_CodeScanPage> createState() => _CodeScanPageState();
}

class _CodeScanPageState extends State<_CodeScanPage> {
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
      appBar: AppBar(title: Text(L.t.scanSecurityCode)),
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
