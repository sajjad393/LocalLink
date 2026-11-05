// Bundle 213 (mock pages 1-3): App version card, Minimum version page,
// "Save for everyone" confirm, and the testers' "Pretend old build" switch.

import 'package:flutter/material.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/admin/data/models/version_rule.dart';
import 'package:locallink/features/admin/data/services/version_guard.dart';
import 'package:locallink/features/admin/data/services/version_rule_service.dart';

String _modeLine(VersionRule? r) {
  if (r == null || r.isRemove) return 'No minimum';
  final v = r.minVersion.isEmpty ? 'build ${r.minBuild}' : r.minVersion;
  if (r.warnOnly) return '$v · warn only';
  final stop = r.stopTime;
  if (stop == null || !DateTime.now().isBefore(stop)) return '$v · older versions stopped';
  final days = (stop.difference(DateTime.now()).inMinutes / 1440).ceil();
  return '$v · stop in $days day${days == 1 ? '' : 's'}';
}

/// Admin panel card under "Block users".
class AdminVersionCard extends StatelessWidget {
  const AdminVersionCard({super.key, this.service});

  final VersionRuleService? service;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: VersionGuard.instance,
      builder: (context, _) {
        final svc = service ?? VersionRuleService.instance;
        final counts = svc?.buildCounts() ?? const <int, ({String version, int phones})>{};
        final builds = counts.keys.toList()..sort((a, b) => b.compareTo(a));
        return Card(
          key: const ValueKey('admin_version_card'),
          elevation: 0,
          margin: const EdgeInsets.only(top: 6, bottom: 6),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Text('App version', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text('This phone: LinkUp $kAppVersion (build $kAppBuild)'
                  '${AppBuild.pretendOld ? ' · pretending ${AppBuild.sent}' : ''}'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                builds.isEmpty
                    ? 'Seen nearby: none yet'
                    : 'Seen nearby: ${builds.map((b) => '${counts[b]!.version.isEmpty ? 'build $b' : counts[b]!.version} (${counts[b]!.phones})').join(', ')}',
                key: const ValueKey('admin_version_seen'),
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
            ListTile(
              key: const ValueKey('admin_version_min'),
              leading: CircleAvatar(
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.system_update_alt, color: scheme.primary)),
              title: const Text('Minimum version', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(_modeLine(VersionGuard.instance.rule)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => AdminMinVersionScreen(service: svc))),
            ),
          ]),
        );
      },
    );
  }
}

enum _Mode { warn, stopNow, stopLater }

/// Mock page 2: pick the minimum version and what happens to older apps.
class AdminMinVersionScreen extends StatefulWidget {
  const AdminMinVersionScreen({super.key, this.service});

  final VersionRuleService? service;

  @override
  State<AdminMinVersionScreen> createState() => _AdminMinVersionScreenState();
}

class _AdminMinVersionScreenState extends State<AdminMinVersionScreen> {
  late int _build;
  _Mode _mode = _Mode.stopLater;
  int _days = 3;
  bool _veryOld = false;
  bool _busy = false;

  VersionRuleService? get _svc => widget.service ?? VersionRuleService.instance;

  @override
  void initState() {
    super.initState();
    final r = VersionGuard.instance.rule;
    _build = kAppBuild;
    if (r != null && !r.isRemove && r.minBuild <= kAppBuild) {
      _build = r.minBuild;
      _veryOld = r.veryOld;
      _mode = r.warnOnly ? _Mode.warn : _Mode.stopLater;
    }
  }

  /// This phone's version and lower ones seen nearby.
  List<({int build, String version})> _choices() {
    final counts = _svc?.buildCounts() ?? const <int, ({String version, int phones})>{};
    final out = <({int build, String version})>[(build: kAppBuild, version: kAppVersion)];
    for (final b in counts.keys.toList()..sort((a, c) => c.compareTo(a))) {
      if (b < kAppBuild) out.add((build: b, version: counts[b]!.version));
    }
    if (_build != kAppBuild && !out.any((c) => c.build == _build)) {
      out.add((build: _build, version: VersionGuard.instance.rule?.minVersion ?? ''));
    }
    return out;
  }

  String _label(({int build, String version}) c) =>
      c.version.isEmpty ? 'Build ${c.build}' : '${c.version} (build ${c.build})';

  String get _versionText {
    for (final c in _choices()) {
      if (c.build == _build) return c.version.isEmpty ? 'build $_build' : c.version;
    }
    return 'build $_build';
  }

  Future<void> _save() async {
    final svc = _svc;
    if (svc == null) return;
    final v = _versionText;
    final affects = svc.affects(_build);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('version_confirm'),
        title: Text(_mode == _Mode.warn ? 'Warn versions below $v?' : 'Stop versions below $v?'),
        content: Text([
          switch (_mode) {
            _Mode.warn => 'Older apps see a yellow "Update" banner. They keep working.',
            _Mode.stopNow => 'Older apps can only read chats from now. They see an Update button.',
            _Mode.stopLater =>
              'Older apps see "Update needed in $_days days". After that they can only read chats.',
          },
          if (_veryOld) 'Very old apps (before 3.0.54) are stopped too.',
          'Phones seen nearby that this affects: $affects.',
          'It goes to every phone nearby, and to the server when online.',
        ].join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const ValueKey('version_confirm_save'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save for everyone'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() => svc.setRule(
          minBuild: _build,
          minVersion: _choices().firstWhere((c) => c.build == _build).version,
          mode: _mode == _Mode.warn ? 'warn' : 'stop',
          stopDays: _mode == _Mode.stopLater ? _days : 0,
          veryOld: _veryOld,
        ), 'Saved. It is spreading to nearby phones.');
  }

  Future<void> _remove() async {
    final svc = _svc;
    if (svc == null) return;
    await _run(() => svc.setRule(minBuild: 0, minVersion: '', mode: 'warn', remove: true),
        'Rule removed for everyone.');
  }

  Future<void> _run(Future<Object?> Function() job, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await job();
      messenger?.showSnackBar(SnackBar(content: Text(done)));
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      final text = e is StateError ? e.message : 'Could not save: $e';
      messenger?.showSnackBar(SnackBar(content: Text(text)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rule = VersionGuard.instance.rule;
    final svc = _svc;
    final affects = svc?.affects(_build) ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Minimum version')),
      body: ListView(
        key: const ValueKey('admin_min_version'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text('Now: ${_modeLine(rule)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          const Text('Lowest version allowed', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          RadioGroup<int>(
            groupValue: _build,
            onChanged: (v) => setState(() => _build = v ?? _build),
            child: Column(children: [
              for (final c in _choices())
                RadioListTile<int>(
                  key: ValueKey('version_pick_${c.build}'),
                  value: c.build,
                  title: Text(_label(c)),
                  subtitle: c.build == kAppBuild ? const Text('This phone') : null,
                ),
            ]),
          ),
          const SizedBox(height: 8),
          const Text('Older apps', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          RadioGroup<_Mode>(
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v ?? _mode),
            child: Column(children: [
          const RadioListTile<_Mode>(
            key: ValueKey('version_mode_warn'),
            value: _Mode.warn,
            title: Text('Warn only'),
            subtitle: Text('Yellow banner, keeps working'),
          ),
          const RadioListTile<_Mode>(
            key: ValueKey('version_mode_now'),
            value: _Mode.stopNow,
            title: Text('Stop now'),
            subtitle: Text('Read only at once'),
          ),
          RadioListTile<_Mode>(
            key: const ValueKey('version_mode_later'),
            value: _Mode.stopLater,
            title: Text('Stop after $_days day${_days == 1 ? '' : 's'}'),
            subtitle: const Text('Warning first, then read only'),
            secondary: _mode == _Mode.stopLater
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      key: const ValueKey('version_days_minus'),
                      onPressed: _days > 1 ? () => setState(() => _days--) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    IconButton(
                      key: const ValueKey('version_days_plus'),
                      onPressed: _days < 30 ? () => setState(() => _days++) : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ])
                : null,
          ),
            ]),
          ),
          SwitchListTile(
            key: const ValueKey('version_very_old'),
            value: _veryOld,
            onChanged: (v) => setState(() => _veryOld = v),
            title: const Text('Also stop very old apps'),
            subtitle: const Text(
                "Apps before 3.0.54 can't read this rule. The server refuses them and updated phones don't link with them."),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Affects $affects phone${affects == 1 ? '' : 's'} seen nearby',
                key: const ValueKey('version_affects')),
          ),
          FilledButton(
            key: const ValueKey('version_save'),
            onPressed: _busy || svc == null ? null : _save,
            child: const Text('Save rule'),
          ),
          if (rule != null && !rule.isRemove)
            TextButton(
              key: const ValueKey('version_remove'),
              onPressed: _busy || svc == null ? null : _remove,
              child: const Text('Remove rule'),
            ),
        ],
      ),
    );
  }
}

/// Testers only: this phone reports one build lower (try the rule with
/// two phones on the same version).
class PretendOldBuildSwitch extends StatefulWidget {
  const PretendOldBuildSwitch({super.key, this.service});

  final VersionRuleService? service;

  @override
  State<PretendOldBuildSwitch> createState() => _PretendOldBuildSwitchState();
}

class _PretendOldBuildSwitchState extends State<PretendOldBuildSwitch> {
  @override
  Widget build(BuildContext context) {
    final svc = widget.service ?? VersionRuleService.instance;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: SwitchListTile(
        key: const ValueKey('pretend_old_build'),
        value: AppBuild.pretendOld,
        onChanged: svc == null
            ? null
            : (v) async {
                await svc.setPretendOld(v);
                if (mounted) setState(() {});
              },
        title: const Text('Pretend old build'),
        subtitle: const Text('This phone says build ${kAppBuild - 1} instead of $kAppBuild'),
      ),
    );
  }
}
