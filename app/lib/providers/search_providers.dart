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
    final orchestrator = ref.read(orchestratorProvider);

    await _sub?.cancel();
    _sub = orchestrator
        .search(sources, SearchQuery(keyword: keyword))
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
      state = _copy(session);
    });
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

/// 结果排序方式：综合（保持各源返回顺序）/ 按类型分组
enum SearchSortMode { relevance, type }

final searchSortModeProvider =
    StateProvider<SearchSortMode>((ref) => SearchSortMode.relevance);

/// 结果按来源筛选：null = 全部；否则只显示该 sourceId 的结果。
///
/// 只在已返回的结果里过滤，**不触发重新搜索**
/// （结果都已经在内存里了，没必要再打一次网络）。
final searchSourceFilterProvider = StateProvider<String?>((ref) => null);
