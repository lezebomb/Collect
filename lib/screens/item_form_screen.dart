import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/collection_options.dart';
import '../core/app_ui.dart';
import '../models/catalog_candidate.dart';
import '../models/collection_item.dart';
import '../repositories/item_repository.dart';
import '../repositories/preferences_repository.dart';
import '../services/cover_image_service.dart';
import '../services/currency_rate_service.dart';
import '../services/game_search_service.dart';
import '../services/image_search_service.dart';
import '../services/ocr_service.dart';
import '../services/product_search_service.dart';
import '../services/search_http.dart';
import '../services/tavily_search_service.dart';
import '../widgets/item_game_section.dart';
import '../widgets/item_image_section.dart';
import '../widgets/item_price_section.dart';
import '../widgets/catalog_candidate_image.dart';
import '../widgets/catalog_selection_dialog.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/section_card.dart';

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
  final _games = GameSearchService();
  final _products = ProductSearchService();
  final _imageSearch = ImageSearchService(
    tavily: TavilySearchService(Supabase.instance.client),
  );
  final _ocr = OcrService();
  final _rates = CurrencyRateService();
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
  String? _loadingMessage;
  bool _categoriesLoading = true;

  void _beginLoading(String message) => setState(() {
    _busy = true;
    _loadingMessage = message;
  });

  void _endLoading() {
    if (mounted) {
      setState(() {
        _busy = false;
        _loadingMessage = null;
      });
    }
  }

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
      if (mounted &&
          widget.initial != null &&
          !_categories.contains(widget.initial!.category)) {
        setState(
          () => _categories = [..._categories, widget.initial!.category],
        );
      }
    } finally {
      if (mounted) setState(() => _categoriesLoading = false);
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
    if (!mounted) return;
    _beginLoading('正在识别图片中的文字…');
    try {
      final lines = await _ocr.recognize(image);
      if (!mounted) return;
      if (lines.isEmpty) {
        _message('没有识别到文字，请手动填写或搜索');
        return;
      }
      final chosen = <String>{};
      setState(() => _loadingMessage = null);
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('选择组成名称的文字'),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.sizeOf(context).height * .5,
              child: ListView(
                children: lines
                    .map(
                      (line) => CheckboxListTile(
                        value: chosen.contains(line),
                        title: Text(line),
                        onChanged: (checked) => update(() {
                          if (checked == true) {
                            chosen.add(line);
                          } else {
                            chosen.remove(line);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: chosen.isEmpty
                    ? null
                    : () => Navigator.pop(
                        context,
                        lines.where(chosen.contains).join(' '),
                      ),
                child: const Text('搜索'),
              ),
            ],
          ),
        ),
      );
      if (selected != null && mounted) {
        if (selected.length > 160) {
          _message('识别文字太长，请减少选择或手动输入名称');
          return;
        }
        if (_name.text.trim().isEmpty && selected.length <= 120) {
          _name.text = selected;
        }
        await _searchCatalog(queryOverride: selected);
      }
    } catch (error) {
      if (mounted) _message('识别失败：$error');
    } finally {
      _endLoading();
    }
  }

  Future<void> _searchCatalog({String? queryOverride}) async {
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    final query = (queryOverride ?? _name.text).trim();
    if (query.isEmpty) {
      _message('先输入要搜索的名称');
      return;
    }
    _beginLoading('正在搜索图片和资料…');
    try {
      final searches = await Future.wait([
        if (_category == '游戏')
          _games.search(query)
        else
          _products.search(query),
        _imageSearch.search(query),
      ]).timeout(const Duration(seconds: 11));
      final found = searches.expand((items) => items);
      final unique = <String, CatalogCandidate>{};
      for (final candidate in found) {
        unique.putIfAbsent(candidate.imageUrl, () => candidate);
      }
      final results = unique.values.toList()
        ..sort(
          (a, b) =>
              _candidateScore(b, query).compareTo(_candidateScore(a, query)),
        );
      if (!mounted) return;
      setState(() => _loadingMessage = null);
      if (results.isEmpty) {
        final alternate = await _promptSearchTerm(query);
        if (alternate != null) await _searchCatalog(queryOverride: alternate);
        return;
      }
      final selected = await showModalBottomSheet<Object>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .78,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Column(
                    children: [
                      Text(
                        '为“$query”选择图片',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      const Text('先选图片，再决定是否使用结果名称'),
                      TextButton(
                        onPressed: () => Navigator.pop(context, 'refine'),
                        child: const Text('换个关键词搜索（不改收藏名称）'),
                      ),
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
                          childAspectRatio: .80,
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
                                child: CatalogCandidateImage(
                                  candidate: result,
                                  images: _imageSearch,
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
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      result.source,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ],
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
      if (selected == 'refine' && mounted) {
        final alternate = await _promptSearchTerm(query);
        if (alternate != null) await _searchCatalog(queryOverride: alternate);
        return;
      }
      if (selected is! CatalogCandidate || !mounted) return;
      final action = await showDialog<CatalogSelection>(
        context: context,
        builder: (_) => CatalogSelectionDialog(title: selected.title),
      );
      if (action == null || !mounted) return;
      try {
        if (action.useImage) {
          _beginLoading('正在下载封面图片…');
          final cover = await _imageSearch.download(selected);
          await _setCover(cover);
        }
        if (!mounted) return;
        if (action.useTitle) _name.text = selected.title;
      } catch (error) {
        debugPrint('Catalog image download failed: $error');
        if (mounted) _message('图片下载失败，请选择另一张');
      }
    } catch (error) {
      if (mounted) _message('搜索失败，请继续手动填写：$error');
    } finally {
      _endLoading();
    }
  }

  Future<String?> _promptSearchTerm(String previous) async {
    if (!mounted) return null;
    var entered = previous;
    final term = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('换个关键词搜索'),
        content: TextFormField(
          initialValue: previous,
          onChanged: (value) => entered = value.trim(),
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '搜索关键词',
            helperText: '可输入英文名；收藏名称会保留',
          ),
          onFieldSubmitted: (value) =>
              Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, entered),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    return term == null || term.runes.length < 2 ? null : term;
  }

  int _candidateScore(CatalogCandidate candidate, String query) {
    final title = normalizedTitle(candidate.title);
    final term = normalizedTitle(query);
    var score = candidate.officialTitle ? 30 : 0;
    if (candidate.source.startsWith('Tavily')) score += 20;
    if (title == term) {
      score += 100;
    } else if (title.startsWith(term)) {
      score += 70;
    } else if (title.contains(term)) {
      score += 45;
    }
    if (candidate.description.isNotEmpty) score += 5;
    return score;
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
    if (!mounted) return;
    _beginLoading('正在添加分类…');
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
    } finally {
      _endLoading();
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
    _beginLoading('正在查询汇率…');
    try {
      final rate = await _rates.cnyRate(_currency);
      if (!mounted) return;
      _priceCny.text = (amount * rate).toStringAsFixed(2);
      if (mounted) _message('已按当前汇率估算，可手动调整');
    } catch (error) {
      if (mounted) _message('汇率获取失败，请手动填写人民币折算金额');
    } finally {
      _endLoading();
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
    _beginLoading('正在保存收藏…');
    final item = CollectionItem(
      id: widget.initial?.id ?? const Uuid().v4(),
      userId: user.id,
      name: _name.text.trim(),
      category: _category,
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
      _endLoading();
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
    isExpanded: true,
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: values
        .map(
          (v) => DropdownMenuItem(
            value: v,
            child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: _busy ? null : onChanged,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.initial == null ? '添加收藏' : '编辑收藏')),
    body: LoadingOverlay(
      loading: _loadingMessage != null,
      message: _loadingMessage ?? '正在处理…',
      child: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: AppSpacing.page,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                if (_categoriesLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(),
                  ),
                ItemImageSection(
                  preview: _preview,
                  imageUrl: _removeCover ? null : widget.initial?.coverImage,
                  images: widget.images,
                  busy: _busy,
                  onGallery: () => _pickCover(ImageSource.gallery),
                  onCamera: () => _pickCover(ImageSource.camera),
                  onRemove: () => setState(() {
                    _newCover = null;
                    _preview = null;
                    _removeCover = true;
                  }),
                ),
                const SizedBox(height: AppSpacing.lg),
                SectionCard(
                  title: '基本信息',
                  icon: Icons.bookmark_outline_rounded,
                  child: Column(
                    children: [
                      TextFormField(
                        enabled: !_busy,
                        controller: _name,
                        maxLength: 120,
                        decoration: InputDecoration(
                          labelText: '名称',
                          suffixIcon: IconButton(
                            tooltip: '搜索资料',
                            icon: const Icon(Icons.search),
                            onPressed: _busy ? null : () => _searchCatalog(),
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
                    ],
                  ),
                ),
                if (_category == '游戏')
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.lg),
                    child: SectionCard(
                      title: '游戏信息',
                      icon: Icons.sports_esports_outlined,
                      child: ItemGameSection(
                        platform: _platform,
                        contentType: _contentType,
                        edition: _edition,
                        playStatus: _playStatus,
                        busy: _busy,
                        onPlatform: (v) => setState(() => _platform = v),
                        onContentType: (v) => setState(() => _contentType = v),
                        onEdition: (v) => setState(() => _edition = v),
                        onPlayStatus: (v) => setState(() => _playStatus = v),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                SectionCard(
                  title: '价格信息',
                  icon: Icons.payments_outlined,
                  child: ItemPriceSection(
                    purchaseDate: _purchaseDate,
                    price: _price,
                    priceCny: _priceCny,
                    currency: _currency,
                    busy: _busy,
                    onChooseDate: _chooseDate,
                    onClearDate: () => setState(() => _purchaseDate = null),
                    onCurrency: (v) => setState(() => _currency = v ?? 'CNY'),
                    onEstimateCny: _estimateCny,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SectionCard(
                  title: '描述 / 故事',
                  icon: Icons.notes_rounded,
                  child: TextFormField(
                    enabled: !_busy,
                    controller: _description,
                    maxLines: 4,
                    maxLength: 3000,
                    decoration: const InputDecoration(
                      hintText: '写下它的来历，或你喜欢它的理由…',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: LoadingButtonLabel(
                    loading: _busy,
                    label: _busy ? '正在处理…' : '保存到收藏柜',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
