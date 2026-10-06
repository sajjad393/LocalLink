import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';

class LocalLinkLoadingView extends StatelessWidget {
  final String? message;

  const LocalLinkLoadingView({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LocalLinkSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (message != null) ...[
              const SizedBox(height: LocalLinkSpacing.lg),
              Text(message!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

class LocalLinkEmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const LocalLinkEmptyView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LocalLinkSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(LocalLinkSpacing.xl),
                child: Icon(icon, size: 36, color: colors.onSecondaryContainer),
              ),
            ),
            const SizedBox(height: LocalLinkSpacing.lg),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: LocalLinkSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(message, textAlign: TextAlign.center),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: LocalLinkSpacing.lg),
              FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class LocalLinkErrorText extends StatelessWidget {
  final String message;
  final TextAlign textAlign;

  const LocalLinkErrorText({
    super.key,
    required this.message,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      textAlign: textAlign,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.error,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class LocalLinkInlineError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const LocalLinkInlineError({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(LocalLinkSpacing.lg, LocalLinkSpacing.sm, LocalLinkSpacing.lg, 0),
      padding: const EdgeInsets.symmetric(horizontal: LocalLinkSpacing.md, vertical: LocalLinkSpacing.sm),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(LocalLinkRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: colors.onErrorContainer, size: 20),
          const SizedBox(width: LocalLinkSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer, fontWeight: FontWeight.w600),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}


class LocalLinkInlineInfo extends StatelessWidget {
  final IconData icon;
  final String message;

  const LocalLinkInlineInfo({
    super.key,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(LocalLinkRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(LocalLinkSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: LocalLinkSpacing.md),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
