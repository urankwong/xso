import 'package:drift/drift.dart';
import '../db.dart';
part 'history_dao.g.dart';

@DriftAccessor(tables: [Histories])
class HistoryDao extends DatabaseAccessor<AppDb> with _$HistoryDaoMixin {
  HistoryDao(super.db);

  /// 记录关键词：已存在则更新时间置顶
  Future<void> record(String keyword) async {
    final existing = await (select(db.histories)
          ..where((h) => h.keyword.equals(keyword)))
        .getSingleOrNull();
    if (existing == null) {
      await into(db.histories)
          .insert(HistoriesCompanion.insert(keyword: keyword));
    } else {
      await (update(db.histories)..where((h) => h.id.equals(existing.id)))
          .write(HistoriesCompanion(searchedAt: Value(DateTime.now())));
    }
  }

  Future<List<History>> all() =>
      (select(db.histories)..orderBy([(h) => OrderingTerm.desc(h.searchedAt)]))
          .get();

  Future<void> clear() => delete(db.histories).go();
}
