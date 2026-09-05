import 'package:core/core.dart';
import 'package:source_engine/source_engine.dart';
import 'package:test/test.dart';

void main() {
  test('适配器包装洛雪脚本为内部 SearchableSource', () async {
    final js = FakeJsRuntime(scriptResults: {
      '__lxSearchTake':
          '{"isEnd":true,"list":[{"name":"测试词-LX","singer":"a","url":"https://lx.com/1.mp3"}]}',
    });
    // 真实洛雪源形态：lx.on('request') + lx.request
    const lxJs = '''
      const EVENT_NAMES = { request: 'request', inited: 'inited' };
      lx.on(EVENT_NAMES.request, function({ source, action, info }) {
        return new Promise(function(resolve) {
          lx.request('https://api.example.com/search?kw=' + info.searchText, { method: 'GET' }, function(err, resp) {
            if (err) return resolve({ isEnd: true, list: [] });
            resolve({ isEnd: true, list: [{ name: info.searchText + '-LX', singer: 'a', url: 'https://lx.com/1.mp3' }] });
          });
        });
      });
      lx.send(EVENT_NAMES.inited, { status: true, sources: [] });
    ''';
    final adapter = LxAdapter(jsRuntime: js);
    final source = await adapter.wrap(lxJs, name: '洛雪测试源');

    expect(source.meta.type, SourceType.music);
    expect(source.meta.origin, 'lx');

    final results = await source.search(SearchQuery(keyword: '测试词'));
    expect(results, hasLength(1));
    expect(results[0].title, '测试词-LX');
  });
}
