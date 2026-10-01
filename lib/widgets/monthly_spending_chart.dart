import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/collection_options.dart';

class MonthlySpendingChart extends StatefulWidget {
  const MonthlySpendingChart({super.key, required this.values, this.year});
  final Map<String, double> values;
  final int? year;

  @override
  State<MonthlySpendingChart> createState() => _MonthlySpendingChartState();
}

class _MonthlySpendingChartState extends State<MonthlySpendingChart> {
  final _scroll = ScrollController();
  bool _showLatest = true;

  @override
  void didUpdateWidget(covariant MonthlySpendingChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year ||
        !mapEquals(oldWidget.values, widget.values)) {
      _showLatest = true;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.values.isEmpty) return const Text('暂无数据');
    final keys = widget.values.keys.toList()..sort();
    final first = DateTime.parse('${keys.first}-01');
    final last = DateTime.parse('${keys.last}-01');
    // Show complete years, including months with no purchases. No data is truncated.
    final start = DateTime(widget.year ?? first.year);
    final end = DateTime(widget.year ?? last.year, 12);
    final months = <String>[];
    for (
      var date = start;
      !date.isAfter(end);
      date = DateTime(date.year, date.month + 1)
    ) {
      months.add('${date.year}-${date.month.toString().padLeft(2, '0')}');
    }
    final amounts = months.map((m) => widget.values[m] ?? 0.0).toList();
    final highest = amounts.reduce(math.max);
    final magnitude = highest <= 0
        ? 1.0
        : math.pow(10, (math.log(highest) / math.ln10).floor()).toDouble();
    final ceiling = highest <= 0
        ? 1.0
        : (highest / magnitude).ceil() * magnitude;
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final plotHeight = 170.0;
    final headerHeight = 28 * scale;
    final labelHeight = 42 * scale;
    final columnWidth = 88.0 * math.max(1, scale);
    if (_showLatest) {
      _showLatest = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          // Start at the newest purchase, rather than future empty months.
          final latestIndex = months.indexOf(keys.last);
          _scroll.jumpTo(
            (latestIndex * columnWidth -
                    _scroll.position.viewportDimension +
                    columnWidth)
                .clamp(0.0, _scroll.position.maxScrollExtent),
          );
        }
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '金额 / CNY',
          style: TextStyle(fontSize: 12, color: AppTheme.muted),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              height: headerHeight + plotHeight,
              child: Padding(
                padding: EdgeInsets.only(top: headerHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 4; i >= 0; i--)
                      SizedBox(
                        height: 15,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _axisLabel(ceiling * i / 4),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.muted,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('monthly-chart-scroll'),
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: months.length * columnWidth,
                  height: headerHeight + plotHeight + labelHeight,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          for (var i = 0; i < months.length; i++)
                            SizedBox(
                              width: columnWidth,
                              height: headerHeight,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      money(amounts[i], 'CNY'),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.muted,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      RepaintBoundary(
                        child: CustomPaint(
                          size: Size(months.length * columnWidth, plotHeight),
                          painter: _TrendPainter(amounts, ceiling, columnWidth),
                        ),
                      ),
                      Row(
                        children: [
                          for (var i = 0; i < months.length; i++)
                            Semantics(
                              label: '${months[i]}，${money(amounts[i], 'CNY')}',
                              child: SizedBox(
                                width: columnWidth,
                                height: labelHeight,
                                child: Center(
                                  child: Text(
                                    months[i],
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '左右滑动查看月份 · 未购入月份为 0',
          style: TextStyle(fontSize: 12, color: AppTheme.muted),
        ),
      ],
    );
  }

  String _axisLabel(double amount) => amount >= 100000000
      ? '${(amount / 100000000).toStringAsFixed(1)}亿'
      : amount >= 10000
      ? '${(amount / 10000).toStringAsFixed(1)}万'
      : amount.toStringAsFixed(amount < 10 && amount != 0 ? 1 : 0);
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values, this.ceiling, this.step);
  final List<double> values;
  final double ceiling;
  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 7.5;
    final height = size.height - inset * 2;
    final grid = Paint()
      ..color = const Color(0xFFE9EEEA)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = inset + height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset((i + .5) * step, inset + height * (1 - values[i] / ceiling)),
    ];
    final curve = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final mid = (a.dx + b.dx) / 2;
      curve.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    final fill = Path.from(curve)
      ..lineTo(points.last.dx, inset + height)
      ..lineTo(points.first.dx, inset + height)
      ..close();
    canvas.drawPath(fill, Paint()..color = const Color(0x145E9F88));
    canvas.drawPath(
      curve,
      Paint()
        ..color = const Color(0xFF5E9F88)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    for (final point in points) {
      canvas.drawCircle(point, 3.5, Paint()..color = const Color(0xFF5E9F88));
      canvas.drawCircle(point, 1.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.ceiling != ceiling ||
      old.step != step ||
      !listEquals(old.values, values);
}
