import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';

/// Bundle 104: the brand-gradient circular FAB used by the People tab,
/// extracted so Chats and Calls share the identical look — blue→cyan
/// gradient circle, raised shadow, white icon. Nothing else changes.
class BrandGradientFab extends StatelessWidget {
  final String heroTag;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const BrandGradientFab({
    super.key,
    required this.heroTag,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: heroTag,
      tooltip: tooltip,
      onPressed: onPressed,
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LocalLinkBrand.linearGradient,
          shape: BoxShape.circle,
        ),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
