import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_theme.dart';
import '../core/app_ui.dart';
import '../core/price_display.dart';
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
  const CollectionScreen({super.key});
  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  final _client = Supabase.instance.client;
  late final _images = CoverImageService(_client);
  late final _itemsRepository = ItemRepository(_client, _images);
  late final _preferencesRepository = PreferencesRepository(_client, _images);
  late final _backup = BackupService(
    _client,
    _itemsRepository,
    _preferencesRepository,
    _images,
  );
  late final _auth = AuthService(_client);
  final _local = LocalWorkspaceStore();
  final _statsKey = GlobalKey<StatsScreenState>();
  PriceDisplay _priceDisplay = PriceDisplay.original;
  late Future<_HomeData> _data = _load();
  _HomeData? _current;
  final _search = TextEditingController();
  int _tab = 0;
  String? _category;
  String _sort = 'created_desc';
  bool _searchExpanded = false;
  bool _signingOut = false;
  bool _confirmingSignOut = false;
  int _loadRevision = 0;

  Future<_HomeData> _load({bool refresh = false}) async {
    final revision = ++_loadRevision;
    final results =
        await Future.wait<Object>([
          _itemsRepository.list(),
          _preferencesRepository.load(refresh: refresh),
          _preferencesRepository.categories(refresh: refresh),
          _local.loadPriceDisplay(_client.auth.currentUser!.id).catchError((
            Object error,
          ) {
            debugPrint('Local display preference could not be loaded: $error');
            return _priceDisplay;
          }),
        ]).catchError((Object error, StackTrace stack) {
          debugPrint('Collection load failed: $error');
          Error.throwWithStackTrace(error, stack);
        });
    final next = (
      items: results[0] as List<CollectionItem>,
      preferences: results[1] as UserPreferences,
      categories: results[2] as List<String>,
    );
    if (revision == _loadRevision) {
      _current = next;
      _priceDisplay = results[3] as PriceDisplay;
    }
    return next;
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
    setState(() {
      _current = (
        items: current.items,
        preferences: preferences,
        categories: List.of(categories),
      );
      _data = Future.value(_current!);
    });
  }

  Future<void> _applyItemChange(String id, CollectionItem? item) async {
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

  Future<void> _chooseSort() async {
    final sort = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Text(
                    '排序方式',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
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
          ),
        ),
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      centerTitle: false,
      title: Text(switch (_tab) {
        1 => '收藏统计',
        2 => '设置',
        _ => 'Dearshelf',
      }),
      actions: [
        if (_tab == 0) ...[
          IconButton(
            tooltip: '搜索收藏',
            isSelected: _searchExpanded,
            icon: const Icon(Icons.search_rounded),
            onPressed: () => setState(() => _searchExpanded = !_searchExpanded),
          ),
          IconButton(
            tooltip: '筛选和排序',
            icon: const Icon(Icons.filter_list_rounded),
            onPressed: _chooseSort,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.filled(
              tooltip: '添加收藏',
              icon: const Icon(Icons.add_rounded),
              onPressed: _add,
            ),
          ),
        ],
        if (_tab == 1) ...[
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
          return IndexedStack(
            index: _tab,
            children: [
              CollectionWall(
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
                onCategory: (value) => setState(() => _category = value),
                onOpen: _open,
                onRefresh: _reload,
              ),
              StatsScreen(key: _statsKey, items: data.items),
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
              ),
            ],
          );
        },
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (index) {
        FocusScope.of(context).unfocus();
        setState(() => _tab = index);
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.shelves), label: '展柜'),
        NavigationDestination(icon: Icon(Icons.bar_chart_rounded), label: '统计'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
      ],
    ),
  );
}
