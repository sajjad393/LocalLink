import 'package:flutter/material.dart';

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/theme/app_tokens.dart';

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
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          LocalLinkSpacing.md,
          LocalLinkSpacing.sm,
          LocalLinkSpacing.md,
          LocalLinkSpacing.screen,
        ),
        children: [
          Text(
            'Choose how LocalLink looks on this phone.',
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
                  title: 'System default',
                  subtitle: 'Follow the phone’s light or dark mode.',
                ),
                const Divider(height: 1, indent: 72),
                _option(
                  context,
                  mode: ThemeMode.light,
                  icon: Icons.light_mode_outlined,
                  title: 'Light',
                  subtitle: 'Always use the light theme.',
                ),
                const Divider(height: 1, indent: 72),
                _option(
                  context,
                  mode: ThemeMode.dark,
                  icon: Icons.dark_mode_outlined,
                  title: 'Dark',
                  subtitle: 'Always use the dark theme.',
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
      title: const Text('Diagnostic capture mode'),
      subtitle: const Text(
          'Verbose logs for support captures. Turns off when the app restarts.'),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: LocalLinkSpacing.md,
        vertical: LocalLinkSpacing.xs,
      ),
    );
  }
}
