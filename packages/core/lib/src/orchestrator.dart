import 'dart:async';
import 'package:core/src/models.dart';

enum SourceStatus { running, done, empty, failed }

/// 搜索事件流：先到先显示
sealed class SearchEvent {}

/// 某源返回结果
class SourceResultsEvent extends SearchEvent {
  final String sourceId;
  final List<SearchResult> results;
  SourceResultsEvent(this.sourceId, this.results);
}

/// 某源状态变化
class SourceStatusEvent extends SearchEvent {
  final String sourceId;
  final SourceStatus status;
  final String? message; // 失败原因
  SourceStatusEvent(this.sourceId, this.status, {this.message});
}

/// 搜索引擎抽象：Orchestrator 不依赖具体实现
abstract class SearchableSource {
  SourceMeta get meta;
  Future<List<SearchResult>> search(SearchQuery query);
}

/// 并发扇出：所有启用源同时搜索，各源独立失败互不影响
class SearchOrchestrator {
  Stream<SearchEvent> search(
      List<SearchableSource> sources, SearchQuery query) {
    final controller = StreamController<SearchEvent>();
    final futures = sources.map((s) async {
      try {
        controller.add(SourceStatusEvent(s.meta.id, SourceStatus.running));
        final results = await s.search(query);
        if (results.isEmpty) {
          controller.add(SourceStatusEvent(s.meta.id, SourceStatus.empty));
        } else {
          controller.add(SourceResultsEvent(s.meta.id, results));
          controller.add(SourceStatusEvent(s.meta.id, SourceStatus.done));
        }
      } catch (e) {
        controller.add(SourceStatusEvent(s.meta.id, SourceStatus.failed,
            message: e.toString()));
      }
    }).toList();
    Future.wait(futures).whenComplete(controller.close);
    return controller.stream;
  }
}
