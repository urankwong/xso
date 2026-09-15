import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import 'engine_providers.dart';
import 'data_providers.dart';

/// 搜索会话状态：结果按源分组 + 各源状态
class SearchSession {
  final String keyword;
  final Map<String, List<SearchResult>> resultsBySource = {};
  final Map<String, SourceStatus> statusBySource = {};
  final Map<String, String?> errorsBySource = {};
  bool finished = false;
  SearchSession(this.keyword);
}

class SearchSessionNotifier extends StateNotifier<SearchSession?> {
  final Ref ref;
  StreamSubscription<SearchEvent>? _sub;

  SearchSessionNotifier(this.ref) : super(null);

  Future<void> search(String keyword) async {
    if (keyword.trim().isEmpty) return;
    final session = SearchSession(keyword);
    state = session;

    // 记录搜索历史（重复关键词自动置顶）
    ref.read(appDbProvider).historyDao.record(keyword);

    final all = await ref.read(searchableSourcesProvider.future);
    // 类型筛选：只让 type 匹配的源参与（null = 全部）
    final typeFilter = ref.read(searchTypeFilterProvider);
    final sources = typeFilter == null
        ? all
        : all.where((s) => s.meta.type == typeFilter).toList();
    // 缓存包装：重复搜索/翻页回搜命中缓存，避免全量打网络
    final cache = ref.read(searchCacheProvider);
    final cached = sources.map((s) => _CachedSource(s, cache)).toList();
    final orchestrator = ref.read(orchestratorProvider);

    await _sub?.cancel();
    _sub = orchestrator
        .search(cached, SearchQuery(keyword: keyword))
        .listen((event) {
      switch (event) {
        case SourceResultsEvent(:final sourceId, :final results):
          session.resultsBySource[sourceId] = [
            ...(session.resultsBySource[sourceId] ?? []),
            ...results,
          ];
        case SourceStatusEvent(:final sourceId, :final status, :final message):
          session.statusBySource[sourceId] = status;
          if (message != null) session.errorsBySource[sourceId] = message;
      }
      state = _copy(session);
    }, onDone: () {
      session.finished = true;
      // 记录各源健康度统计（用于跨源排序优先级）
      final stats = ref.read(sourceStatsProvider);
      for (final entry in session.statusBySource.entries) {
        switch (entry.value) {
          case SourceStatus.done:
            stats.recordSuccess(entry.key);
          case SourceStatus.failed:
            stats.recordFailure(entry.key);
          default:
            break;
        }
      }
      state = _copy(session);
      // 后台预取网盘详情（不阻塞 UI，用户点开即见）
      _prefetchPanDetails(session);
    });
  }

  /// 后台预取网盘详情：搜索完成后对前几条网盘结果预取详情页，
  /// 提前发现网盘链接。总共最多 10 条，避免请求过量。
  void _prefetchPanDetails(SearchSession session) async {
    try {
      final assembler = await ref.read(sourceAssemblerProvider.future);
      final candidates = <MapEntry<String, SearchResult>>[];
      for (final entry in session.resultsBySource.entries) {
        for (final r
            in entry.value.where((r) => r.type == SourceType.pan).take(2)) {
          candidates.add(MapEntry(entry.key, r));
        }
        if (candidates.length >= 10) break;
      }
      if (candidates.isEmpty) return;
      final results = <String, List<SearchResult>>{};
      for (final c in candidates.take(10)) {
        try {
          final links = await assembler.fetchDetail(c.key, c.value);
          if (links.isNotEmpty) results['${c.key}:${c.value.url}'] = links;
        } catch (_) {}
      }
      if (results.isNotEmpty) {
        ref.read(panPrefetchProvider.notifier).state = results;
      }
    } catch (_) {}
  }

  static SearchSession _copy(SearchSession s) {
    final n = SearchSession(s.keyword);
    n.resultsBySource.addAll(s.resultsBySource);
    n.statusBySource.addAll(s.statusBySource);
    n.errorsBySource.addAll(s.errorsBySource);
    n.finished = s.finished;
    return n;
  }

  /// 清空当前会话（切换类型筛选 / 首页入口进入时调用，不自动发起搜索）
  Future<void> clear() async {
    await _sub?.cancel();
    state = null;
  }

  /// 中止当前搜索但保留已返回的结果（搜索页「停止」按钮）。
  /// 只是取消订阅，不会抹掉用户已经看到的结果。
  Future<void> cancel() async {
    await _sub?.cancel();
    _sub = null;
    final s = state;
    if (s == null) return;
    s.finished = true;
    state = _copy(s);
  }

  /// 是否存在进行中的搜索（用于决定要不要显示「停止」）
  bool get running => state != null && !state!.finished;
}

final searchSessionProvider =
    StateNotifierProvider<SearchSessionNotifier, SearchSession?>(
        (ref) => SearchSessionNotifier(ref));

/// 结果排序方式：综合（保持各源返回顺序）/ 按类型分组 / 按时间 / 按大小
enum SearchSortMode { relevance, type, time, size }

final searchSortModeProvider =
    StateProvider<SearchSortMode>((ref) => SearchSortMode.relevance);

/// 结果按来源筛选：null = 全部；否则只显示该 sourceId 的结果。
///
/// 只在已返回的结果里过滤，**不触发重新搜索**
/// （结果都已经在内存里了，没必要再打一次网络）。
final searchSourceFilterProvider = StateProvider<String?>((ref) => null);

/// 二次检索：在已返回结果中按关键词前端过滤（空串 = 不过滤）
final searchInResultProvider = StateProvider<String>((ref) => '');
// ─── 搜索结果缓存 ───────────────────────────────────────────────
// 重复搜索、翻页回搜、短时重搜不重复打网络。LRU + TTL，不缓存空结果与失败。

/// 搜索结果缓存实例（App 级单例，跨搜索持久化）
final searchCacheProvider = Provider<_SearchResultCache>(
    (ref) => _SearchResultCache(),
    name: 'searchCacheProvider');

/// 缓存包装源：透明拦截 search()，命中缓存直接返回，未命中才调真实源。
/// 失败（抛异常）不缓存，下次仍重试。
class _CachedSource implements SearchableSource {
  final SearchableSource inner;
  final _SearchResultCache cache;
  _CachedSource(this.inner, this.cache);

  @override
  SourceMeta get meta => inner.meta;

  @override
  Future<List<SearchResult>> search(SearchQuery query) async {
    final cached = cache.get(meta.id, query.keyword, query.page);
    if (cached != null) return cached;
    final results = await inner.search(query);
    cache.put(meta.id, query.keyword, query.page, results);
    return results;
  }
}

/// LRU + TTL 搜索结果缓存
class _SearchResultCache {
  static const _maxEntries = 80;
  static const _ttl = Duration(minutes: 10);

  final _cache = <_CacheKey, _CacheEntry>{};
  final _accessOrder = <_CacheKey>[];

  List<SearchResult>? get(String sourceId, String keyword, int page) {
    final key = _CacheKey(sourceId, keyword, page);
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.time) > _ttl) {
      _cache.remove(key);
      _accessOrder.remove(key);
      return null;
    }
    _accessOrder.remove(key);
    _accessOrder.add(key);
    return entry.results;
  }

  void put(String sourceId, String keyword, int page,
      List<SearchResult> results) {
    if (results.isEmpty) return;
    final key = _CacheKey(sourceId, keyword, page);
    _cache[key] = _CacheEntry(results, DateTime.now());
    _accessOrder.remove(key);
    _accessOrder.add(key);
    while (_accessOrder.length > _maxEntries) {
      final oldest = _accessOrder.removeAt(0);
      _cache.remove(oldest);
    }
  }

  void clear() {
    _cache.clear();
    _accessOrder.clear();
  }
}

class _CacheKey {
  final String sourceId;
  final String keyword;
  final int page;
  _CacheKey(this.sourceId, this.keyword, this.page);
  @override
  bool operator ==(Object other) =>
      other is _CacheKey &&
      sourceId == other.sourceId &&
      keyword == other.keyword &&
      page == other.page;
  @override
  int get hashCode => Object.hash(sourceId, keyword, page);
}

class _CacheEntry {
  final List<SearchResult> results;
  final DateTime time;
  _CacheEntry(this.results, this.time);
}
// ─── 源健康度统计 ───────────────────────────────────────────────
// 记录各源成功/失败次数，用于跨源排序优先级：好源结果前置，差源降级。
// 纯内存（冷启动从 0.5 开始），积累几轮搜索后即有意义。

final sourceStatsProvider = Provider<SourceStatsTracker>(
    (ref) => SourceStatsTracker(),
    name: 'sourceStatsProvider');

/// 网盘预取结果：`sourceId:itemUrl` → 网盘链接列表。
/// 搜索完成后后台预取，UI 列表项可提前展示"已发现 N 个网盘链接"。
final panPrefetchProvider =
    StateProvider<Map<String, List<SearchResult>>>((ref) => {});

class SourceStatsTracker {
  final Map<String, _SourceStat> _stats = {};

  /// 健康度 [0,1]：success/(success+fail)，冷启动 0.5。
  double healthOf(String sourceId) {
    final s = _stats[sourceId];
    if (s == null) return 0.5;
    final total = s.success + s.fail;
    if (total == 0) return 0.5;
    return s.success / total;
  }

  void recordSuccess(String sourceId) {
    final s = _stats.putIfAbsent(sourceId, () => _SourceStat());
    s.success++;
    // 衰减：超过 50 次后重置，避免老数据淹没近期表现
    if (s.success + s.fail > 50) s.reset();
  }

  void recordFailure(String sourceId) {
    final s = _stats.putIfAbsent(sourceId, () => _SourceStat());
    s.fail++;
    if (s.success + s.fail > 50) s.reset();
  }
}

class _SourceStat {
  int success = 0;
  int fail = 0;
  void reset() {
    success = 0;
    fail = 0;
  }
}
