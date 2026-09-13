import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gbk_codec/gbk_codec.dart' as gbk;
import 'package:path_provider/path_provider.dart';
import 'package:source_engine/source_engine.dart';
import 'package:core/core.dart';
import '../runtime/quickjs_runtime_impl.dart';
import 'plugin_store.dart';
import 'ua_provider.dart';

final dioProvider = Provider<Dio>((ref) {
  // UA 走 userAgentProvider：设置里改完 invalidate 即生效（无需重启）。
  // 未就绪时先用内置桌面 UA，保证首屏搜索不受异步读取影响。
  final ua = ref.watch(userAgentProvider).valueOrNull ??
      UaPresets.of(UaPresets.defaultMode, '');
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'User-Agent': ua,
      // 完整浏览器头：只发 UA 而不带 Accept 系列，仍是明显的"脚本特征"，
      // 不少站点据此返回 403。
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    },
    followRedirects: true,
    maxRedirects: 5,
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

/// 取已预载的插件存储（main 启动时已 await pluginStoreProvider）
PluginStore _pluginStore(Ref ref) =>
    ref.read(pluginStoreProvider).requireValue;

void _bindStorage(Ref ref, QuickJsRuntimeImpl rt) {
  rt.registerStorage(
    (ns) => _pluginStore(ref).loadStorage(ns),
    (ns, key, value) => _pluginStore(ref).writeStorage(ns, key, value),
  );
}

final jsRuntimeProvider = Provider<JsRuntime>((ref) {
  final rt = QuickJsRuntimeImpl();
  _bindStorage(ref, rt);
  ref.onDispose(rt.dispose);
  return rt;
});

/// JS 源专用运行时工厂：每个 musicfree/lx 源独立实例
final jsRuntimeFactoryProvider =
    Provider<JsRuntime Function()>((ref) {
  return () {
    final rt = QuickJsRuntimeImpl(dio: ref.read(dioProvider));
    _bindStorage(ref, rt);
    return rt;
  };
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
