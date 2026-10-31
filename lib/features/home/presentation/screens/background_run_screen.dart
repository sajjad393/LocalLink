import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/features/calls/data/transport/network_policy.dart';
import 'package:locallink/features/home/domain/background_brand_guide.dart';
import 'package:locallink/features/home/presentation/widgets/background_status_card.dart';

/// Bundle 140: "Keep LocalLink running" — approved mock.
/// Opt-in on tap only; once granted, options LOCK and only explain themselves
/// via a toast (user requirement: the app must stay reachable).
class BackgroundRunScreen extends StatefulWidget {
  final LocalStore store;
  const BackgroundRunScreen({super.key, required this.store});

  /// Bundle 177 (9.4): the Location "All the time" card was answered once.
  static const bgLocationAskedKey = 'bg_location_asked';

  @override
  State<BackgroundRunScreen> createState() => _BackgroundRunScreenState();
}

class _BackgroundRunScreenState extends State<BackgroundRunScreen>
    with WidgetsBindingObserver {
  static const _bg = MethodChannel('locallink/background');
  static const _notif = MethodChannel('locallink/notifications');
  // Bundle 175 (10): STATUS card. Null until the first read.
  bool? _running;
  bool _notificationsOn = true;
  bool _starting = false;
  static const _keepAliveKey = 'keep_alive_enabled';
  // Bundle 177 (10, 9): Nearby while closed + the one-time Location ask.
  String? _nearby;
  bool _bgLocationNeeded = false;
  bool _bgLocationAsked = false;

  bool _keepAlive = true;
  bool _batteryExempt = false;
  bool _busy = false;
  // Bundle 163 (5.6): steps for this phone's brand (user can pick another).
  static const _brandKey = 'background_brand_override';
  BackgroundBrandGuide _brand = backgroundBrandByKey('other');

  static const _lockedToast =
      'LocalLink needs this to stay on — messages and calls must keep arriving '
      'in the background.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Settings (notifications / battery): read the status again.
    if (state == AppLifecycleState.resumed) _loadStatus();
  }

  /// Bundle 175 (10): is the background service running right now?
  Future<void> _loadStatus() async {
    try {
      final raw = await _bg.invokeMethod<Map<Object?, Object?>>('backgroundStatus');
      if (!mounted || raw == null) return;
      final adminOff = widget.store.effectiveNetworkPolicy.wifiRadioPolicy ==
          AdminWifiRadioPolicy.forcedOff;
      setState(() {
        _running = raw['running'] == true;
        _notificationsOn = raw['notifications'] != false;
        final nearby = raw['nearby']?.toString();
        _nearby = nearby == null ? null : (adminOff ? 'admin_off' : nearby);
      });
    } catch (_) {/* older native side: no card */}
    await _loadBackgroundLocation();
  }

  /// Bundle 177 (9.3-9.5): Android 10-12 only, asked once, never from the
  /// closed app, not part of the 10-minute permission loop.
  Future<void> _loadBackgroundLocation() async {
    try {
      final needed =
          await _bg.invokeMethod<bool>('backgroundLocationNeeded') ?? false;
      final asked =
          (await widget.store.readSetting(BackgroundRunScreen.bgLocationAskedKey) ?? '') == '1';
      if (!mounted) return;
      setState(() {
        _bgLocationNeeded = needed;
        _bgLocationAsked = asked;
      });
    } catch (_) {/* older native side: no card */}
  }

  Future<void> _answerBackgroundLocation(bool allow) async {
    await widget.store.writeSetting(BackgroundRunScreen.bgLocationAskedKey, '1');
    if (mounted) setState(() => _bgLocationAsked = true);
    if (allow) {
      try {
        await _bg.invokeMethod<void>('requestBackgroundLocation');
      } catch (_) {}
    }
  }

  Widget _backgroundLocationCard() {
    const orange = BackgroundStatusCard.orange;
    if (_bgLocationAsked) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('bg-location-turn-on'),
          onPressed: () => _answerBackgroundLocation(true),
          icon: const Icon(Icons.location_on_outlined, size: 18),
          label: const Text('Find nearby friends when closed - Turn on'),
        ),
      );
    }
    return Container(
      key: const ValueKey('bg-location-card'),
      decoration: BoxDecoration(
        color: orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: orange, width: 1.5),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.location_on_rounded, color: orange, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text('Find nearby friends when closed',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ]),
          const SizedBox(height: 6),
          const Text(
              'Your Android needs Location "All the time" for this. '
              'LocalLink never saves where you are.',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton(
              key: const ValueKey('bg-location-allow'),
              style: FilledButton.styleFrom(backgroundColor: orange),
              onPressed: () => _answerBackgroundLocation(true),
              child: const Text('Allow'),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const ValueKey('bg-location-not-now'),
              onPressed: () => _answerBackgroundLocation(false),
              child: const Text('Not now'),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _startService() async {
    setState(() => _starting = true);
    try {
      await _bg.invokeMethod<void>('keepAliveStart');
    } catch (_) {}
    // The service needs a moment to come up.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await _loadStatus();
    if (mounted) setState(() => _starting = false);
  }

  Future<void> _allowNotifications() async {
    try {
      await _notif.invokeMethod<void>('openSettings');
    } catch (_) {
      _toast('Could not open notification settings right now.');
    }
  }

  Future<void> _load() async {
    try {
      final stored = await widget.store.readSetting(_keepAliveKey);
      final exempt = await _bg.invokeMethod<bool>('batteryExempted');
      if (!mounted) return;
      setState(() {
        _keepAlive = stored != 'false'; // default ON
        _batteryExempt = exempt ?? false;
      });
    } catch (_) {/* best effort */}
    await _loadBrand();
    await _loadStatus();
  }

  Future<void> _loadBrand() async {
    try {
      final picked = await widget.store.readSetting(_brandKey);
      final guide = picked != null && picked.isNotEmpty
          ? backgroundBrandByKey(picked)
          : backgroundBrandFor(
              await _bg.invokeMethod<String>('deviceBrand') ?? '');
      if (mounted) setState(() => _brand = guide);
    } catch (_) {/* stays on "Other phones" */}
  }

  Future<void> _pickBrand() async {
    final key = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final g in kBackgroundBrandGuides)
              ListTile(
                title: Text(g.title),
                trailing: g.key == _brand.key
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(sheetContext, g.key),
              ),
          ],
        ),
      ),
    );
    if (key == null || !mounted) return;
    await widget.store.writeSetting(_brandKey, key);
    if (mounted) setState(() => _brand = backgroundBrandByKey(key));
  }

  Future<void> _openBrandSettings() async {
    try {
      await _bg.invokeMethod<String>(
          'openBrandSettings', <String, Object?>{'brand': _brand.key});
    } catch (_) {
      _toast('Could not open your phone’s settings right now.');
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _enableKeepAlive() async {
    try {
      await _bg.invokeMethod<void>('keepAliveStart');
    } catch (_) {}
    await widget.store.writeSetting(_keepAliveKey, 'true');
    if (mounted) setState(() => _keepAlive = true);
  }

  Future<void> _requestBattery() async {
    if (_batteryExempt) {
      _toast('$_lockedToast Battery optimization is already ignored.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _bg.invokeMethod<void>('requestBatteryExemption');
    } catch (_) {
      _toast('Could not open the battery dialog right now — try again.');
    }
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  void _explainRecentsLock() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Lock LocalLink in Recents',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          const Text(
            '1. Open the Recents (recent apps) screen.\n'
            '2. Tap the LocalLink app icon at the top of its card.\n'
            '3. Choose “Lock”. A padlock stays on the card — the system '
            'won’t swipe the app away in “clear all”.',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
        ]),
      ),
    );
  }

  /// Bundle 163 (5.6): brand card - title, numbered steps, Open settings.
  Widget _brandCard(ColorScheme scheme) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your phone: ${_brand.title}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              for (var i = 0; i < _brand.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: scheme.primary.withValues(alpha: 0.12),
                        child: Text('${i + 1}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: scheme.primary)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(_brand.steps[i],
                              style: const TextStyle(fontSize: 14, height: 1.35))),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton(
                    onPressed: _openBrandSettings,
                    child: const Text('Open settings'),
                  ),
                  TextButton(
                    onPressed: _pickBrand,
                    child: const Text('Other brand? Tap to pick'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _icon(IconData icon, {Color? color}) => CircleAvatar(
      backgroundColor:
          (color ?? Theme.of(context).colorScheme.primary).withValues(alpha: 0.12),
      child: Icon(icon,
          color: color ?? Theme.of(context).colorScheme.primary, size: 20));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Keep LocalLink running')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_running != null) ...[
            Text('STATUS',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: scheme.onSurface.withValues(alpha: 0.55))),
            const SizedBox(height: 10),
            BackgroundStatusCard(
              running: _running!,
              notifications: _notificationsOn,
              starting: _starting,
              onStart: _startService,
              onAllowNotifications: _allowNotifications,
              nearby: _nearby,
            ),
            const SizedBox(height: 20),
          ],
          if (_bgLocationNeeded) ...[
            _backgroundLocationCard(),
            const SizedBox(height: 20),
          ],
          Text('BACKGROUND',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: scheme.onSurface.withValues(alpha: 0.55))),
          const SizedBox(height: 10),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side:
                    BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
            child: Column(children: [
              // Row 1 — master switch (locks ON after grant)
              SwitchListTile(
                secondary: _icon(Icons.power_settings_new_rounded),
                title: const Text('Keep running in background',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Stay reachable even when the app is closed'),
                value: _keepAlive,
                onChanged: (wantOn) async {
                  if (!wantOn) {
                    // Locked — required for background delivery, per app policy.
                    _toast(_lockedToast);
                    return;
                  }
                  await _enableKeepAlive();
                },
              ),
              Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
              // Row 2 — battery exemption (locks after grant)
              ListTile(
                leading: _icon(
                    Icons.battery_charging_full_rounded,
                    color: _batteryExempt ? Colors.green : null),
                title: const Text('Ignore battery optimization',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(_batteryExempt
                    ? 'Allowed — required'
                    : 'Recommended — messages arrive instantly'),
                trailing: _batteryExempt
                    ? Icon(Icons.check_circle, color: Colors.green[700])
                    : (_busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.chevron_right)),
                onTap: _requestBattery,
              ),
              Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
              // Row 4 — recents lock how-to
              ListTile(
                leading: _icon(Icons.lock_outline_rounded),
                title: const Text('Lock app in recents',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Open Recents, tap the LocalLink icon, choose Lock'),
                trailing: const Icon(Icons.info_outline, size: 18),
                onTap: _explainRecentsLock,
              ),
            ]),
          ),
          const SizedBox(height: 20),
          Text('YOUR PHONE',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: scheme.onSurface.withValues(alpha: 0.55))),
          const SizedBox(height: 10),
          _brandCard(scheme),
          const SizedBox(height: 14),
          Text(
            'Battery-permission dialogs are shown only when you tap a row. '
            'Nothing is enabled silently.',
            style: TextStyle(
                fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.55)),
          ),
        ],
      ),
    );
  }
}
