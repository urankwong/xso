import 'dart:convert';
import 'package:core/core.dart';
import 'package:source_engine/src/js_runtime.dart';

/// MusicFree 插件适配器。
///
/// 真实插件规范（musicfree.upup.fun）：`module.exports = {platform, version,
/// srcUrl?, search(keyword, page, type)}`，search 返回 `{isEnd, data:[{title,
/// artist?, album?, url?}]}`。插件普遍 `require('axios')` / `require('env')`，
/// 本适配器在沙箱内提供：
/// - CommonJS 环境（module/exports/require）
/// - axios 模块：可调用函数 + get/post，返回 {status, data}（data 自动 JSON 化）
/// - 异步网络走 __jsHost.request（宿主实现 hostRequest 通道）
class MusicFreeAdapter {
  final JsRuntime jsRuntime;
  MusicFreeAdapter({required this.jsRuntime});

  static const _bootstrap = r'''
    globalThis.__mfModule = { exports: {} };
    globalThis.__mfEnv = { axios: __jsAxios };
    globalThis.__mfRequire = function(name) {
      if (name === 'env') return __mfEnv;
      if (name === 'axios') return { default: __jsAxios, get: __jsAxios.get, post: __jsAxios.post };
      throw new Error('沙箱不支持模块: ' + name);
    };
    function require(name) { return __mfRequire(name); }
    var module = globalThis.__mfModule;
    var exports = module.exports;
    if (typeof console === 'undefined') { globalThis.console = { log: function(){}, warn: function(){}, error: function(){} }; }
  ''';

  /// axios polyfill：cfg 或 url；返回 {status, data, headers}，data 自动 JSON 化
  static const _axios = r'''
    globalThis.__jsAxios = function(cfgOrUrl, maybeCfg) {
      var cfg = typeof cfgOrUrl === 'string' ? Object.assign({ url: cfgOrUrl }, maybeCfg || {})
        : (cfgOrUrl || {});
      var method = (cfg.method || 'GET').toUpperCase();
      var url = cfg.url;
      var p;
      if ((method === 'GET' || method === 'DELETE') && cfg.params) {
        var qs = Object.keys(cfg.params).map(function(k){ return encodeURIComponent(k)+'='+encodeURIComponent(cfg.params[k]); }).join('&');
        if (qs) url += (url.indexOf('?') >= 0 ? '&' : '?') + qs;
      }
      if (typeof __jsHost !== 'undefined' && __jsHost.request) {
        p = __jsHost.request({ url: url, method: method, headers: cfg.headers || {}, body: cfg.data || null });
      } else {
        p = Promise.reject(new Error('宿主未提供网络桥'));
      }
      return p.then(function(resp) {
        var data = resp && resp.data;
        if (typeof data === 'string') {
          try { data = JSON.parse(data); } catch (_) {}
        }
        return { status: (resp && resp.status) || 0, data: data, headers: (resp && resp.headers) || {} };
      });
    };
    globalThis.__jsAxios.get = function(url, cfg) { return globalThis.__jsAxios(url, Object.assign({}, cfg, { method: 'GET' })); };
    globalThis.__jsAxios.post = function(url, data, cfg) { return globalThis.__jsAxios(url, Object.assign({}, cfg, { method: 'POST', data: data })); };
    globalThis.__jsAxios.default = globalThis.__jsAxios;
    1
  ''';

  static const _bridge = r'''
    globalThis.__mfSearchState = { result: '__pending__' };
    globalThis.__mfSearchStart = function(keyword, page) {
      __mfSearchState.result = '__pending__';
      var plugin = globalThis.__mfModule.exports;
      Promise.resolve()
        .then(function() { return plugin.search(keyword, page, 'music'); })
        .then(function(r) { __mfSearchState.result = JSON.stringify(r === undefined ? null : r); })
        .catch(function(e) { __mfSearchState.result = JSON.stringify({ __error: (e && e.message) || String(e) }); });
      return 1;
    };
    globalThis.__mfSearchTake = function() { return __mfSearchState.result; };
    1
  ''';

  Future<MusicFreeSource> wrap(String pluginJs, {String? name}) async {
    await jsRuntime.evaluate(_axios);
    await jsRuntime.evaluate(_bootstrap);
    await jsRuntime.evaluate(pluginJs); // 加载插件本体
    await jsRuntime.evaluate(_bridge);

    final metaJson = await jsRuntime
        .evaluate('JSON.stringify({name: __mfModule.exports.platform})');
    final resolved = ((jsonDecode(metaJson) as Map)['name']?.toString());
    final pluginName = (resolved == null || resolved == 'undefined' || resolved.isEmpty)
        ? (name ?? 'MusicFree源')
        : resolved;
    return MusicFreeSource._(jsRuntime, pluginName);
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
    await _js.evaluate(
      '__mfSearchStart(${jsonEncode(query.keyword)}, ${query.page})',
      timeout: const Duration(seconds: 15),
    );
    final raw = await _pollUntilDone();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    if (decoded['__error'] != null) {
      throw Exception('MusicFree 源搜索失败: ${decoded['__error']}');
    }
    final data = (decoded['data'] ?? decoded['list']) as List?;
    return (data ?? [])
        .whereType<Map>()
        .map((m) => SearchResult(
              sourceId: meta.id,
              sourceName: meta.name,
              type: SourceType.music,
              title: (m['title'] ?? m['name'])?.toString() ?? '(无标题)',
              url: (m['url'] ?? m['audio'] ?? '')?.toString() ?? '',
              extra: {
                if (m['artist'] != null) 'artist': m['artist'].toString(),
                if (m['singer'] != null) 'artist': m['singer'].toString(),
                if (m['album'] != null) 'album': m['album'].toString(),
              },
            ))
        .toList();
  }

  Future<String> _pollUntilDone(
      {Duration interval = const Duration(milliseconds: 150),
      int maxTries = 80}) async {
    for (var i = 0; i < maxTries; i++) {
      await Future<void>.delayed(interval);
      final raw =
          await _js.evaluate('__mfSearchTake()', timeout: const Duration(seconds: 5));
      if (raw != '__pending__') return raw;
    }
    throw Exception('MusicFree 源搜索超时');
  }
}
