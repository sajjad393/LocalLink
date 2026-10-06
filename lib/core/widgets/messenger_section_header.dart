import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';

class MessengerSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const MessengerSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LocalLinkSpacing.lg,
        LocalLinkSpacing.lg,
        LocalLinkSpacing.lg,
        LocalLinkSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(child: Text(title, style: LocalLinkTypography.sectionTitle)),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
