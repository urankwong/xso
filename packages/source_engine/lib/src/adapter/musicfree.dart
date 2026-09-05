import 'dart:convert';
import 'package:core/core.dart';
import 'package:source_engine/src/js_runtime.dart';

/// MusicFree 插件适配器：
/// 沙箱内构造 CommonJS 环境（module/exports/require('env').axios），
/// 加载插件后把 module.exports.search 桥接为内部 SearchableSource。
class MusicFreeAdapter {
  final JsRuntime jsRuntime;
  MusicFreeAdapter({required this.jsRuntime});

  /// 包装脚本：加载插件、把 search 转为全局可调用入口
  static const _bootstrap = r'''
    globalThis.__mfModule = { exports: {} };
    globalThis.__mfEnv = {
      axios: {
        get: function(url, cfg) { return __hostFetch({url: url, method: 'GET'}); }
      }
    };
    function require(name) {
      if (name === 'env') return __mfEnv;
      throw new Error('require 只允许 env');
    }
    var module = globalThis.__mfModule;
    var exports = module.exports;
  ''';

  static const _bridge = r'''
    globalThis.__mfSearch = function(keyword, page) {
      var plugin = globalThis.__mfModule.exports;
      return Promise.resolve(plugin.search(keyword, page, 'music'))
        .then(function(r) { return JSON.stringify(r); });
    };
  ''';

  Future<MusicFreeSource> wrap(String pluginJs) async {
    // 1. bootstrap（CommonJS 环境）
    await jsRuntime.evaluate(_bootstrap);
    // 2. 加载插件本体（真实的插件代码执行）
    await jsRuntime.evaluate(pluginJs);
    // 3. 桥接 search 为全局函数
    await jsRuntime.evaluate(_bridge);

    // 4. 读取 plugin.platform 作为源名
    final metaJson = await jsRuntime
        .evaluate('JSON.stringify({name: __mfModule.exports.platform})');
    final name = (jsonDecode(metaJson) as Map)['name']?.toString() ??
        'MusicFree源';

    return MusicFreeSource._(jsRuntime, name);
  }
}

/// 适配后的内部源：实现 core 的 SearchableSource
class MusicFreeSource implements SearchableSource {
  final JsRuntime _js;
  @override
  late final SourceMeta meta;

  MusicFreeSource._(this._js, String name) {
    meta = SourceMeta(
      id: 'musicfree://${name.hashCode}',
      name: name,
      type: SourceType.music,
      version: 1,
      origin: 'musicfree',
    );
  }

  @override
  Future<List<SearchResult>> search(SearchQuery query) async {
    final raw = await _js.evaluate(
      '__mfSearch(${jsonEncode(query.keyword)}, ${query.page})',
      timeout: const Duration(seconds: 10),
    );
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final data = (decoded['data'] as List?) ?? [];
    return data.map((e) {
      final m = e as Map<String, dynamic>;
      return SearchResult(
        sourceId: meta.id,
        sourceName: meta.name,
        type: SourceType.music,
        title: m['title']?.toString() ?? '(无标题)',
        url: m['url']?.toString() ?? '',
        extra: {
          if (m['artist'] != null) 'artist': m['artist'].toString(),
          if (m['album'] != null) 'album': m['album'].toString(),
        },
      );
    }).toList();
  }
}
