import 'package:core/core.dart';
import 'package:source_engine/source_engine.dart';
import 'package:test/test.dart';

void main() {
  const pluginJs = '''
    const { axios } = require("env");
    module.exports = {
      platform: "测试音源",
      version: "1.0.0",
      async search(keyword, page, type) {
        return { isEnd: true, data: [
          { title: keyword + "-歌曲", artist: "歌手", url: "https://play.com/1.mp3" }
        ]};
      }
    };
  ''';

  test('适配器包装为内部 SearchableSource 并桥接 search', () async {
    final js = FakeJsRuntime(scriptResults: {
      'JSON.stringify({name: __mfModule.exports.platform})': '{"name":"测试音源"}',
      '__mfSearch':
          '{"isEnd":true,"data":[{"title":"测试词-歌曲","artist":"歌手","url":"https://play.com/1.mp3"}]}',
    });
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
