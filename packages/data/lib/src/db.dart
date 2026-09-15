import 'package:drift/drift.dart';
import 'dao/favorite_dao.dart';
import 'dao/history_dao.dart';
import 'dao/recent_dao.dart';

part 'db.g.dart';

class Favorites extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sourceId => text()();
  TextColumn get sourceName => text()();
  TextColumn get type => text()(); // SourceType.name
  TextColumn get title => text()();
  TextColumn get url => text()();
  TextColumn get extractCode => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDead => boolean().withDefault(const Constant(false))();
}

class Histories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get keyword => text()();
  DateTimeColumn get searchedAt => dateTime().withDefault(currentDateAndTime)();
}

/// 最近使用记录（阅读/播放），供 AI 对话「打开最近读的书 / 播放最近听的歌」
/// 与「最近阅读 / 最近播放」常规入口查询。按 kind + 时间倒序取最近 N 条。
class RecentItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sourceId => text()();
  TextColumn get sourceName => text()();

  /// 'read'（阅读）| 'play'（播放）
  TextColumn get kind => text()();
  TextColumn get title => text()();
  TextColumn get url => text()();
  TextColumn get extractCode => text().nullable()();
  DateTimeColumn get usedAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(
  tables: [Favorites, Histories, RecentItems],
  daos: [FavoriteDao, HistoryDao, RecentDao],
)
class AppDb extends _$AppDb {
  AppDb(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(recentItems);
          }
        },
      );
}
