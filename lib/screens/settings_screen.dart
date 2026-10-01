import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/collection_options.dart';
import '../core/app_ui.dart';
import '../models/user_preferences.dart';
import '../repositories/preferences_repository.dart';
import '../services/backup_service.dart';
import '../services/cover_image_service.dart';
import '../widgets/private_cover.dart';
import '../widgets/section_card.dart';
import '../widgets/loading_overlay.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    required this.backup,
    required this.images,
    required this.onChanged,
  });
  final PreferencesRepository repository;
  final BackupService backup;
  final CoverImageService images;
  final VoidCallback onChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  UserPreferences? _prefs;
  List<String> _categories = [];
  bool _busy = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loadFailed = false);
    try {
      final prefs = await widget.repository.load();
      final categories = await widget.repository.categories();
      if (mounted) {
        setState(() {
          _prefs = prefs;
          _categories = categories;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _loadFailed = true);
        _message('设置加载失败：$error');
      }
    }
  }

  void _message(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));

  Future<void> _save(UserPreferences next) async {
    setState(() => _busy = true);
    try {
      final saved = await widget.repository.save(next);
      if (mounted) setState(() => _prefs = saved);
      widget.onChanged();
    } catch (error) {
      if (mounted) _message('保存设置失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _wallpaper(bool remove) async {
    XFile? file;
    if (!remove) {
      file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        imageQuality: 85,
      );
      if (file == null) return;
    }
    setState(() => _busy = true);
    try {
      final saved = await widget.repository.setWallpaper(_prefs!, file);
      if (mounted) setState(() => _prefs = saved);
      widget.onChanged();
    } catch (error) {
      if (mounted) _message('设置壁纸失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newCategory() async {
    var enteredName = '';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加分类'),
        content: TextField(
          onChanged: (text) => enteredName = text,
          maxLength: 60,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, enteredName.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.addCategory(value);
      await _load();
      widget.onChanged();
    } catch (error) {
      if (mounted) _message('添加分类失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeCategory(String value) async {
    setState(() => _busy = true);
    try {
      await widget.repository.removeCategory(value);
      await _load();
      widget.onChanged();
    } catch (error) {
      if (mounted) _message('删除分类失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final result = await widget.backup.export();
      if (mounted && result != null) _message('备份已保存：$result');
    } catch (error) {
      if (mounted) _message('备份失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入备份'),
        content: const Text('备份中的同 ID 物品会覆盖当前记录，其他物品会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('选择文件'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final count = await widget.backup.import();
      if (count != null && mounted) {
        _message('已导入 $count 件收藏');
        await _load();
        widget.onChanged();
      }
    } catch (error) {
      if (mounted) _message('导入失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _prefs;
    if (prefs == null) {
      return Center(
        child: _loadFailed
            ? TextButton(onPressed: _load, child: const Text('设置加载失败，点击重试'))
            : const CircularProgressIndicator(),
      );
    }
    return LoadingOverlay(
      loading: _busy,
      message: '正在更新，请稍候…',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: AppSpacing.page,
            children: [
              Text(
                '让展柜更像你',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 18),
              SectionCard(
                title: '展柜卡片',
                icon: Icons.shelves,
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('展示价格'),
                      value: prefs.showPrice,
                      onChanged: _busy
                          ? null
                          : (v) => _save(prefs.copyWith(showPrice: v)),
                    ),
                    SwitchListTile(
                      title: const Text('展示已拥有天数'),
                      value: prefs.showOwnedDays,
                      onChanged: _busy
                          ? null
                          : (v) => _save(prefs.copyWith(showOwnedDays: v)),
                    ),
                    SwitchListTile(
                      title: const Text('展示每天花费'),
                      value: prefs.showDailyCost,
                      onChanged: _busy
                          ? null
                          : (v) => _save(prefs.copyWith(showDailyCost: v)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionCard(
                title: '展柜壁纸',
                icon: Icons.wallpaper_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (prefs.wallpaperUrl != null)
                      SizedBox(
                        height: 130,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.input),
                          child: PrivateCover(
                            imageUrl: prefs.wallpaperUrl,
                            images: widget.images,
                          ),
                        ),
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _wallpaper(false),
                          icon: const Icon(Icons.wallpaper),
                          label: const Text('添加或更换壁纸'),
                        ),
                        if (prefs.wallpaperUrl != null)
                          TextButton(
                            onPressed: _busy ? null : () => _wallpaper(true),
                            child: const Text('移除'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionCard(
                title: '收藏分类',
                icon: Icons.category_outlined,
                trailing: IconButton(
                  tooltip: '添加分类',
                  onPressed: _busy ? null : _newCategory,
                  icon: const Icon(Icons.add),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in _categories)
                      if (collectionCategories.contains(category))
                        Chip(label: Text(category))
                      else
                        InputChip(
                          label: Text(category),
                          onDeleted: _busy
                              ? null
                              : () => _removeCategory(category),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionCard(
                title: '数据备份',
                icon: Icons.cloud_download_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '导出包含收藏、封面、分类、壁纸和展示设置的 ZIP 文件。仍可导入旧版 JSON 备份。请妥善保存。',
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _export,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('导出备份'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _import,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('导入备份'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
