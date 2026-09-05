import 'dart:io';
import 'package:data/data.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late SourceRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sources');
    repo = SourceRepository(tmp.path);
  });
  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('保存/列出/启停/删除源', () async {
    const own = '{"meta":{"id":"com.a","name":"A","type":"magnet","version":1},'
        '"search":{"request":{"url":"https://a.com?q={{keyword}}"}}}';
    await repo.save('com.a', format: 'own', raw: own);

    final list = await repo.list();
    expect(list, hasLength(1));
    expect(list.first.id, 'com.a');
    expect(list.first.enabled, isTrue);

    await repo.setEnabled('com.a', false);
    expect((await repo.list()).first.enabled, isFalse);

    await repo.delete('com.a');
    expect(await repo.list(), isEmpty);
  });

  test('读取原始内容（导入时供检测器/适配器用）', () async {
    const js = 'module.exports = { platform: "x" };';
    await repo.save('musicfree-x', format: 'musicfree', raw: js);
    final entry = (await repo.list()).first;
    expect(entry.format, 'musicfree');
    expect(await repo.readRaw('musicfree-x'), js);
  });
}
