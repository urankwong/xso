import 'package:source_engine/source_engine.dart';
import 'package:test/test.dart';

void main() {
  test('自有格式：合法 JSON 含 meta.id + search', () {
    const json = '{"meta":{"id":"a","name":"n","type":"magnet","version":1},'
        '"search":{"request":{"url":"https://a.com?q={{keyword}}"}}}';
    expect(detectSourceFormat(json), SourceFormat.own);
  });

  test('MusicFree：含 module.exports 且有 platform/search', () {
    const js = '''
      const { axios } = require("env");
      module.exports = {
        platform: "测试音源",
        version: "1.0.0",
        async search(keyword, page, type) { return { isEnd: true, data: [] }; }
      };
    ''';
    expect(detectSourceFormat(js), SourceFormat.musicfree);
  });

  test('洛雪：含 Environment 或 lx 全局', () {
    const js = '''
      const ENVIRONMENT = "lx-music-source";
      async function handleSearch(keywords) { return []; }
    ''';
    expect(detectSourceFormat(js), SourceFormat.lx);
  });

  test('Legado：JSON 含 bookSourceUrl', () {
    const json = '{"bookSourceUrl":"https://a.com","bookSourceName":"n"}';
    expect(detectSourceFormat(json), SourceFormat.legado);
  });

  test('无法识别抛 SourceFormatException', () {
    expect(() => detectSourceFormat('随便一段文本'),
        throwsA(isA<SourceFormatException>()));
  });
}
