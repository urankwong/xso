import 'package:core/core.dart';
import 'package:source_engine/source_engine.dart';
import 'package:test/test.dart';

void main() {
  test('适配器包装为内部 SearchableSource 并桥接 search', () async {
    final js = FakeJsRuntime(scriptResults: {
      'JSON.stringify({name:': '{"name":"测试音源"}',
      '__mfSearchTake':
          '{"isEnd":true,"data":[{"title":"测试词-歌曲","artist":"歌手","url":"https://play.com/1.mp3"}]}',
    });
    const pluginJs = '''
      const axios = require("axios").default;
      module.exports = {
        platform: "测试音源",
        version: "1.0.0",
        async search(keyword, page, type) {
          const r = await axios.get("https://api.example.com/search?q=" + keyword);
          return { isEnd: true, data: r.data.list };
        }
      };
    ''';
    final adapter = MusicFreeAdapter(jsRuntime: js);
    final source = await adapter.wrap(pluginJs);

    expect(source.meta.type, SourceType.music);
    expect(source.meta.name, '测试音源');
    expect(source.meta.origin, 'musicfree');

    final results = await source.search(SearchQuery(keyword: '测试词'));
    expect(results, hasLength(1));
    expect(results[0].title, contains('测试词'));
    expect(results[0].url, 'https://play.com/1.mp3');
  });
}
