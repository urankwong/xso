import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/providers/source_assembly.dart';
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
    final assembler = SourceAssembler(engine: engine, repoPath: tmp.path);
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
        await SourceAssembler(engine: engine, repoPath: tmp.path).loadEnabled();
    expect(sources, hasLength(1));
    expect(sources.first.meta.id, 'com.b');
  });
}
