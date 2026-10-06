import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';

class LocalLinkStatusLine extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final String? detail;

  const LocalLinkStatusLine({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Connection status: $label${detail == null ? '' : '. $detail'}',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LocalLinkSpacing.md,
          vertical: LocalLinkSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: color.withOpacity(0.09),
          borderRadius: BorderRadius.circular(LocalLinkRadius.md),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: LocalLinkSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: LocalLinkSpacing.xs),
                    Text(detail!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
