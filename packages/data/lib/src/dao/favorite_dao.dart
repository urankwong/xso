import 'package:core/core.dart';
import 'package:drift/drift.dart';
import '../db.dart';
part 'favorite_dao.g.dart';

@DriftAccessor(tables: [Favorites])
class FavoriteDao extends DatabaseAccessor<AppDb> with _$FavoriteDaoMixin {
  FavoriteDao(super.db);

  Future<int> add(SearchResult r, {String? code}) => into(db.favorites).insert(
        FavoritesCompanion.insert(
          sourceId: r.sourceId,
          sourceName: r.sourceName,
          type: r.type.name,
          title: r.title,
          url: r.url,
          extractCode: Value(code ?? r.extractCode),
        ),
      );

  Future<List<Favorite>> all() =>
      (select(db.favorites)..orderBy([(f) => OrderingTerm.desc(f.createdAt)]))
          .get();

  Future<List<Favorite>> byType(SourceType type) =>
      (select(db.favorites)..where((f) => f.type.equals(type.name))).get();

  Future<void> remove(int id) =>
      (delete(db.favorites)..where((f) => f.id.equals(id))).go();

  Future<void> markDead(int id, {required bool dead}) => (update(db.favorites)
        ..where((f) => f.id.equals(id)))
      .write(FavoritesCompanion(isDead: Value(dead)));
}
