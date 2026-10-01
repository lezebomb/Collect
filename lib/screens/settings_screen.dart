import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_ui.dart';
import '../models/user_preferences.dart';
import '../repositories/preferences_repository.dart';
import '../services/backup_service.dart';
import '../services/cover_image_service.dart';
import '../widgets/private_cover.dart';
import '../widgets/section_card.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/category_chip.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    required this.backup,
    required this.images,
    required this.onChanged,
    required this.onDataChanged,
    required this.initialPreferences,
    required this.initialCategories,
  });
  final PreferencesRepository repository;
  final BackupService backup;
  final CoverImageService images;
  final void Function(UserPreferences, List<String>) onChanged;
  final VoidCallback onDataChanged;
  final UserPreferences initialPreferences;
  final List<String> initialCategories;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late UserPreferences _prefs = widget.initialPreferences;
  late UserPreferences _confirmedPrefs = _prefs;
  late List<String> _categories = List.of(widget.initialCategories);
  bool _busy = false;
  bool _savingPrefs = false;
  final _pendingCategories = <String>{};
  bool get _heavyDisabled =>
      _busy || _savingPrefs || _pendingCategories.isNotEmpty;

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy && !_savingPrefs && _pendingCategories.isEmpty) {
      _prefs = _confirmedPrefs = widget.initialPreferences;
      _categories = List.of(widget.initialCategories);
    }
  }

  Future<void> _load() async {
    final prefs = await widget.repository.load();
    final categories = await widget.repository.categories();
    if (mounted) {
      setState(() {
        _prefs = _confirmedPrefs = prefs;
        _categories = categories;
      });
    }
  }

  void _notify() {
    if (mounted) widget.onChanged(_prefs, List.of(_categories));
  }

  void _message(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));

  Future<void> _save(UserPreferences next) async {
    setState(() => _prefs = next);
    _notify();
    if (_savingPrefs) return;
    setState(() => _savingPrefs = true);
    try {
      // Serialize requests and coalesce rapid toggles so older saves cannot win.
      while (mounted) {
        final requested = _prefs;
        final saved = await widget.repository.save(requested);
        _confirmedPrefs = saved;
        if (!mounted) return;
        if (identical(_prefs, requested)) {
          setState(() => _prefs = saved);
          _notify();
          break;
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _prefs = _confirmedPrefs);
        _notify();
        _message('保存设置失败，已恢复原设置：$error');
      }
    } finally {
      if (mounted) setState(() => _savingPrefs = false);
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
      final saved = await widget.repository.setWallpaper(_prefs, file);
      if (mounted) setState(() => _prefs = _confirmedPrefs = saved);
      _notify();
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
    if (_categories.contains(value) || _pendingCategories.contains(value)) {
      return;
    }
    setState(() {
      _pendingCategories.add(value);
      _categories = [..._categories, value];
    });
    _notify();
    try {
      await widget.repository.addCategory(value);
    } catch (error) {
      if (mounted) {
        setState(() => _categories.remove(value));
        _notify();
        _message('添加分类失败：$error');
      }
    } finally {
      if (mounted) setState(() => _pendingCategories.remove(value));
    }
  }

  Future<void> _removeCategory(String value) async {
    if (_pendingCategories.contains(value)) return;
    final index = _categories.indexOf(value);
    setState(() {
      _pendingCategories.add(value);
      _categories.remove(value);
    });
    _notify();
    try {
      await widget.repository.removeCategory(value);
    } catch (error) {
      if (mounted) {
        setState(
          () => _categories.insert(index.clamp(0, _categories.length), value),
        );
        _notify();
        _message('删除分类失败，已恢复分类：$error');
      }
    } finally {
      if (mounted) setState(() => _pendingCategories.remove(value));
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
        _notify();
        widget.onDataChanged();
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
                    if (_savingPrefs)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: LinearProgressIndicator(minHeight: 2),
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
                          onPressed: _heavyDisabled
                              ? null
                              : () => _wallpaper(false),
                          icon: const Icon(Icons.wallpaper),
                          label: const Text('添加或更换壁纸'),
                        ),
                        if (prefs.wallpaperUrl != null)
                          TextButton(
                            onPressed: _heavyDisabled
                                ? null
                                : () => _wallpaper(true),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final category in _categories)
                          CategoryChip(
                            label: category,
                            deleting: _pendingCategories.contains(category),
                            onDeleted: () {
                              if (!_busy) _removeCategory(category);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '删除分类只会移除选项，已有收藏会保留原分类。',
                      style: TextStyle(fontSize: 12),
                    ),
                    if (_pendingCategories.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 2),
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
                      onPressed: _heavyDisabled ? null : _export,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('导出备份'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _heavyDisabled ? null : _import,
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
