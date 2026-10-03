import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_theme.dart';
import '../core/app_ui.dart';
import '../core/price_display.dart';
import '../core/collection_snapshot.dart';
import '../models/collection_item.dart';
import '../models/user_preferences.dart';
import '../repositories/item_repository.dart';
import '../repositories/preferences_repository.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/cover_image_service.dart';
import '../services/local_workspace_store.dart';
import '../widgets/confirmation_dialog.dart';
import '../widgets/collection_wall.dart';
import '../widgets/selection_sheet.dart';
import 'item_detail_screen.dart';
import 'item_form_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

typedef _HomeData = ({
  List<CollectionItem> items,
  UserPreferences preferences,
  List<String> categories,
});

const _sortOptions = <String, String>{
  'created_desc': '添加时间：新到旧',
  'created_asc': '添加时间：旧到新',
  'purchase_desc': '购入时间：新到旧',
  'purchase_asc': '购入时间：旧到新',
  'price_desc': '价格：高到低',
  'price_asc': '价格：低到高',
  'name': '名称',
};

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({
    super.key,
    this.client,
    this.itemsRepository,
    this.preferencesRepository,
    this.images,
    this.local,
  });
  final SupabaseClient? client;
  final ItemRepository? itemsRepository;
  final PreferencesRepository? preferencesRepository;
  final CoverImageService? images;
  final LocalWorkspaceStore? local;
  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  late final _client = widget.client ?? Supabase.instance.client;
  late final _images = widget.images ?? CoverImageService(_client);
  late final _itemsRepository =
      widget.itemsRepository ?? ItemRepository(_client, _images);
  late final _preferencesRepository =
      widget.preferencesRepository ?? PreferencesRepository(_client, _images);
  late final _backup = BackupService(
    _client,
    _itemsRepository,
    _preferencesRepository,
    _images,
  );
  late final _auth = AuthService(_client);
  late final _local = widget.local ?? LocalWorkspaceStore();
  final _statsKey = GlobalKey<StatsScreenState>();
  PriceDisplay _priceDisplay = PriceDisplay.original;
  late Future<_HomeData> _data;
  _HomeData? _current;
  final _search = TextEditingController();
  int _tab = 0;
  String? _category;
  String _sort = 'created_desc';
  bool _searchExpanded = false;
  bool _signingOut = false;
  bool _confirmingSignOut = false;
  int _loadRevision = 0;
  int _itemEdits = 0;
  int _preferenceEdits = 0;
  int _categoryEdits = 0;
  bool _syncing = false;
  bool _syncError = false;
  bool _settingsReady = false;
  bool _selecting = false;
  final _selectedIds = <String>{};
  String? _managementMessage;
  int _managementDone = 0;
  int _managementTotal = 0;
  bool get _managing => _managementMessage != null;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  void _persist() {
    final current = _current;
    final owner = _client.auth.currentUser?.id;
    if (current == null || owner == null || !_settingsReady || _signingOut) {
      return;
    }
    unawaited(
      _local
          .saveCollectionSnapshot(
            owner,
            CollectionSnapshot(
              items: current.items,
              preferences: current.preferences,
              categories: current.categories,
            ),
          )
          .catchError((Object _) {
            debugPrint('Collection cache could not be saved');
          }),
    );
  }

  Future<_HomeData> _load({bool refresh = false}) async {
    final revision = ++_loadRevision;
    final owner = _client.auth.currentUser!.id;
    final itemEdits = _itemEdits;
    final preferenceEdits = _preferenceEdits;
    final categoryEdits = _categoryEdits;
    var items = _current?.items;
    var prefs = _current?.preferences ?? const UserPreferences();
    var categories = _current?.categories ?? <String>[];
    var itemsLoaded = false;
    var prefsLoaded = false;
    var categoriesLoaded = false;
    var prefsReady = _settingsReady;
    var categoriesReady = _settingsReady;
    var failed = false;
    _syncing = true;
    _syncError = false;

    void publish() {
      if (!mounted ||
          revision != _loadRevision ||
          items == null ||
          _client.auth.currentUser?.id != owner) {
        return;
      }
      setState(() {
        _current = (
          items: _itemEdits == itemEdits ? items! : _current!.items,
          preferences: _preferenceEdits == preferenceEdits
              ? prefs
              : _current!.preferences,
          categories: _categoryEdits == categoryEdits
              ? categories
              : _current!.categories,
        );
        _settingsReady = prefsReady && categoriesReady;
        _selectedIds.retainAll(_current!.items.map((item) => item.id));
      });
      _persist();
    }

    // Start cloud work and local restoration concurrently. The wall and stats
    // become usable as soon as items arrive, without waiting on settings.
    await Future.wait<void>([
      _itemsRepository
          .list(refresh: refresh)
          .then((value) {
            itemsLoaded = true;
            items = value;
            publish();
          })
          .catchError((Object _) {
            failed = true;
          }),
      _preferencesRepository
          .load(refresh: refresh)
          .then((value) {
            prefsLoaded = prefsReady = true;
            prefs = value;
            publish();
          })
          .catchError((Object _) {
            failed = true;
          }),
      _preferencesRepository
          .categories(refresh: refresh)
          .then((value) {
            categoriesLoaded = categoriesReady = true;
            categories = value;
            publish();
          })
          .catchError((Object _) {
            failed = true;
          }),
      if (!refresh && _current == null)
        _local
            .loadCollectionSnapshot(owner)
            .then((value) {
              if (value == null) return;
              if (!itemsLoaded) items = value.items;
              if (!prefsLoaded) prefs = value.preferences;
              if (!categoriesLoaded) categories = value.categories;
              prefsReady = categoriesReady = true;
              publish();
            })
            .catchError((Object _) {
              debugPrint('Collection cache unavailable; using cloud data');
            }),
      _local
          .loadPriceDisplay(owner)
          .then((value) {
            if (mounted && revision == _loadRevision) {
              setState(() => _priceDisplay = value);
            }
          })
          .catchError((Object _) {}),
    ]);
    if (mounted && revision == _loadRevision) {
      setState(() {
        _syncing = false;
        _syncError = failed;
      });
    }
    final current = _current;
    if (current == null) throw StateError('数据加载失败，请重试');
    return current;
  }

  Future<void> _reload() async {
    final next = _load(refresh: true);
    setState(() {
      _data = next;
    });
    try {
      await next;
    } catch (error) {
      if (mounted && _current != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('刷新失败：$error')));
      }
    }
  }

  void _settingsChanged(UserPreferences preferences, List<String> categories) {
    final current = _current;
    if (!mounted || current == null) return;
    ++_preferenceEdits;
    ++_categoryEdits;
    setState(() {
      _current = (
        items: current.items,
        preferences: preferences,
        categories: List.of(categories),
      );
      _data = Future.value(_current!);
    });
    _persist();
  }

  void _categoryRenamed(String oldName, String newName) {
    final current = _current;
    if (current == null) return;
    ++_itemEdits;
    _itemsRepository.categoryRenamed(oldName, newName);
    _statsKey.currentState?.categoryRenamed(oldName, newName);
    setState(() {
      if (_category == oldName) _category = newName;
      _current = (
        items: List.unmodifiable([
          for (final item in current.items)
            if (item.category == oldName)
              CollectionSnapshot.withCategory(item, newName)
            else
              item,
        ]),
        preferences: current.preferences,
        categories: current.categories,
      );
      _data = Future.value(_current!);
    });
  }

  void _itemsImported(List<CollectionItem> items) {
    final current = _current;
    if (!mounted || current == null) return;
    ++_itemEdits;
    setState(() {
      _current = (
        items: List.unmodifiable([...items, ...current.items]),
        preferences: current.preferences,
        categories: current.categories,
      );
      _data = Future.value(_current!);
    });
    _persist();
  }

  Future<void> _applyItemChange(String id, CollectionItem? item) async {
    ++_itemEdits;
    final current = _current ?? await _data;
    final items = current.items.where((existing) => existing.id != id).toList();
    if (item != null) items.insert(0, item);
    if (mounted) {
      setState(() {
        _current = (
          items: items,
          preferences: current.preferences,
          categories: current.categories,
        );
        _data = Future.value(_current!);
      });
    }
    _persist();
  }

  Future<void> _syncCategories() async {
    final categories = await _preferencesRepository.categories();
    if (mounted && _current != null) {
      _settingsChanged(_current!.preferences, categories);
    }
  }

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<CollectionItem>(
      MaterialPageRoute(
        builder: (_) => ItemFormScreen(
          repository: _itemsRepository,
          images: _images,
          preferences: _preferencesRepository,
          drafts: _local,
        ),
      ),
    );
    if (!mounted) return;
    if (saved != null) await _applyItemChange(saved.id, saved);
    await _syncCategories();
  }

  Future<void> _open(CollectionItem item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ItemDetailScreen(
          item: item,
          repository: _itemsRepository,
          images: _images,
          preferences: _preferencesRepository,
          onChanged: (updated) => _applyItemChange(item.id, updated),
        ),
      ),
    );
    if (mounted) await _syncCategories();
  }

  List<CollectionItem> _visible(List<CollectionItem> source) {
    final query = _search.text.trim().toLowerCase();
    final items = source
        .where(
          (item) =>
              (_category == null || item.category == _category) &&
              (query.isEmpty ||
                  item.name.toLowerCase().contains(query) ||
                  item.description.toLowerCase().contains(query)),
        )
        .toList();
    switch (_sort) {
      case 'created_asc':
        items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case 'purchase_desc':
        items.sort(
          (a, b) => (b.purchaseDate ?? DateTime(1900)).compareTo(
            a.purchaseDate ?? DateTime(1900),
          ),
        );
      case 'purchase_asc':
        items.sort(
          (a, b) => (a.purchaseDate ?? DateTime(9999)).compareTo(
            b.purchaseDate ?? DateTime(9999),
          ),
        );
      case 'price_desc':
        items.sort((a, b) => (b.priceCny ?? -1).compareTo(a.priceCny ?? -1));
      case 'price_asc':
        items.sort(
          (a, b) => (a.priceCny ?? double.infinity).compareTo(
            b.priceCny ?? double.infinity,
          ),
        );
      case 'name':
        items.sort((a, b) => a.name.compareTo(b.name));
      default:
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return items;
  }

  void _startSelection([CollectionItem? first]) {
    if (_managing) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _selecting = true;
      _selectedIds.clear();
      if (first != null) _selectedIds.add(first.id);
    });
  }

  void _finishSelection() {
    if (_managing) return;
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(CollectionItem item) {
    if (_managing) return;
    setState(() {
      if (!_selectedIds.add(item.id)) _selectedIds.remove(item.id);
    });
  }

  bool get _allVisibleSelected {
    final visible = _visible(_current?.items ?? []);
    return visible.isNotEmpty &&
        visible.every((item) => _selectedIds.contains(item.id));
  }

  void _selectAll() {
    if (_managing) return;
    final ids = _visible(_current?.items ?? []).map((item) => item.id);
    final clear = _allVisibleSelected;
    setState(() {
      if (clear) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  List<CollectionItem> get _selectedItems => (_current?.items ?? [])
      .where((item) => _selectedIds.contains(item.id))
      .toList();

  Future<void> _quickActions(CollectionItem item) async {
    if (_managing) return;
    if (_selecting) {
      _toggleSelection(item);
      return;
    }
    final action = await showSelectionSheet<String>(
      context: context,
      title: item.name,
      builder: (context) => Column(
        children: [
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
            leading: const Icon(Icons.checklist_rounded),
            title: const Text('批量管理'),
            onTap: () => Navigator.pop(context, 'select'),
          ),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
            leading: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              '删除收藏',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'select') _startSelection(item);
    if (action == 'delete') await _deleteTargets([item]);
  }

  Future<void> _changeSelectedCategory() async {
    final targets = _selectedItems;
    if (targets.isEmpty || _managing) return;
    final categories = _current!.categories;
    final category = await showSelectionSheet<String>(
      context: context,
      title: '修改 ${targets.length} 件藏品的分类',
      builder: (context) => categories.isEmpty
          ? const Text('还没有可用分类，请先到设置中添加分类。')
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in categories)
                  SelectionOption(
                    label: name,
                    selected: targets.every((item) => item.category == name),
                    onTap: () => Navigator.pop(context, name),
                  ),
              ],
            ),
    );
    if (category != null && mounted) {
      await _runManagement(targets, category: category);
    }
  }

  Future<void> _deleteTargets(List<CollectionItem> targets) async {
    if (targets.isEmpty || _managing) return;
    final confirmed = await confirmAction(
      context,
      title: targets.length == 1 ? '删除这件收藏？' : '删除选中的 ${targets.length} 件收藏？',
      content: targets.length == 1
          ? '“${targets.single.name}”及它的封面将从收藏柜中移除。'
          : '${targets.take(3).map((item) => '“${item.name}”').join('、')}${targets.length > 3 ? '等 ${targets.length} 件收藏' : ''}及它们的封面将从收藏柜中移除。',
      confirm: '删除',
    );
    if (confirmed == true && mounted) await _runManagement(targets);
  }

  void _applyBatch(List<CollectionItem> changed, Set<String> deleted) {
    final current = _current!;
    ++_itemEdits;
    final byId = {for (final item in changed) item.id: item};
    setState(() {
      _current = (
        items: [
          for (final item in current.items)
            if (!deleted.contains(item.id)) byId[item.id] ?? item,
        ],
        preferences: current.preferences,
        categories: current.categories,
      );
      _data = Future.value(_current!);
      _selectedIds.removeAll({...byId.keys, ...deleted});
    });
    _persist();
  }

  Future<void> _runManagement(
    List<CollectionItem> targets, {
    String? category,
  }) async {
    if (_managing) return;
    setState(() {
      _managementMessage = category == null ? '正在删除收藏，请稍候…' : '正在修改分类，请稍候…';
      _managementDone = 0;
      _managementTotal = targets.length;
    });
    var succeeded = false;
    try {
      for (
        var offset = 0;
        offset < targets.length;
        offset += ItemRepository.bulkChunkSize
      ) {
        final chunk = targets
            .skip(offset)
            .take(ItemRepository.bulkChunkSize)
            .toList();
        final ids = chunk.map((item) => item.id).toList();
        List<CollectionItem> changed = [];
        Set<String> deleted = {};
        if (category == null) {
          deleted = await _itemsRepository.deleteMany(ids);
        } else {
          changed = await _itemsRepository.changeCategory(ids, category);
        }
        if (!mounted) return;
        final confirmed = {...deleted, ...changed.map((item) => item.id)};
        _applyBatch(changed, deleted);
        setState(() => _managementDone += confirmed.length);
        if (confirmed.length != ids.length) {
          throw StateError('部分收藏未能处理');
        }
      }
      succeeded = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              category == null
                  ? '已删除 ${targets.length} 件收藏'
                  : '已将 ${targets.length} 件收藏移至“$category”',
            ),
          ),
        );
      }
    } catch (_) {
      // A response can fail after a write; reconcile before offering a retry.
      if (mounted) await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已确认完成 $_managementDone / ${targets.length} 件，请检查剩余藏品后重试。',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _managementMessage = null;
          if (succeeded) {
            _selecting = false;
            _selectedIds.clear();
          }
        });
      }
    }
  }

  Widget _managementBar() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: _managing
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LinearProgressIndicator(minHeight: 3),
                const SizedBox(height: 8),
                Text(
                  '$_managementMessage $_managementDone / $_managementTotal',
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : _changeSelectedCategory,
                    icon: const Icon(Icons.category_outlined),
                    label: const Text('修改分类'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () => _deleteTargets(_selectedItems),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('删除'),
                  ),
                ),
              ],
            ),
    ),
  );

  Future<void> _chooseSort() async {
    final sort = await showSelectionSheet<String>(
      context: context,
      title: '排序方式',
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in _sortOptions.entries)
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              selected: entry.key == _sort,
              selectedTileColor: AppTheme.accent.withValues(alpha: .08),
              title: Text(entry.value),
              trailing: entry.key == _sort
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(context, entry.key),
            ),
        ],
      ),
    );
    if (sort != null && mounted) setState(() => _sort = sort);
  }

  Future<void> _signOut() async {
    if (_signingOut || _confirmingSignOut) return;
    _confirmingSignOut = true;
    bool? confirmed;
    try {
      confirmed = await confirmAction(context, title: '确认要退出登录吗');
    } finally {
      _confirmingSignOut = false;
    }
    if (confirmed != true || !mounted) return;
    setState(() => _signingOut = true);
    try {
      final owner = _client.auth.currentUser!.id;
      // Keep local drafts, but remove cached cloud data after explicit logout.
      await _local.clearCollectionSnapshot(owner).catchError((Object _) {});
      await _auth.signOut();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('退出失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _setPriceDisplay(PriceDisplay value) async {
    final before = _priceDisplay;
    setState(() => _priceDisplay = value);
    try {
      await _local.savePriceDisplay(_client.auth.currentUser!.id, value);
    } catch (_) {
      if (mounted) setState(() => _priceDisplay = before);
      rethrow;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    unawaited(
      _images.clearSession().catchError((Object error) {
        debugPrint('Image cache cleanup failed: $error');
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_selecting && !_managing,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !_managing) _finishSelection();
    },
    child: Scaffold(
      appBar: AppBar(
        centerTitle: false,
        leading: _selecting
            ? IconButton(
                tooltip: '退出批量管理',
                onPressed: _managing ? null : _finishSelection,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: _selecting
            ? FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('已选 ${_selectedIds.length} 件'),
              )
            : Text(switch (_tab) {
                1 => '收藏统计',
                2 => '设置',
                _ => 'Dearshelf',
              }),
        actions: [
          if (_selecting)
            TextButton(
              onPressed: _managing ? null : _selectAll,
              child: Text(_allVisibleSelected ? '全不选' : '全选'),
            ),
          if (_tab == 0 && !_selecting) ...[
            IconButton(
              tooltip: '搜索收藏',
              isSelected: _searchExpanded,
              icon: const Icon(Icons.search_rounded),
              onPressed: _managing
                  ? null
                  : () => setState(() => _searchExpanded = !_searchExpanded),
            ),
            IconButton(
              tooltip: '筛选和排序',
              icon: const Icon(Icons.filter_list_rounded),
              onPressed: _managing ? null : _chooseSort,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton.filled(
                tooltip: '添加收藏',
                icon: const Icon(Icons.add_rounded),
                onPressed: _managing ? null : _add,
              ),
            ),
          ],
          if (_tab == 1) ...[
            IconButton(
              tooltip: '筛选藏品',
              icon: const Icon(Icons.checklist_rounded),
              onPressed: () => _statsKey.currentState?.chooseItems(),
            ),
            IconButton(
              tooltip: '筛选分类',
              icon: const Icon(Icons.category_outlined),
              onPressed: () => _statsKey.currentState?.chooseCategory(),
            ),
            IconButton(
              tooltip: '筛选年份',
              icon: const Icon(Icons.calendar_month_outlined),
              onPressed: () => _statsKey.currentState?.chooseYear(),
            ),
          ],
          if (_tab == 2)
            IconButton(
              tooltip: _signingOut ? '正在退出登录，请稍候...' : '退出登录',
              onPressed: _signingOut ? null : _signOut,
              icon: _signingOut
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<_HomeData>(
          future: _data,
          builder: (context, snapshot) {
            final data = _current ?? snapshot.data;
            if (data == null) {
              if (snapshot.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: _reload,
                    child: const Text('数据加载失败，点击重试'),
                  ),
                );
              }
              return const Center(child: CircularProgressIndicator());
            }
            final categories = {
              ...data.categories,
              ...data.items.map((item) => item.category),
            }.toList();
            return Column(
              children: [
                if (_syncing) const LinearProgressIndicator(minHeight: 2),
                if (_syncError)
                  TextButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.sync_problem_outlined, size: 16),
                    label: const Text('部分数据同步失败，点击重试'),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      AbsorbPointer(
                        absorbing: _managing,
                        child: CollectionWall(
                          items: _visible(data.items),
                          total: data.items.length,
                          categories: categories,
                          category: _category,
                          preferences: data.preferences,
                          priceDisplay: _priceDisplay,
                          images: _images,
                          search: _search,
                          searchExpanded: _searchExpanded,
                          onSearch: () => setState(() {}),
                          onCloseSearch: () {
                            FocusScope.of(context).unfocus();
                            setState(() {
                              _search.clear();
                              _searchExpanded = false;
                            });
                          },
                          onCategory: (value) =>
                              setState(() => _category = value),
                          onOpen: _selecting ? _toggleSelection : _open,
                          onLongPress: _quickActions,
                          onManage: _startSelection,
                          selectionMode: _selecting,
                          selectedIds: _selectedIds,
                          onRefresh: _reload,
                        ),
                      ),
                      StatsScreen(key: _statsKey, items: data.items),
                      if (!_settingsReady)
                        Center(
                          child: _syncing
                              ? const CircularProgressIndicator()
                              : TextButton(
                                  onPressed: _reload,
                                  child: const Text('设置加载失败，点击重试'),
                                ),
                        )
                      else
                        SettingsScreen(
                          repository: _preferencesRepository,
                          backup: _backup,
                          images: _images,
                          initialPreferences: data.preferences,
                          initialCategories: data.categories,
                          priceDisplay: _priceDisplay,
                          onPriceDisplayChanged: _setPriceDisplay,
                          onChanged: _settingsChanged,
                          onDataChanged: _reload,
                          onCategoryRenamed: _categoryRenamed,
                          onItemsImported: _itemsImported,
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: _selecting || _managing
          ? _managementBar()
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (index) {
                FocusScope.of(context).unfocus();
                setState(() => _tab = index);
              },
              destinations: const [
                NavigationDestination(icon: Icon(Icons.shelves), label: '展柜'),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_rounded),
                  label: '统计',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: '设置',
                ),
              ],
            ),
    ),
  );
}
