import 'package:drift/native.dart';
import 'package:data/data.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  late AppDb db;

  setUp(() {
    db = AppDb(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
  });

  test('收藏：增删查、按类型筛选', () async {
    final r = SearchResult(
        sourceId: 's1',
        sourceName: '源',
        type: SourceType.pan,
        title: 't',
        url: 'https://pan.baidu.com/s/1a');
    await db.favoriteDao.add(r, code: 'ab12');
    expect((await db.favoriteDao.all()).length, 1);

    final panOnly = await db.favoriteDao.byType(SourceType.pan);
    expect(panOnly.length, 1);
    expect(panOnly.first.extractCode, 'ab12');

    await db.favoriteDao.remove(panOnly.first.id);
    expect((await db.favoriteDao.all()), isEmpty);
  });

  test('历史：记录关键词、去重置顶、清空', () async {
    await db.historyDao.record('关键词A');
    await db.historyDao.record('关键词B');
    await db.historyDao.record('关键词A'); // 重复→置顶不重复
    final all = await db.historyDao.all();
    expect(all.length, 2);
    expect(all.first.keyword, '关键词A');
    await db.historyDao.clear();
    expect(await db.historyDao.all(), isEmpty);
  });

  test('收藏活性：标记失效状态', () async {
    final r = SearchResult(
        sourceId: 's',
        sourceName: 'n',
        type: SourceType.pan,
        title: 't',
        url: 'https://pan.quark.cn/s/x');
    await db.favoriteDao.add(r);
    final f = (await db.favoriteDao.all()).first;
    await db.favoriteDao.markDead(f.id, dead: true);
    expect((await db.favoriteDao.all()).first.isDead, isTrue);
  });
}
