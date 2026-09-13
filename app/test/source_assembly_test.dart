import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/providers/source_assembly.dart';
import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:source_engine/source_engine.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('asm');
  });
  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('自有格式源装配为引擎代理源', () async {
    final own = '{"meta":{"id":"com.a","name":"A","type":"magnet","version":1},'
        '"search":{"request":{"url":"https://a.com?q={{keyword}}"}}}';
    await SourceRepository(tmp.path).save('com.a', format: 'own', raw: own);

    final js = FakeJsRuntime();
    final engine = SourceEngine(
      jsRuntime: js,
      fetcher: (url,
              {method = 'GET', headers = const {}, charset = 'utf-8'}) async =>
          '',
    );
    final assembler = SourceAssembler(engine: engine, repoPath: tmp.path, jsRuntimeFactory: () => FakeJsRuntime());
    final sources = await assembler.loadEnabled();
    expect(sources, hasLength(1));
    expect(sources.first.meta.id, 'com.a');
  });

  test('损坏的源被跳过，不影响其他源装配', () async {
    await SourceRepository(tmp.path).save('bad', format: 'own', raw: '{ broken');
    await SourceRepository(tmp.path).save('com.b', format: 'own',
        raw: '{"meta":{"id":"com.b","name":"B","type":"pan","version":1},'
            '"search":{"request":{"url":"https://b.com?q={{keyword}}"}}}');

    final engine = SourceEngine(
      jsRuntime: FakeJsRuntime(),
      fetcher: (url,
              {method = 'GET', headers = const {}, charset = 'utf-8'}) async =>
          '',
    );
    final sources =
        await SourceAssembler(engine: engine, repoPath: tmp.path, jsRuntimeFactory: () => FakeJsRuntime()).loadEnabled();
    expect(sources, hasLength(1));
    expect(sources.first.meta.id, 'com.b');
  });

  test('洛雪源可被装配器解析出播放地址', () async {
    await SourceRepository(tmp.path).save('lx-one', format: 'lx', raw: '''
      lx.on('request', function() { return { isEnd: true, list: [] }; });
    ''');
    // 同一 runtime 实例复用：装配器按源建 runtime，测试里只需一套预置响应
    final js = FakeJsRuntime(scriptResults: {
      '__lxSearchTake':
          '{"isEnd":true,"list":[{"name":"洛雪歌","singer":"甲"}]}',
      '__lxInvokeTake': '{"data":"https://cdn.lx.com/real.mp3"}',
    });
    final engine = SourceEngine(
      jsRuntime: js,
      fetcher: (url,
              {method = 'GET', headers = const {}, charset = 'utf-8'}) async =>
          '',
    );
    final assembler = SourceAssembler(
        engine: engine, repoPath: tmp.path, jsRuntimeFactory: () => js);
    final sources = await assembler.loadEnabled();
    expect(sources, hasLength(1));

    final track = (await sources.first
        .search(SearchQuery(keyword: '洛雪歌'))).single;
    // 该源 search 不给直链，只能靠 musicUrl 现取
    expect(track.url, isEmpty);
    expect(
        await assembler.resolveMedia('lx-one', track),
        'https://cdn.lx.com/real.mp3');
  });
}
