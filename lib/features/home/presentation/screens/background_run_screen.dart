import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/theme/app_tokens.dart';

/// Bundle 140: "Keep LocalLink running" — approved mock.
/// Opt-in on tap only; once granted, options LOCK and only explain themselves
/// via a toast (user requirement: the app must stay reachable).
class BackgroundRunScreen extends StatefulWidget {
  final LocalStore store;
  const BackgroundRunScreen({super.key, required this.store});

  @override
  State<BackgroundRunScreen> createState() => _BackgroundRunScreenState();
}

class _BackgroundRunScreenState extends State<BackgroundRunScreen> {
  static const _bg = MethodChannel('locallink/background');
  static const _keepAliveKey = 'keep_alive_enabled';

  bool _keepAlive = true;
  bool _batteryExempt = false;
  bool _busy = false;

  static const _lockedToast =
      'LocalLink needs this to stay on — messages and calls must keep arriving '
      'in the background.';

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _openVendor() async {
    try {
      await _bg.invokeMethod<String>('openVendorSettings');
    } catch (_) {
      _toast('Could not open your phone’s app settings right now.');
    }
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

  Widget _icon(IconData icon, {Color? color}) => CircleAvatar(
      backgroundColor:
          (color ?? Theme.of(context).colorScheme.primary).withOpacity(0.12),
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
          Text('BACKGROUND',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: scheme.onSurface.withOpacity(0.55))),
          const SizedBox(height: 10),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side:
                    BorderSide(color: scheme.outlineVariant.withOpacity(0.5))),
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
              Divider(height: 1, color: scheme.outlineVariant.withOpacity(0.5)),
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
              Divider(height: 1, color: scheme.outlineVariant.withOpacity(0.5)),
              // Row 3 — vendor settings deep link
              ListTile(
                leading: _icon(Icons.settings_suggest_rounded),
                title: const Text('Phone vendor settings',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Autostart and background activity (HiOS and others)'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openVendor,
              ),
              Divider(height: 1, color: scheme.outlineVariant.withOpacity(0.5)),
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
          const SizedBox(height: 14),
          Text(
            'Battery-permission dialogs are shown only when you tap a row. '
            'Nothing is enabled silently.',
            style: TextStyle(
                fontSize: 12, color: scheme.onSurface.withOpacity(0.55)),
          ),
        ],
      ),
    );
  }
}
