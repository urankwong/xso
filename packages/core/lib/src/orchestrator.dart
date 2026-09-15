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

/// 并发扇出：所有启用源同时搜索，各源独立失败互不影响。
///
/// 当源总数超过 [maxConcurrent] 时，用信号量做滑动窗口限流，
/// 避免瞬间 100+ 请求压垮设备/网络/站点（触发限流/429）。
/// 源数 ≤ 上限时退化为全并发（零开销路径）。
class SearchOrchestrator {
  /// 最大并发源数
  static const maxConcurrent = 10;

  Stream<SearchEvent> search(
      List<SearchableSource> sources, SearchQuery query) {
    final controller = StreamController<SearchEvent>();
    final sem = _Semaphore(maxConcurrent);

    final futures = sources.map((s) async {
      await sem.acquire();
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
      } finally {
        sem.release();
      }
    }).toList();
    Future.wait(futures).whenComplete(controller.close);
    return controller.stream;
  }
}

/// 简单异步信号量：控制同时 in-flight 的源请求数。
class _Semaphore {
  int _permits;
  final _waiters = <Completer<void>>[];
  _Semaphore(this._permits);

  Future<void> acquire() {
    if (_permits > 0) {
      _permits--;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _permits++;
    }
  }
}
