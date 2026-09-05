import 'package:drift/drift.dart';
import 'dao/favorite_dao.dart';
import 'dao/history_dao.dart';

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

@DriftDatabase(tables: [Favorites, Histories], daos: [FavoriteDao, HistoryDao])
class AppDb extends _$AppDb {
  AppDb(super.e);

  @override
  int get schemaVersion => 1;
}
