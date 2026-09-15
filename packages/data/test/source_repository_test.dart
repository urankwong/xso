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

  test('updateRaw：换掉源内容但不动启用状态', () async {
    const oldRaw = '{"bookSourceName":"X","ruleSearch":{"name":"a@title"}}';
    const newRaw = '{"bookSourceName":"X","ruleSearch":{"name":"h3 a@title"}}';
    await repo.save('legado://x.com', format: 'legado', raw: oldRaw);

    // 用户把内置源禁用了 → 重新下发内容时这个状态必须保留
    await repo.setEnabled('legado://x.com', false);

    await repo.updateRaw('legado://x.com', raw: newRaw, name: 'X', type: 'novel');

    expect(await repo.readRaw('legado://x.com'), newRaw);
    final entry = (await repo.list()).first;
    expect(entry.enabled, isFalse, reason: '重新下发内置源不能把用户禁用的源重新打开');
    expect(entry.name, 'X');
    expect(entry.type, 'novel');
  });

  test('updateMeta：只改展示名/类型，内容保持不变', () async {
    const raw = '{"bookSourceName":"旧名字"}';
    await repo.save('legado://y.com', format: 'legado', raw: raw);

    await repo.updateMeta('legado://y.com', name: '新名字', type: 'novel');

    expect(await repo.readRaw('legado://y.com'), raw);
    expect((await repo.list()).first.name, '新名字');
  });
}
