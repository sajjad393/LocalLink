import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'package:locallink/core/theme/app_tokens.dart';

class LocalLinkLoadingView extends StatefulWidget {
  final String? message;

  const LocalLinkLoadingView({super.key, this.message});

  @override
  State<LocalLinkLoadingView> createState() => _LocalLinkLoadingViewState();
}

class _LocalLinkLoadingViewState extends State<LocalLinkLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final highlight = scheme.surfaceContainerHigh;
    final widths = <double>[0.72, 0.5, 0.62, 0.4];

    Widget bar(double widthFactor, double height) => FractionallySizedBox(
          widthFactor: widthFactor,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(height / 2.4),
            ),
          ),
        );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LocalLinkSpacing.xxxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value * 2 - 1;
              return ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (rect) => LinearGradient(
                  begin: Alignment(t - 0.6, 0),
                  end: Alignment(t + 0.6, 0),
                  colors: [base, highlight, base],
                  stops: const [0.0, 0.5, 1.0],
                ).createShader(rect),
                child: child,
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final w in widths) ...[
                  bar(w, 46),
                  const SizedBox(height: LocalLinkSpacing.md),
                ],
                if (widget.message != null) ...[
                  const SizedBox(height: LocalLinkSpacing.xs),
                  Center(
                    child: Text(
                      widget.message!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ],
            ),
          ),
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

  /// Optional Lottie animation shown instead of the icon circle
  /// (e.g. 'assets/animations/empty_inbox.json'). The asset must exist.
  final String? lottieAsset;

  const LocalLinkEmptyView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.lottieAsset,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lottie = lottieAsset;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LocalLinkSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (lottie != null)
              Lottie.asset(
                lottie,
                width: 160,
                height: 150,
                repeat: true,
                errorBuilder: (context, error, stackTrace) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(LocalLinkSpacing.xl),
                    child: Icon(icon, size: 36, color: colors.onSecondaryContainer),
                  ),
                ),
              )
            else
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
