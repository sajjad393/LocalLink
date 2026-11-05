// Bundle 213 (mock pages 1-3): App version card, Minimum version page,
// "Save for everyone" confirm, and the testers' "Pretend old build" switch.

import 'package:flutter/material.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/admin/data/models/version_rule.dart';
import 'package:locallink/features/admin/data/services/version_guard.dart';
import 'package:locallink/features/admin/data/services/version_rule_service.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';

String _modeLine(VersionRule? r) {
  if (r == null || r.isRemove) return 'No minimum';
  final v = r.minVersion.isEmpty ? 'build ${r.minBuild}' : r.minVersion;
  if (r.warnOnly) return '$v · warn only';
  final stop = r.stopTime;
  if (stop == null || !DateTime.now().isBefore(stop)) return '$v · older versions stopped';
  final days = (stop.difference(DateTime.now()).inMinutes / 1440).ceil();
  return '$v · stop in $days day${days == 1 ? '' : 's'}';
}

/// Admin panel card under "Block users". Bundle 216 (page 4): section
/// 'App version' + one card: Minimum version row, then this phone and the
/// versions seen nearby.
class AdminVersionCard extends StatelessWidget {
  const AdminVersionCard({super.key, this.service});

  final VersionRuleService? service;

  static String seenLine(VersionRuleService? svc) {
    final counts = svc?.buildCounts() ?? const <int, ({String version, int phones})>{};
    final builds = counts.keys.toList()..sort((a, b) => b.compareTo(a));
    return builds.isEmpty
        ? 'Seen nearby: none yet'
        : 'Seen nearby: ${builds.map((b) => '${counts[b]!.version.isEmpty ? 'build $b' : counts[b]!.version} (${counts[b]!.phones})').join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VersionGuard.instance,
      builder: (context, _) {
        final svc = service ?? VersionRuleService.instance;
        final c = A216.colors(context);
        final t = A216Text(c);
        return Column(
          key: const ValueKey('admin_version_card'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AdminSection216('App version'),
            AdminCard216(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const ValueKey('admin_version_min'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => AdminMinVersionScreen(service: svc))),
                    child: SizedBox(
                      height: 60,
                      child: Row(children: [
                        const SizedBox(width: 12),
                        const SizedBox(
                            width: 40,
                            child: Center(
                                child: AdminToneIcon216(
                                    Icons.system_update_outlined, A216Tone.purple))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Minimum version', style: t.rowTitle),
                              const SizedBox(height: 3),
                              Text(_modeLine(VersionGuard.instance.rule),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.rowSub),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, size: 16, color: c.grey2),
                        const SizedBox(width: 18),
                      ]),
                    ),
                  ),
                ),
                Container(height: 1, color: c.div),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('This phone: LinkUp $kAppVersion (build $kAppBuild)'
                        '${AppBuild.pretendOld ? ' · pretending ${AppBuild.sent}' : ''}',
                        style: t.cardSub),
                    const SizedBox(height: 4),
                    Text(seenLine(svc),
                        key: const ValueKey('admin_version_seen'), style: t.cardSub),
                  ]),
                ),
              ]),
            ),
          ],
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
    final choices = _choices();
    return AdminPage216(
      title: 'Minimum version',
      body: Builder(builder: (context) {
        final c = A216.colors(context);
        final t = A216Text(c);
        return ListView(
          key: const ValueKey('admin_min_version'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          children: [
            // Bundle 216 (page 11): purple head card.
            AdminCard216(
              fill: const Color(0xFFF4F0FF),
              border: const Color(0xFFE3D8FF),
              shadow: false,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const AdminToneIcon216(Icons.system_update_outlined, A216Tone.purple,
                    radius: 15, size: 16),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Now: ${rule == null || rule.isRemove ? 'no minimum' : _modeLine(rule)}',
                        style: t.custom(14, FontWeight.w600, c.ink)),
                    const SizedBox(height: 4),
                    Text('This phone: LinkUp $kAppVersion (build $kAppBuild)', style: t.cardSub),
                    const SizedBox(height: 2),
                    Text(AdminVersionCard.seenLine(svc), style: t.cardSub),
                  ]),
                ),
              ]),
            ),
            const AdminSection216('Lowest version allowed'),
            AdminChips216(
              wrap: true,
              items: [for (final ch in choices) _label(ch)],
              selected: choices.indexWhere((ch) => ch.build == _build),
              keys: [for (final ch in choices) ValueKey('version_pick_${ch.build}')],
              onSelected: (i) => setState(() => _build = choices[i].build),
            ),
            const AdminSection216('Older apps'),
            AdminRadioCard216(
              key: const ValueKey('version_mode_warn'),
              title: 'Warn only',
              subtitle: 'Yellow banner, keeps working',
              selected: _mode == _Mode.warn,
              onTap: () => setState(() => _mode = _Mode.warn),
            ),
            const SizedBox(height: 10),
            AdminRadioCard216(
              key: const ValueKey('version_mode_now'),
              title: 'Stop now',
              subtitle: 'Read only at once',
              selected: _mode == _Mode.stopNow,
              onTap: () => setState(() => _mode = _Mode.stopNow),
            ),
            const SizedBox(height: 10),
            AdminRadioCard216(
              key: const ValueKey('version_mode_days'),
              title: 'Stop after $_days day${_days == 1 ? '' : 's'}',
              subtitle: 'Warning first, then read only',
              selected: _mode == _Mode.stopLater,
              onTap: () => setState(() => _mode = _Mode.stopLater),
              trailing: _mode == _Mode.stopLater
                  ? AdminStepper216(
                      value: '$_days day${_days == 1 ? '' : 's'}',
                      minusKey: const ValueKey('version_days_minus'),
                      plusKey: const ValueKey('version_days_plus'),
                      onMinus: _days > 1 ? () => setState(() => _days--) : null,
                      onPlus: _days < 30 ? () => setState(() => _days++) : null,
                    )
                  : null,
            ),
            const SizedBox(height: 10),
            AdminCard216(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Also stop very old apps', style: t.radioTitle),
                    const SizedBox(height: 3),
                    Text("Apps before 3.0.54 can't read this rule. The server refuses them.",
                        style: t.radioSub),
                  ]),
                ),
                const SizedBox(width: 12),
                A216Switch(
                  key: const ValueKey('version_very_old'),
                  value: _veryOld,
                  onChanged: (v) => setState(() => _veryOld = v),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('Affects $affects phone${affects == 1 ? '' : 's'} seen nearby',
                  key: const ValueKey('version_affects'),
                  textAlign: TextAlign.center,
                  style: t.note),
            ),
            AdminButton216('Save rule',
                key: const ValueKey('version_save'),
                onTap: _busy || svc == null ? null : _save),
            if (rule != null && !rule.isRemove) ...[
              const SizedBox(height: 10),
              AdminButton216('Remove rule',
                  key: const ValueKey('version_remove'),
                  kind: A216ButtonKind.outline,
                  onTap: _busy || svc == null ? null : _remove),
            ],
          ],
        );
      }),
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
    final t = A216Text.of(context);
    // Bundle 216 (page 26): a Testers row with the 216 switch.
    return SizedBox(
      height: 56,
      child: Row(children: [
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pretend old build', style: t.rowTitle),
              const SizedBox(height: 3),
              Text('This phone reports one build lower', style: t.rowSub),
            ],
          ),
        ),
        A216Switch(
          key: const ValueKey('pretend_old_build'),
          value: AppBuild.pretendOld,
          onChanged: svc == null
              ? null
              : (v) async {
                  await svc.setPretendOld(v);
                  if (mounted) setState(() {});
                },
        ),
        const SizedBox(width: 14),
      ]),
    );
  }
}
