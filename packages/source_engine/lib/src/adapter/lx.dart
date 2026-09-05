import 'dart:convert';
import 'package:core/core.dart';
import 'package:source_engine/src/js_runtime.dart';

/// 洛雪音乐源适配器（真实协议）。
///
/// 洛雪自定义源规范：脚本用 `lx.on(EVENT_NAMES.request, handler)` 注册请求
/// 处理器，搜索请求为 `{source:'musicSearch', action:'search',
/// info:{searchText}}`，返回（或 resolve）`{isEnd, list:[{name, singer,...}]}`；
/// 网络用 `lx.request(url, options, callback)`（callback(err, resp)，
/// resp.body 为响应文本）。本适配器模拟 lx 全局并提供该协议的桥接。
class LxAdapter {
  final JsRuntime jsRuntime;
  LxAdapter({required this.jsRuntime});

  static const _bootstrap = r'''
    globalThis.__lxHandlers = {};
    globalThis.EVENT_NAMES = { request: 'request', inited: 'inited', updateAlert: 'updateAlert' };
    globalThis.lx = {
      on: function(event, handler) { globalThis.__lxHandlers[event] = handler; },
      send: function(event, data) {
        if (event === 'inited') globalThis.__lxInited = data;
        return Promise.resolve();
      },
      request: function(url, options, callback, config) {
        var opts = typeof url === 'string' ? Object.assign({ url: url }, options || {}) : (url || {});
        __jsHost.request({ url: opts.url, method: opts.method || 'GET', headers: opts.headers || {}, body: opts.body || null })
          .then(function(resp) {
            if (typeof callback === 'function') callback(null, { body: resp && resp.data, statusCode: resp && resp.status, headers: (resp && resp.headers) || {} });
          })
          .catch(function(e) {
            if (typeof callback === 'function') callback(e, null);
          });
      },
      utils: {
        buffer: { from: function(s){ return s; }, bufToString: function(b){ return String(b); } },
        crypto: {
          md5: function(s){ return s; }, aesEn: function(){ throw new Error('aes 不支持'); },
          rsaEncrypt: function(){ throw new Error('rsa 不支持'); },
          randomBytes: function(n){ var s=''; for(var i=0;i<n;i++) s+='0'; return s; }
        },
        zlib: {}
      },
      env: 'lx-music-mobile',
      version: '1.5.0',
      currentScriptInfo: { name: globalThis.__lxName || '洛雪源', description: '', version: '1.0.0', author: '' },
      DEEP_LINK: 'lxmusic://'
    };
    if (typeof console === 'undefined') { globalThis.console = { log: function(){}, warn: function(){}, error: function(){} }; }
    1
  ''';

  static const _bridge = r'''
    globalThis.__lxSearchState = { result: '__pending__' };
    globalThis.__lxSearchStart = function(keyword) {
      __lxSearchState.result = '__pending__';
      Promise.resolve()
        .then(function() {
          var h = globalThis.__lxHandlers['request'];
          if (!h) throw new Error('源未注册 request 处理器');
          var out = h({ source: 'musicSearch', action: 'search', info: { searchText: keyword } });
          if (out && typeof out.then === 'function') return out;
          // 部分源用回调/同步返回数组
          return out;
        })
        .then(function(r) { __lxSearchState.result = JSON.stringify(r === undefined ? null : r); })
        .catch(function(e) { __lxSearchState.result = JSON.stringify({ __error: (e && e.message) || String(e) }); });
      return 1;
    };
    globalThis.__lxSearchTake = function() { return __lxSearchState.result; };
    1
  ''';

  Future<LxSource> wrap(String lxJs, {String name = '洛雪源'}) async {
    await jsRuntime.evaluate(_bootstrap);
    await jsRuntime.evaluate(lxJs); // 加载源脚本本体
    await jsRuntime.evaluate(_bridge);
    return LxSource._(jsRuntime, name);
  }
}

class LxSource implements SearchableSource {
  final JsRuntime _js;
  @override
  late final SourceMeta meta;

  LxSource._(this._js, String name) {
    meta = SourceMeta(
      id: 'lx://${name.hashCode}',
      name: name,
      type: SourceType.music,
      version: 1,
      origin: 'lx',
    );
  }

  @override
  Future<List<SearchResult>> search(SearchQuery query) async {
    await _js.evaluate(
      '__lxSearchStart(${jsonEncode(query.keyword)})',
      timeout: const Duration(seconds: 15),
    );
    final raw = await _pollUntilDone();
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded['__error'] != null) {
      throw Exception('洛雪源搜索失败: ${decoded['__error']}');
    }
    final list = decoded is Map ? (decoded['list'] ?? decoded['data']) as List? : decoded as List;
    return (list ?? [])
        .whereType<Map>()
        .map((m) => SearchResult(
              sourceId: meta.id,
              sourceName: meta.name,
              type: SourceType.music,
              title: (m['name'] ?? m['title'])?.toString() ?? '(无标题)',
              url: (m['url'] ?? m['audio'] ?? '')?.toString() ?? '',
              extra: {
                if (m['singer'] != null) 'artist': m['singer'].toString(),
                if (m['artist'] != null) 'artist': m['artist'].toString(),
                if (m['albumName'] != null) 'album': m['albumName'].toString(),
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
          await _js.evaluate('__lxSearchTake()', timeout: const Duration(seconds: 5));
      if (raw != '__pending__') return raw;
    }
    throw Exception('洛雪源搜索超时');
  }
}
