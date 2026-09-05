import 'package:core/core.dart';
import 'package:source_engine/source_engine.dart';
import 'package:test/test.dart';

void main() {
  test('适配器包装洛雪脚本为内部 SearchableSource', () async {
    final js = FakeJsRuntime(scriptResults: {
      '__lxSearch': '[{"title":"测试词-LX","artist":"a","url":"https://lx.com/1.mp3"}]',
    });
    const lxJs = '''
      const ENVIRONMENT = "lx-music-source";
      on("musicSearch", function(keywords, callback) {
        callback([{ title: keywords + "-LX", artist: "a", url: "https://lx.com/1.mp3" }]);
      });
    ''';
    final adapter = LxAdapter(jsRuntime: js);
    final source = await adapter.wrap(lxJs);

    expect(source.meta.type, SourceType.music);
    expect(source.meta.origin, 'lx');

    final results = await source.search(SearchQuery(keyword: '测试词'));
    expect(results, hasLength(1));
    expect(results[0].title, '测试词-LX');
  });
}
