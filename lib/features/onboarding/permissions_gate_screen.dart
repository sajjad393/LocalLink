import 'package:flutter/material.dart';

import 'package:locallink/core/permissions/permission_gate_service.dart';

/// Bundle 94 — pre-dashboard permission setup (user-selected policy).
///
/// Rules:
///  * Microphone + Nearby devices are REQUIRED (calls & discovery are the core
///    product); Camera + Notifications are OPTIONAL and can be skipped.
///  * Shown at EVERY cold start while a required permission is missing;
///    disappears forever once both are granted (a revoked grant re-opens it).
///  * Every grant tap runs the REAL Android runtime prompt (one batch), and
///    every row re-verifies itself afterwards — a dismissed dialog changes
///    nothing visibly.
class PermissionsGateScreen extends StatefulWidget {
  const PermissionsGateScreen({super.key});

  /// Returns true when the required set was satisfied by the time the screen
  /// closed (whether the user finished or never needed the screen).
  static Future<bool> maybeShow(BuildContext context) async {
    try {
      final statuses = await PermissionGate.statuses();
      if (PermissionGate.requiredSatisfied(statuses)) return true;
      if (!context.mounted) return false;
      final done = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const PermissionsGateScreen()),
      );
      return done == true;
    } catch (_) {
      // A channel hiccup must never block the dashboard (playbook rule).
      return true;
    }
  }

  @override
  State<PermissionsGateScreen> createState() => _PermissionsGateScreenState();
}

class _PermissionsGateScreenState extends State<PermissionsGateScreen> {
  Map<String, Map<String, bool>> _statuses = const {};
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final s = await PermissionGate.statuses();
      if (mounted) setState(() => _statuses = s);
    } catch (_) {}
  }

  Future<void> _grant(List<String> names) async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      final s = await PermissionGate.request(names);
      if (mounted) setState(() => _statuses = s);
    } catch (_) {} finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  bool get _requiredDone => PermissionGate.requiredSatisfied(_statuses);

  Widget _row({
    required String name,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final entry = _statuses[name];
    final granted = entry?['granted'] == true;
    final canRequest = entry?['can_request'] != false;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, size: 30),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: granted
            ? const Chip(
                avatar: Icon(Icons.check, size: 16),
                label: Text('Granted'),
              )
            : _requesting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : canRequest
                    ? FilledButton.tonal(
                        onPressed: () => _grant([name]),
                        child: const Text('Allow'),
                      )
                    : OutlinedButton(
                        onPressed: PermissionGate.openSettings,
                        child: const Text('Open settings'),
                      ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        visualDensity: VisualDensity.comfortable,
        subtitleTextStyle: Theme.of(context).textTheme.bodySmall,
        titleTextStyle: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Set up LocalLink'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Allow these so calls and nearby discovery work. You only get '
                'this screen when a required one is missing.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              _row(
                name: 'microphone',
                icon: Icons.mic_rounded,
                title: 'Microphone',
                subtitle: 'So others can hear you on calls · REQUIRED',
              ),
              _row(
                name: 'nearby',
                icon: Icons.wifi_tethering_rounded,
                title: 'Nearby devices',
                subtitle: 'Find people on Wi-Fi Direct / mesh · REQUIRED',
              ),
              _row(
                name: 'camera',
                icon: Icons.videocam_rounded,
                title: 'Camera',
                subtitle: 'Video calls · optional',
              ),
              _row(
                name: 'notifications',
                icon: Icons.notifications_rounded,
                title: 'Notifications',
                subtitle: 'Incoming-call alerts in background · optional',
              ),
              const Spacer(),
              if (!_requiredDone)
                Text(
                  'Grant Microphone and Nearby devices to continue.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _requiredDone
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
