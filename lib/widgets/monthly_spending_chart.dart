import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/collection_options.dart';
import 'section_card.dart';
import 'selection_sheet.dart';

class MonthlySpendingChart extends StatefulWidget {
  const MonthlySpendingChart({super.key, required this.values, this.year});
  final Map<String, double> values;
  final int? year;
  @override
  State<MonthlySpendingChart> createState() => _MonthlySpendingChartState();
}

class _MonthlySpendingChartState extends State<MonthlySpendingChart> {
  final _scroll = ScrollController();
  static const _firstYear = 1900;
  late int _visibleYear = widget.year ?? _latest.year;
  double _step = 0;
  double? _pendingIndex;
  bool _initialPosition = true;

  DateTime get _latest {
    if (widget.values.isEmpty) return DateTime.now();
    final keys = widget.values.keys.toList()..sort();
    return DateTime.parse('${keys.last}-01');
  }

  int _index(DateTime date) => (date.year - _firstYear) * 12 + date.month - 1;
  DateTime _date(int index) => DateTime(_firstYear, index + 1);
  String _key(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';
  double _amount(int index) => widget.values[_key(_date(index))] ?? 0;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (_step <= 0) return;
    final year = _date((_scroll.offset / _step + .01).floor()).year;
    if (year != _visibleYear && mounted) setState(() => _visibleYear = year);
  }

  @override
  void didUpdateWidget(covariant MonthlySpendingChart old) {
    super.didUpdateWidget(old);
    if (old.year != widget.year) {
      _pendingIndex = _index(DateTime(widget.year ?? _latest.year)).toDouble();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _chooseYear() async {
    final years = widget.values.keys.map(
      (key) => int.parse(key.substring(0, 4)),
    );
    final first = math.min(
      _visibleYear - 1,
      years.isEmpty ? DateTime.now().year - 1 : years.reduce(math.min) - 1,
    );
    final last = math.max(
      _visibleYear + 1,
      math.max(DateTime.now().year, _latest.year),
    );
    final selected = await showSelectionSheet<int>(
      context: context,
      title: '查看年份',
      builder: (context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var year = last; year >= math.max(_firstYear, first); year--)
            SelectionOption(
              label: '$year 年',
              selected: year == _visibleYear,
              onTap: () => Navigator.pop(context, year),
            ),
        ],
      ),
    );
    if (selected != null && mounted && _scroll.hasClients) {
      _scroll.jumpTo(
        (_index(DateTime(selected)) * _step).clamp(
          0.0,
          _scroll.position.maxScrollExtent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = (math.max(2100, _latest.year + 1) - _firstYear + 1) * 12;
    final highest = widget.values.isEmpty
        ? 0.0
        : widget.values.values.reduce(math.max);
    final ceiling = highest <= 0 ? 1.0 : highest * 1.12;
    final scale = (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(
      1.0,
      2.0,
    );
    return SectionCard(
      title: '月度消费趋势',
      trailing: TextButton.icon(
        key: const ValueKey('monthly-chart-year'),
        onPressed: _chooseYear,
        icon: const Icon(Icons.calendar_month_outlined, size: 16),
        label: Text('$_visibleYear 年', style: const TextStyle(fontSize: 12)),
      ),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final step = math.max(bounds.maxWidth / 6, 46.0 * scale);
          if (_step != 0 && _step != step && _scroll.hasClients) {
            _pendingIndex ??= _scroll.offset / _step;
          }
          _step = step;
          if (_initialPosition || _pendingIndex != null) {
            final target =
                _pendingIndex ??
                (widget.year != null
                    ? _index(DateTime(widget.year!)).toDouble()
                    : math.max(0, _index(_latest) - 4).toDouble());
            _pendingIndex = null;
            _initialPosition = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _scroll.hasClients) {
                _scroll.jumpTo(
                  (target * step).clamp(0.0, _scroll.position.maxScrollExtent),
                );
                _onScroll();
              }
            });
          }
          final plotHeight = 168.0 + 16 * (scale - 1),
              amountHeight = 20.0 * scale,
              labelHeight = 28.0 * scale;
          return Column(
            children: [
              SizedBox(
                height: amountHeight + plotHeight + labelHeight,
                child: ListView.builder(
                  key: const ValueKey('monthly-chart-scroll'),
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  itemExtent: step,
                  itemCount: count,
                  itemBuilder: (context, index) {
                    final date = _date(index), amount = _amount(index);
                    final pointY =
                        amountHeight +
                        (plotHeight - 12) * (1 - amount / ceiling);
                    return Semantics(
                      label: '${_key(date)}，${money(amount, 'CNY')}',
                      child: Column(
                        children: [
                          SizedBox(
                            height: amountHeight + plotHeight,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      painter: _MonthPainter(
                                        index == 0
                                            ? amount
                                            : _amount(index - 1),
                                        amount,
                                        index == count - 1
                                            ? amount
                                            : _amount(index + 1),
                                        ceiling,
                                        amountHeight,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: math.max(0, pointY - amountHeight - 6),
                                  left: 2,
                                  right: 2,
                                  height: amountHeight,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      money(amount, 'CNY'),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.muted,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: labelHeight,
                            child: Center(
                              child: Text(
                                '${date.month}月',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.muted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '左右滑动查看月份，滑过年末可继续查看相邻年份',
                style: TextStyle(fontSize: 11, color: AppTheme.muted),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Paint only a visible point and its adjoining arcs, with consistent scale.
class _MonthPainter extends CustomPainter {
  _MonthPainter(this.previous, this.amount, this.next, this.ceiling, this.top);
  final double previous, amount, next, ceiling, top;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final height = size.height - top - 12;
    final grid = Paint()
      ..color = const Color(0xFFE9EEEA)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = top + height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final points = [
      Offset(-size.width / 2, top + height * (1 - previous / ceiling)),
      Offset(size.width / 2, top + height * (1 - amount / ceiling)),
      Offset(size.width * 1.5, top + height * (1 - next / ceiling)),
    ];
    final curve = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i], mid = (a.dx + b.dx) / 2;
      curve.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    final fill = Path.from(curve)
      ..lineTo(points.last.dx, top + height)
      ..lineTo(points.first.dx, top + height)
      ..close();
    canvas.drawPath(fill, Paint()..color = const Color(0x145E9F88));
    canvas.drawPath(
      curve,
      Paint()
        ..color = const Color(0xFF5E9F88)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(points[1], 4, Paint()..color = const Color(0xFF5E9F88));
    canvas.drawCircle(points[1], 2.2, Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MonthPainter old) =>
      old.previous != previous ||
      old.amount != amount ||
      old.next != next ||
      old.ceiling != ceiling ||
      old.top != top;
}
