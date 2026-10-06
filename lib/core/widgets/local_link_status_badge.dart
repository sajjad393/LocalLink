import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';

class LocalLinkStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const LocalLinkStatusBadge({
    super.key,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Connection status: $label',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
          border: Border.all(color: color.withOpacity(0.28)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LocalLinkSpacing.md,
            vertical: LocalLinkSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: LocalLinkSpacing.xs),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
