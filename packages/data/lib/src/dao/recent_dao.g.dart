// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recent_dao.dart';

// ignore_for_file: type=lint
mixin _$RecentDaoMixin on DatabaseAccessor<AppDb> {
  $RecentItemsTable get recentItems => attachedDatabase.recentItems;
  RecentDaoManager get managers => RecentDaoManager(this);
}

class RecentDaoManager {
  final _$RecentDaoMixin _db;
  RecentDaoManager(this._db);
  $$RecentItemsTableTableManager get recentItems =>
      $$RecentItemsTableTableManager(_db.attachedDatabase, _db.recentItems);
}
