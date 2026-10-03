import 'package:flutter/material.dart';

import '../core/collection_options.dart';
import '../core/collection_stats.dart';
import '../core/app_theme.dart';
import '../core/app_ui.dart';
import '../models/collection_item.dart';
import '../widgets/section_card.dart';
import '../widgets/selection_sheet.dart';
import '../widgets/monthly_spending_chart.dart';
import '../widgets/stats_item_selection.dart';

/// Reuse computed values when tab changes/search/selection rebuild the parent.
/// The existing CollectionStats remains the source of all calculations.
class _DashboardStats {
  _DashboardStats(CollectionStats stats)
    : items = stats.items,
      inHand = stats.inHand,
      totalInvestment = stats.totalInvestment,
      inHandValue = stats.inHandValue,
      categoryCounts = stats.categoryCounts,
      categorySpending = stats.categorySpending,
      gameStatuses = stats.gameStatuses;
  final List<CollectionItem> items;
  final List<CollectionItem> inHand;
  final double totalInvestment;
  final double inHandValue;
  final Map<String, int> categoryCounts;
  final Map<String, double> categorySpending;
  final Map<String, int> gameStatuses;
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.items});
  final List<CollectionItem> items;

  @override
  State<StatsScreen> createState() => StatsScreenState();
}

class StatsScreenState extends State<StatsScreen> {
  String? _category;
  int? _year;
  final Set<String> _excludedIds = {};
  _DashboardStats? _cachedStats;
  Map<String, double>? _cachedMonthly;

  @override
  void didUpdateWidget(covariant StatsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items)) {
      final available = widget.items.map((item) => item.id).toSet();
      _excludedIds.removeWhere((id) => !available.contains(id));
      _cachedStats = null;
      _cachedMonthly = null;
    }
  }

  void categoryRenamed(String oldName, String newName) {
    if (_category == oldName) setState(() => _category = newName);
    _cachedStats = null;
    _cachedMonthly = null;
  }

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
      setState(() {
        final category = value.isEmpty ? null : value;
        if (_category != category) _excludedIds.clear();
        _category = category;
        _cachedStats = null;
        _cachedMonthly = null;
      });
    }
  }

  bool _matchesScope(CollectionItem item) =>
      (_category == null || item.category == _category) &&
      (_year == null || (item.purchaseDate ?? item.createdAt).year == _year);

  Future<void> chooseItems() async {
    final candidates = widget.items.where(_matchesScope).toList();
    final excluded = await showSelectionSheet<Set<String>>(
      context: context,
      title: '筛选藏品',
      heightFraction: .76,
      scrollable: false,
      builder: (context) => StatsItemSelection(
        items: candidates,
        excludedIds: _excludedIds,
        scope:
            '${_category ?? '全部分类'} · ${_year == null ? '全部年份' : '$_year 年'}',
      ),
    );
    if (excluded == null || !mounted) return;
    setState(() {
      final available = widget.items.map((item) => item.id).toSet();
      _excludedIds
        ..clear()
        ..addAll(excluded.where(available.contains));
      _cachedStats = null;
      _cachedMonthly = null;
    });
  }

  void _resetItems() => setState(() {
    _excludedIds.clear();
    _cachedStats = null;
    _cachedMonthly = null;
  });

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
    if (value != null && mounted) {
      setState(() {
        _year = int.tryParse(value);
        _cachedStats = null;
      });
    }
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
    final stats = _cachedStats ??= _DashboardStats(
      CollectionStats(
        widget.items
            .where(
              (item) => _matchesScope(item) && !_excludedIds.contains(item.id),
            )
            .toList(),
      ),
    );
    final monthly = _cachedMonthly ??= CollectionStats(
      widget.items
          .where(
            (item) =>
                (_category == null || item.category == _category) &&
                !_excludedIds.contains(item.id),
          )
          .toList(),
    ).monthlySpending;
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
            if (_excludedIds.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: chooseItems,
                    icon: const Icon(Icons.checklist_rounded, size: 18),
                    label: Text(
                      '统计 ${stats.items.length} 件 · 已排除 ${_excludedIds.length} 件',
                    ),
                  ),
                  TextButton(onPressed: _resetItems, child: const Text('恢复全部')),
                ],
              ),
              const SizedBox(height: 8),
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
              child: MonthlySpendingChart(values: monthly, year: _year),
            ),
            if (_category == null || stats.items.any((item) => item.isGame))
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
