import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:drift/native.dart';
import 'source_assembly.dart';
import 'engine_providers.dart';

final appDbProvider = Provider<AppDb>((ref) {
  final db = AppDb(NativeDatabase.memory()); // 第一期内存库；持久化后续接 path_provider
  ref.onDispose(db.close);
  return db;
});

final sourceAssemblerProvider = FutureProvider<SourceAssembler>((ref) async {
  final engine = ref.watch(sourceEngineProvider);
  final repoPath = await ref.watch(sourceRepositoryPathProvider.future);
  return SourceAssembler(engine: engine, repoPath: repoPath);
});

final searchableSourcesProvider =
    FutureProvider<List<SearchableSource>>((ref) async {
  final assembler = await ref.watch(sourceAssemblerProvider.future);
  return assembler.loadEnabled();
});
