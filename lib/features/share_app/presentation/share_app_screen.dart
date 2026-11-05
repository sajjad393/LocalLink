// Bundle 210: the Share LinkUp screen (mock 210 pages 3, 4, 5, 7).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:locallink/features/share_app/data/app_share_channel.dart';
import 'package:locallink/features/share_app/data/apk_share_server.dart';
import 'package:locallink/features/share_app/domain/app_share_controller.dart';

class ShareAppScreen extends StatefulWidget {
  final String ownerName;
  final AppShareNative native;

  /// Tests pass a ready controller (it is still disposed by the screen).
  final AppShareController? controller;

  const ShareAppScreen({
    super.key,
    required this.ownerName,
    this.native = const MethodChannelAppShareNative(),
    this.controller,
  });

  @override
  State<ShareAppScreen> createState() => _ShareAppScreenState();
}

class _ShareAppScreenState extends State<ShareAppScreen> {
  late final AppShareController _c;

  @override
  void initState() {
    super.initState();
    _c = widget.controller ??
        AppShareController(native: widget.native, ownerName: widget.ownerName);
    _c.addListener(_changed);
    if (widget.controller == null) scheduleMicrotask(() => _c.start());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    // Leaving the screen stops sharing (no question).
    _c.dispose();
    super.dispose();
  }

  Future<void> _stopAndClose() async {
    final nav = Navigator.of(context);
    await _c.stop('user');
    if (mounted) nav.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share LinkUp')),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    switch (_c.stage) {
      case ShareStage.checking:
      case ShareStage.starting:
        return _starting(context);
      case ShareStage.batteryLow:
        return _batteryLow(context);
      case ShareStage.step1:
        return _step1(context);
      case ShareStage.step2:
        return _step2(context);
      case ShareStage.ownHotspot:
      case ShareStage.sameWifi:
        return _fallback(context);
      case ShareStage.failed:
        return _failed(context);
      case ShareStage.stopped:
        return _stopped(context);
      case ShareStage.cantShare:
        return _message(
          context,
          key: 'share_cant',
          icon: Icons.block,
          title: "This copy of LinkUp can't be shared",
          body: 'It was installed in parts (for example from a store). '
              'Ask a friend who installed the LinkUp file to share it.',
          actions: [
            FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('OK')),
          ],
        );
    }
  }

  // ------------------------------------------------------------ pieces

  Widget _scroll(List<Widget> children, {String? key}) => ListView(
        key: key == null ? null : ValueKey(key),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: children,
      );

  Widget _note(BuildContext context, String text, {bool warm = false}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warm
            ? const Color(0xFFFFF7E6)
            : colors.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              color: warm ? const Color(0xFF7A4800) : colors.onSurface)),
    );
  }

  Widget _qrCard(BuildContext context,
      {required String data, required String key, double size = 210,
      List<Widget> below = const []}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(6),
          child: QrImageView(
            key: ValueKey(key),
            data: data,
            size: size,
            version: QrVersions.auto,
            gapless: true,
            backgroundColor: Colors.white,
          ),
        ),
        ...below,
      ]),
    );
  }

  Widget _steps(BuildContext context, int active) {
    final colors = Theme.of(context).colorScheme;
    Widget chip(int n, String label) {
      final on = n == active;
      final done = n < active;
      return Expanded(
        child: InkWell(
          key: ValueKey('share_chip_$n'),
          borderRadius: BorderRadius.circular(20),
          onTap: () => _c.goToStep(n),
          child: Container(
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? colors.primary : colors.surface,
              borderRadius: BorderRadius.circular(20),
              border: on ? null : Border.all(color: colors.outlineVariant),
            ),
            child: Text(
              '${done ? '✓ ' : ''}$n  $label',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: on
                    ? colors.onPrimary
                    : (done ? Colors.green.shade700 : colors.onSurfaceVariant),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        chip(1, 'Join Wi-Fi'),
        const SizedBox(width: 8),
        chip(2, 'Download'),
      ]),
    );
  }

  Widget _stopButton({bool filled = false}) => filled
      ? FilledButton(
          key: const ValueKey('share_stop'),
          style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              minimumSize: const Size.fromHeight(48)),
          onPressed: _stopAndClose,
          child: const Text('Stop sharing'),
        )
      : TextButton(
          key: const ValueKey('share_stop'),
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade600),
          onPressed: _stopAndClose,
          child: const Text('Stop sharing',
              style: TextStyle(fontWeight: FontWeight.w700)),
        );

  Widget _phones(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final list = _c.phones;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text('Phones getting LinkUp',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 6),
        if (list.isEmpty)
          Text('None yet. Waiting…',
              key: const ValueKey('share_phones_none'),
              style: TextStyle(color: colors.onSurfaceVariant)),
        for (final p in list) _phoneRow(context, p),
      ],
    );
  }

  Widget _phoneRow(BuildContext context, SharePhone p) {
    final colors = Theme.of(context).colorScheme;
    final pct = (p.progress * 100).floor();
    String mb(int b) => (b / (1024 * 1024)).toStringAsFixed(0);
    return Container(
      key: ValueKey('share_phone_${p.number}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: p.done
              ? Colors.green.shade50
              : colors.primaryContainer.withValues(alpha: 0.6),
          child: p.done
              ? Icon(Icons.check, size: 18, color: Colors.green.shade700)
              : Text('${p.number}',
                  style: TextStyle(
                      color: colors.primary, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text('Phone ${p.number}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                if (p.done)
                  Text('${p.took?.inSeconds ?? 0} s',
                      style: TextStyle(color: colors.onSurfaceVariant))
                else
                  Text('$pct%',
                      style: TextStyle(
                          color: colors.primary, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 4),
              if (p.done)
                Text('Done, ${mb(p.total)} MB',
                    style: TextStyle(color: Colors.green.shade700))
              else ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                      value: p.progress, minHeight: 7),
                ),
                const SizedBox(height: 3),
                Text('${mb(p.upTo)} of ${mb(p.total)} MB',
                    style: TextStyle(
                        fontSize: 12, color: colors.onSurfaceVariant)),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------ stages

  Widget _starting(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = _c.apk == null ? '' : 'About ${_c.sizeLabel} free space';
    return _scroll(key: 'share_starting', [
      const SizedBox(height: 40),
      Center(
        child: SizedBox(
          width: 120,
          height: 120,
          child: Stack(alignment: Alignment.center, children: [
            const SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(strokeWidth: 5)),
            CircleAvatar(
              radius: 36,
              backgroundColor: colors.primary,
              child: Icon(Icons.wifi_tethering, color: colors.onPrimary),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 24),
      const Text('Turning on LinkUp Wi-Fi…',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(
          'Your friend will join this Wi-Fi to download the app. '
          'No internet used.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.onSurfaceVariant)),
      _note(
          context,
          "Nearby chats with other LinkUp phones may pause for a moment if "
          "your phone can't do both. They come back by themselves when you "
          'stop sharing.'),
      const SizedBox(height: 14),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('What your friend needs',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('•  An Android phone'),
              if (size.isNotEmpty) Text('•  $size'),
              const Text('•  No internet, no SIM needed'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      OutlinedButton(
        key: const ValueKey('share_cancel'),
        onPressed: _stopAndClose,
        child: const Text('Cancel'),
      ),
    ]);
  }

  Widget _batteryLow(BuildContext context) => _message(
        context,
        key: 'share_battery',
        icon: Icons.battery_alert,
        warm: true,
        title: 'Battery low (10% or less)',
        body: 'Sharing uses a lot of battery. Plug in the charger first.',
        actions: [
          FilledButton(
            key: const ValueKey('share_anyway'),
            onPressed: () => _c.shareAnyway(),
            child: const Text('Share anyway'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Cancel'),
          ),
        ],
      );

  Widget _step1(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const mono = TextStyle(
        fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 15);
    return _scroll(key: 'share_step1', [
      _steps(context, 1),
      _qrCard(context, data: _c.wifiQr, key: 'share_qr_wifi', below: [
        const SizedBox(height: 10),
        const Text('On the new phone:',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Settings → Wi-Fi → tap the QR icon and scan this code.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text('(or scan with the camera app)',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
      ]),
      const SizedBox(height: 10),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Or type it',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Row(children: [
                    SizedBox(
                        width: 84,
                        child: Text('Wi-Fi name',
                            style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant))),
                    Flexible(
                        child: SelectableText(_c.ssid,
                            key: const ValueKey('share_ssid'), style: mono)),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    SizedBox(
                        width: 84,
                        child: Text('Password',
                            style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant))),
                    Flexible(
                        child: SelectableText(
                            _c.password.isEmpty ? '(none)' : _c.password,
                            key: const ValueKey('share_password'),
                            style: mono)),
                  ]),
                ],
              ),
            ),
            GestureDetector(
              onLongPress: () => _copy(_c.password, 'Password copied'),
              child: TextButton(
                key: const ValueKey('share_copy'),
                onPressed: () => _copy(_c.ssid, 'Wi-Fi name copied'),
                child: const Text('Copy'),
              ),
            ),
          ]),
        ),
      ),
      _note(
          context,
          'If the new phone says "This Wi-Fi has no internet. Stay '
          'connected?" tap Yes / Stay.',
          warm: true),
      const SizedBox(height: 18),
      FilledButton(
        key: const ValueKey('share_next'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: () => _c.goToStep(2),
        child: const Text('Next: Download  →'),
      ),
      const SizedBox(height: 4),
      Center(child: _stopButton()),
      Center(
        child: Text('Screen stays on while sharing',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
      ),
    ]);
  }

  void _copy(String text, String done) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(done)));
  }

  List<Widget> _downloadQr(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final url = _c.downloadUrl;
    if (url == null) {
      // Rare: we couldn't tell which address is the Wi-Fi one.
      return [
        _note(context,
            "Couldn't find this Wi-Fi's address. Tap the one that starts with "
            '192.168 (not 192.168.49).'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final a in _c.ipChoices)
            ActionChip(
              key: ValueKey('share_ip_${a.ip}'),
              label: Text('${a.ip}  (${a.iface})'),
              onPressed: () => _c.chooseIp(a.ip),
            ),
        ]),
      ];
    }
    return [
      _qrCard(context, data: url, key: 'share_qr_download', size: 190, below: [
        const SizedBox(height: 10),
        const Text('Scan with the camera, open in Chrome',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('or type:',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
        SelectableText(_c.downloadLabel ?? '',
            key: const ValueKey('share_url'),
            style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.primary)),
        const SizedBox(height: 2),
        Text('LinkUp ${_c.apk?.version ?? ''}  ·  ${_c.sizeLabel}',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
      ]),
    ];
  }

  Widget _step2(BuildContext context) {
    return _scroll(key: 'share_step2', [
      _steps(context, 2),
      ..._downloadQr(context),
      _phones(context),
      _note(
          context,
          'Sharing stops by itself after 10 minutes with no download, or '
          'when you leave this screen.'),
      const SizedBox(height: 18),
      OutlinedButton(
        key: const ValueKey('share_back'),
        style:
            OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: () => _c.goToStep(1),
        child: const Text('←  Back to step 1'),
      ),
      const SizedBox(height: 8),
      _stopButton(filled: true),
    ]);
  }

  Widget _fallback(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final own = _c.stage == ShareStage.ownHotspot;
    return _scroll(key: own ? 'share_own_hotspot' : 'share_same_wifi', [
      _note(
          context,
          own
              ? "Your phone hotspot is already on, so LinkUp can't start its "
                  'own Wi-Fi. Ask your friend to join your hotspot, then scan:'
              : "LinkUp couldn't turn on its own Wi-Fi. If your friend is on "
                  'the same Wi-Fi as you, they can scan this:'),
      const SizedBox(height: 12),
      ..._downloadQr(context),
      if (own)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
              "Name and password: in your phone's hotspot settings",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
        ),
      _phones(context),
      const SizedBox(height: 18),
      if (own)
        OutlinedButton(
          key: const ValueKey('share_open_hotspot'),
          style:
              OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => widget.native.openHotspotSettings(),
          child: const Text('Open hotspot settings'),
        )
      else
        OutlinedButton(
          key: const ValueKey('share_try_again'),
          style:
              OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () async {
            await _c.stop('retry');
            await _c.start();
          },
          child: const Text('Try LinkUp Wi-Fi again'),
        ),
      const SizedBox(height: 8),
      _stopButton(filled: true),
    ]);
  }

  Widget _failed(BuildContext context) {
    final r = _c.reason ?? 'error';
    final tryAgain = FilledButton(
      key: const ValueKey('share_try_again'),
      onPressed: () => _c.start(),
      child: const Text('Try again'),
    );
    switch (r) {
      case 'permission':
        return _message(context,
            key: 'share_failed',
            icon: Icons.wifi_off,
            title: "Couldn't turn on Wi-Fi",
            body: 'LinkUp needs the "Nearby devices" permission to turn on '
                'its Wi-Fi. Allow it in LinkUp\'s app settings.',
            actions: [tryAgain]);
      case 'location_off':
        return _message(context,
            key: 'share_failed',
            icon: Icons.location_off,
            title: 'Turn on Location',
            body: 'On this phone Android needs Location on to start a '
                'LinkUp Wi-Fi. Nothing is tracked.',
            actions: [
              OutlinedButton(
                  key: const ValueKey('share_location'),
                  onPressed: () => widget.native.openLocationSettings(),
                  child: const Text('Turn on Location')),
              tryAgain,
            ]);
      case 'own_hotspot':
        return _message(context,
            key: 'share_failed',
            icon: Icons.wifi_tethering_off,
            title: 'Your phone hotspot is on',
            body: 'Turn your hotspot off and try again, or let your friend '
                'join your hotspot.',
            actions: [
              OutlinedButton(
                  key: const ValueKey('share_open_hotspot'),
                  onPressed: () => widget.native.openHotspotSettings(),
                  child: const Text('Open hotspot settings')),
              tryAgain,
            ]);
      case 'blocked':
        return _message(context,
            key: 'share_failed',
            icon: Icons.block,
            title: "This phone doesn't allow it",
            body: 'This phone blocks hotspots made by apps.',
            actions: [tryAgain]);
      case 'port_busy':
        return _message(context,
            key: 'share_failed',
            icon: Icons.error_outline,
            title: "Couldn't start the download page",
            body: 'Close other sharing apps and try again.',
            actions: [tryAgain]);
      case 'apk_missing':
        return _message(context,
            key: 'share_failed',
            icon: Icons.error_outline,
            title: "Couldn't read the LinkUp app file",
            body: 'Try again in a moment.',
            actions: [tryAgain]);
      default:
        return _message(context,
            key: 'share_failed',
            icon: Icons.wifi_off,
            title: "Couldn't turn on Wi-Fi",
            body: 'Wi-Fi is off or Android said no.',
            actions: [
              OutlinedButton(
                  key: const ValueKey('share_wifi'),
                  onPressed: () => widget.native.openWifiSettings(),
                  child: const Text('Turn on Wi-Fi')),
              tryAgain,
            ]);
    }
  }

  Widget _stopped(BuildContext context) {
    final r = _c.reason;
    final again = FilledButton(
      key: const ValueKey('share_again'),
      onPressed: () => _c.start(),
      child: Text(r == 'stopped' ? 'Try again' : 'Share again'),
    );
    if (r == 'stopped') {
      return _message(context,
          key: 'share_stopped',
          icon: Icons.wifi_off,
          title: 'Wi-Fi stopped',
          body: 'Android turned the LinkUp Wi-Fi off.',
          actions: [again]);
    }
    return _message(context,
        key: 'share_stopped',
        icon: Icons.timer_off_outlined,
        warm: r == 'idle',
        title: 'Sharing stopped',
        body: r == 'idle' ? 'No downloads for 10 minutes.' : 'LinkUp Wi-Fi is off.',
        actions: [again]);
  }

  Widget _message(
    BuildContext context, {
    required String key,
    required IconData icon,
    required String title,
    required String body,
    required List<Widget> actions,
    bool warm = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return _scroll(key: key, [
      const SizedBox(height: 36),
      Icon(icon,
          size: 56, color: warm ? const Color(0xFFEA8C00) : colors.primary),
      const SizedBox(height: 16),
      Text(title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(body,
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.onSurfaceVariant)),
      const SizedBox(height: 24),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: actions,
      ),
    ]);
  }
}
