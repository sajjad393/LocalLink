import 'package:flutter/material.dart';

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/l10n/l10n.dart';

class AppearanceSettingsScreen extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const AppearanceSettingsScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(L.t.appearance)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          LocalLinkSpacing.md,
          LocalLinkSpacing.sm,
          LocalLinkSpacing.md,
          LocalLinkSpacing.screen,
        ),
        children: [
          Text(
            L.t.chooseHowLinkupLooksOnThis,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: LocalLinkSpacing.lg),
          Card(
            child: Column(
              children: [
                _option(
                  context,
                  mode: ThemeMode.system,
                  icon: Icons.brightness_auto_outlined,
                  title: L.t.systemDefault,
                  subtitle: L.t.followThePhoneSLightOr,
                ),
                const Divider(height: 1, indent: 72),
                _option(
                  context,
                  mode: ThemeMode.light,
                  icon: Icons.light_mode_outlined,
                  title: L.t.light,
                  subtitle: L.t.alwaysUseTheLightTheme,
                ),
                const Divider(height: 1, indent: 72),
                _option(
                  context,
                  mode: ThemeMode.dark,
                  icon: Icons.dark_mode_outlined,
                  title: L.t.dark,
                  subtitle: L.t.alwaysUseTheDarkTheme,
                ),
              ],
            ),
          ),
          const SizedBox(height: LocalLinkSpacing.lg),
          const Card(child: _VerboseLogsTile()),
        ],
      ),
    );
  }

  Widget _option(
    BuildContext context, {
    required ThemeMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return RadioListTile<ThemeMode>(
      value: mode,
      groupValue: themeMode,
      onChanged: (value) {
        if (value != null) onThemeModeChanged(value);
      },
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: LocalLinkSpacing.md,
        vertical: LocalLinkSpacing.xs,
      ),
    );
  }
}

/// Verbose app logs are OFF by default (they flood logcat). Turn on only when
/// a support capture is requested; warnings/errors are always logged either
/// way. Not persisted: the app starts quiet again after a restart.
class _VerboseLogsTile extends StatefulWidget {
  const _VerboseLogsTile();

  @override
  State<_VerboseLogsTile> createState() => _VerboseLogsTileState();
}

class _VerboseLogsTileState extends State<_VerboseLogsTile> {
  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: AppLogger.verbose,
      onChanged: (value) => setState(() => AppLogger.verbose = value),
      secondary: const Icon(Icons.terminal_outlined),
      title: Text(L.t.diagnosticCaptureMode),
      subtitle: Text(
          L.t.verboseLogsForSupportCapturesTurns),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: LocalLinkSpacing.md,
        vertical: LocalLinkSpacing.xs,
      ),
    );
  }
}
