import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';

class LocalLinkCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final BorderSide? borderSide;

  const LocalLinkCard({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(LocalLinkSpacing.lg),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.borderSide,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      color: color,
      margin: margin,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LocalLinkRadius.xl),
        side: borderSide ?? BorderSide.none,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LocalLinkRadius.xl),
      child: card,
    );
  }
}

class LocalLinkInfoCard extends StatelessWidget {
  final Widget icon;
  final String title;
  final String message;
  final Color? color;

  const LocalLinkInfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cardColor = color ?? colors.primaryContainer;
    final foreground = ThemeData.estimateBrightnessForColor(cardColor) == Brightness.dark
        ? Colors.white
        : colors.onPrimaryContainer;
    return LocalLinkCard(
      color: cardColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTheme(
            data: IconThemeData(color: foreground, size: 28),
            child: icon,
          ),
          const SizedBox(width: LocalLinkSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: foreground)),
                const SizedBox(height: LocalLinkSpacing.xs),
                Text(
                  message,
                  style: TextStyle(color: foreground.withOpacity(0.78)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
