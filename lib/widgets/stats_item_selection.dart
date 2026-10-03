import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/app_ui.dart';
import '../core/collection_options.dart';
import '../models/collection_item.dart';

/// Edits a local copy; dismissing the sheet leaves the dashboard unchanged.
class StatsItemSelection extends StatefulWidget {
  const StatsItemSelection({
    super.key,
    required this.items,
    required this.excludedIds,
    required this.scope,
  });

  final List<CollectionItem> items;
  final Set<String> excludedIds;
  final String scope;

  @override
  State<StatsItemSelection> createState() => _StatsItemSelectionState();
}

class _StatsItemSelectionState extends State<StatsItemSelection> {
  late final Set<String> _excluded = {...widget.excludedIds};

  @override
  Widget build(BuildContext context) {
    final selectedCount = widget.items
        .where((item) => !_excluded.contains(item.id))
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.scope, style: Theme.of(context).textTheme.bodySmall),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('已选 $selectedCount / ${widget.items.length} 件'),
            Wrap(
              children: [
                TextButton(
                  onPressed: widget.items.isEmpty
                      ? null
                      : () => setState(() {
                          _excluded.removeAll(
                            widget.items.map((item) => item.id),
                          );
                        }),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: widget.items.isEmpty
                      ? null
                      : () => setState(() {
                          _excluded.addAll(widget.items.map((item) => item.id));
                        }),
                  child: const Text('全不选'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: widget.items.isEmpty
              ? const Center(child: Text('此分类和年份下暂无藏品'))
              : ListView.separated(
                  itemCount: widget.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    final date = item.purchaseDate ?? item.createdAt;
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      clipBehavior: Clip.antiAlias,
                      child: CheckboxListTile(
                        key: ValueKey('stats-item-${item.id}'),
                        value: !_excluded.contains(item.id),
                        onChanged: (selected) => setState(() {
                          if (selected == true) {
                            _excluded.remove(item.id);
                          } else {
                            _excluded.add(item.id);
                          }
                        }),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.only(
                          left: 4,
                          right: 12,
                        ),
                        title: Text(item.name),
                        subtitle: Text(
                          '${item.category} · ${date.year}年${date.month}月 · '
                          '${item.priceCny == null ? '未记录价格' : money(item.priceCny!, 'CNY')}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        activeColor: AppTheme.accent,
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _excluded),
                child: const Text('应用筛选'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
