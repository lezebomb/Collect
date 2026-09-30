import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../models/user_preferences.dart';
import '../repositories/item_repository.dart';
import '../repositories/preferences_repository.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/cover_image_service.dart';
import '../widgets/collection_card.dart';
import '../widgets/private_cover.dart';
import 'item_detail_screen.dart';
import 'item_form_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

typedef _HomeData = ({List<CollectionItem> items, UserPreferences preferences});

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
  late Future<_HomeData> _data = _load();
  final _search = TextEditingController();
  int _tab = 0;
  String? _category;
  String _sort = 'created_desc';

  Future<_HomeData> _load() async {
    try {
      final results = await Future.wait<Object>([
        _itemsRepository.list(),
        _preferencesRepository.load(),
      ]);
      return (
        items: results[0] as List<CollectionItem>,
        preferences: results[1] as UserPreferences,
      );
    } catch (error) {
      debugPrint('Collection load failed: $error');
      rethrow;
    }
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() {
      _data = next;
    });
    try {
      await next;
    } catch (_) {}
  }

  Future<void> _applyItemChange(String id, CollectionItem? item) async {
    final current = await _data;
    final items = current.items.where((existing) => existing.id != id).toList();
    if (item != null) items.insert(0, item);
    if (mounted) {
      setState(() {
        _data = Future.value((items: items, preferences: current.preferences));
      });
    }
  }

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<CollectionItem>(
      MaterialPageRoute(
        builder: (_) => ItemFormScreen(
          repository: _itemsRepository,
          images: _images,
          preferences: _preferencesRepository,
        ),
      ),
    );
    if (saved != null && mounted) await _applyItemChange(saved.id, saved);
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('收藏柜'),
      actions: [
        IconButton(
          tooltip: '退出登录',
          icon: const Icon(Icons.logout_rounded),
          onPressed: () async {
            try {
              await _auth.signOut();
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('退出失败：$error')));
              }
            }
          },
        ),
      ],
    ),
    body: SafeArea(
      child: FutureBuilder<_HomeData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('数据暂时没有加载出来'),
                  TextButton(onPressed: _reload, child: const Text('重试')),
                ],
              ),
            );
          }
          final data = snapshot.data!;
          return switch (_tab) {
            1 => StatsScreen(items: data.items),
            2 => SettingsScreen(
              repository: _preferencesRepository,
              backup: _backup,
              images: _images,
              onChanged: _reload,
            ),
            _ => _home(data.items, data.preferences),
          };
        },
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (index) => setState(() => _tab = index),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.shelves), label: '展柜'),
        NavigationDestination(icon: Icon(Icons.bar_chart_rounded), label: '统计'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
      ],
    ),
    floatingActionButton: _tab == 0
        ? FloatingActionButton(
            onPressed: _add,
            tooltip: '添加收藏',
            child: const Icon(Icons.add),
          )
        : null,
  );

  Widget _home(List<CollectionItem> all, UserPreferences preferences) {
    final categories = all.map((item) => item.category).toSet().toList()
      ..sort();
    final items = _visible(all);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 800
            ? 4
            : constraints.maxWidth >= 600
            ? 3
            : 2;
        return RefreshIndicator(
          onRefresh: _reload,
          child: CustomScrollView(
            slivers: [
              if (preferences.wallpaperUrl != null)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 135,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PrivateCover(
                          imageUrl: preferences.wallpaperUrl,
                          images: _images,
                        ),
                        const ColoredBox(color: Color(0x55000000)),
                        const Center(
                          child: Text(
                            '我的收藏柜',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: '搜索我的收藏',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButton<String?>(
                              isExpanded: true,
                              value: _category,
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('全部分类'),
                                ),
                                ...categories.map(
                                  (v) => DropdownMenuItem<String?>(
                                    value: v,
                                    child: Text(v),
                                  ),
                                ),
                              ],
                              onChanged: (v) => setState(() => _category = v),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _sort,
                              items: const [
                                DropdownMenuItem(
                                  value: 'created_desc',
                                  child: Text('添加时间：新到旧'),
                                ),
                                DropdownMenuItem(
                                  value: 'created_asc',
                                  child: Text('添加时间：旧到新'),
                                ),
                                DropdownMenuItem(
                                  value: 'purchase_desc',
                                  child: Text('购入时间：新到旧'),
                                ),
                                DropdownMenuItem(
                                  value: 'purchase_asc',
                                  child: Text('购入时间：旧到新'),
                                ),
                                DropdownMenuItem(
                                  value: 'price_desc',
                                  child: Text('价格：高到低'),
                                ),
                                DropdownMenuItem(
                                  value: 'price_asc',
                                  child: Text('价格：低到高'),
                                ),
                                DropdownMenuItem(
                                  value: 'name',
                                  child: Text('名称'),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _sort = v ?? _sort),
                            ),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('${items.length} / ${all.length} 件收藏'),
                      ),
                    ],
                  ),
                ),
              ),
              if (items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      all.isEmpty ? '收藏柜还是空的，点击 + 添加第一件收藏' : '没有符合条件的物品',
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 90),
                  sliver: SliverGrid.builder(
                    itemCount: items.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: .68,
                    ),
                    itemBuilder: (context, index) => CollectionCard(
                      item: items[index],
                      images: _images,
                      preferences: preferences,
                      onTap: () => _open(items[index]),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
