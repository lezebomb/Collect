import 'package:flutter/material.dart';

import '../core/collection_options.dart';
import '../core/collection_stats.dart';
import '../core/app_theme.dart';
import '../core/app_ui.dart';
import '../models/collection_item.dart';
import '../widgets/section_card.dart';
import '../widgets/selection_sheet.dart';
import '../widgets/monthly_spending_chart.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.items});
  final List<CollectionItem> items;

  @override
  State<StatsScreen> createState() => StatsScreenState();
}

class StatsScreenState extends State<StatsScreen> {
  String? _category;
  int? _year;

  Future<String?> _choose(
    String title,
    List<String> values,
    String selected,
    String Function(String) label,
  ) => showSelectionSheet<String>(
    context: context,
    title: title,
    builder: (context) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          SelectionOption(
            label: label(value),
            selected: value == selected,
            onTap: () => Navigator.pop(context, value),
          ),
      ],
    ),
  );

  Future<void> chooseCategory() async {
    final categories = widget.items.map((i) => i.category).toSet().toList()
      ..sort();
    final value = await _choose(
      '筛选分类',
      ['', ...categories],
      _category ?? '',
      (v) => v.isEmpty ? '全部分类' : v,
    );
    if (value != null && mounted) {
      setState(() => _category = value.isEmpty ? null : value);
    }
  }

  Future<void> chooseYear() async {
    final years =
        widget.items
            .map((i) => (i.purchaseDate ?? i.createdAt).year)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    final value = await _choose(
      '筛选年份',
      ['', ...years.map((v) => '$v')],
      _year?.toString() ?? '',
      (v) => v.isEmpty ? '全部年份' : '$v 年',
    );
    if (value != null && mounted) setState(() => _year = int.tryParse(value));
  }

  static const _barColors = [
    Color(0xFF5E9F88),
    Color(0xFF6B9DCE),
    Color(0xFFE2A05E),
    Color(0xFFB18BC4),
    Color(0xFFD77F8D),
    Color(0xFF71AFB9),
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items.where((item) {
      if (_category != null && item.category != _category) return false;
      if (_year != null &&
          (item.purchaseDate ?? item.createdAt).year != _year) {
        return false;
      }
      return true;
    }).toList();
    final stats = CollectionStats(filtered);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: AppSpacing.page,
          children: [
            if (_category != null || _year != null) ...[
              Text(
                '${_category ?? '全部分类'} · ${_year == null ? '全部年份' : '$_year 年'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],

            Row(
              children: [
                Expanded(
                  child: _summary(
                    context,
                    '藏品价值',
                    money(stats.totalInvestment, 'CNY'),
                    '${stats.items.length} 件物品',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _summary(
                    context,
                    '藏品数量',
                    '${stats.inHand.length}',
                    '购入金额 ${money(stats.inHandValue, 'CNY')}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _panel(
              context,
              '类型占比（按投入）',
              _bars(
                stats.categorySpending,
                stats.totalInvestment,
                moneyLabels: true,
              ),
            ),
            _panel(
              context,
              '各类型数量',
              _bars(
                stats.categoryCounts.map((k, v) => MapEntry(k, v.toDouble())),
                stats.items.length.toDouble(),
                moneyLabels: false,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: MonthlySpendingChart(
                values: CollectionStats(
                  widget.items
                      .where(
                        (item) =>
                            _category == null || item.category == _category,
                      )
                      .toList(),
                ).monthlySpending,
                year: _year,
              ),
            ),
            if (_category == null || _category == '游戏')
              _panel(
                context,
                '游戏 · 游玩状态',
                _bars(
                  stats.gameStatuses.map((k, v) => MapEntry(k, v.toDouble())),
                  stats.items.where((item) => item.isGame).length.toDouble(),
                  moneyLabels: false,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summary(
    BuildContext context,
    String title,
    String value,
    String detail,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 5),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );

  Widget _panel(BuildContext context, String title, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
    child: SectionCard(title: title, child: child),
  );

  Widget _bars(
    Map<String, double> values,
    double total, {
    required bool moneyLabels,
  }) {
    if (values.isEmpty) return const Text('暂无数据');
    final sorted = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      children: [
        for (final (index, entry) in sorted.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: Text(entry.key)),
                    Expanded(
                      child: Text(
                        moneyLabels
                            ? '${money(entry.value, 'CNY')} · ${total == 0 ? 0 : entry.value / total * 100 ~/ 1}%'
                            : '${entry.value.toInt()}',
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                LinearProgressIndicator(
                  color: index < _barColors.length
                      ? _barColors[index]
                      : HSLColor.fromAHSL(
                          1,
                          (index * 137.5) % 360,
                          .4,
                          .56,
                        ).toColor(),
                  backgroundColor: const Color(0xFFF0F2EF),
                  value: total == 0 ? 0 : (entry.value / total).clamp(0, 1),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
