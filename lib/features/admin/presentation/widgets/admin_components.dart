import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/admin_theme.dart';

// ---------------------------------------------------------------------------
// Primitives
// ---------------------------------------------------------------------------

/// Base panel: flat surface, hairline border, restrained radius. Every card in
/// the admin surface is built from this so spacing and borders stay uniform.
class AdminPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? title;
  final String? subtitle;
  final List<Widget> actions;
  final bool compact;

  const AdminPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AdminSpace.lg),
    this.title,
    this.subtitle,
    this.actions = const [],
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    final hasHeader = title != null || actions.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AdminRadius.lg),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasHeader)
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? AdminSpace.md : AdminSpace.lg,
                compact ? AdminSpace.md : AdminSpace.lg,
                AdminSpace.md,
                AdminSpace.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (title != null)
                          Text(title!,
                              style: AdminText.sectionTitle
                                  .copyWith(color: palette.textPrimary)),
                        if (subtitle != null) ...[
                          const SizedBox(height: AdminSpace.xxs),
                          Text(subtitle!,
                              style: AdminText.caption
                                  .copyWith(color: palette.textSecondary)),
                        ],
                      ],
                    ),
                  ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(width: AdminSpace.sm),
                    Wrap(spacing: AdminSpace.xs, children: actions),
                  ],
                ],
              ),
            ),
          Padding(
            padding: hasHeader
                ? EdgeInsets.fromLTRB(
                    compact ? AdminSpace.md : AdminSpace.lg,
                    0,
                    compact ? AdminSpace.md : AdminSpace.lg,
                    compact ? AdminSpace.md : AdminSpace.lg,
                  )
                : padding,
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Section heading used between major dashboard blocks.
class AdminSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final IconData? icon;

  const AdminSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AdminSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: palette.textSecondary),
            const SizedBox(width: AdminSpace.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: AdminText.sectionTitle
                        .copyWith(color: palette.textPrimary)),
                if (subtitle != null) ...[
                  const SizedBox(height: AdminSpace.xxs),
                  Text(subtitle!,
                      style: AdminText.caption
                          .copyWith(color: palette.textSecondary)),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Wrap(spacing: AdminSpace.sm, children: actions),
        ],
      ),
    );
  }
}

/// Small semantic badge (status, severity, counts).
class AdminStatusBadge extends StatelessWidget {
  final String label;
  final Color foreground;
  final Color background;
  final IconData? icon;
  final bool dot;

  const AdminStatusBadge({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    this.icon,
    this.dot = false,
  });

  /// Builds a badge from a server status string (healthy / warning / ...).
  factory AdminStatusBadge.status(String status, AdminPalette palette,
      {String? label}) {
    final style = AdminStatusStyle.of(status, palette);
    return AdminStatusBadge(
      label: label ?? style.label,
      foreground: style.foreground,
      background: style.background,
      dot: true,
    );
  }

  factory AdminStatusBadge.severity(String severity, AdminPalette palette) {
    final style = AdminSeverityStyle.of(severity, palette);
    return AdminStatusBadge(
      label: severity[0].toUpperCase() + severity.substring(1),
      foreground: style.foreground,
      background: style.background,
      icon: style.icon,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AdminSpace.sm, vertical: AdminSpace.xs),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AdminRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 6),
              decoration:
                  BoxDecoration(color: foreground, shape: BoxShape.circle),
            ),
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AdminText.label.copyWith(
                  color: foreground, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Metrics
// ---------------------------------------------------------------------------

class AdminMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final String? contextLabel;
  final IconData icon;
  final String? trend;
  final double? trendDelta;
  final List<double> sparkline;
  final Color? accent;

  const AdminMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.unit,
    this.contextLabel,
    this.trend,
    this.trendDelta,
    this.sparkline = const [],
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    final accentColor = accent ?? palette.primary;

    Widget? trendWidget;
    if (trend != null && trend != 'flat' && trendDelta != null) {
      final rising = trend == 'up';
      final colour = rising ? palette.success : palette.danger;
      trendWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(rising ? Icons.trending_up : Icons.trending_down,
              size: 14, color: colour),
          const SizedBox(width: 3),
          Text('${trendDelta!.abs().toStringAsFixed(1)}%',
              style: AdminText.label.copyWith(color: colour)),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(AdminSpace.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AdminRadius.lg),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AdminRadius.sm),
                ),
                child: Icon(icon, size: 16, color: accentColor),
              ),
              const SizedBox(width: AdminSpace.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AdminText.metricLabel
                      .copyWith(color: palette.textSecondary),
                ),
              ),
              if (trendWidget != null) trendWidget,
            ],
          ),
          const SizedBox(height: AdminSpace.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AdminText.metricValue
                      .copyWith(color: palette.textPrimary),
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(unit!,
                    style: AdminText.caption
                        .copyWith(color: palette.textTertiary)),
              ],
            ],
          ),
          if (contextLabel != null) ...[
            const SizedBox(height: AdminSpace.xs),
            Text(contextLabel!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AdminText.caption.copyWith(color: palette.textSecondary)),
          ],
          if (sparkline.isNotEmpty) ...[
            const SizedBox(height: AdminSpace.md),
            SizedBox(
              height: 28,
              child: AdminSparkline(values: sparkline, color: accentColor),
            ),
          ],
        ],
      ),
    );
  }
}

/// Health row for one subsystem: value, threshold meter, status and trend.
class AdminHealthIndicator extends StatelessWidget {
  final String label;
  final String status;
  final double? value;
  final String unit;
  final double? threshold;
  final String? trend;
  final String? detail;
  final String? updatedAt;
  final bool dense;

  const AdminHealthIndicator({
    super.key,
    required this.label,
    required this.status,
    this.value,
    this.unit = '',
    this.threshold,
    this.trend,
    this.detail,
    this.updatedAt,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    final style = AdminStatusStyle.of(status, palette);

    final isPercent = unit == '%';
    final ratio = value == null
        ? null
        : isPercent
            ? (value! / 100).clamp(0.0, 1.0)
            : null;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? AdminSpace.sm : AdminSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: style.foreground, shape: BoxShape.circle),
              ),
              const SizedBox(width: AdminSpace.sm),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AdminText.bodyStrong
                        .copyWith(color: palette.textPrimary)),
              ),
              if (value != null)
                Text(
                  '${adminFormatNumber(value)}${unit == '%' ? '%' : (unit.isNotEmpty ? ' $unit' : '')}',
                  style: AdminText.mono.copyWith(color: palette.textPrimary),
                ),
              const SizedBox(width: AdminSpace.sm),
              AdminStatusBadge.status(status, palette),
            ],
          ),
          if (isPercent && ratio != null) ...[
            const SizedBox(height: AdminSpace.sm),
            _ThresholdMeter(
              ratio: ratio,
              threshold: threshold == null ? null : threshold! / 100,
              colour: style.foreground,
            ),
          ],
          if (detail != null) ...[
            const SizedBox(height: AdminSpace.xs),
            Row(
              children: [
                Expanded(
                  child: Text(detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AdminText.caption
                          .copyWith(color: palette.textSecondary)),
                ),
                if (trend != null && trend != 'flat') ...[
                  const SizedBox(width: AdminSpace.sm),
                  Icon(
                    trend == 'up' ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 12,
                    color: palette.textTertiary,
                  ),
                ],
                if (updatedAt != null) ...[
                  const SizedBox(width: AdminSpace.sm),
                  Text(adminRelativeTime(updatedAt),
                      style: AdminText.caption
                          .copyWith(color: palette.textTertiary)),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ThresholdMeter extends StatelessWidget {
  final double ratio;
  final double? threshold;
  final Color colour;

  const _ThresholdMeter(
      {required this.ratio, this.threshold, required this.colour});

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: 6,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: palette.surfaceMuted,
                  borderRadius: BorderRadius.circular(AdminRadius.pill),
                ),
              ),
              FractionallySizedBox(
                widthFactor: ratio.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: colour,
                    borderRadius: BorderRadius.circular(AdminRadius.pill),
                  ),
                ),
              ),
              if (threshold != null)
                Positioned(
                  left: (constraints.maxWidth * threshold!).clamp(0.0, constraints.maxWidth - 2),
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: palette.textTertiary),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline / activity
// ---------------------------------------------------------------------------

class AdminTimelineEntry {
  final String title;
  final String? detail;
  final String? timestamp;
  final String severity;
  final IconData? icon;
  final VoidCallback? onTap;

  const AdminTimelineEntry({
    required this.title,
    this.detail,
    this.timestamp,
    this.severity = 'info',
    this.icon,
    this.onTap,
  });
}

class AdminActivityTimeline extends StatelessWidget {
  final List<AdminTimelineEntry> entries;
  final String emptyMessage;
  final int maxEntries;

  const AdminActivityTimeline({
    super.key,
    required this.entries,
    this.emptyMessage = 'No recent activity',
    this.maxEntries = 12,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    if (entries.isEmpty) {
      return AdminEmptyState(
        icon: Icons.history_toggle_off_outlined,
        title: 'Nothing yet',
        message: emptyMessage,
        dense: true,
      );
    }
    final visible = entries.take(maxEntries).toList();
    return Column(
      children: [
        for (var i = 0; i < visible.length; i++)
          _TimelineRow(
            entry: visible[i],
            isLast: i == visible.length - 1,
            palette: palette,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final AdminTimelineEntry entry;
  final bool isLast;
  final AdminPalette palette;

  const _TimelineRow(
      {required this.entry, required this.isLast, required this.palette});

  @override
  Widget build(BuildContext context) {
    final style = AdminSeverityStyle.of(entry.severity, palette);
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: style.background,
                shape: BoxShape.circle,
                border: Border.all(color: style.foreground.withValues(alpha: 0.35)),
              ),
              child: Icon(entry.icon ?? style.icon, size: 12, color: style.foreground),
            ),
            if (!isLast)
              Container(
                width: 1.5,
                height: 26,
                color: palette.border,
              ),
          ],
        ),
        const SizedBox(width: AdminSpace.md),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : AdminSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AdminText.bodyStrong
                              .copyWith(color: palette.textPrimary)),
                    ),
                    if (entry.timestamp != null) ...[
                      const SizedBox(width: AdminSpace.sm),
                      Text(adminRelativeTime(entry.timestamp),
                          style: AdminText.caption
                              .copyWith(color: palette.textTertiary)),
                    ],
                  ],
                ),
                if (entry.detail != null && entry.detail!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(entry.detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AdminText.caption
                          .copyWith(color: palette.textSecondary)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
    if (entry.onTap == null) return content;
    return InkWell(
      onTap: entry.onTap,
      borderRadius: BorderRadius.circular(AdminRadius.sm),
      child: content,
    );
  }
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

class AdminEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool dense;

  const AdminEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
            vertical: dense ? AdminSpace.lg : AdminSpace.xxxl,
            horizontal: AdminSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: dense ? 36 : 44,
              height: dense ? 36 : 44,
              decoration: BoxDecoration(
                color: palette.surfaceMuted,
                borderRadius: BorderRadius.circular(AdminRadius.md),
              ),
              child: Icon(icon,
                  size: dense ? 18 : 22, color: palette.textTertiary),
            ),
            const SizedBox(height: AdminSpace.md),
            Text(title,
                textAlign: TextAlign.center,
                style: AdminText.bodyStrong.copyWith(color: palette.textPrimary)),
            const SizedBox(height: AdminSpace.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(message,
                  textAlign: TextAlign.center,
                  style: AdminText.caption.copyWith(color: palette.textSecondary)),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AdminSpace.md),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class AdminErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool dense;

  const AdminErrorState(
      {super.key, required this.message, this.onRetry, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AdminSpace.lg),
      decoration: BoxDecoration(
        color: palette.dangerSoft,
        borderRadius: BorderRadius.circular(AdminRadius.md),
        border: Border.all(color: palette.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: palette.danger),
          const SizedBox(width: AdminSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Something went wrong',
                    style: AdminText.bodyStrong.copyWith(color: palette.danger)),
                const SizedBox(height: AdminSpace.xxs),
                Text(message,
                    style: AdminText.caption.copyWith(color: palette.textSecondary)),
              ],
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: palette.danger),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

/// Skeleton block used while a panel's data is in flight. The pulse is subtle
/// and disabled when the platform requests reduced motion.
class AdminLoadingSkeleton extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;

  const AdminLoadingSkeleton({
    super.key,
    this.height = 16,
    this.width,
    this.radius = AdminRadius.sm,
  });

  @override
  State<AdminLoadingSkeleton> createState() => _AdminLoadingSkeletonState();
}

class _AdminLoadingSkeletonState extends State<AdminLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final base = palette.surfaceMuted;
    final highlight = Color.alphaBlend(palette.hover, palette.surfaceMuted);

    final block = Container(
      height: widget.height,
      width: widget.width,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    );
    if (reduceMotion) return block;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Color.lerp(base, highlight, _controller.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Skeleton for a metric card, matching the real card's proportions so the
/// layout does not jump when data arrives.
class AdminMetricSkeleton extends StatelessWidget {
  const AdminMetricSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AdminSpace.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AdminRadius.lg),
        border: Border.all(color: palette.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              AdminLoadingSkeleton(height: 30, width: 30, radius: AdminRadius.sm),
              SizedBox(width: AdminSpace.sm),
              Expanded(child: AdminLoadingSkeleton(height: 12)),
            ],
          ),
          SizedBox(height: AdminSpace.md),
          AdminLoadingSkeleton(height: 24, width: 110),
          SizedBox(height: AdminSpace.sm),
          AdminLoadingSkeleton(height: 12, width: 150),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation / chrome
// ---------------------------------------------------------------------------

class AdminNavigationItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;
  final int badge;
  final bool ownerOnly;

  const AdminNavigationItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.collapsed = false,
    this.badge = 0,
    this.ownerOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    final foreground = selected ? palette.primary : palette.textSecondary;

    final row = Container(
      height: 38,
      margin: const EdgeInsets.symmetric(
          horizontal: AdminSpace.sm, vertical: 1),
      padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 0 : AdminSpace.md),
      decoration: BoxDecoration(
        color: selected ? palette.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(AdminRadius.sm),
        border: Border.all(
          color: selected ? palette.primary.withValues(alpha: 0.35) : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisAlignment:
            collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foreground),
          if (!collapsed) ...[
            const SizedBox(width: AdminSpace.md),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AdminText.body.copyWith(
                  color: selected ? palette.textPrimary : palette.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: palette.danger,
                  borderRadius: BorderRadius.circular(AdminRadius.pill),
                ),
                child: Text('$badge',
                    style: AdminText.label
                        .copyWith(color: palette.onPrimary, fontSize: 10)),
              ),
            if (ownerOnly && badge == 0)
              Icon(Icons.lock_outline, size: 12, color: palette.textTertiary),
          ],
        ],
      ),
    );

    return Tooltip(
      message: collapsed ? label : '',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AdminRadius.sm),
        hoverColor: palette.hover,
        child: row,
      ),
    );
  }
}

class AdminSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;
  final double width;
  final VoidCallback? onSubmitted;

  const AdminSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = 'Search users, devices…',
    this.width = 320,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    return SizedBox(
      width: width,
      height: 36,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: (_) => onSubmitted?.call(),
        textInputAction: TextInputAction.search,
        style: AdminText.body.copyWith(color: palette.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          prefixIconConstraints:
              const BoxConstraints(minWidth: 34, minHeight: 34),
          prefixIcon:
              const Icon(Icons.search, size: 17, color: null),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 15),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 0, horizontal: AdminSpace.md),
        ),
      ),
    );
  }
}

/// Segmented control used for the analytics time range.
class AdminSegmentedControl<T> extends StatelessWidget {
  final List<AdminSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  const AdminSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(AdminRadius.sm),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final segment in segments)
            InkWell(
              onTap: () => onChanged(segment.value),
              borderRadius: BorderRadius.circular(AdminRadius.xs),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AdminSpace.md, vertical: 5),
                decoration: BoxDecoration(
                  color: segment.value == value
                      ? palette.surface
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AdminRadius.xs),
                  border: Border.all(
                    color: segment.value == value
                        ? palette.borderStrong
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  segment.label,
                  style: AdminText.caption.copyWith(
                    color: segment.value == value
                        ? palette.textPrimary
                        : palette.textSecondary,
                    fontWeight: segment.value == value
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AdminSegment<T> {
  final T value;
  final String label;
  const AdminSegment(this.value, this.label);
}

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

class AdminTableColumn {
  final String label;
  final double? width;
  final bool numeric;
  const AdminTableColumn(this.label, {this.width, this.numeric = false});
}

class AdminTableRow {
  final List<Widget> cells;
  final VoidCallback? onTap;
  final bool highlight;
  const AdminTableRow(this.cells, {this.onTap, this.highlight = false});
}

/// Compact data table with a sticky-looking header. Rows are plain widgets so
/// callers compose badges and actions without losing alignment.
class AdminDataTable extends StatelessWidget {
  final List<AdminTableColumn> columns;
  final List<AdminTableRow> rows;
  final String emptyMessage;

  const AdminDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.emptyMessage = 'No records',
  });

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    if (rows.isEmpty) {
      return AdminEmptyState(
        icon: Icons.inbox_outlined,
        title: 'No records',
        message: emptyMessage,
        dense: true,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Rows carry horizontal padding, so the column budget is the incoming
        // width minus that padding; otherwise the cells overflow the row.
        const horizontalPadding = AdminSpace.md * 2;
        final available = constraints.maxWidth.isFinite
            ? math.max(0.0, constraints.maxWidth - horizontalPadding)
            : columns.fold<double>(0, (sum, c) => sum + (c.width ?? 160));
        final fixed = columns.where((c) => c.width != null);
        final flexCount = columns.length - fixed.length;
        final fixedWidth = fixed.fold<double>(0, (sum, c) => sum + c.width!);
        final flexWidth = flexCount == 0
            ? 0.0
            : ((available - fixedWidth) / flexCount).clamp(90.0, 400.0);

        double widthFor(AdminTableColumn column) => column.width ?? flexWidth;

        final contentWidth = columns.fold<double>(0, (sum, c) => sum + widthFor(c));
        // The outer width has to leave room for the row padding, otherwise the
        // cells overflow their row; wider tables scroll horizontally instead.
        final tableWidth = constraints.maxWidth.isFinite
            ? math.max(constraints.maxWidth, contentWidth + horizontalPadding)
            : contentWidth + horizontalPadding;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth > 0 ? tableWidth : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: palette.surfaceMuted,
                    borderRadius: BorderRadius.circular(AdminRadius.sm),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AdminSpace.md, vertical: AdminSpace.sm),
                  child: Row(
                    children: [
                      for (final column in columns)
                        SizedBox(
                          width: widthFor(column),
                          child: Text(
                            column.label.toUpperCase(),
                            textAlign: column.numeric
                                ? TextAlign.right
                                : TextAlign.left,
                            style: AdminText.tableHeader.copyWith(
                                color: palette.textTertiary,
                                letterSpacing: 0.5),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AdminSpace.xs),
                for (final row in rows)
                  InkWell(
                    onTap: row.onTap,
                    borderRadius: BorderRadius.circular(AdminRadius.sm),
                    hoverColor: palette.hover,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AdminSpace.md, vertical: AdminSpace.sm),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AdminRadius.sm),
                        border: Border(
                            bottom: BorderSide(color: palette.border, width: 0.6)),
                      ),
                      child: Row(
                        children: [
                          for (var i = 0; i < columns.length; i++)
                            SizedBox(
                              width: widthFor(columns[i]),
                              child: Align(
                                alignment: columns[i].numeric
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: i < row.cells.length
                                    ? row.cells[i]
                                    : const SizedBox.shrink(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Dialogs / notifications
// ---------------------------------------------------------------------------

/// Destructive-action confirmation used by admin controls.
Future<bool> showAdminConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final palette = AdminPalette.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title, style: AdminText.sectionTitle.copyWith(color: palette.textPrimary)),
      content: SizedBox(
        width: 380,
        child: Text(message,
            style: AdminText.body.copyWith(color: palette.textSecondary)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: palette.danger,
                  foregroundColor: palette.onPrimary,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

class AdminNotificationItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? detail;
  final String? timestamp;
  final String severity;
  final bool unread;
  final VoidCallback? onTap;

  const AdminNotificationItem({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.timestamp,
    this.severity = 'info',
    this.unread = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    final style = AdminSeverityStyle.of(severity, palette);
    return InkWell(
      onTap: onTap,
      hoverColor: palette.hover,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AdminSpace.lg, vertical: AdminSpace.md),
        decoration: BoxDecoration(
          color: unread ? palette.selected : Colors.transparent,
          border: Border(bottom: BorderSide(color: palette.border, width: 0.6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: style.background,
                borderRadius: BorderRadius.circular(AdminRadius.sm),
              ),
              child: Icon(icon, size: 15, color: style.foreground),
            ),
            const SizedBox(width: AdminSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AdminText.body
                          .copyWith(color: palette.textPrimary)),
                  if (detail != null)
                    Text(detail!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AdminText.caption
                            .copyWith(color: palette.textSecondary)),
                  if (timestamp != null) ...[
                    const SizedBox(height: 2),
                    Text(adminRelativeTime(timestamp),
                        style: AdminText.caption
                            .copyWith(color: palette.textTertiary)),
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

/// Small inline chart used inside metric cards.
class AdminSparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double strokeWidth;

  const AdminSparkline({
    super.key,
    required this.values,
    required this.color,
    this.strokeWidth = 1.6,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    return CustomPaint(
      painter: _SparklinePainter(
        values: values,
        color: color,
        grid: palette.chartGrid,
        strokeWidth: strokeWidth,
      ),
      size: Size.infinite,
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final Color grid;
  final double strokeWidth;

  _SparklinePainter({
    required this.values,
    required this.color,
    required this.grid,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final range = (maxValue - minValue) == 0 ? 1.0 : (maxValue - minValue);

    final path = Path();
    final fill = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - ((values[i] - minValue) / range) * (size.height - 4) - 2;
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width, size.height);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

/// One selectable value inside an [AdminFilterBar] dropdown.
class AdminFilterOption {
  final String value;
  final String label;
  const AdminFilterOption(this.value, this.label);
}

/// Search + dropdown filter strip used above tables and lists.
///
/// Filters are declared by the screen so each module keeps ownership of its
/// own query semantics; this widget only renders state and reports changes.
class AdminFilterBar extends StatelessWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onSearchChanged;
  final String searchHint;
  final List<AdminFilterOption> options;
  final String? selectedValue;
  final ValueChanged<String?>? onSelected;
  final String? filterLabel;
  final List<String> activeFilters;
  final VoidCallback? onClearFilters;
  final List<Widget> trailing;

  const AdminFilterBar({
    super.key,
    this.controller,
    this.onSearchChanged,
    this.searchHint = 'Search…',
    this.options = const [],
    this.selectedValue,
    this.onSelected,
    this.filterLabel,
    this.activeFilters = const [],
    this.onClearFilters,
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    return Wrap(
      spacing: AdminSpace.md,
      runSpacing: AdminSpace.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (controller != null)
          AdminSearchBar(
            controller: controller!,
            onChanged: onSearchChanged ?? (_) {},
            hint: searchHint,
            width: 280,
          ),
        if (options.isNotEmpty)
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: AdminSpace.md),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(AdminRadius.md),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (filterLabel != null) ...[
                  Text(filterLabel!,
                      style: AdminText.caption
                          .copyWith(color: palette.textTertiary)),
                  const SizedBox(width: AdminSpace.sm),
                ],
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedValue,
                    isDense: true,
                    hint: Text('All',
                        style: AdminText.body
                            .copyWith(color: palette.textSecondary)),
                    dropdownColor: palette.surfaceRaised,
                    style: AdminText.body.copyWith(color: palette.textPrimary),
                    icon: Icon(Icons.expand_more,
                        size: 18, color: palette.textSecondary),
                    items: [
                      for (final option in options)
                        DropdownMenuItem(
                            value: option.value, child: Text(option.label)),
                    ],
                    onChanged: onSelected,
                  ),
                ),
              ],
            ),
          ),
        for (final filter in activeFilters)
          AdminStatusBadge(
            label: filter,
            foreground: palette.primary,
            background: palette.primarySoft,
            icon: Icons.filter_alt_outlined,
          ),
        if (activeFilters.isNotEmpty && onClearFilters != null)
          TextButton(
            onPressed: onClearFilters,
            child: const Text('Clear'),
          ),
        ...trailing,
      ],
    );
  }
}
