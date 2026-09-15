import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gbk_codec/gbk_codec.dart' as gbk;
import 'package:path_provider/path_provider.dart';
import 'package:source_engine/source_engine.dart';
import 'package:core/core.dart';
import '../runtime/quickjs_runtime_impl.dart';
import 'content_filter_provider.dart';
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

/// 引擎网络层：dio fetcher（含智能编码检测）。
///
/// 始终以 bytes 方式获取，再从三个来源确定最终编码：
/// 1) 源规则声明的 charset（最高优先级，源作者最清楚站点编码）
/// 2) HTTP Content-Type 头中的 charset
/// 3) HTML 内 `<meta charset>` / `<meta content="...charset=...">`
///
/// 支持 GBK/GB2312/GB18030 等中文编码统一走 gbk_codec 解码，
/// 避免 Dio 内部默认 UTF-8 造成的中文网页乱码。
final fetcherProvider = Provider<Fetcher>((ref) {
  final dio = ref.watch(dioProvider);
  return (url,
      {method = 'GET', headers = const {}, charset = 'utf-8', String? body}) async {
    final resp = await dio.request<List<int>>(
      url,
      // POST 体：java.post 重放协议带过来的表单/JSON 串
      data: body,
      options: Options(
        method: method,
        headers: headers,
        responseType: ResponseType.bytes,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    final bytes = resp.data ?? const [];
    if (bytes.isEmpty) return '';

    // 编码判定优先级：源规则声明 > HTTP 头 > HTML meta > 默认 UTF-8
    String? detected;
    if (charset.isNotEmpty && !_isUtf8Alias(charset)) {
      detected = charset;
    } else {
      final ct = resp.headers.value('content-type') ??
          resp.headers.value('Content-Type') ??
          '';
      detected = _extractCharsetFromHeader(ct);
      detected ??= _extractCharsetFromHtml(bytes);
    }
    return _decodeBytes(bytes, detected);
  };
});

/// 常见 UTF-8 别名（源规则写这些时跳过，让 HTTP/HTML 自动检测）
bool _isUtf8Alias(String s) {
  final low = s.toLowerCase().replaceAll('-', '').replaceAll('_', '');
  return low == 'utf8' || low == 'utf' || low == 'unicode';
}

/// 从 Content-Type 头提取 charset 参数（Dio 解析后会保留原始值）
String? _extractCharsetFromHeader(String ct) {
  if (ct.isEmpty) return null;
  // 普通字符串（非 raw）：`\\s` → `\s`，`[\"']?` → 可选双/单引号
  final m = RegExp("charset\\s*=\\s*[\"']?([\\w-]+)", caseSensitive: false)
      .firstMatch(ct);
  return m?.group(1)?.trim();
}

/// 从 HTML 字节内容中提取 meta charset。
/// 只看前 4KB（meta 都在 head 里，前几百字节就够），避免扫描整页。
String? _extractCharsetFromHtml(List<int> bytes) {
  try {
    final headLen = bytes.length < 4096 ? bytes.length : 4096;
    // 先用 latin1 把前 4KB 转成字符串（不丢失任何字节），再做正则匹配
    final head = String.fromCharCodes(bytes.take(headLen));
    // <meta charset="gbk"> 或 <meta http-equiv="Content-Type" content="...charset=gbk">
    final direct = RegExp("<meta\\s+[^>]*charset\\s*=\\s*[\"']?([\\w-]+)",
            caseSensitive: false)
        .firstMatch(head);
    if (direct != null) return direct.group(1)?.trim();
    final equiv = RegExp(
            "<meta\\s+[^>]*content\\s*=\\s*[\"'][^\"']*charset\\s*=\\s*([\\w-]+)",
            caseSensitive: false)
        .firstMatch(head);
    return equiv?.group(1)?.trim();
  } catch (_) {
    return null;
  }
}

/// 按检测到的编码解码字节。GBK/GB2312/GB18030 统一走 gbk_codec，
/// 其余默认 UTF-8（含检测失败的情况，UTF-8 解码失败会自动用 replacement）。
String _decodeBytes(List<int> bytes, String? charset) {
  final cs = charset ?? 'utf-8';
  final low = cs.toLowerCase().replaceAll('-', '').replaceAll('_', '');
  switch (low) {
    case 'gbk':
    case 'gb2312':
    case 'gb18030':
    case 'gb':
    case 'chinese':
      return gbk.gbk_bytes.decode(bytes);
    case 'utf8':
    case 'utf':
    case 'unicode':
      return utf8.decode(bytes, allowMalformed: true);
    case 'iso88591':
    case 'latin1':
    case 'latin':
    case 'windows1252':
      return String.fromCharCodes(bytes);
    default:
      // 其他编码也尝试 gbk 兜底（中文站最常见），失败再 UTF-8
      try {
        return gbk.gbk_bytes.decode(bytes);
      } catch (_) {
        return utf8.decode(bytes, allowMalformed: true);
      }
  }
}

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
  final engine = SourceEngine(
    jsRuntime: ref.watch(jsRuntimeProvider),
    fetcher: ref.watch(fetcherProvider),
  );
  // 用户自定义的正文替换规则：就绪或变更时注入引擎。
  //
  // 这里用 listen 而不是 watch —— watch 会让 provider 重建出一个**新的**
  // SourceEngine，而阅读页已经持有旧实例（repo 里），规则就落不到正在读的
  // 那本书上。listen 保持单例，只把新规则推进去。
  ref.listen<AsyncValue<List<ContentFilterRule>>>(
    contentFilterProvider,
    (_, next) => next.whenData(engine.setContentFilters),
    fireImmediately: true,
  );
  return engine;
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
