import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('SearchResult 保留源信息与可选字段', () {
    final r = SearchResult(
      sourceId: 'com.example.x',
      sourceName: '某站',
      type: SourceType.magnet,
      title: '资源名',
      url: 'magnet:?xt=urn:btih:abc',
      extra: {'size': '1.2GB'},
    );
    expect(r.type, SourceType.magnet);
    expect(r.extra!['size'], '1.2GB');
  });

  test('SourceType 开放枚举可扩展', () {
    expect(
        SourceType.values.map((e) => e.name),
        containsAll(['pan', 'magnet', 'ed2k', 'book', 'music', 'game']));
  });

  test('SearchQuery 含关键词与页码', () {
    final q = SearchQuery(keyword: '测试', page: 1);
    expect(q.keyword, '测试');
    expect(q.page, 1);
  });
}
