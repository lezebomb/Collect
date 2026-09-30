import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/collection_options.dart';
import '../models/collection_item.dart';
import '../repositories/item_repository.dart';
import '../repositories/preferences_repository.dart';
import '../services/catalog_service.dart';
import '../services/cover_image_service.dart';
import '../widgets/private_cover.dart';

class ItemFormScreen extends StatefulWidget {
  const ItemFormScreen({
    super.key,
    required this.repository,
    required this.images,
    required this.preferences,
    this.initial,
  });

  final ItemRepository repository;
  final CoverImageService images;
  final PreferencesRepository preferences;
  final CollectionItem? initial;

  @override
  State<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends State<ItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final _catalog = CatalogService();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _description = TextEditingController(
    text: widget.initial?.description,
  );
  late final _price = TextEditingController(
    text: widget.initial?.price?.toStringAsFixed(2),
  );
  late final _priceCny = TextEditingController(
    text: widget.initial?.priceCny?.toStringAsFixed(2),
  );
  late String _category =
      widget.initial?.category ?? collectionCategories.first;
  late String _status = widget.initial?.status ?? 'owned';
  late String _currency = widget.initial?.currency ?? 'CNY';
  late String? _platform = widget.initial?.gamePlatform;
  late String? _contentType = widget.initial?.gameContentType;
  late String? _edition = widget.initial?.gameEdition;
  late String? _playStatus = widget.initial?.gamePlayStatus;
  late DateTime? _purchaseDate = widget.initial?.purchaseDate;
  late List<String> _categories = {
    ...collectionCategories,
    if (widget.initial != null) widget.initial!.category,
  }.toList();
  XFile? _newCover;
  Uint8List? _preview;
  bool _removeCover = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _recoverLostImage();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await widget.preferences.categories(
        itemCategories: [if (widget.initial != null) widget.initial!.category],
      );
      if (mounted) setState(() => _categories = categories);
    } catch (_) {
      if (widget.initial != null &&
          !_categories.contains(widget.initial!.category)) {
        setState(
          () => _categories = [..._categories, widget.initial!.category],
        );
      }
    }
  }

  Future<void> _recoverLostImage() async {
    try {
      final lost = await _picker.retrieveLostData();
      if (lost.files?.isNotEmpty == true) await _setCover(lost.files!.first);
    } catch (_) {}
  }

  Future<void> _setCover(XFile image) async {
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    if (bytes.length > CoverImageService.maxBytes) {
      _message('图片不能超过 10 MB');
      return;
    }
    setState(() {
      _newCover = image;
      _preview = bytes;
      _removeCover = false;
    });
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pickCover(ImageSource source) async {
    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 85,
      );
      if (image != null) await _setCover(image);
      if (image != null && source == ImageSource.camera) {
        await _recognize(image);
      }
    } catch (error) {
      if (mounted) _message('获取图片失败：$error');
    }
  }

  Future<void> _recognize(XFile image) async {
    setState(() => _busy = true);
    try {
      final lines = await _catalog.recognize(image);
      if (!mounted) return;
      if (lines.isEmpty) {
        _message('没有识别到文字，请手动填写或搜索');
        return;
      }
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择识别到的名称'),
          children: lines
              .map(
                (line) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, line),
                  child: Text(line),
                ),
              )
              .toList(),
        ),
      );
      if (selected != null) {
        _name.text = selected;
        await _searchCatalog();
      }
    } catch (error) {
      if (mounted) _message('识别失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _searchCatalog() async {
    final query = _name.text.trim();
    if (query.isEmpty) {
      _message('先输入要搜索的名称');
      return;
    }
    setState(() => _busy = true);
    try {
      final results = await _catalog.searchImages(query, category: _category);
      if (!mounted) return;
      if (results.isEmpty) {
        _message('没有找到图片，可以换个关键词或自行选图');
        return;
      }
      final selected = await showModalBottomSheet<CatalogImage>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .78,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Column(
                    children: [
                      Text(
                        '为“$query”选择图片',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      const Text('选中图片后，可决定是否使用图片对应的标题'),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: results.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: .78,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                    itemBuilder: (context, index) {
                      final result = results[index];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.pop(context, result),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Image.network(
                                  result.previewUrl ?? result.imageUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Center(
                                    child: Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                                child: Text(
                                  result.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                                child: Text(
                                  result.source,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (selected == null || !mounted) return;
      final useSelectedTitle = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('名称如何填写？'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('保留我输入的名称'),
                subtitle: Text(
                  query,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(dialogContext, false),
              ),
              ListTile(
                title: const Text('使用图片对应的标题'),
                subtitle: Text(
                  selected.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(dialogContext, true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
          ],
        ),
      );
      if (useSelectedTitle == null || !mounted) return;
      try {
        final cover = await _catalog.coverFile(selected.imageUrl);
        await _setCover(cover);
        if (useSelectedTitle) _name.text = selected.title;
      } catch (_) {
        if (mounted) _message('图片下载失败，请选择另一张');
      }
    } catch (error) {
      if (mounted) _message('搜索失败，请继续手动填写：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addCategory() async {
    var enteredName = '';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建分类'),
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
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty) return;
    try {
      await widget.preferences.addCategory(value);
      if (mounted) {
        setState(() {
          _categories = {..._categories, value}.toList();
          _category = value;
        });
      }
    } catch (error) {
      if (mounted) _message('添加分类失败：$error');
    }
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _purchaseDate ?? now,
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (selected != null && mounted) setState(() => _purchaseDate = selected);
  }

  Future<void> _estimateCny() async {
    final amount = double.tryParse(_price.text.trim());
    if (amount == null || amount < 0) {
      _message('先填写有效价格');
      return;
    }
    setState(() => _busy = true);
    try {
      final rate = await _catalog.cnyRate(_currency);
      _priceCny.text = (amount * rate).toStringAsFixed(2);
      if (mounted) _message('已按当前汇率估算，可手动调整');
    } catch (error) {
      if (mounted) _message('汇率获取失败，请手动填写人民币折算金额');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final price = _price.text.trim().isEmpty
        ? null
        : double.tryParse(_price.text.trim());
    final priceCny = _currency == 'CNY'
        ? price
        : double.tryParse(_priceCny.text.trim());
    if (price != null &&
        (!price.isFinite || price < 0 || price > 9999999999.99)) {
      _message('请输入有效价格');
      return;
    }
    if (_currency != 'CNY' &&
        price != null &&
        (priceCny == null ||
            !priceCny.isFinite ||
            priceCny < 0 ||
            priceCny > 9999999999.99)) {
      _message('请填写人民币折算金额，用于统计');
      return;
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _busy = true);
    final item = CollectionItem(
      id: widget.initial?.id ?? const Uuid().v4(),
      userId: user.id,
      name: _name.text.trim(),
      category: _category,
      status: _status,
      coverImage: widget.initial?.coverImage,
      description: _description.text.trim(),
      purchaseDate: _purchaseDate,
      price: price,
      currency: _currency,
      priceCny: priceCny,
      gamePlatform: _platform,
      gameContentType: _contentType,
      gameEdition: _edition,
      gamePlayStatus: _playStatus,
      createdAt: widget.initial?.createdAt ?? DateTime.now().toUtc(),
    );
    try {
      final saved = widget.initial == null
          ? await widget.repository.create(item, _newCover)
          : await widget.repository.update(
              item,
              newCover: _newCover,
              removeCover: _removeCover,
            );
      if (mounted) Navigator.of(context).pop(saved);
    } catch (error) {
      if (mounted) _message('保存失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _priceCny.dispose();
    super.dispose();
  }

  Widget _choice(
    String label,
    String? value,
    List<String> values,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: values
        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
        .toList(),
    onChanged: _busy ? null : onChanged,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.initial == null ? '添加收藏' : '编辑收藏')),
    body: Form(
      key: _formKey,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AspectRatio(
                  aspectRatio: 1.7,
                  child: _preview != null
                      ? Image.memory(_preview!, fit: BoxFit.contain)
                      : (!_removeCover && widget.initial?.coverImage != null)
                      ? PrivateCover(
                          imageUrl: widget.initial!.coverImage,
                          images: widget.images,
                        )
                      : const ColoredBox(
                          color: Color(0xFFE5EAE4),
                          child: Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 54,
                          ),
                        ),
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _pickCover(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('选择图片'),
                  ),
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _pickCover(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('拍照识别'),
                  ),
                  if (_preview != null || widget.initial?.coverImage != null)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _newCover = null;
                              _preview = null;
                              _removeCover = true;
                            }),
                      child: const Text('移除图片'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: '名称',
                  suffixIcon: IconButton(
                    tooltip: '搜索资料',
                    icon: const Icon(Icons.search),
                    onPressed: _busy ? null : _searchCatalog,
                  ),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请输入名称' : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _choice(
                      '分类',
                      _category,
                      _categories,
                      (v) => setState(() => _category = v ?? _category),
                    ),
                  ),
                  IconButton(
                    tooltip: '添加分类',
                    onPressed: _busy ? null : _addCategory,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              if (_category == '游戏') ...[
                const SizedBox(height: 14),
                _choice(
                  '平台',
                  _platform,
                  gamePlatforms,
                  (v) => setState(() => _platform = v),
                ),
                const SizedBox(height: 14),
                _choice(
                  '内容类型',
                  _contentType,
                  gameContentTypes,
                  (v) => setState(() => _contentType = v),
                ),
                const SizedBox(height: 14),
                _choice(
                  '版本类型',
                  _edition,
                  gameEditions,
                  (v) => setState(() => _edition = v),
                ),
                const SizedBox(height: 14),
                _choice(
                  '游玩状态',
                  _playStatus,
                  gamePlayStatuses,
                  (v) => setState(() => _playStatus = v),
                ),
              ],
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: '收藏状态'),
                items: itemStatusLabels.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _status = v ?? _status),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _busy ? null : _chooseDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  _purchaseDate == null ? '选择购入日期' : dateOnly(_purchaseDate!),
                ),
              ),
              if (_purchaseDate != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _purchaseDate = null),
                    child: const Text('清除日期'),
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: '购入价格'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _choice(
                      '货币',
                      _currency,
                      currencies.keys.toList(),
                      (v) => setState(() => _currency = v ?? 'CNY'),
                    ),
                  ),
                ],
              ),
              if (_currency != 'CNY') ...[
                const SizedBox(height: 14),
                TextFormField(
                  controller: _priceCny,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: '折合人民币',
                    suffixIcon: IconButton(
                      tooltip: '按当前汇率估算',
                      onPressed: _busy ? null : _estimateCny,
                      icon: const Icon(Icons.currency_exchange),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextFormField(
                controller: _description,
                maxLines: 4,
                maxLength: 3000,
                decoration: const InputDecoration(
                  labelText: '描述 / 故事',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? '正在处理…' : '保存到收藏柜'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
