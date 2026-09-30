import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/collection_options.dart';
import '../models/user_preferences.dart';
import '../repositories/preferences_repository.dart';
import '../services/backup_service.dart';
import '../services/cover_image_service.dart';
import '../widgets/private_cover.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
      if (mounted) _message('设置加载失败：$error');
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
    try {
      await widget.repository.addCategory(value);
      await _load();
      widget.onChanged();
    } catch (error) {
      if (mounted) _message('添加分类失败：$error');
    }
  }

  Future<void> _removeCategory(String value) async {
    try {
      await widget.repository.removeCategory(value);
      await _load();
      widget.onChanged();
    } catch (error) {
      if (mounted) _message('删除分类失败：$error');
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
    if (prefs == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 100),
      children: [
        Text(
          '设置',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 18),
        Text('展柜卡片', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          title: const Text('展示价格'),
          value: prefs.showPrice,
          onChanged: _busy ? null : (v) => _save(prefs.copyWith(showPrice: v)),
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
        const Divider(height: 30),
        Text('壁纸', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        if (prefs.wallpaperUrl != null)
          SizedBox(
            height: 130,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
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
        const Divider(height: 30),
        Row(
          children: [
            Expanded(
              child: Text('分类', style: Theme.of(context).textTheme.titleMedium),
            ),
            IconButton(
              tooltip: '添加分类',
              onPressed: _busy ? null : _newCategory,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in _categories)
              InputChip(
                label: Text(category),
                onDeleted: collectionCategories.contains(category) || _busy
                    ? null
                    : () => _removeCategory(category),
              ),
          ],
        ),
        const Divider(height: 30),
        Text('数据备份', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('导出包含收藏、封面、分类、壁纸和展示设置的 JSON 文件。请妥善保存。'),
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
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}
