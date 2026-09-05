// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_dao.dart';

// ignore_for_file: type=lint
mixin _$HistoryDaoMixin on DatabaseAccessor<AppDb> {
  $HistoriesTable get histories => attachedDatabase.histories;
  HistoryDaoManager get managers => HistoryDaoManager(this);
}

class HistoryDaoManager {
  final _$HistoryDaoMixin _db;
  HistoryDaoManager(this._db);
  $$HistoriesTableTableManager get histories =>
      $$HistoriesTableTableManager(_db.attachedDatabase, _db.histories);
}
