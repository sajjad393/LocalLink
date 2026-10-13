import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';

/// Brand gradient pill button from the reference messenger design
/// (blue→cyan, fully rounded, white label). Replaces FilledButton only where
/// the accent look is desired (welcome/hero actions).
class GradientPillButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;

  const GradientPillButton({super.key, required this.onPressed, required this.child});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final labelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Colors.white,
      fontSize: 16,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
        child: Ink(
          decoration: BoxDecoration(
            gradient: enabled
                ? LocalLinkBrand.linearGradient
                : const LinearGradient(colors: [Color(0xFF9A9AAF), Color(0xFF9A9AAF)]),
            borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: LocalLinkBrand.gradientStart.withValues(alpha: 0.32),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: LocalLinkSpacing.xl),
            child: DefaultTextStyle(
              style: labelStyle ?? const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              child: IconTheme(data: const IconThemeData(color: Colors.white, size: 20), child: child),
            ),
          ),
        ),
      ),
    );
  }
}
