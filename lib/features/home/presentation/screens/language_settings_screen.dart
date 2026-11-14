import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/l10n/l10n.dart';

/// 304 (H3): Settings > Language. Phone language (default) / English / اردو.
/// The words change at once on every open screen and the choice is kept.
/// "English" and "اردو" are always written in their own language.
class LanguageSettingsScreen extends StatelessWidget {
  const LanguageSettingsScreen({super.key});

  /// The line under "Language" in Settings.
  static String label(AppLanguage304 v) => switch (v) {
        AppLanguage304.phone => L.t.phoneLanguage304,
        AppLanguage304.english => 'English',
        AppLanguage304.urdu => 'اردو',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<AppLanguage304>(
      valueListenable: LanguageBook304.instance,
      builder: (context, value, _) => Scaffold(
        appBar: AppBar(title: Text(L.t.language304)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
            LocalLinkSpacing.md,
            LocalLinkSpacing.sm,
            LocalLinkSpacing.md,
            LocalLinkSpacing.screen,
          ),
          children: [
            Text(L.t.chooseLanguage304, style: theme.textTheme.bodyLarge),
            const SizedBox(height: LocalLinkSpacing.lg),
            Card(
              child: Column(
                children: [
                  _option(context, value, AppLanguage304.phone,
                      icon: Icons.smartphone_outlined,
                      subtitle: L.t.phoneLanguageHint304),
                  const Divider(height: 1, indent: 72),
                  _option(context, value, AppLanguage304.english,
                      icon: Icons.translate_rounded),
                  const Divider(height: 1, indent: 72),
                  _option(context, value, AppLanguage304.urdu,
                      icon: Icons.translate_rounded),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(BuildContext context, AppLanguage304 current, AppLanguage304 mode,
      {required IconData icon, String? subtitle}) {
    return RadioListTile<AppLanguage304>(
      key: ValueKey('language_304_${LanguageBook304.store(mode)}'),
      value: mode,
      groupValue: current,
      onChanged: (v) {
        if (v != null) LanguageBook304.instance.choose(v);
      },
      secondary: Icon(icon),
      title: Text(label(mode)),
      subtitle: subtitle == null ? null : Text(subtitle),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: LocalLinkSpacing.md,
        vertical: LocalLinkSpacing.xs,
      ),
    );
  }
}
