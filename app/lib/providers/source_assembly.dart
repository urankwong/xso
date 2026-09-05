import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:source_engine/source_engine.dart';

/// 装配器：源仓库 → 运行时可搜索源列表
class SourceAssembler {
  final SourceEngine engine;
  final String repoPath;

  SourceAssembler({required this.engine, required this.repoPath});

  Future<List<SearchableSource>> loadEnabled() async {
    final repo = SourceRepository(repoPath);
    final stored = await repo.list();
    final result = <SearchableSource>[];

    for (final s in stored.where((e) => e.enabled)) {
      final raw = await repo.readRaw(s.id);
      try {
        switch (s.format) {
          case 'own':
            result.add(_EngineSource(engine, parseSource(raw)));
          case 'legado':
            result.add(_EngineSource(engine, LegadoAdapter().translate(raw)));
          case 'musicfree':
            result.add(
                await MusicFreeAdapter(jsRuntime: engine.jsRuntime).wrap(raw));
          case 'lx':
            result.add(await LxAdapter(jsRuntime: engine.jsRuntime).wrap(raw));
          default:
            continue; // 未知格式跳过（不炸全局）
        }
      } catch (e) {
        // 单源损坏不影响其他源装配（源级隔离从装配开始）
        continue;
      }
    }
    return result;
  }
}

/// 自有/Legado 格式的运行时包装
class _EngineSource implements SearchableSource {
  final SourceEngine _engine;
  final Source _source;
  _EngineSource(this._engine, this._source);

  @override
  SourceMeta get meta => _source.meta;

  @override
  Future<List<SearchResult>> search(SearchQuery query) =>
      _engine.search(_source, query);
}
