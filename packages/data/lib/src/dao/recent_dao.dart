import 'package:drift/drift.dart';
import '../db.dart';
part 'recent_dao.g.dart';

@DriftAccessor(tables: [RecentItems])
class RecentDao extends DatabaseAccessor<AppDb> with _$RecentDaoMixin {
  RecentDao(super.db);

  /// 记录一次内容使用（阅读/播放）。同 (kind, url) 视为同一内容，刷新
  /// 元数据与时间置顶；不同 kind（如一首歌与一部同名书）互不干扰。
  Future<void> record({
    required String sourceId,
    required String sourceName,
    required String kind,
    required String title,
    required String url,
    String? extractCode,
  }) async {
    final now = DateTime.now();
    final existing = await (select(db.recentItems)
          ..where((r) => r.kind.equals(kind) & r.url.equals(url)))
        .getSingleOrNull();
    if (existing == null) {
      await into(db.recentItems).insert(RecentItemsCompanion.insert(
        sourceId: sourceId,
        sourceName: sourceName,
        kind: kind,
        title: title,
        url: url,
        extractCode: Value(extractCode),

      ));
    } else {
      await (update(db.recentItems)..where((r) => r.id.equals(existing.id)))
          .write(RecentItemsCompanion(
        sourceId: Value(sourceId),
        sourceName: Value(sourceName),
        title: Value(title),
        extractCode: Value(extractCode),
        usedAt: Value(now),
      ));
    }
  }

  /// 最近使用列表（按时间倒序）。[kind] 为空时不过滤。
  Future<List<RecentItem>> recent({String? kind, int limit = 10}) {
    final q = select(db.recentItems)
      ..orderBy([(r) => OrderingTerm.desc(r.usedAt)])
      ..limit(limit);
    if (kind != null) q.where((r) => r.kind.equals(kind));
    return q.get();
  }
}