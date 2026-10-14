import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/admin_theme.dart';
import 'admin_components.dart';

/// One point on an admin chart.
@immutable
class AdminSeriesPoint {
  final String label;
  final double value;
  const AdminSeriesPoint(this.label, this.value);

  /// Builds points from the server's `{t, v}` series shape.
  static List<AdminSeriesPoint> fromServer(
    List<dynamic>? raw, {
    required bool longRange,
  }) {
    if (raw == null) return const [];
    final points = <AdminSeriesPoint>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final label = entry['t']?.toString() ?? '';
      final value = (entry['v'] as num?)?.toDouble() ?? 0;
      points.add(AdminSeriesPoint(
        label.isEmpty ? '' : adminBucketLabel(label, longRange: longRange),
        value,
      ));
    }
    return points;
  }
}

/// Line/area chart with a value axis, gridlines and adaptive x labels.
/// Drawn with CustomPaint so the admin surface adds no charting dependency.
class AdminLineChart extends StatefulWidget {
  final List<AdminSeriesPoint> points;
  final Color color;
  final double height;
  final bool showArea;
  final bool showGrid;
  final String? unit;
  final int xLabelCount;
  final bool longRange;

  const AdminLineChart({
    super.key,
    required this.points,
    required this.color,
    this.height = 220,
    this.showArea = true,
    this.showGrid = true,
    this.unit,
    this.xLabelCount = 6,
    this.longRange = false,
  });

  @override
  State<AdminLineChart> createState() => _AdminLineChartState();
}

class _AdminLineChartState extends State<AdminLineChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void initState() {
    super.initState();
    final reduceMotion = WidgetsBinding
            .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (reduceMotion) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant AdminLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Replay the draw-in when the series changes (for example after the range
    // selector switches) so the transition reads as a data change.
    if (oldWidget.points.length != widget.points.length) {
      final reduceMotion = WidgetsBinding
          .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
      _controller.value = reduceMotion ? 1 : 0;
      if (!reduceMotion) _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    if (widget.points.length < 2) {
      return SizedBox(
        height: widget.height,
        child: const AdminEmptyState(
          icon: Icons.show_chart,
          title: 'No data for this period',
          message:
              'The server returned no activity buckets for the selected range.',
          dense: true,
        ),
      );
    }
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _LineChartPainter(
            points: widget.points,
            color: widget.color,
            grid: palette.chartGrid,
            axisText: palette.textTertiary,
            textDirection: Directionality.of(context),
            progress: _controller.value,
            showArea: widget.showArea,
            showGrid: widget.showGrid,
            unit: widget.unit,
            xLabelCount: widget.xLabelCount,
          ),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<AdminSeriesPoint> points;
  final Color color;
  final Color grid;
  final Color axisText;
  final TextDirection textDirection;
  final double progress;
  final bool showArea;
  final bool showGrid;
  final String? unit;
  final int xLabelCount;

  static const _leftGutter = 46.0;
  static const _bottomGutter = 22.0;
  static const _topPadding = 10.0;

  _LineChartPainter({
    required this.points,
    required this.color,
    required this.grid,
    required this.axisText,
    required this.textDirection,
    required this.progress,
    required this.showArea,
    required this.showGrid,
    required this.unit,
    required this.xLabelCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = size.width - _leftGutter;
    final plotHeight = size.height - _bottomGutter - _topPadding;
    if (plotWidth <= 10 || plotHeight <= 10) return;

    final maxValue = points.fold<double>(0, (m, p) => math.max(m, p.value));
    final scaleMax = maxValue <= 0 ? 1.0 : maxValue * 1.15;

    // gridlines + y axis labels
    const lines = 4;
    if (showGrid) {
      final gridPaint = Paint()
        ..color = grid
        ..strokeWidth = 1;
      for (var i = 0; i <= lines; i++) {
        final y = _topPadding + plotHeight * i / lines;
        canvas.drawLine(Offset(_leftGutter, y), Offset(size.width, y), gridPaint);
      }
    }
    for (var i = 0; i <= lines; i++) {
      final value = scaleMax * (lines - i) / lines;
      final y = _topPadding + plotHeight * i / lines;
      _text(
        canvas,
        unit == '%'
            ? '${value.toStringAsFixed(0)}%'
            : adminFormatNumber(value),
        Offset(0, y - 6),
        axisText,
        maxWidth: _leftGutter - 6,
        align: TextAlign.right,
      );
    }

    // x labels
    final labelStride = math.max(1, (points.length / xLabelCount).ceil());
    for (var i = 0; i < points.length; i += labelStride) {
      final x = _leftGutter + plotWidth * i / (points.length - 1);
      _text(canvas, points[i].label, Offset(x, size.height - _bottomGutter + 6),
          axisText, align: TextAlign.center, centerOnX: true);
    }

    // build path
    final line = Path();
    final area = Path();
    final visible = (points.length - 1) * progress.clamp(0.0, 1.0);
    final lastIndex = visible.floor().clamp(0, points.length - 1);
    final fraction = visible - lastIndex;

    Offset pointAt(int index) {
      final x = _leftGutter + plotWidth * index / (points.length - 1);
      final y = _topPadding +
          plotHeight -
          (points[index].value / scaleMax) * plotHeight;
      return Offset(x, y);
    }

    for (var i = 0; i <= lastIndex; i++) {
      final offset = pointAt(i);
      if (i == 0) {
        line.moveTo(offset.dx, offset.dy);
        area.moveTo(offset.dx, _topPadding + plotHeight);
        area.lineTo(offset.dx, offset.dy);
      } else {
        line.lineTo(offset.dx, offset.dy);
        area.lineTo(offset.dx, offset.dy);
      }
    }
    if (fraction > 0 && lastIndex < points.length - 1) {
      final from = pointAt(lastIndex);
      final to = pointAt(lastIndex + 1);
      final interpolated = Offset(
        from.dx + (to.dx - from.dx) * fraction,
        from.dy + (to.dy - from.dy) * fraction,
      );
      line.lineTo(interpolated.dx, interpolated.dy);
      area.lineTo(interpolated.dx, interpolated.dy);
    }

    if (showArea) {
      final endX = pointAt(lastIndex).dx +
          (fraction > 0 && lastIndex < points.length - 1
              ? (pointAt(lastIndex + 1).dx - pointAt(lastIndex).dx) * fraction
              : 0);
      area.lineTo(endX, _topPadding + plotHeight);
      area.close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.24),
              color.withValues(alpha: 0.02),
            ],
          ).createShader(Rect.fromLTWH(0, _topPadding, size.width, plotHeight)),
      );
    }

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // highlight the newest point
    if (progress >= 1 && points.isNotEmpty) {
      final last = pointAt(points.length - 1);
      canvas.drawCircle(last, 3.5, Paint()..color = color);
      canvas.drawCircle(
        last,
        3.5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _text(Canvas canvas, String value, Offset offset, Color color,
      {double? maxWidth,
      TextAlign align = TextAlign.left,
      bool centerOnX = false}) {
    if (value.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
          text: value, style: TextStyle(color: color, fontSize: 10.5, height: 1.1)),
      textDirection: textDirection,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? 90);
    painter.paint(
      canvas,
      centerOnX ? Offset(offset.dx - painter.width / 2, offset.dy) : offset,
    );
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.progress != progress ||
      oldDelegate.color != color;
}

/// Vertical bar chart for categorical counts (device mix, per-day volumes).
class AdminBarChart extends StatelessWidget {
  final List<AdminSeriesPoint> points;
  final Color color;
  final double height;
  final String? unit;
  final int xLabelCount;

  const AdminBarChart({
    super.key,
    required this.points,
    required this.color,
    this.height = 200,
    this.unit,
    this.xLabelCount = 6,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: const AdminEmptyState(
          icon: Icons.bar_chart,
          title: 'No data',
          message: 'Nothing recorded for this period.',
          dense: true,
        ),
      );
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _BarChartPainter(
          points: points,
          color: color,
          grid: palette.chartGrid,
          axisText: palette.textTertiary,
          textDirection: Directionality.of(context),
          xLabelCount: xLabelCount,
        ),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<AdminSeriesPoint> points;
  final Color color;
  final Color grid;
  final Color axisText;
  final TextDirection textDirection;
  final int xLabelCount;

  static const _leftGutter = 46.0;
  static const _bottomGutter = 22.0;
  static const _topPadding = 10.0;

  _BarChartPainter({
    required this.points,
    required this.color,
    required this.grid,
    required this.axisText,
    required this.textDirection,
    required this.xLabelCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = size.width - _leftGutter;
    final plotHeight = size.height - _bottomGutter - _topPadding;
    if (plotWidth <= 10 || plotHeight <= 10) return;

    final maxValue = points.fold<double>(0, (m, p) => math.max(m, p.value));
    final scaleMax = maxValue <= 0 ? 1.0 : maxValue * 1.15;

    const lines = 4;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= lines; i++) {
      final y = _topPadding + plotHeight * i / lines;
      canvas.drawLine(Offset(_leftGutter, y), Offset(size.width, y), gridPaint);
      final value = scaleMax * (lines - i) / lines;
      final painter = TextPainter(
        text: TextSpan(
            text: adminFormatNumber(value),
            style: TextStyle(color: axisText, fontSize: 10.5, height: 1.1)),
        textDirection: textDirection,
      )..layout(maxWidth: _leftGutter - 6);
      painter.paint(canvas, Offset(_leftGutter - 6 - painter.width, y - 6));
    }

    final slot = plotWidth / points.length;
    final barWidth = math.max(2.0, math.min(28.0, slot * 0.62));

    for (var i = 0; i < points.length; i++) {
      final heightRatio = points[i].value / scaleMax;
      final barHeight = plotHeight * heightRatio;
      final left = _leftGutter + slot * i + (slot - barWidth) / 2;
      final top = _topPadding + plotHeight - barHeight;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, top, barWidth, math.max(barHeight, 1)),
        topLeft: const Radius.circular(2.5),
        topRight: const Radius.circular(2.5),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = points[i].value == 0
              ? grid
              : color.withValues(alpha: 0.85),
      );
    }

    final stride = math.max(1, (points.length / xLabelCount).ceil());
    for (var i = 0; i < points.length; i += stride) {
      final painter = TextPainter(
        text: TextSpan(
            text: points[i].label,
            style: TextStyle(color: axisText, fontSize: 10.5, height: 1.1)),
        textDirection: textDirection,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: slot * stride);
      painter.paint(
        canvas,
        Offset(
          _leftGutter + slot * i + (slot - painter.width) / 2,
          size.height - _bottomGutter + 6,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

/// Radial gauge for a single percentage reading (CPU, memory, storage).
class AdminGauge extends StatelessWidget {
  final double value;
  final double? threshold;
  final String label;
  final String? sublabel;
  final Color color;
  final double size;

  const AdminGauge({
    super.key,
    required this.value,
    required this.label,
    required this.color,
    this.threshold,
    this.sublabel,
    this.size = 132,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(
          value: value,
          threshold: threshold,
          color: color,
          track: palette.surfaceMuted,
          marker: palette.textTertiary,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${value.toStringAsFixed(0)}%',
                  style: AdminText.metricValue
                      .copyWith(color: palette.textPrimary, fontSize: 22)),
              Text(label,
                  style: AdminText.caption
                      .copyWith(color: palette.textSecondary)),
              if (sublabel != null)
                Text(sublabel!,
                    style: AdminText.caption
                        .copyWith(color: palette.textTertiary, fontSize: 10.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final double? threshold;
  final Color color;
  final Color track;
  final Color marker;

  _GaugePainter({
    required this.value,
    required this.threshold,
    required this.color,
    required this.track,
    required this.marker,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    const startAngle = math.pi * 0.75;
    const sweep = math.pi * 1.5;

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        startAngle,
        sweep,
        false,
        trackPaint);

    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      startAngle,
      sweep * (value.clamp(0, 100) / 100),
      false,
      valuePaint,
    );

    if (threshold != null && threshold! > 0 && threshold! < 100) {
      final angle = startAngle + sweep * (threshold! / 100);
      final inner = radius - 8;
      final outer = radius + 8;
      final vector = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        centre + vector * inner,
        centre + vector * outer,
        Paint()
          ..color = marker
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.color != color ||
      oldDelegate.threshold != threshold;
}

/// Donut used for small categorical mixes (LAN / mesh / offline devices).
class AdminDonutSegment {
  final String label;
  final double value;
  final Color color;
  const AdminDonutSegment(this.label, this.value, this.color);
}

class AdminDonutChart extends StatelessWidget {
  final List<AdminDonutSegment> segments;
  final double size;
  final String? centerLabel;
  final String? centerValue;

  const AdminDonutChart({
    super.key,
    required this.segments,
    this.size = 148,
    this.centerLabel,
    this.centerValue,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    final total = segments.fold<double>(0, (sum, s) => sum + s.value);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(
          segments: segments,
          total: total,
          track: palette.surfaceMuted,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(centerValue ?? adminFormatNumber(total),
                  style: AdminText.metricValue
                      .copyWith(color: palette.textPrimary, fontSize: 22)),
              if (centerLabel != null)
                Text(centerLabel!,
                    style: AdminText.caption
                        .copyWith(color: palette.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<AdminDonutSegment> segments;
  final double total;
  final Color track;

  _DonutPainter(
      {required this.segments, required this.total, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12,
    );

    if (total <= 0) return;
    var start = -math.pi / 2;
    for (final segment in segments) {
      if (segment.value <= 0) continue;
      final sweep = math.pi * 2 * (segment.value / total);
      canvas.drawArc(
        rect,
        start,
        sweep - 0.02,
        false,
        Paint()
          ..color = segment.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.butt,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.segments != segments || oldDelegate.total != total;
}

/// Chart panel: header, actions, and the loading / empty / error states a
/// production dashboard needs around every visualisation.
class AdminChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final bool isEmpty;
  final String emptyMessage;

  const AdminChartCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.loading = false,
    this.error,
    this.onRetry,
    this.isEmpty = false,
    this.emptyMessage = 'No data for this period',
  });

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (loading) {
      body = const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminLoadingSkeleton(height: 160, radius: AdminRadius.md),
          SizedBox(height: AdminSpace.md),
          AdminLoadingSkeleton(height: 12, width: 220),
        ],
      );
    } else if (error != null) {
      body = AdminErrorState(message: error!, onRetry: onRetry);
    } else if (isEmpty) {
      body = AdminEmptyState(
        icon: Icons.query_stats_outlined,
        title: 'No activity recorded',
        message: emptyMessage,
      );
    } else {
      body = child;
    }

    return AdminPanel(
      title: title,
      subtitle: subtitle,
      actions: actions,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(key: ValueKey(body.runtimeType), child: body),
      ),
    );
  }
}

/// Legend row used beside donuts and multi-series charts.
class AdminChartLegend extends StatelessWidget {
  final List<AdminDonutSegment> items;
  final String Function(double value) formatValue;

  const AdminChartLegend({
    super.key,
    required this.items,
    this.formatValue = adminFormatNumber,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AdminSpace.xs),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: item.color,
                      borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: AdminSpace.sm),
                Expanded(
                  child: Text(item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AdminText.caption
                          .copyWith(color: palette.textSecondary)),
                ),
                Text(formatValue(item.value),
                    style: AdminText.mono.copyWith(color: palette.textPrimary)),
              ],
            ),
          ),
      ],
    );
  }
}
