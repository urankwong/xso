import 'dart:async';
import 'package:core/core.dart';
import 'package:test/test.dart';

class FakeSource implements SearchableSource {
  @override
  final SourceMeta meta;
  final Future<List<SearchResult>> Function(SearchQuery) behavior;
  FakeSource(this.meta, this.behavior);

  @override
  Future<List<SearchResult>> search(SearchQuery query) => behavior(query);
}

SourceMeta metaOf(String id, SourceType t) =>
    SourceMeta(id: id, name: id, type: t, version: 1);

void main() {
  test('多源并发，结果带源状态流式回传', () async {
    final ok1 = FakeSource(
      metaOf('s1', SourceType.magnet),
      (q) async => [
        SearchResult(
            sourceId: 's1',
            sourceName: '源1',
            type: SourceType.magnet,
            title: 'a',
            url: 'u1'),
      ],
    );
    final fail = FakeSource(
      metaOf('s2', SourceType.pan),
      (q) async => throw Exception('boom'),
    );
    final empty = FakeSource(
      metaOf('s3', SourceType.ed2k),
      (q) async => [],
    );

    final events = await SearchOrchestrator()
        .search([ok1, fail, empty], SearchQuery(keyword: 'k'))
        .toList();

    final resultEvents = events.whereType<SourceResultsEvent>().toList();
    final statusEvents = events.whereType<SourceStatusEvent>().toList();

    expect(resultEvents.expand((e) => e.results), hasLength(1));
    expect(
      statusEvents.map((e) => e.status),
      containsAll([SourceStatus.done, SourceStatus.failed, SourceStatus.empty]),
    );
    expect(
      statusEvents.firstWhere((e) => e.status == SourceStatus.failed).message,
      contains('boom'),
    );
  });
}
