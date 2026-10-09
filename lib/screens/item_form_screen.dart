import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../core/app_ui.dart';
import '../models/catalog_candidate.dart';
import '../models/collection_item.dart';
import '../repositories/item_repository.dart';
import '../repositories/preferences_repository.dart';
import '../services/cover_image_service.dart';
import '../services/local_workspace_store.dart';
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
import '../widgets/rounded_choice_field.dart';
import '../widgets/confirmation_dialog.dart';
import '../widgets/selection_sheet.dart';
import 'cover_crop_screen.dart';

class ItemFormScreen extends StatefulWidget {
  const ItemFormScreen({
    super.key,
    required this.repository,
    required this.images,
    required this.preferences,
    this.initial,
    this.drafts,
  });

  final ItemRepository repository;
  final CoverImageService images;
  final PreferencesRepository preferences;
  final CollectionItem? initial;
  final LocalWorkspaceStore? drafts;

  @override
  State<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends State<ItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final _games = GameSearchService();
  final _products = ProductSearchService();
  late final _imageSearch = ImageSearchService(
    tavily: TavilySearchService(widget.repository.client),
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
  late String? _category = widget.initial?.category;
  late String _currency = widget.initial?.currency ?? 'CNY';
  late String? _platform = widget.initial?.gamePlatform;
  late String? _contentType = widget.initial?.gameContentType;
  late String? _edition = widget.initial?.gamePlatform == 'PC'
      ? '数字版'
      : widget.initial?.gameEdition;
  late String? _playStatus = widget.initial?.gamePlayStatus;
  late DateTime? _purchaseDate = widget.initial?.purchaseDate;
  late List<String> _categories = {
    if (widget.initial != null) widget.initial!.category,
  }.toList();
  XFile? _newCover;
  Uint8List? _preview;
  Uint8List? _sourcePreview;
  bool _removeCover = false;
  bool _busy = false;
  String? _loadingMessage;
  bool _categoriesLoading = true;
  late final _drafts = widget.drafts ?? LocalWorkspaceStore();
  late final String _owner = widget.preferences.userId;
  late Map<String, dynamic> _baseline;
  bool _allowPop = false;
  bool _leaving = false;
  bool _restoredDraft = false;
  Map<String, dynamic>? _savedDraft;
  Map<String, dynamic>? _draftSnapshot;
  String _newItemId = const Uuid().v4();

  Map<String, dynamic> _fields() => {
    'name': _name.text,
    'description': _description.text,
    'price': _price.text,
    'price_cny': _priceCny.text,
    'category': _category,
    'currency': _currency,
    'platform': _platform,
    'content_type': _contentType,
    'edition': _edition,
    'play_status': _playStatus,
    'purchase_date': _purchaseDate?.toIso8601String(),
    'remove_cover': _removeCover,
    'cover_identity': _newCover == null ? null : identityHashCode(_newCover),
  };

  bool get _dirty => jsonEncode(_fields()) != jsonEncode(_baseline);
  bool get _showGameFields =>
      _category == '游戏' ||
      (widget.initial?.isGame == true && _category == widget.initial?.category);

  Future<void> _initializeForm() async {
    await _loadCategories();
    if (!mounted) return;
    _baseline = _fields();
    if (widget.initial == null) {
      try {
        final draft = await _drafts.loadDraft(_owner);
        if (draft != null && mounted) {
          _restoreDraft(draft);
        }
      } catch (error) {
        if (mounted) _message('读取草稿失败，原草稿仍保留：$error');
      }
    }
    if (mounted) {
      _endLoading();
      await _recoverLostImage();
    }
  }

  void _restoreDraft(Map<String, dynamic> draft) {
    final savedId = draft['draft_item_id'];
    if (savedId is String && RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(savedId)) {
      _newItemId = savedId;
    }
    final encodedCover = draft['cover_bytes'] as String?;
    final bytes = encodedCover == null ? null : base64Decode(encodedCover);
    if (bytes != null && bytes.length > CoverImageService.maxBytes) {
      throw const FormatException('草稿封面超过 10 MB');
    }
    final original = draft['original_cover_bytes'] as String?;
    final source = original == null ? bytes : base64Decode(original);
    if (source != null && source.length > CoverImageService.maxBytes) {
      throw const FormatException('草稿原图超过 10 MB');
    }
    setState(() {
      _name.text = draft['name'] as String? ?? '';
      _description.text = draft['description'] as String? ?? '';
      _price.text = draft['price'] as String? ?? '';
      _priceCny.text = draft['price_cny'] as String? ?? '';
      _category = draft['category'] as String?;
      _currency = draft['currency'] as String? ?? 'CNY';
      _platform = draft['platform'] as String?;
      _contentType = draft['content_type'] as String?;
      _edition = _platform == 'PC' ? '数字版' : draft['edition'] as String?;
      _playStatus = draft['play_status'] as String?;
      _purchaseDate = DateTime.tryParse(
        draft['purchase_date'] as String? ?? '',
      );
      _removeCover = draft['remove_cover'] == true;
      if (_category != null && !_categories.contains(_category)) {
        _categories = [..._categories, _category!];
      }
      _preview = bytes;
      _sourcePreview = source;
      _newCover = bytes == null
          ? null
          : XFile.fromData(
              bytes,
              path: draft['cover_name'] as String? ?? 'draft.jpg',
              mimeType: draft['cover_mime'] as String?,
            );
      _restoredDraft = true;
      _savedDraft = draft;
      _draftSnapshot = _fields();
    });
  }

  Future<void> _showDrafts() async {
    final draft = _savedDraft;
    if (draft == null || _busy) return;
    FocusScope.of(context).unfocus();
    final action = await showSelectionSheet<String>(
      context: context,
      title: '草稿箱',
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.input)),
            ),
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(
              (draft['name'] as String?)?.trim().isNotEmpty == true
                  ? draft['name'] as String
                  : '未命名的收藏',
            ),
            subtitle: const Text('点击载入已保存的草稿'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.pop(context, 'restore'),
          ),
          const SizedBox(height: 8),
          const Text('草稿已自动载入，可以继续编辑。', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => Navigator.pop(context, 'delete'),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('删除已保存的草稿'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'restore') {
      if (jsonEncode(_fields()) != jsonEncode(_draftSnapshot)) {
        final confirmed = await confirmAction(
          context,
          title: '用草稿替换当前填写的内容吗',
          confirm: '载入草稿',
        );
        if (confirmed != true || !mounted) return;
      }
      try {
        _restoreDraft(draft);
      } catch (_) {
        _message('读取草稿失败，当前内容仍保留');
      }
    } else if (action == 'delete') {
      final confirmed = await confirmAction(
        context,
        title: '删除已保存的草稿吗',
        content: '当前页面已填写的内容会保留。',
        confirm: '删除',
      );
      if (confirmed != true || !mounted) return;
      _beginLoading('正在删除草稿…');
      try {
        await _drafts.clearDraft(_owner);
        if (mounted) {
          setState(() {
            _savedDraft = null;
            _draftSnapshot = null;
            _restoredDraft = false;
          });
        }
      } catch (_) {
        if (mounted) _message('删除草稿失败，原草稿仍保留');
      } finally {
        _endLoading();
      }
    }
  }

  Future<void> _close([CollectionItem? saved]) async {
    if (!mounted) return;
    setState(() => _allowPop = true);
    // Let PopScope publish canPop before asking Navigator to close the route.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(saved);
  }

  Future<void> _leave() async {
    if (_busy || _leaving || _allowPop) return;
    _leaving = true;
    try {
      if (!_dirty && !_restoredDraft) {
        await _close();
        return;
      }
      FocusScope.of(context).unfocus();
      final save = await confirmAction(
        context,
        title: widget.initial == null ? '是否要保存至草稿箱' : '是否保存修改',
        confirm: '保存',
        cancel: '不保存',
      );
      if (save == null || !mounted) return;
      if (widget.initial != null) {
        if (save) {
          await _save();
        } else {
          await _close();
        }
        return;
      }
      _beginLoading(save ? '正在保存草稿，请稍候...' : '正在移除草稿，请稍候...');
      try {
        if (save) {
          await _drafts.saveDraft(_owner, {
            'draft_item_id': _newItemId,
            ..._fields()..remove('cover_identity'),
            'version': 1,
            if (_preview != null) 'cover_bytes': base64Encode(_preview!),
            if (_sourcePreview != null)
              'original_cover_bytes': base64Encode(_sourcePreview!),
            if (_newCover != null) 'cover_name': _newCover!.name,
            if (_newCover?.mimeType != null) 'cover_mime': _newCover!.mimeType,
          });
        } else {
          await _drafts.clearDraft(_owner);
        }
        await _close();
      } catch (error) {
        if (mounted) _message('草稿处理失败，当前内容仍保留：$error');
      } finally {
        _endLoading();
      }
    } finally {
      _leaving = false;
    }
  }

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
    _baseline = _fields();
    _busy = true;
    _loadingMessage = widget.initial == null ? '正在读取草稿…' : '正在读取收藏…';
    _initializeForm();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await widget.preferences.categories(
        itemCategories: [if (widget.initial != null) widget.initial!.category],
      );
      if (mounted) {
        setState(() {
          _categories = categories;
          if (!_categories.contains(_category)) {
            _category = _categories.firstOrNull;
          }
        });
      }
    } catch (error) {
      if (mounted) _message('分类加载失败：$error');
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
    await _cropCover(bytes);
  }

  Future<void> _cropCover(Uint8List bytes) async {
    if (!mounted) return;
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => CoverCropScreen(bytes: bytes)),
    );
    if (cropped == null || !mounted) return;
    if (cropped.length > CoverImageService.maxBytes) {
      _message('裁剪后的封面超过 10 MB，请缩小取景范围');
      return;
    }
    setState(() {
      _newCover = XFile.fromData(
        cropped,
        path: 'cover.png',
        mimeType: 'image/png',
      );
      _preview = cropped;
      _sourcePreview = bytes;
      _removeCover = false;
    });
  }

  Future<void> _adjustCover() async {
    if (_busy) return;
    var bytes = _sourcePreview ?? _preview;
    if (bytes == null && widget.initial?.coverImage != null && !_removeCover) {
      _beginLoading('正在读取封面…');
      try {
        final original = widget.initial!.coverImage!;
        final signed = await widget.images.signedUrl(original);
        if (signed == null) throw StateError('封面不可用');
        final cached = await widget.images.imageCache.getSingleFile(
          signed,
          key: widget.images.cacheKey(original),
        );
        bytes = await cached.readAsBytes();
      } catch (_) {
        if (mounted) _message('封面读取失败，请重试或从相册选择');
      } finally {
        _endLoading();
      }
    }
    if (bytes != null && mounted) {
      if (bytes.length > CoverImageService.maxBytes) {
        _message('图片不能超过 10 MB');
        return;
      }
      await _cropCover(bytes);
    }
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
      final selected = await showSelectionSheet<Object>(
        context: context,
        heightFraction: .78,
        scrollable: false,
        builder: (context) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
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
            ),
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: .80,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
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
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }, childCount: results.length),
              ),
            ),
          ],
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
    if (_busy || _allowPop) return;
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
    final user = widget.repository.client.auth.currentUser;
    if (user == null) return;
    _beginLoading(widget.initial == null ? '正在保存收藏…' : '正在保存修改…');
    final item = CollectionItem(
      id: widget.initial?.id ?? _newItemId,
      userId: user.id,
      name: _name.text.trim(),
      category: _category!,
      coverImage: widget.initial?.coverImage,
      description: _description.text.trim(),
      purchaseDate: _purchaseDate,
      price: price,
      currency: _currency,
      priceCny: priceCny,
      gamePlatform: _platform,
      gameContentType: _contentType,
      gameEdition: _platform == 'PC' ? '数字版' : _edition,
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
      if (widget.initial == null) {
        try {
          await _drafts.clearDraft(_owner);
        } catch (error) {
          if (mounted) _message('收藏已保存，但草稿清理失败：$error');
        }
      }
      await _close(saved);
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
  ) => RoundedChoiceField(
    label: label,
    value: value,
    values: values,
    validator: (v) => v == null ? '请选择或添加分类' : null,
    onChanged: _busy ? null : onChanged,
  );

  @override
  Widget build(BuildContext context) => PopScope<CollectionItem>(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _leave),
        title: Text(widget.initial == null ? '添加收藏' : '编辑收藏'),
        actions: [
          if (widget.initial == null && _savedDraft != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: _busy ? null : _showDrafts,
                style: TextButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary
                      .withValues(alpha: .08),
                ),
                icon: const Icon(Icons.inventory_2_outlined, size: 20),
                label: const Text('草稿箱'),
              ),
            ),
        ],
      ),
      body: LoadingOverlay(
        loading: _loadingMessage == '正在保存收藏…' || _loadingMessage == '正在保存修改…',
        message: _loadingMessage ?? '正在保存收藏…',
        child: Form(
          key: _formKey,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: AppSpacing.page,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  if (_loadingMessage != null &&
                      _loadingMessage != '正在保存收藏…' &&
                      _loadingMessage != '正在保存修改…')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          const LinearProgressIndicator(minHeight: 2),
                          const SizedBox(height: 6),
                          Text(
                            _loadingMessage!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
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
                    onAdjust: _adjustCover,
                    onRemove: () => setState(() {
                      _newCover = null;
                      _preview = null;
                      _sourcePreview = null;
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
                              icon: _busy && _loadingMessage != null
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.search),
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
                                (v) =>
                                    setState(() => _category = v ?? _category),
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
                  if (_showGameFields)
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
                          onPlatform: (v) => setState(() {
                            _platform = v;
                            if (v == 'PC') _edition = '数字版';
                          }),
                          onContentType: (v) =>
                              setState(() => _contentType = v),
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
                    title: '简介',
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
                      label: _busy
                          ? (_loadingMessage ?? '正在选择图片…')
                          : widget.initial == null
                          ? '保存到收藏柜'
                          : '保存修改',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
