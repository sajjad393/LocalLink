import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';

enum LocalLinkButtonVariant { primary, secondary, text }

class LocalLinkButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final LocalLinkButtonVariant variant;
  final bool loading;
  final bool expanded;

  const LocalLinkButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = LocalLinkButtonVariant.primary,
    this.loading = false,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);

    final Widget button;
    switch (variant) {
      case LocalLinkButtonVariant.primary:
        button = icon == null
            ? FilledButton(onPressed: loading ? null : onPressed, child: child)
            : FilledButton.icon(
                onPressed: loading ? null : onPressed,
                icon: icon!,
                label: child,
              );
      case LocalLinkButtonVariant.secondary:
        button = icon == null
            ? OutlinedButton(onPressed: loading ? null : onPressed, child: child)
            : OutlinedButton.icon(
                onPressed: loading ? null : onPressed,
                icon: icon!,
                label: child,
              );
      case LocalLinkButtonVariant.text:
        button = icon == null
            ? TextButton(onPressed: loading ? null : onPressed, child: child)
            : TextButton.icon(
                onPressed: loading ? null : onPressed,
                icon: icon!,
                label: child,
              );
    }

    if (!expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

class LocalLinkIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final String? tooltip;
  final bool filled;

  const LocalLinkIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = filled
        ? IconButton.filled(onPressed: onPressed, icon: icon)
        : IconButton(onPressed: onPressed, icon: icon);
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
