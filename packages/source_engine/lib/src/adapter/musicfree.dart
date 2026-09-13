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
    // 插件存储（env.storage）：命名空间按源 id 隔离，经 hostStorage 同步通道
    // 读写宿主持久化（登录态需跨重启保留）；宿主未注入时退化为会话内存。
    globalThis.__mfStorage = (function(){
      var ns = globalThis.__mfStorageNs || 'default';
      var mem = {};
      try {
        var loaded = sendMessage('hostStorage', JSON.stringify(['load', ns]));
        if (loaded) mem = JSON.parse(loaded) || {};
      } catch (e) {}
      function persist(op, k, v) {
        try { sendMessage('hostStorage', JSON.stringify([op, ns, k, v])); } catch (e) {}
      }
      return {
        get: function(k){ return k == null ? mem : mem[k]; },
        set: function(k, v){ mem[k] = v; persist('set', k, v == null ? null : String(v)); return true; },
        remove: function(k){ delete mem[k]; persist('del', k, null); return true; },
        clear: function(){ mem = {}; persist('clear', null, null); return true; }
      };
    })();
    // XMLHttpRequest 最小垫片（走 __jsHost.request）
    globalThis.XMLHttpRequest = function() {
      this.readyState = 0; this.status = 0; this.responseText = '';
      this.onload = null; this.onerror = null; this.onreadystatechange = null;
    };
    globalThis.XMLHttpRequest.prototype.open = function(method, url) {
      this._method = method.toUpperCase(); this._url = url;
      this.readyState = 1;
    };
    globalThis.XMLHttpRequest.prototype.setRequestHeader = function(k, v) {
      this._headers = this._headers || {}; this._headers[k] = v;
    };
    globalThis.XMLHttpRequest.prototype.send = function(body) {
      var self = this;
      __jsHost.request({ url: this._url, method: this._method, headers: this._headers || {}, body: body || null })
        .then(function(resp) {
          self.readyState = 4; self.status = (resp && resp.status) || 0;
          self.responseText = (resp && resp.data) != null ? String(resp.data) : '';
          if (self.onreadystatechange) self.onreadystatechange();
          if (self.onload) self.onload();
        })
        .catch(function(e) { if (self.onerror) self.onerror(e); });
    };
    // 内置库懒加载：require('dayjs'|'qs'|'he'|'cheerio') 时经 hostAsset 通道
    // 取库源码，在函数作用域内 eval（隔离 module/exports），结果缓存。
    globalThis.__mfLibs = {};
    globalThis.__mfLibGlobals = {
      dayjs: 'dayjs', qs: 'Qs', he: 'he', cheerio: 'cheerio', 'big-integer': 'bigInt'
    };
    // console 捕获：插件日志进 __mfLogs（调试冒烟用，上限 100 条）
    globalThis.__mfLogs = [];
    globalThis.console = {
      log: function(){
        __mfLogs.push([].slice.call(arguments).map(String).join(' '));
        if (__mfLogs.length > 100) __mfLogs.shift();
      },
      warn: function(){ this.log.apply(this, arguments); },
      error: function(){ this.log.apply(this, arguments); },
      info: function(){ this.log.apply(this, arguments); }
    };
    globalThis.__mfLoadLib = function(name) {
      if (__mfLibs[name]) return __mfLibs[name];
      // flutter_js 会对消息做 JSON 解码，必须发 JSON 字符串
      var src = sendMessage('hostAsset', JSON.stringify(name));
      if (!src) throw new Error('内置库缺失: ' + name);
      var module = { exports: {} };
      var exports = module.exports;
      var define = undefined;
      var gname = __mfLibGlobals[name];
      eval(src + '\n;module.exports = (module.exports && Object.keys(module.exports).length) ? module.exports : (typeof ' + gname + ' !== "undefined" ? ' + gname + ' : module.exports);');
      var out = module.exports;
      if (!out || (typeof out === 'object' && Object.keys(out).length === 0 && typeof out !== 'function')) {
        throw new Error('库加载失败: ' + name);
      }
      __mfLibs[name] = out;
      return out;
    };
    globalThis.__mfEnv = {
      axios: __jsAxios,
      CryptoJS: (typeof CryptoJS !== 'undefined') ? CryptoJS : undefined,
      storage: __mfStorage,
      // 插件规范的用户变量（如 B站 Cookie）：宿主按源注入
      getUserVariables: function(){ return globalThis.__mfUserVars || {}; },
      getUserVariable: function(k){ return (globalThis.__mfUserVars || {})[k]; },
    };
    globalThis.env = __mfEnv;
    globalThis.__mfRequire = function(name) {
      if (globalThis.__mfLogs) __mfLogs.push('[require] ' + name);
      if (name === 'env') return __mfEnv;
      if (name === 'axios') {
        // 必须返回可调用函数：Parcel 打包插件会 require('axios')({url,...}) 直接调用，
        // 兼容 .get/.post/.default 三种用法。
        return __jsAxios;
      }
      if (name === 'CryptoJS' || name === 'crypto-js') {
        // 不能裸引用 CryptoJS：插件顶层若声明 const CryptoJS（require('crypto-js') 赋值），
        // 该词法绑定在初始化前对 typeof 也是 TDZ，必须走 bootstrap 期捕获的快照。
        var c = __mfEnv.CryptoJS;
        if (!c) {
          c = (typeof globalThis.CryptoJS !== 'undefined') ? globalThis.CryptoJS : null;
        }
        if (!c) throw new Error('CryptoJS 未注入');
        return c;
      }
      if (name === 'dayjs' || name === 'qs' || name === 'he' || name === 'cheerio' || name === 'big-integer') {
        return __mfLoadLib(name);
      }
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
        // responseType==='arraybuffer' 时宿主按 latin1 还原字节串，charCodeAt 可无损取字节
        var binary = cfg.responseType === 'arraybuffer';
        p = __jsHost.request({ url: url, method: method, headers: cfg.headers || {}, body: cfg.data || null, binary: binary });
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
    globalThis.__mfSearchStart = function(keyword, page, type) {
      __mfSearchState.result = '__pending__';
      var plugin = globalThis.__mfModule.exports;
      // Parcel 打包的插件只挂 module.exports.default（getter），顶层无 search，需解包
      if (plugin && plugin.default && typeof plugin.default.search === 'function') {
        plugin = plugin.default;
      }
      Promise.resolve()
        .then(function() { return plugin.search(keyword, page, type || 'music'); })
        .then(function(r) { __mfSearchState.result = JSON.stringify(r === undefined ? null : r); })
        .catch(function(e) { __mfSearchState.result = JSON.stringify({ __error: (e && e.message) || String(e), __stack: (e && e.stack) || '' }); });
      return 1;
    };
    globalThis.__mfSearchTake = function() { return __mfSearchState.result; };
    1
  ''';

  /// 通用插件方法调用桥（getAlbumInfo / getMediaSource 等）
  static const _callBridge = r'''
    globalThis.__mfCallState = { result: '__pending__' };
    globalThis.__mfCall = function(fnName, argsJson) {
      __mfCallState.result = '__pending__';
      var plugin = globalThis.__mfModule.exports;
      if (plugin && plugin.default && typeof plugin.default.search === 'function') {
        plugin = plugin.default;
      }
      var args = JSON.parse(argsJson || '[]');
      Promise.resolve()
        .then(function() { return plugin[fnName].apply(plugin, args); })
        .then(function(r) { __mfCallState.result = JSON.stringify(r === undefined ? null : r); })
        .catch(function(e) { __mfCallState.result = JSON.stringify({ __error: (e && e.message) || String(e), __stack: (e && e.stack) || '' }); });
      return 1;
    };
    globalThis.__mfCallTake = function() { return __mfCallState.result; };
    1
  ''';

  Future<MusicFreeSource> wrap(String pluginJs,
      {String? name,
       SourceType type = SourceType.music,
       String? storageKey,
       Map<String, String> userVariables = const {}}) async {
    await jsRuntime.evaluate(_axios);
    // 命名空间与用户变量必须在 bootstrap 前就位（storage 初始化时读取）
    await jsRuntime.evaluate('globalThis.__mfStorageNs = '
        '${jsonEncode(storageKey ?? "default")};'
        'globalThis.__mfUserVars = ${jsonEncode(userVariables)}; 1');
    await jsRuntime.evaluate(_bootstrap);
    await jsRuntime.evaluate(pluginJs); // 加载插件本体
    await jsRuntime.evaluate(_bridge);
    await jsRuntime.evaluate(_callBridge);

    final metaJson = await jsRuntime.evaluate(r'''
      (function(){
        var p = globalThis.__mfModule.exports;
        if (p && p.default && typeof p.default.search === 'function') p = p.default;
        var vars = (p && p.userVariables) || [];
        return JSON.stringify({
          name: p && p.platform,
          vars: vars.map(function(v){
            return {key:v.key, name:v.name, type:v.type, description:v.description};
          }),
        });
      })()
    ''');
    Map decoded;
    try {
      final parsed = jsonDecode(metaJson);
      decoded = parsed is Map ? parsed : const {};
    } catch (_) {
      decoded = const {}; // meta 脚本异常不阻塞装配，退回传入名
    }
    final resolved = decoded['name']?.toString();
    final pluginName = (resolved == null || resolved == 'undefined' || resolved.isEmpty)
        ? (name ?? 'MusicFree源')
        : resolved;
    final specs = ((decoded['vars'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    return MusicFreeSource._(jsRuntime, pluginName, type,
        storageKey: storageKey ?? pluginName, userVariableSpec: specs);
  }
}

/// 适配后的内部源：实现 core 的 SearchableSource
class MusicFreeSource implements SearchableSource {
  final JsRuntime _js;
  @override
  late final SourceMeta meta;

  /// env.storage 命名空间（一般为仓库源 id），登录态按此持久化
  final String storageKey;

  /// 插件声明的用户变量（B站 Cookie 等），供宿主渲染配置表单
  final List<Map<String, dynamic>> userVariableSpec;

  MusicFreeSource._(this._js, String name, SourceType type,
      {this.storageKey = 'default', this.userVariableSpec = const []}) {
    meta = SourceMeta(
      id: 'musicfree://${name.hashCode}',
      name: name,
      type: type,
      version: 1,
      origin: 'musicfree',
    );
  }

  @override
  Future<List<SearchResult>> search(SearchQuery query) {
    // 有声播客源按专辑粒度搜索（插件 search 的 type 参数用 'album'）
    final searchType = meta.type == SourceType.audiobook ? 'album' : 'music';
    return _searchWithType(query.keyword, query.page, searchType);
  }

  /// 按关键词搜「专辑」条目：用于音乐源点专辑名进专辑页（先搜专辑拿 id）
  Future<List<SearchResult>> searchAlbums(String keyword, {int page = 1}) =>
      _searchWithType(keyword, page, 'album', keepRaw: true);

  Future<List<SearchResult>> _searchWithType(
      String keyword, int page, String searchType,
      {bool keepRaw = false}) async {
    await _js.evaluate(
      '__mfSearchStart(${jsonEncode(keyword)}, $page, ${jsonEncode(searchType)})',
      timeout: const Duration(seconds: 15),
    );
    final raw = await _pollUntilDone();
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw Exception(
          'MusicFree 源返回无法解析: ${raw.length > 120 ? raw.substring(0, 120) : raw}');
    }
    if (decoded is Map && decoded['__error'] != null) {
      throw Exception('MusicFree 源搜索失败: ${decoded['__error']}');
    }
    final data = (decoded is Map ? (decoded['data'] ?? decoded['list']) : decoded) as List?;
    return (data ?? [])
        .whereType<Map>()
        .map((m) => _toSearchResult(m, keepRaw: keepRaw))
        .toList();
  }

  /// 插件曲目/专辑条目 → 归一化结果。有声播客条目标记 needsDetail（两段式拉曲目）。
  SearchResult _toSearchResult(Map m, {bool keepRaw = false}) {
    final q = m['_qualitys'] ?? m['qualities'];
    final isAlbum = meta.type == SourceType.audiobook;
    final url = (m['url'] ?? m['audio'] ?? '')?.toString() ?? '';
    return SearchResult(
      sourceId: meta.id,
      sourceName: meta.name,
      type: meta.type,
      title: (m['title'] ?? m['name'])?.toString() ?? '(无标题)',
      url: url,
      needsDetail: isAlbum && !url.startsWith('http'),
      extra: {
        if (m['id'] != null) 'itemId': m['id'].toString(),
        if (m['albumId'] != null) 'albumId': m['albumId'].toString(),
        // B 站等视频型音源带 bvid/aid，供 MV 解析使用
        if (m['bvid'] != null) 'bvid': m['bvid'].toString(),
        if (m['aid'] != null) 'aid': m['aid'].toString(),
        if (m['artist'] != null) 'artist': m['artist'].toString(),
        if (m['singer'] != null) 'artist': m['singer'].toString(),
        if (m['album'] != null) 'album': m['album'].toString(),
        if (m['description'] != null) 'desc': m['description'].toString(),
        if (m['artwork'] != null) 'cover': m['artwork'].toString(),
        if (m['cover'] != null) 'cover': m['cover'].toString(),
        if (q != null) 'qualities': jsonEncode(q),
        // 始终保留插件原始条目：搜索结果普遍不带直链，
        // 点播时 resolveMedia 靠 __item 调 getMediaSource 解析真实地址。
        '__item': jsonEncode(m),
      },
    );
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

  /// 通用异步调用桥：fn 为插件导出的方法名，argsJson 为参数数组 JSON
  Future<Map<String, dynamic>> _call(String fnName, List<Object?> args) async {
    await _js.evaluate(
        '__mfCall(${jsonEncode(fnName)}, ${jsonEncode(jsonEncode(args))})',
        timeout: const Duration(seconds: 15));
    final raw = await _pollCallUntilDone();
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded['__error'] != null) {
      throw Exception('插件调用 $fnName 失败: ${decoded['__error']}');
    }
    return (decoded as Map?)?.cast<String, dynamic>() ?? {};
  }

  Future<String> _pollCallUntilDone(
      {Duration interval = const Duration(milliseconds: 150),
      int maxTries = 160}) async {
    for (var i = 0; i < maxTries; i++) {
      await Future<void>.delayed(interval);
      final raw =
          await _js.evaluate('__mfCallTake()', timeout: const Duration(seconds: 5));
      if (raw != '__pending__') return raw;
    }
    throw Exception('插件调用超时');
  }

  /// 专辑两段式：拉取专辑/有声书下的曲目列表。
  /// MusicFree 标准签名为 getAlbumInfo(albumItem)（对象，插件内部取 .id），
  /// 但部分插件（如懒人听书）把首参直接当 id 字符串用 —— 两种约定都试一次。
  Future<List<SearchResult>> fetchAlbumTracks(SearchResult album) async {
    final rawItem = album.extra?['__item'];
    final albumId = album.extra?['itemId'] ?? album.url;
    final Object standard = rawItem != null
        ? jsonDecode(rawItem)
        : {
            'id': albumId,
            'title': album.title,
            if (album.extra?['artist'] != null) 'artist': album.extra!['artist'],
          };

    Object? firstError;
    for (final arg in [standard, if (albumId.isNotEmpty) albumId]) {
      try {
        final tracks = await _albumTracksWith(arg, album);
        if (tracks.isNotEmpty) return tracks;
      } catch (e) {
        firstError ??= e;
      }
    }
    if (firstError != null) throw Exception('专辑曲目获取失败: $firstError');
    return const [];
  }

  Future<List<SearchResult>> _albumTracksWith(Object arg, SearchResult album) async {
    final info = await _call('getAlbumInfo', [arg]);
    final list = (info['musicList'] ?? info['data'] ?? []) as List;
    return list.whereType<Map>().map((m) {
      final r = _toSearchResult(m);
      return SearchResult(
        sourceId: album.sourceId,
        sourceName: album.sourceName,
        type: SourceType.music, // 曲目是可播放的音频单元
        title: r.title,
        url: r.url,
        extra: {...?r.extra, '__item': jsonEncode(m)},
      );
    }).toList();
  }

  /// 解析曲目播放地址：插件 getMediaSource(item, quality) → {url}
  Future<String> resolveMedia(SearchResult track,
      {String quality = 'standard'}) async {
    final rawItem = track.extra?['__item'];
    if (rawItem == null) return track.url;
    final item = jsonDecode(rawItem);
    final media = await _call('getMediaSource', [item, quality]);
    final url = media['url']?.toString() ?? '';
    if (!url.startsWith('http')) return track.url;

    // 部分源（网易云等）的 CDN 地址必须带 Referer / Cookie / UA 才能取流，
    // 插件会在 headers 里给出。原实现只取 url 把 headers 丢掉，
    // 结果是播放器直接报 Source error —— 地址解析成功了却播不出来。
    final headers = media['headers'];
    final extra = track.extra;
    if (headers is Map && headers.isNotEmpty && extra != null) {
      extra['__headers'] = jsonEncode(
          headers.map((k, v) => MapEntry(k.toString(), v.toString())));
    }
    assert(() {
      // ignore: avoid_print
      print('[MusicFree] resolveMedia url=$url headers=$headers');
      return true;
    }());
    return url;
  }

  /// 歌单两段式：按歌单 id 拉曲目（MusicFree 标准 getMusicSheetInfo(sheet, page)）。
  /// 公开歌单无需登录即可解析；返回曲目带 __item 供点播解析真实地址。
  Future<List<SearchResult>> fetchSheetTracks(String sheetId,
      {int page = 1}) async {
    final info =
        await _call('getMusicSheetInfo', [
          {'id': sheetId},
          page
        ]);
    final list = (info['musicList'] ?? info['data'] ?? []) as List;
    return list.whereType<Map>().map((m) {
      final r = _toSearchResult(m);
      return SearchResult(
        sourceId: meta.id,
        sourceName: meta.name,
        type: SourceType.music,
        title: r.title,
        url: r.url,
        extra: {...?r.extra, '__item': jsonEncode(m)},
      );
    }).toList();
  }

  /// 歌单标题（部分插件在 getMusicSheetInfo 返回 sheetItem.title）
  Future<String?> fetchSheetTitle(String sheetId) async {
    try {
      final info = await _call('getMusicSheetInfo', [
        {'id': sheetId},
        1
      ]);
      return (info['sheetItem']?['title'] ?? info['title'])?.toString();
    } catch (_) {
      return null;
    }
  }
}
