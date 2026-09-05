import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gbk_codec/gbk_codec.dart' as gbk;
import 'package:path_provider/path_provider.dart';
import 'package:source_engine/source_engine.dart';
import 'package:core/core.dart';
import '../runtime/quickjs_runtime_impl.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36'},
  ));
  return dio;
});

/// 引擎网络层：dio fetcher（含 GBK 解码）
final fetcherProvider = Provider<Fetcher>((ref) {
  final dio = ref.watch(dioProvider);
  return (url,
      {method = 'GET', headers = const {}, charset = 'utf-8'}) async {
    if (charset.toLowerCase() == 'gbk') {
      // GBK 站点直接拿 bytes 解码
      final resp = await dio.get<List<int>>(
        url,
        options: Options(
            responseType: ResponseType.bytes,
            headers: headers,
            validateStatus: (s) => s != null && s < 500),
      );
      return gbk.gbk_bytes.decode(resp.data ?? []);
    }
    final resp = await dio.request<String>(
      url,
      options: Options(
        method: method,
        headers: headers,
        responseType: ResponseType.plain,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    return resp.data ?? '';
  };
});

final jsRuntimeProvider = Provider<JsRuntime>((ref) {
  final rt = QuickJsRuntimeImpl();
  ref.onDispose(rt.dispose);
  return rt;
});

final sourceEngineProvider = Provider<SourceEngine>((ref) {
  return SourceEngine(
    jsRuntime: ref.watch(jsRuntimeProvider),
    fetcher: ref.watch(fetcherProvider),
  );
});

/// Orchestrator：把仓库中的源装配为 SearchableSource 列表
final orchestratorProvider =
    Provider<SearchOrchestrator>((ref) => SearchOrchestrator());

final livenessCheckerProvider = Provider<LivenessChecker>((ref) {
  final dio = ref.watch(dioProvider);
  return LivenessChecker(fetcher: (url) async {
    final resp = await dio.get<String>(url,
        options: Options(responseType: ResponseType.plain));
    return resp.data ?? '';
  });
});

/// 源仓库目录（App 支持目录下的 sources/）
final sourceRepositoryPathProvider = FutureProvider<String>((ref) async {
  final dir = await getApplicationSupportDirectory();
  return '${dir.path}${Platform.pathSeparator}sources';
});
