import 'dart:convert';
import 'package:core/core.dart';
import 'package:source_engine/src/js_runtime.dart';
import 'package:source_engine/src/search/lx_host_search.dart';

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
    // aes-<bits>-<cbc|ecb> → CryptoJS；key/iv 按 utf8 字节解析，Pkcs7 填充
    globalThis.__lxAes = function(encrypt, data, mode, key, iv) {
      if (typeof CryptoJS === 'undefined') throw new Error('CryptoJS 未注入');
      var m = /aes-(\d+)-(cbc|ecb|cfb|ofb)/.exec(String(mode || 'aes-128-cbc').toLowerCase());
      if (!m) throw new Error('不支持的 aes 模式: ' + mode);
      var alg = m[2], bits = parseInt(m[1], 10);
      var keyBuf = CryptoJS.enc.Utf8.parse(String(key));
      if (bits !== keyBuf.sigBytes * 8) {
        // key 长度与位数不符时按位数截断/补零到 16/24/32 字节
        var target = bits / 8, src = keyBuf.words, out = [];
        for (var i = 0; i < target; i++) out.push(i < src.length ? src[i] : 0);
        keyBuf = CryptoJS.lib.WordArray.create(out, target);
      }
      var opts = { mode: (alg === 'ecb' ? CryptoJS.mode.ECB : CryptoJS.mode.CBC), padding: CryptoJS.pad.Pkcs7 };
      if (iv != null && alg !== 'ecb') opts.iv = CryptoJS.enc.Utf8.parse(String(iv));
      if (alg === 'ecb') opts.iv = CryptoJS.lib.WordArray.create();
      return encrypt
          ? CryptoJS.AES.encrypt(String(data), keyBuf, opts).toString()
          : CryptoJS.AES.decrypt(String(data), keyBuf, opts).toString(CryptoJS.enc.Utf8);
    };
    globalThis.lx = {
      // ★ 洛雪标准写法是 `const { EVENT_NAMES, request, on, send } = globalThis.lx`，
      //   即 EVENT_NAMES 必须是 lx 的属性。只把它挂在顶层 globalThis 上，
      //   源解构出来是 undefined → `on(EVENT_NAMES.request, ...)` 直接抛 TypeError，
      //   源的 request 处理器注册不上，表现为「所有洛雪源都搜不到/播不了」。
      //   顶层 globalThis.EVENT_NAMES 保留，兼容少数直接引用全局的旧源。
      EVENT_NAMES: globalThis.EVENT_NAMES,
      on: function(event, handler) { globalThis.__lxHandlers[event] = handler; },
      send: function(event, data) {
        if (event === 'inited') globalThis.__lxInited = data;
        return Promise.resolve();
      },
      request: function(url, options, callback, config) {
        var opts = typeof url === 'string' ? Object.assign({ url: url }, options || {}) : (url || {});
        __jsHost.request({
          url: opts.url,
          method: opts.method || 'GET',
          headers: opts.headers || {},
          body: opts.body || null,
          binary: opts.responseType === 'arraybuffer'
        })
          .then(function(resp) {
            if (typeof callback !== 'function') return;
            var raw = resp && resp.data;
            var text = (raw == null) ? '' : (typeof raw === 'string' ? raw : String(raw));
            var body = raw;
            if (typeof raw === 'string') {
              var head = text.replace(/^\uFEFF/, '').trim().charAt(0);
              if (head === '{' || head === '[') {
                try { body = JSON.parse(text); } catch (_) { body = raw; }
              }
            }
            var out = { body: body, statusCode: resp && resp.status, headers: (resp && resp.headers) || {} };
            // ★ 源的 callback 是非 Promise 的同步回调：它内部抛错不会进入任何 reject 链，
            //   而是变成未捕获异常直接炸掉整个 JS runtime（实测 TX 取链时源第三方的
            //   响应对象为 null，源写 `resp.body.code` 直接 TypeError 把 runtime 打死）。
            //   宿主必须兜住 —— 第三方源质量不可控，单源异常不能拖垮整个沙箱。
            try {
              callback(null, out, text); // 第三个参数给原始文本，兼容 (err, _, bodyText) 写法
            } catch (e) {
              if (typeof console !== 'undefined' && console.error) {
                console.error('lx request callback error: ' + ((e && e.message) || String(e)));
              }
            }
          })
          .catch(function(e) {
            if (typeof callback !== 'function') return;
            try {
              callback(e, null, null);
            } catch (e2) { /* 同上：源的失败分支也可能抛错，一并吞掉 */ }
          });
      },
      utils: {
        buffer: { from: function(s){ return s; }, bufToString: function(b){ return String(b); } },
        crypto: {
          md5: function(s){ return CryptoJS.MD5(String(s)).toString(); },
          aesEn: function(data, mode, key, iv){ return __lxAes(true, data, mode, key, iv); },
          aesDe: function(data, mode, key, iv){ return __lxAes(false, data, mode, key, iv); },
          rsaEncrypt: function(pubkey, data){
            if (typeof __jsHost === 'undefined' || !__jsHost.rsaEncrypt) throw new Error('宿主未提供 RSA 桥');
            return __jsHost.rsaEncrypt(String(pubkey), String(data));
          },
          randomBytes: function(n){
            var s=''; for(var i=0;i<n;i++){ s+=Math.floor(Math.random()*256).toString(16).padStart(2,'0'); } return s;
          },
          base64: function(s){ return CryptoJS.enc.Base64.stringify(CryptoJS.enc.Utf8.parse(String(s))); }
        },
        zlib: {}
      },
      env: 'lx-music-mobile',
      version: '1.5.0',
      currentScriptInfo: {
        // 部分源（如「無名」）会校验 currentScriptInfo 的 name/description，
        // 与源内声明不符就抛错拒载 —— 宿主须用源文件头部的 @name/@description 还原。
        name: globalThis.__lxName || '洛雪源',
        description: globalThis.__lxDesc || '',
        version: globalThis.__lxVersion || '1.0.0',
        author: globalThis.__lxAuthor || ''
      },
      DEEP_LINK: 'lxmusic://'
    };
    if (typeof console === 'undefined') { globalThis.console = { log: function(){}, warn: function(){}, error: function(){} }; }
    // 读取源在 send(EVENT_NAMES.inited) 里声明的平台列表（如 ['kg','kw','tx']）。
    // 宿主搜索据此决定对哪些平台做搜索回退 —— 只搜源真正声明了 musicUrl 的平台。
    globalThis.__lxGetSources = function() {
      try {
        var s = (globalThis.__lxInited && globalThis.__lxInited.sources) || {};
        var out = [];
        for (var k in s) if (Object.prototype.hasOwnProperty.call(s, k)) out.push(k);
        return JSON.stringify(out);
      } catch (e) { return '[]'; }
    };
    // 源是否声明了指定平台的 musicUrl（没有就不必为其做宿主搜索）
    globalThis.__lxSourceSupports = function(platform) {
      try {
        var s = (globalThis.__lxInited && globalThis.__lxInited.sources) || {};
        var item = s[platform];
        if (!item) return false;
        var acts = item.actions || [];
        for (var i = 0; i < acts.length; i++) if (acts[i] === 'musicUrl') return true;
        return false;
      } catch (e) { return false; }
    };
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
    // 通用异步动作桥（musicUrl / leaderboard 等）。
    // 按 id 分队列而非单槽：并发解析两首歌时，后发起的不得覆盖先发起的结果。
    globalThis.__lxAsync = { seq: 0, map: {} };
    globalThis.__lxInvoke = function(requestJson) {
      var id = String(++globalThis.__lxAsync.seq);
      globalThis.__lxAsync.map[id] = '__pending__';
      Promise.resolve()
        .then(function() {
          var h = globalThis.__lxHandlers['request'];
          if (!h) throw new Error('源未注册 request 处理器');
          return h(JSON.parse(requestJson));
        })
        .then(function(r) { globalThis.__lxAsync.map[id] = JSON.stringify({ data: r === undefined ? null : r }); })
        .catch(function(e) { globalThis.__lxAsync.map[id] = JSON.stringify({ __error: (e && e.message) || String(e) }); });
      return id;
    };
    globalThis.__lxInvokeTake = function(id) {
      var v = globalThis.__lxAsync.map[id];
      if (v === undefined) return '__pending__';
      delete globalThis.__lxAsync.map[id];
      return v;
    };
    1
  ''';

  /// 从源文件头部解析 `@name` / `@description` / `@version` / `@author`。
  ///
  /// 必要性：部分源在初始化时校验 `lx.currentScriptInfo`，与源内声明不符就抛错
  /// 拒载（作者的防二次分发机制）。宿主必须还原源自身声明的元信息，否则这类源
  /// 一律加载失败。取不到时回退空串，由 bootstrap 用默认值兜底。
  static Map<String, String> parseMeta(String lxJs) {
    String pick(String key) {
      final m = RegExp('@' + key + r'\s+([^\n*]+)').firstMatch(lxJs);
      return m?.group(1)?.trim() ?? '';
    }

    return {
      'name': pick('name'),
      'description': pick('description'),
      'version': pick('version'),
      'author': pick('author'),
    };
  }

  Future<LxSource> wrap(String lxJs, {String name = '洛雪源'}) async {
    // ① 先注入源元信息：必须在 bootstrap 之前，bootstrap 据此构造 currentScriptInfo
    final srcMeta = parseMeta(lxJs);
    final infoName = srcMeta['name']!.isEmpty ? name : srcMeta['name']!;
    await jsRuntime.evaluate(
      'globalThis.__lxName = ${jsonEncode(infoName)};'
      'globalThis.__lxDesc = ${jsonEncode(srcMeta['description'])};'
      'globalThis.__lxVersion = ${jsonEncode(srcMeta['version'])};'
      'globalThis.__lxAuthor = ${jsonEncode(srcMeta['author'])}; 1',
    );
    await jsRuntime.evaluate(_bootstrap);
    // ② 宿主侧搜索器（移植自 lx-music-desktop 的 kg/kw musicSearch）。
    //    洛雪协议里搜索是宿主职责，标准源只声明 musicUrl，
    //    故需在装配期就把宿主搜索器注入沙箱。详见 lx_host_search.dart。
    await jsRuntime.evaluate(LxHostSearchBundle.js);
    await jsRuntime.evaluate(lxJs); // ③ 加载源脚本本体
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

  /// 宿主搜索器已覆盖的平台（与 lx_host_search.dart 的 `__lxHostSearch` 对齐）
  static const _hostPlatforms = {'kg', 'kw', 'tx', 'wy', 'mg'};

  @override
  Future<List<SearchResult>> search(SearchQuery query) async {
    // ① 优先问源自身：兼容实现了 search / musicSearch 动作的扩展源
    //    （如「全豆要-聚合音源V4.1」的汽水子源）。标准洛雪源会 reject。
    final fromSource = await _searchFromSource(query);
    if (fromSource.isNotEmpty) return fromSource;

    // ② 源不含搜索 —— 这不是源残缺，而是洛雪协议把搜索放在宿主，
    //    故此处用宿主侧搜索器（酷狗/酷我）补齐。
    return _searchFromHost(query);
  }

  /// 调源 handler 的搜索动作，依次兼容两种社区约定：
  ///
  /// - **约定 A（xso 原有）**：`{source:'musicSearch', action:'search', info:{searchText}}`
  /// - **约定 B（社区扩展源，如「全豆要-聚合音源V4.1」的汽水子源）**：
  ///   `{source:平台id, action:'musicSearch', info:{keyword, page, pagesize}}`
  ///
  /// 两者的差异在于 `source` 字段与查询参数名：约定 A 把 `'musicSearch'` 当 source，
  /// 约定 B 要求 source 是源自身声明的平台 id（源内以 `if (source === 平台id)` 分流）。
  /// 全部失败/不支持时返回空表，交由宿主搜索兜底。
  Future<List<SearchResult>> _searchFromSource(SearchQuery query) async {
    final a = await _searchSourceConventionA(query);
    if (a.isNotEmpty) return a;
    return _searchSourceConventionB(query);
  }

  /// 约定 A：xso 原有调用式（保留向后兼容，勿删）
  Future<List<SearchResult>> _searchSourceConventionA(SearchQuery query) async {
    try {
      await _js.evaluate(
        '__lxSearchStart(${jsonEncode(query.keyword)})',
        timeout: const Duration(seconds: 15),
      );
      final raw = await _pollUntilDone();
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['__error'] != null) return const [];
      final list = decoded is Map
          ? (decoded['list'] ?? decoded['data']) as List?
          : decoded as List;
      return (list ?? []).whereType<Map>().map(_toSearchResult).toList();
    } catch (_) {
      return const []; // 「源未实现搜索」是洛雪标准源的预期行为，静默回退
    }
  }

  /// 约定 B：社区扩展源 —— 逐个平台发 `action='musicSearch'`，参数用 `keyword`
  Future<List<SearchResult>> _searchSourceConventionB(SearchQuery query) async {
    final platforms = await _sourcePlatforms();
    if (platforms.isEmpty) return const [];
    final out = <SearchResult>[];
    for (final p in platforms) {
      try {
        final request = jsonEncode({
          'source': p,
          'action': 'musicSearch',
          'info': {
            'keyword': query.keyword,
            'page': query.page,
            'pagesize': 30,
          },
        });
        final id = await _js.evaluate('__lxInvoke(${jsonEncode(request)})',
            timeout: const Duration(seconds: 15));
        final raw = await _pollInvoke(id);
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['__error'] != null) continue;
        final data = decoded is Map ? decoded['data'] : decoded;
        final list = data is Map
            ? (data['list'] ?? data['data']) as List?
            : (data is List ? data : null);
        out.addAll((list ?? []).whereType<Map>().map(_toSearchResult));
      } catch (_) {
        // 该平台未实现 musicSearch 属预期，继续下一个
      }
    }
    return out;
  }

  /// 宿主侧搜索：按源声明的平台，用内置搜索器（酷狗/酷我）搜出条目。
  /// 条目带 `__lxItem` 句柄，点播时仍由该源的 `musicUrl` 解析直链 ——
  /// 即「宿主搜索 + 源解析」，与洛雪原生架构一致。
  Future<List<SearchResult>> _searchFromHost(SearchQuery query) async {
    final platforms = await _sourcePlatforms();
    final out = <SearchResult>[];
    for (final p in platforms) {
      if (!_hostPlatforms.contains(p)) continue;
      // 实测：国内平台接口存在间歇性抖动（ECONNRESET / 偶发限流），连续 3 轮测试中
      // 出现过单次失败而下一轮成功的情况。失败后重试一次，避免因抖动白白丢掉
      // 一整个平台的结果；仍失败则静默跳过（单平台失败不阻塞其它平台）。
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          out.addAll(await _hostSearch(p, query.keyword, query.page));
          break;
        } catch (_) {
          if (attempt == 1) break;
        }
      }
    }
    return out;
  }

  /// 源 `send(EVENT_NAMES.inited)` 声明的平台列表（如 ['kg','kw','tx']）
  Future<List<String>> _sourcePlatforms() async {
    try {
      final raw = await _js.evaluate('__lxGetSources()',
          timeout: const Duration(seconds: 5));
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return const [];
  }

  Future<List<SearchResult>> _hostSearch(
      String platform, String keyword, int page) async {
    await _js.evaluate(
      '__lxHostSearchStart(${jsonEncode(platform)}, ${jsonEncode(keyword)}, $page, 30)',
      timeout: const Duration(seconds: 15),
    );
    final raw = await _pollHostSearch();
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded['__error'] != null) {
      throw Exception('宿主搜索失败: ${decoded['__error']}');
    }
    final list = decoded is Map ? decoded['list'] as List? : null;
    return (list ?? []).whereType<Map>().map(_toSearchResult).toList();
  }

  Future<String> _pollHostSearch(
      {Duration interval = const Duration(milliseconds: 150),
      int maxTries = 80}) async {
    for (var i = 0; i < maxTries; i++) {
      await Future<void>.delayed(interval);
      final raw = await _js.evaluate('__lxHostSearchTake()',
          timeout: const Duration(seconds: 5));
      if (raw != '__pending__') return raw;
    }
    throw Exception('宿主搜索超时');
  }

  /// 洛雪 musicInfo → xso SearchResult（源搜索与宿主搜索结果共用同一映射）
  SearchResult _toSearchResult(Map m) {
    // 源搜索给 qualities/_qualitys，宿主搜索给 types —— 三者都带上
    final q = m['qualities'] ?? m['_qualitys'] ?? m['types'];
    // 歌词优先取内联文本（洛雪 musicInfo._lyrText），其次歌词 URL。
    // 不带上它就只能去第三方歌词库按歌名撞，播放条线自带歌词的源也会显示"暂无歌词"
    final lyr = m['_lyrText'] ?? m['lyric'] ?? m['lyrics'];
    return SearchResult(
      sourceId: meta.id,
      sourceName: meta.name,
      type: SourceType.music,
      title: (m['name'] ?? m['title'])?.toString() ?? '(无标题)',
      url: (m['url'] ?? m['audio'] ?? '')?.toString() ?? '',
      extra: {
        if (m['singer'] != null) 'artist': m['singer'].toString(),
        if (m['artist'] != null) 'artist': m['artist'].toString(),
        if (m['albumName'] != null) 'album': m['albumName'].toString(),
        if (m['cover'] != null) 'cover': m['cover'].toString(),
        if (m['artwork'] != null) 'cover': m['artwork'].toString(),
        if (q != null) 'qualities': jsonEncode(q),
        if (lyr != null) 'lyric': lyr.toString(),
        if (m['source'] != null) 'lxSource': m['source'].toString(),
        // 洛雪取播放地址（action=musicUrl）要求把原 musicInfo 整体传回，
        // 缺这个句柄该源的歌就只能停在"未返回可播放地址"
        '__lxItem': jsonEncode(m),
      },
    );
  }

  /// 洛雪音质档位：MusicFree 的档位名转洛雪的 type
  static String _lxQuality(String quality) => switch (quality) {
        'higher' => '320k',
        'super' => 'flac',
        '128k' || '320k' || 'flac' => quality,
        _ => '128k',
      };

  /// 解析播放地址：洛雪协议 action='musicUrl'，info={type, musicInfo}，
  /// 多数源 resolve 出字符串，个别源返回 {url, headers}。
  Future<String> resolveMedia(SearchResult track,
      {String quality = 'standard'}) async {
    final rawItem = track.extra?['__lxItem'];
    if (rawItem == null || rawItem.isEmpty) return track.url;
    final musicInfo = jsonDecode(rawItem);
    final request = jsonEncode({
      'source': musicInfo is Map && musicInfo['source'] != null
          ? musicInfo['source'].toString()
          : 'musicUri',
      'action': 'musicUrl',
      'info': {
        'type': _lxQuality(quality),
        'musicInfo': musicInfo,
      },
    });
    final id = await _js.evaluate('__lxInvoke(${jsonEncode(request)})',
        timeout: const Duration(seconds: 15));
    final raw = await _pollInvoke(id);
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded['__error'] != null) {
      throw Exception('洛雪源取播放地址失败: ${decoded['__error']}');
    }
    final data = decoded is Map ? decoded['data'] : decoded;
    final url = data is String
        ? data
        : (data is Map ? (data['url'] ?? data['audio'])?.toString() : null) ?? '';
    if (!url.startsWith('http')) return track.url;

    // 洛雪 CDN 常要求 Referer，源把 headers 放在 {url, headers} 里返回时带给播放器
    final headers = data is Map ? data['headers'] : null;
    final extra = track.extra;
    if (headers is Map && headers.isNotEmpty && extra != null) {
      extra['__headers'] =
          jsonEncode(headers.map((k, v) => MapEntry(k.toString(), v.toString())));
    }
    return url;
  }

  /// 歌词（洛雪 action='lyric'）；源未提供时返回 null，交由上层退回第三方库
  Future<String?> fetchLyric(SearchResult track) async {
    final inline = track.extra?['lyric'];
    if (inline != null && inline.isNotEmpty) return inline;
    final rawItem = track.extra?['__lxItem'];
    if (rawItem == null || rawItem.isEmpty) return null;
    final musicInfo = jsonDecode(rawItem);
    final request = jsonEncode({
      'source': musicInfo is Map && musicInfo['source'] != null
          ? musicInfo['source'].toString()
          : 'musicLyric',
      'action': 'lyric',
      'info': {'musicInfo': musicInfo, 'quality': 'normal'},
    });
    try {
      final id = await _js.evaluate('__lxInvoke(${jsonEncode(request)})',
          timeout: const Duration(seconds: 15));
      final decoded = jsonDecode(await _pollInvoke(id));
      if (decoded is Map && decoded['__error'] != null) return null;
      final data = decoded is Map ? decoded['data'] : decoded;
      final text = data is String
          ? data
          : (data is Map ? (data['lyric'] ?? data['text'])?.toString() : null);
      return (text == null || text.isEmpty) ? null : text;
    } catch (_) {
      return null; // 无歌词不阻塞播放
    }
  }

  Future<String> _pollInvoke(String id,
      {Duration interval = const Duration(milliseconds: 120),
      int maxTries = 120}) async {
    for (var i = 0; i < maxTries; i++) {
      await Future<void>.delayed(interval);
      final raw = await _js.evaluate('__lxInvokeTake(${jsonEncode(id)})',
          timeout: const Duration(seconds: 5));
      if (raw != '__pending__') return raw;
    }
    throw Exception('洛雪源响应超时');
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
