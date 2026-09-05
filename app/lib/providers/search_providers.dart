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

    final sources = await ref.read(searchableSourcesProvider.future);
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
}

final searchSessionProvider =
    StateNotifierProvider<SearchSessionNotifier, SearchSession?>(
        (ref) => SearchSessionNotifier(ref));
