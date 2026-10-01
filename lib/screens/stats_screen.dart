import 'package:flutter/material.dart';

import '../core/collection_options.dart';
import '../core/collection_stats.dart';
import '../core/app_theme.dart';
import '../core/app_ui.dart';
import '../models/collection_item.dart';
import '../widgets/section_card.dart';
import '../widgets/rounded_choice_field.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.items});
  final List<CollectionItem> items;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  String? _category;
  int? _year;

  @override
  Widget build(BuildContext context) {
    final categories =
        widget.items.map((item) => item.category).toSet().toList()..sort();
    final years =
        widget.items
            .map((item) => (item.purchaseDate ?? item.createdAt).year)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
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
            Text(
              '收藏的足迹',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('每一件喜欢，都有迹可循。', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: RoundedChoiceField(
                    label: '分类',
                    value: _category ?? '',
                    values: ['', ...categories],
                    optionLabel: (v) => v.isEmpty ? '全部分类' : v,
                    onChanged: (v) =>
                        setState(() => _category = v == '' ? null : v),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: RoundedChoiceField(
                    label: '年份',
                    value: _year?.toString() ?? '',
                    values: ['', ...years.map((v) => '$v')],
                    optionLabel: (v) => v.isEmpty ? '全部年份' : '$v 年',
                    onChanged: (v) =>
                        setState(() => _year = int.tryParse(v ?? '')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _summary(
                    context,
                    '总投入',
                    money(stats.totalInvestment, 'CNY'),
                    '${stats.items.length} 件物品',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _summary(
                    context,
                    '在手物品',
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
            _panel(context, '月度消费趋势', _monthly(stats.monthlySpending)),
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
        for (final entry in sorted)
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

  Widget _monthly(Map<String, double> values) {
    if (values.isEmpty) return const Text('暂无数据');
    final months = values.keys.toList()..sort();
    final recent = months.length > 12
        ? months.sublist(months.length - 12)
        : months;
    final max = recent
        .map((month) => values[month]!)
        .reduce((a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final month in recent)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: Text(month)),
                    Expanded(
                      child: Text(
                        money(values[month]!, 'CNY'),
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: max == 0 ? 0 : values[month]! / max,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
