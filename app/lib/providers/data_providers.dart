import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart' show LazyDatabase;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:path_provider/path_provider.dart';
import 'source_assembly.dart';
import 'engine_providers.dart';
import 'plugin_store.dart';

final appDbProvider = Provider<AppDb>((ref) {
  final db = AppDb(_openDatabase());
  ref.onDispose(db.close);
  return db;
});

/// 收藏 / 搜索历史持久化到应用文档目录。
///
/// 用 LazyDatabase 把建库推迟到首次查询之后，避免阻塞首帧；
/// 落盘失败（权限/存储不可用）时回退内存库，保证功能仍可用。
LazyDatabase _openDatabase() => LazyDatabase(() async {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file =
            File('${dir.path}${Platform.pathSeparator}huisou.sqlite');
        return NativeDatabase(file);
      } catch (_) {
        return NativeDatabase.memory();
      }
    });

/// 内置源用的 HTTP 取文本实现（dio）。
///
/// 部分聚合 API / 音乐 CDN 对默认 UA 敏感，统一带上浏览器 UA；
/// source_engine 只声明 `HttpTextGetter` 抽象，具体实现留在 app 层，
/// 以保持该包的「纯 Dart」定位。
Future<String> _builtinHttpText(
  String url, {
  Map<String, String>? headers,
  Duration? timeout,
}) async {
  final dio = Dio(BaseOptions(
    connectTimeout: timeout ?? const Duration(seconds: 10),
    receiveTimeout: timeout ?? const Duration(seconds: 15),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
      ...?headers,
    },
  ));
  try {
    final resp = await dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return resp.data ?? '';
  } finally {
    dio.close(force: false);
  }
}

final sourceAssemblerProvider = FutureProvider<SourceAssembler>((ref) async {
  final engine = ref.watch(sourceEngineProvider);
  final repoPath = await ref.watch(sourceRepositoryPathProvider.future);
  final store = await ref.watch(pluginStoreProvider.future);
  return SourceAssembler(
    engine: engine,
    repoPath: repoPath,
    jsRuntimeFactory: ref.watch(jsRuntimeFactoryProvider),
    userVariablesOf: store.userVars,
    // 内置「歌名即直链」源（oiapi.net，免 key）
    builtinHttpGet: _builtinHttpText,
  );
});

final searchableSourcesProvider =
    FutureProvider<List<SearchableSource>>((ref) async {
  final assembler = await ref.watch(sourceAssemblerProvider.future);
  return assembler.loadEnabled();
});

/// 搜索类型筛选：null = 全部；发起搜索时只让 type 匹配的源参与
class SearchTypeFilterNotifier extends StateNotifier<SourceType?> {
  SearchTypeFilterNotifier() : super(null);
  void set(SourceType? type) => state = type;
}

final searchTypeFilterProvider =
    StateNotifierProvider<SearchTypeFilterNotifier, SourceType?>(
        (ref) => SearchTypeFilterNotifier());

/// 待搜索关键词：首页宫格/最近搜索等入口写入，搜索页消费一次后置空
final pendingSearchKeywordProvider = StateProvider<String?>((ref) => null);
