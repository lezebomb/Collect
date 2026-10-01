import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/app_ui.dart';
import '../core/collection_options.dart';
import '../models/collection_item.dart';
import '../repositories/item_repository.dart';
import '../repositories/preferences_repository.dart';
import '../services/cover_image_service.dart';
import '../widgets/private_cover.dart';
import '../widgets/section_card.dart';
import 'item_form_screen.dart';

class ItemDetailScreen extends StatefulWidget {
  const ItemDetailScreen({
    super.key,
    required this.item,
    required this.repository,
    required this.images,
    required this.preferences,
    required this.onChanged,
  });

  final CollectionItem item;
  final ItemRepository repository;
  final CoverImageService images;
  final PreferencesRepository preferences;
  final Future<void> Function(CollectionItem?) onChanged;

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  late CollectionItem _item = widget.item;
  bool _deleting = false;

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<CollectionItem>(
      MaterialPageRoute(
        builder: (_) => ItemFormScreen(
          repository: widget.repository,
          images: widget.images,
          preferences: widget.preferences,
          initial: _item,
        ),
      ),
    );
    if (saved != null && mounted) {
      await widget.onChanged(saved);
      if (mounted) setState(() => _item = saved);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这件收藏？'),
        content: Text('“${_item.name}”及它的封面将从收藏柜中移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.repository.delete(_item);
      await widget.onChanged(null);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('收藏详情'),
      actions: [
        PopupMenuButton<String>(
          enabled: !_deleting,
          onSelected: (value) => value == 'edit' ? _edit() : _delete(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('编辑收藏')),
            PopupMenuItem(value: 'delete', child: Text('删除收藏')),
          ],
        ),
      ],
    ),
    body: _deleting
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: AppSpacing.page,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      child: AspectRatio(
                        aspectRatio: 1.35,
                        child: ColoredBox(
                          color: const Color(0xFFEFF1EC),
                          child: PrivateCover(
                            imageUrl: _item.coverImage,
                            images: widget.images,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        Chip(label: Text(_item.category)),
                        if (_item.isGame && _item.gamePlayStatus != null)
                          Chip(label: Text(_item.gamePlayStatus!)),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _item.name,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: AppTheme.ink,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    if (_item.isGame) ...[
                      const SizedBox(height: AppSpacing.xl),
                      SectionCard(
                        title: '游戏信息',
                        icon: Icons.sports_esports_outlined,
                        child: Column(
                          children: [
                            if (_item.gamePlatform != null)
                              _FactRow('平台', _item.gamePlatform!),
                            if (_item.gameContentType != null)
                              _FactRow('内容类型', _item.gameContentType!),
                            if (_item.gameEdition != null)
                              _FactRow('版本类型', _item.gameEdition!),
                            if (_item.gamePlayStatus != null)
                              _FactRow('游玩状态', _item.gamePlayStatus!),
                          ],
                        ),
                      ),
                    ],
                    if (_item.purchaseDate != null || _item.price != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      SectionCard(
                        title: '收藏记录',
                        icon: Icons.bookmark_outline_rounded,
                        child: Column(
                          children: [
                            if (_item.purchaseDate != null)
                              _FactRow('购买日期', dateOnly(_item.purchaseDate!)),
                            if (_item.price != null)
                              _FactRow(
                                '购买价格',
                                money(_item.price!, _item.currency),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      '关于它',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _item.description.isEmpty
                          ? '还没有写下它的故事。'
                          : _item.description,
                      style: const TextStyle(
                        color: AppTheme.muted,
                        height: 1.7,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}

class _FactRow extends StatelessWidget {
  const _FactRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: AppTheme.muted)),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: AppTheme.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
