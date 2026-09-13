import 'dart:convert';
import 'package:core/core.dart';
import 'package:source_engine/src/schema.dart';

class LegadoUnsupportedException implements Exception {
  final String feature;
  LegadoUnsupportedException(this.feature);
  @override
  String toString() => 'LegadoUnsupportedException: 不支持 $feature';
}

/// Legado 书源子集适配器：把简单书源翻译为内部自有格式 Source。
/// 支持：{{key}} 模板、@css:/@json: 规则、@text/@href/@title/@src 提取、
/// `||` 兜底链（取首个非空）、`##` 正则替换。
///
/// 兼容性判定仅作用于「搜索必需字段」（searchUrl + ruleSearch 的
/// bookList/name/bookUrl）。ruleSearch 的可选字段与正文/目录/发现页规则
/// 不影响搜索，不参与判定 —— 避免误杀可用书源。
/// 若必需字段使用了 java.* 宿主、`&&` 规则链或 `<js>` 内联脚本，
/// 仍会明确报 LegadoUnsupportedException（此类源需 JS 规则运行时）。
class LegadoAdapter {
  /// 尚不支持的语法（出现在搜索必需字段上才会拒绝整源）。
  /// `##`（正则替换）与 `||`（兜底链）已在 P1 实现，故不再拦截；
  /// 剩余项都依赖 JS 宿主或规则求值器，需 JS 运行时（P2）。
  ///
  /// `@js:` 与 `<js>` 已由 JS 运行时（buildRequest/parse 钩子）承接，不再拦截；
  /// 剩下三项都是无法在静态路径下正确处理的：
  /// - `java.`：裸宿主调用（不在 {{}} 或 @js: 内）无法静态求值
  /// - `&&`：Legado 的"且"规则链，JS 运行时也未实现
  /// - `{{js`：JS 模板表达式，同上
  static const _unsupportedMarkers = [
    'java.',
    '&&',
    '{{js',
  ];

  Source translate(String legadoJson) {
    final Map<String, dynamic> raw;
    try {
      raw = jsonDecode(legadoJson) as Map<String, dynamic>;
    } catch (_) {
      throw LegadoUnsupportedException('非法 JSON');
    }

    final searchUrl = raw['searchUrl'] as String?;
    final ruleSearch = _asRuleMap(raw['ruleSearch']);
    if (searchUrl == null || ruleSearch == null) {
      throw LegadoUnsupportedException('缺少 searchUrl 或 ruleSearch');
    }

    // 只校验「搜索必需字段」的不支持语法。原实现对整个 JSON 字符串做
    // contains 扫描，导致正文/目录/发现页/登录脚本里出现的 java./<js>/## 等
    // 也会一票否决整个源 —— 实测把可用书源的通过率从 ~52% 压到 8%。
    // 现在可选字段（author/kind/intro…）与搜索无关字段一律不参与判定。
    final base = (raw['bookSourceUrl'] as String? ?? '').trim();
    // 书源自带的公共 JS 库：规则里调用的 Config/getConfig/Api 等多定义在此。
    // 不加载它，规则执行必然报 "xxx is not defined"。
    final jsLib = (raw['jsLib'] as String? ?? '');
    final rawList = (ruleSearch['bookList'] as String? ?? '').trim();
    final rawName = (ruleSearch['name'] as String? ?? '').trim();
    final rawUrl = (ruleSearch['bookUrl'] as String? ?? '').trim();

    // searchUrl 三种形态：
    // 1) @js:/<js> 动态地址 → buildRequest 钩子真跑 JS
    // 2) 含 {{java.x}}/{{source.x}} 的动态模板 → 钩子 + renderTpl 渲染
    // 3) 静态地址 → 校验语法 + 相对路径补全
    String? buildRequestHook;
    var url = searchUrl;
    final jsUrl = _extractJs(searchUrl);
    if (jsUrl != null) {
      buildRequestHook = _buildRequestHook(jsUrl, base, jsLib);
      url = 'about:legado-js'; // 占位，实际地址由钩子返回
    } else if (_needsJsTemplate(searchUrl)) {
      buildRequestHook =
          '${_jsPrelude(base, jsLib: jsLib)}\n'
              'return renderTpl(${jsonEncode(searchUrl)});';
      url = 'about:legado-js';
    } else {
      _checkSupported(searchUrl, 'searchUrl');
      url = url.replaceAll('{{key}}', '{{keyword}}');
      // 相对路径（/search?q={{key}}）不补全会请求到一个假 URL —— 实测约半数源如此
      if (base.startsWith('http') && !url.startsWith('http')) {
        url = _joinUrl(base, url);
      }
    }

    // 解析规则里含 JS（@js:/<js>）时，整段解析交给 JS 运行时（parse 钩子），
    // 否则走静态 CSS/JSON 路径（更快，也不依赖 JS 引擎）。
    final jsInRules = [rawList, rawName, rawUrl].any((r) => _extractJs(r) != null);
    String? parseHook;
    ResultRule resultRule;
    if (jsInRules) {
      if (rawList.isEmpty || rawName.isEmpty) {
        throw LegadoUnsupportedException('缺少 ruleSearch.bookList 或 name');
      }
      parseHook = _buildParseHook(
          rawList, rawName, rawUrl.isEmpty ? 'a@href' : rawUrl, base, jsLib);
      // 占位：parse 钩子优先级最高，不会真的走 CSS 解析
      resultRule = const ResultRule(container: 'body', fields: {});
    } else {
      final bl = _requiredRule(ruleSearch, 'bookList');
      final nm = _requiredRule(ruleSearch, 'name');
      // bookUrl 可选：缺失或含不支持语法时降级到容器内首个 <a> 的 href
      final bu = _optionalRule(ruleSearch, 'bookUrl') ?? 'a@href';
      final titleRule = _buildFieldRule(nm);
      final urlRule = _buildFieldRule(bu);
      // Legado 里 `@json:` 前缀常被省略，直接写成 `$.data.list`。
      // 只认 `@json:` 会把这类源当成 CSS 选择器，直接抛 FormatException。
      final jsonList = _jsonPathOf(bl);
      resultRule = jsonList != null
          ? ResultRule(
              jsonPath: jsonList,
              fields: {'title': titleRule, 'url': urlRule},
            )
          : ResultRule(
              container: _parseSelector(bl),
              fields: {'title': titleRule, 'url': urlRule},
            );
    }

    return Source(
      meta: SourceMeta(
        id: 'legado://${raw['bookSourceUrl'] ?? ''}',
        name: raw['bookSourceName'] as String? ?? 'Legado书源',
        type: _mapType(raw['bookSourceType']),
        version: 1,
        origin: 'legado',
      ),
      search: SearchRule(
        request: RequestRule(url: url, headers: _parseHeaders(raw['header'])),
        result: resultRule,
      ),
      hooks: (buildRequestHook == null && parseHook == null)
          ? null
          : HooksRule(buildRequest: buildRequestHook, parse: parseHook),
      bookMeta: _buildBookMeta(raw['ruleBookInfo']),
      toc: _buildToc(null, raw['ruleToc']),
      content: _buildContent(raw['ruleContent']),
    );
  }

  /// Legado `ruleBookInfo` → 书籍详情元信息规则。
  ///
  /// 只有静态规则会被采纳：字段里含 `@js:`/`<js>` 的需要"逐字段 JS 求值"，
  /// 当前引擎还没这能力，返回 null 让上层隐藏该字段（而不是给出错误内容）。
  BookMetaRule? _buildBookMeta(dynamic rawInfo) {
    final info = _asRuleMap(rawInfo);
    if (info == null) return null;
    final r = BookMetaRule(
      cover: _optField(info['coverUrl']),
      intro: _optField(info['intro']),
      kind: _optField(info['kind']),
      lastChapter: _optField(info['lastChapter']),
      wordCount: _optField(info['wordCount']),
    );
    return r.isEmpty ? null : r;
  }

  /// Legado `ruleToc` → 目录规则。
  /// [chapterList] 参数用于兼容"目录就在详情页里"的写法（详情页即目录页）。
  TocRule? _buildToc(String? _, dynamic rawToc) {
    final toc = _asRuleMap(rawToc);
    if (toc == null) return null;
    final list = (toc['chapterList'] as String? ?? '').trim();
    final name = _optField(toc['chapterName']);
    final url = _optField(toc['chapterUrl']);
    if (list.isEmpty || name == null || url == null) return null;
    return TocRule(list: _parseSelector(list), name: name, url: url);
  }

  /// Legado `ruleContent` → 正文规则。
  ContentRule? _buildContent(dynamic rawContent) {
    final c = _asRuleMap(rawContent);
    if (c == null) return null;
    final content = _optField(c['content']);
    if (content == null) return null;
    return ContentRule(content: content, nextUrl: _optField(c['nextUrl']));
  }

  /// 把可选规则字段转成 FieldRule；含 JS 规则时返回 null（见 _buildBookMeta 说明）。
  FieldRule? _optField(dynamic raw) {
    if (raw is! String) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (_extractJs(s) != null) return null;
    if (s.contains('&&') || s.contains('{{js')) return null;
    return _buildFieldRule(s);
  }

  /// searchUrl 里的 `{{...}}` 是否需要真跑 JS 才能得出。
  ///
  /// 纯变量（`{{key}}`/`{{keyword}}`/`{{page}}`）走静态模板渲染即可；
  /// 但只要表达式里出现 `(`/`)`/`;`/`=`/`.`，就说明它是 Legado 的 JS 模板
  /// （典型如 `{{url=source.getKey(); cookie.removeCookie(url);}}`）——
  /// 此前只识别 `{{java.`/`{{source.` 开头，导致这类源把整段 JS 原样拼进 URL，
  /// 请求必然 400（实测御宅屋）。
  bool _needsJsTemplate(String url) {
    // 用 [\s\S] 而非 `.`：Legado 的 JS 模板常跨行书写
    // （`{{url=source.getKey();\ncookie.removeCookie(url);}}`），
    // `.` 不匹配换行会导致漏判。
    for (final m in RegExp(r'\{\{([\s\S]+?)\}\}').allMatches(url)) {
      final expr = (m.group(1) ?? '').trim();
      if (RegExp(r'[();=.]').hasMatch(expr)) return true;
    }
    return false;
  }

  /// 提取规则里的 JS 代码：`@js:` 之后，或 `<js>...</js>` 块内
  String? _extractJs(String rule) {
    final i = rule.indexOf('@js:');
    if (i >= 0) return rule.substring(i + 4).trim();
    final m = RegExp(r'<js>([\s\S]*?)</js>').firstMatch(rule);
    if (m != null) return m.group(1)!.trim();
    if (rule.startsWith('<js>')) {
      return rule.substring(4).replaceFirst(RegExp(r'</js>\s*$'), '').trim();
    }
    return null;
  }

  /// 把 Legado 的 JS searchUrl 包装成 buildRequest 钩子函数体，
  /// 并注入 Legado 规则依赖的运行时上下文（key/page/source/java）。
  ///
  /// 返回值约定：代码自带 return 时原样嵌入；否则用 eval 取最后表达式的值
  /// （Legado 的 JS 规则普遍以末行表达式作为结果）。
  String _buildRequestHook(String code, String base, [String jsLib = '']) {
    final body =
        code.contains('return') ? code : 'return eval(${jsonEncode(code)});';
    return '${_jsPrelude(base, jsLib: jsLib)}\n$body';
  }

  /// Legado 规则运行时上下文：key/page/baseUrl/source/java + 模板渲染
  /// （renderTpl，支持 {{java.xxx()}}）+ 规则求值（@js:/@css:/@json:/##/||）。
  ///
  /// 以源码字符串注入到 buildRequest / parse 钩子里，由 QuickJS 执行。
  /// HTML 提取优先用宿主内置的 cheerio（hostAsset 通道），拿不到时静默返回空。
  /// 拼装完整的 JS 运行环境。
  ///
  /// **顺序很关键，这里踩过两个坑：**
  /// - jsLib 拼在宿主对象**之后** → jsLib 里的 `var source` 会反向覆盖宿主
  ///   source，造成 `source.getVariable is not a function`（21 个源）；
  /// - jsLib 拼在宿主对象**之前** → jsLib 顶层代码若立即调用 `source.xxx`
  ///   又会因宿主尚未定义而报 undefined。
  ///
  /// 所以采用「宿主 → jsLib → 宿主再注入一次」：
  /// jsLib 执行时能用到宿主对象，执行完又被宿主对象复位，双向都不丢。
  /// jsLib 用 try 包裹做块级隔离 —— 它与规则代码常有 let/const 重名，
  /// 不隔离会让整个脚本在**解析阶段**就语法错误（语法错误 try 捕不到）。
  String _jsPrelude(String base, {String jsLib = ''}) {
    final host = _hostRuntime(base);
    if (jsLib.trim().isEmpty) return host;
    return '$host\ntry {\n$jsLib\n} catch (e) {}\n$host';
  }

  /// 宿主运行时对象：baseUrl/key/source/java/cookie/cache/crypto + 规则求值函数
  String _hostRuntime(String base) =>
      r'''
      var baseUrl = ''' +
      jsonEncode(base) +
      r''';
      var key = (typeof keyword !== 'undefined') ? keyword : '';
      var source = {
        bookSourceUrl: baseUrl,
        bookSourceName: '',
        bookSourceType: 0,
        lang: 'zh',
        getKey: function(){ return baseUrl; },
        getVariable: function(){ return globalThis.__legadoVar || '{}'; },
        setVariable: function(v){ globalThis.__legadoVar = v; },
        putVariable: function(v){ globalThis.__legadoVar = v; },
        // 书源常用 source.put/get 做跨规则缓存（等价 cache）
        put: function(k, v){ cache.put(k, v); },
        get: function(k){ return cache.get(k); },
        getUserAgent: function(){ return ''; },
        getLoginInfoMap: function(){ return {}; },
        getHeaderMap: function(){ return {}; },
        toString: function(){ return baseUrl; }
      };
      // Legado 的 Java 互操作入口：源里常 `JavaImporter(...).xxx`，
      // 缺这个全局会直接 "JavaImporter is not defined"（实测 3 个源）。
      var JavaImporter = (typeof JavaImporter !== 'undefined') ? JavaImporter
        : function(){ return new Proxy({}, {
            get: function(t, p){ return function(){ return ''; }; }
          }); };
      // Legado 的 crypto 宿主（加密/Base64）。注意不能只判 typeof：
      // 浏览器/Node 自带 webcrypto，同名但方法不同，必须按方法是否存在判断。
      var __cjs = (typeof CryptoJS !== 'undefined') ? CryptoJS : null;
      var crypto = (typeof crypto !== 'undefined' &&
                    typeof crypto.encryptBase64 === 'function') ? crypto : {
        md5: function(s){ return __cjs ? __cjs.MD5(String(s)).toString() : String(s); },
        encodeBase64: function(s){ return btoa(unescape(encodeURIComponent(String(s)))); },
        decodeBase64: function(s){ return decodeURIComponent(escape(atob(String(s)))); },
        encryptBase64: function(s, k){ try { return __cjs ? __cjs.AES.encrypt(String(s), String(k || '')).toString() : btoa(unescape(encodeURIComponent(String(s)))); } catch (e) { return ''; } },
        decryptBase64: function(s, k){ try { return __cjs ? __cjs.AES.decrypt(String(s), String(k || '')).toString(__cjs.enc.Utf8) : decodeURIComponent(escape(atob(String(s)))); } catch (e) { return ''; } },
        encryptAES: function(s, k){ return this.encryptBase64(s, k); },
        decryptAES: function(s, k){ return this.decryptBase64(s, k); },
        encryptDES: function(s, k){ return this.encryptBase64(s, k); },
        decryptDES: function(s, k){ return this.decryptBase64(s, k); }
      };
      // Legado 的 cache 宿主：书源用它做跨规则的键值缓存。
      // 方法名按 Legado 实际 API 补全（getMemory/putMemory 等缺失会让
      // 规则直接抛 "cache.putMemory is not a function"，实测 18 个源）。
      var cache = (typeof cache !== 'undefined') ? cache : {
        _m: {},
        get: function(k){ return this._m[k]; },
        put: function(k, v){ this._m[k] = v; },
        getMemory: function(k){ return this._m[k]; },
        putMemory: function(k, v){ this._m[k] = v; },
        getString: function(k){ var v = this._m[k]; return (v == null ? '' : String(v)); },
        putString: function(k, v){ this._m[k] = (v == null ? '' : String(v)); },
        delete: function(k){ delete this._m[k]; },
        remove: function(k){ delete this._m[k]; },
        clear: function(){ this._m = {}; }
      };
      var __javaBase = {
        encodeURI: encodeURI,
        encodeURIComponent: encodeURIComponent,
        base64Encode: function(s){ return btoa(unescape(encodeURIComponent(String(s)))); },
        base64Decode: function(s){ return decodeURIComponent(escape(atob(String(s)))); },
        md5: function(s){ return (typeof CryptoJS !== 'undefined') ? CryptoJS.MD5(String(s)).toString() : String(s); },
        md5Encode: function(s){ return this.md5(s); },
        hexDecodeToString: function(s){ return String(s); },
        toast: function(){}, longToast: function(){}, log: function(){},
        startBrowser: function(){ return true; },
        put: function(k, v){ cache.put(k, v); },
        get: function(k){ return cache.get(k); },
        ajax: function(){ throw new Error('java.ajax 需异步宿主，暂不支持'); }
      };
      // 未知 java.* 方法兜底：Legado 的 java 宿主方法很多（加密/文件/UI…），
      // 逐个实现不现实。用 Proxy 对未实现方法返回空函数，避免
      // "java.xxx is not a function" 直接炸掉整个源（实测约 8 个源因此失败）。
      var java = (typeof java !== 'undefined') ? java : new Proxy(__javaBase, {
        get: function(t, p){
          if (p in t) return t[p];
          if (typeof p !== 'string') return undefined;
          return function(){ return ''; };
        }
      });
      var cookie = { getCookie: function(){ return ''; }, removeCookie: function(){}, setCookie: function(){} };
      function loadCheerio(){
        if (typeof cheerio !== 'undefined') return cheerio;
        try {
          var src = sendMessage('hostAsset', JSON.stringify('cheerio'));
          if (src) { var geval = eval; geval(src); }
        } catch (e) {}
        return (typeof cheerio !== 'undefined') ? cheerio : null;
      }
      // Legado 大量书源直接调用 Java 的 Jsoup（Packages.org.jsoup.Jsoup.parse）
      // 解析 HTML。QuickJS/Node 里没有 Java 宿主，这里用 cheerio 提供
      // 语义兼容的最小实现（parse/select/text/attr/html/first/eq…）。
      function wrapEls($, els){
        try {
          var arr = els.toArray();
          arr.size = function(){ return arr.length; };
          arr.first = function(){ return wrapEls($, els.first()); };
          arr.last = function(){ return wrapEls($, els.last()); };
          arr.eq = function(i){ return wrapEls($, els.eq(i)); };
          arr.get = function(i){ return arr[i]; };
          arr.text = function(){ return els.text(); };
          arr.html = function(){ return els.html(); };
          arr.attr = function(s){ return els.attr(s); };
          arr.select = function(s){ return wrapEls($, els.find(s)); };
          return arr;
        } catch (e) { return []; }
      }
      var Packages = (typeof Packages !== 'undefined') ? Packages : {
        org: { jsoup: { Jsoup: {
          parse: function(html){
            var ch = loadCheerio();
            if (!ch) return { select: function(){ return []; } };
            try {
              var $ = ch.load(String(html == null ? '' : html));
              return {
                select: function(s){ return wrapEls($, $(String(s))); },
                body: function(){ return wrapEls($, $('body')); },
                text: function(){ return $('body').text(); }
              };
            } catch (e) { return { select: function(){ return []; } }; }
          }
        }}}
      };
      function renderTpl(tpl){
        return String(tpl).replace(/\{\{(.+?)\}\}/g, function(m, expr){
          expr = String(expr).trim();
          if (expr === 'key' || expr === 'keyword') return encodeURIComponent(key);
          if (expr === 'page') return String(page);
          try { var v = eval(expr); return (v == null ? '' : String(v)); } catch (e) { return ''; }
        });
      }
      function jsCodeOf(r){
        var s = String(r);
        var i = s.indexOf('@js:');
        if (i >= 0) return s.substring(i + 4);
        var m = /<js>([\s\S]*?)<\/js>/.exec(s);
        if (m) return m[1];
        return null;
      }
      function runJs(code, result){
        var body = (code.indexOf('return') >= 0) ? code : ('return eval(' + JSON.stringify(code) + ');');
        var fn = new Function('result', 'baseUrl', 'key', 'page', 'source', 'java', 'cookie', body);
        return fn(result, baseUrl, key, page, source, java, cookie);
      }
      function cssOf(r){
        var s = String(r);
        var i = s.indexOf('@css:');
        if (i >= 0) s = s.substring(i + 5);
        else if (s.indexOf('@json:') >= 0) s = s.substring(s.indexOf('@json:') + 6);
        var ai = s.indexOf('@');
        var attr = 'text';
        if (ai >= 0) { attr = s.substring(ai + 1).replace(/^@/, '').trim(); s = s.substring(0, ai); }
        return { sel: s.trim(), attr: attr };
      }
      function evalAtom(r, result){
        if (!r) return '';
        // 字段名直取：bookList 用 @js: 返回对象数组时，name/bookUrl 常写成
        // 'name'/'url' 这样的纯字段路径（不是选择器），此前会被当 CSS 处理而落空。
        if (result && typeof result === 'object' && !Array.isArray(result)) {
          var k = String(r).trim();
          if (/^[A-Za-z_][\w-]*$/.test(k) && Object.prototype.hasOwnProperty.call(result, k)) {
            var fv = result[k];
            return (fv == null ? '' : String(fv));
          }
        }
        var js = jsCodeOf(r);
        if (js) { try { var v = runJs(js, result); return (v == null ? '' : String(v)); } catch (e) { return ''; } }
        var c = cssOf(r);
        var ch = loadCheerio();
        if (!ch || !c.sel) return '';
        try {
          var $ = ch.load(String(result));
          var el = $(c.sel).first();
          if (!el || el.length === 0) return '';
          var v = (c.attr === 'text') ? el.text() : (c.attr === 'html' ? el.html() : el.attr(c.attr));
          return (v == null ? '' : String(v));
        } catch (e) { return ''; }
      }
      function evalRule(rule, result){
        var r = String(rule || '');
        var rep = null, to = '';
        var hi = r.indexOf('##');
        if (hi >= 0) {
          var rest = r.substring(hi + 2);
          r = r.substring(0, hi);
          var parts = rest.split('##');
          rep = parts[0]; to = parts.length > 1 ? parts.slice(1).join('##') : '';
        }
        var cands = r.split('||');
        for (var i = 0; i < cands.length; i++) {
          var v = evalAtom(cands[i].trim(), result);
          if (v != null && String(v).length > 0) {
            if (rep) { try { v = String(v).replace(new RegExp(rep), to); } catch (e) {} }
            return String(v);
          }
        }
        return '';
      }
      function evalList(rule, body){
        var js = jsCodeOf(rule);
        if (js) {
          try {
            var v = runJs(js, body);
            if (Array.isArray(v)) return v;
            if (v && typeof v === 'object') return [v];
            if (typeof v === 'string') {
              try { var p = JSON.parse(v); if (Array.isArray(p)) return p; } catch (e) {}
              return [v];
            }
          } catch (e) { return []; }
        }
        var r = String(rule || '');
        if (r.indexOf('@json:') >= 0) {
          var p2 = r.substring(r.indexOf('@json:') + 6).split('@')[0].trim();
          try {
            var cur = JSON.parse(String(body));
            var segs = p2.replace(/^\$\.?/, '').split(/[.\[\]]+/).filter(function(x){ return x; });
            for (var i = 0; i < segs.length; i++) { cur = cur[segs[i]]; }
            return Array.isArray(cur) ? cur : [cur];
          } catch (e) { return []; }
        }
        var c = cssOf(r);
        var ch = loadCheerio();
        if (!ch || !c.sel) return [];
        try {
          var $ = ch.load(String(body));
          var out = [];
          $(c.sel).each(function(){ out.push($.html(this)); });
          return out;
        } catch (e) { return []; }
      }
      function absUrl(u){
        var s = String(u || '').trim();
        if (!s) return '';
        if (/^https?:\/\//i.test(s)) return s;
        if (s.indexOf('//') === 0) return 'https:' + s;
        var b = String(baseUrl).replace(/\/+$/, '');
        return s.indexOf('/') === 0 ? (b + s) : (b + '/' + s);
      }
''' +
      // 书源自带的公共 JS 库必须在这里执行：大量源把 getConfig/Config/Api/
      // host 等函数定义在 jsLib 里，规则只是调用它们。此前完全忽略 jsLib，
      // 直接执行规则 → "X is not defined"（实测约 15 个源因此失败）。
      '';

  /// 解析规则含 JS 时，把"取列表 → 逐条取标题/链接"整段交给 JS 运行时。
  String _buildParseHook(String listRule, String nameRule, String urlRule,
      String base, [String jsLib = '']) {
    return '${_jsPrelude(base, jsLib: jsLib)}\n'
        // Legado 规则里 `result` 指"上一段结果"，取列表时就是整页 body。
        // 不声明会让源里的 `result.xxx` 直接 ReferenceError（实测 3 个源）。
        'var result = body;\n'
        'var __items = evalList(${jsonEncode(listRule)}, body);\n'
        'var __rows = [];\n'
        'for (var __i = 0; __i < __items.length; __i++) {\n'
        '  var __it = __items[__i];\n'
        '  var __t = evalRule(${jsonEncode(nameRule)}, __it);\n'
        '  var __u = evalRule(${jsonEncode(urlRule)}, __it);\n'
        '  if (!__u) __u = evalAtom("a@href", __it);\n'
        '  if (!__t && !__u) continue;\n'
        '  __rows.push({ title: __t || "", url: absUrl(__u) });\n'
        '}\n'
        'return JSON.stringify(__rows);';
  }

  /// 把一条 Legado 规则解析为结构化 FieldRule：
  /// - `||` 拆成候选链，取首个命中且非空的值
  /// - `##regex##replacement`（或 `##regex` 表示删除）转成正则替换
  FieldRule _buildFieldRule(String rule) {
    var core = rule;
    String? regex;
    String? replacement;
    final h = core.indexOf('##');
    if (h >= 0) {
      final rest = core.substring(h + 2);
      core = core.substring(0, h);
      final parts = rest.split('##');
      regex = parts[0].trim();
      replacement = parts.length > 1 ? parts.sublist(1).join('##') : '';
    }
    final cands = core
        .split('||')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (cands.isEmpty) {
      return FieldRule(
          selector: 'a',
          attr: 'href',
          replaceRegex: regex,
          replacement: replacement);
    }
    final sels = cands.map(_parseSelector).toList();
    return FieldRule(
      selector: sels.first,
      fallbackSelectors: sels.skip(1).toList(),
      attr: _extractAttr(cands.first),
      replaceRegex: regex,
      replacement: replacement,
    );
  }

  /// 解析书源自带的 header（Legado 的 `header` 字段）。
  ///
  /// 很多书源在这里带站点专用的 User-Agent / Cookie / Referer —— 这是源作者
  /// 针对该站风控调好的。此前整段忽略，导致请求以默认 UA 直连，
  /// 被站点按"非浏览器/异常客户端"拦截（403/444）。
  /// 值既可能是 JSON 字符串，也可能是对象，两种都兼容。
  Map<String, String> _parseHeaders(dynamic raw) {
    final out = <String, String>{};
    Map<dynamic, dynamic>? m;
    if (raw is Map) {
      m = raw;
    } else if (raw is String && raw.trim().startsWith('{')) {
      try {
        m = jsonDecode(raw) as Map<dynamic, dynamic>;
      } catch (_) {
        m = null; // 非法 JSON：忽略，不让一个坏字段炸掉整源
      }
    }
    m?.forEach((k, v) {
      if (k == null || v == null) return;
      final key = k.toString().trim();
      if (key.isNotEmpty) out[key] = v.toString();
    });
    return out;
  }

  /// 识别列表规则的 JSON 路径：支持 `@json:$.x` 与省略前缀的 `$.x`。
  /// 返回 null 表示这不是 JSON 规则，应按 HTML/CSS 处理。
  String? _jsonPathOf(String rule) {
    final s = rule.trim();
    if (s.startsWith('@json:')) {
      return _toJsonPath(s.substring(6).split('@').first.trim());
    }
    // Legado 常把 @json: 省略，直接写 $.data.list
    if (s.startsWith(r'$')) {
      return _toJsonPath(s.split('@').first.trim());
    }
    return null;
  }

  /// 规范化 jsonPath：缺 `$` 前缀自动补（Legado 常省略）
  String _toJsonPath(String path) {
    final p = path.trim();
    if (p.startsWith(r'$')) return p;
    return r'$..' + p;
  }

  /// 把相对路径按 Legado 语义拼到站点地址上
  String _joinUrl(String base, String path) {
    final b = base.replaceAll(RegExp(r'/+$'), '');
    return path.startsWith('/') ? '$b$path' : '$b/$path';
  }

  /// Legado bookSourceType → 内部 SourceType。
  ///
  /// 0=文本（**网文/小说**）→ novel，不是 book！
  /// book 保留给"电子书文件"型资源（zlib / 安娜档案馆的 epub/pdf），
  /// 二者混用会导致搜索结果里小说与电子书无法区分、无法分别筛选。
  /// 1=音频（有声书）/ 2=图片（漫画）/ 3=文件 / 4=视频（影视）。
  /// 缺省或无法识别的值按 0 处理（Legado 默认即文本型）。
  SourceType _mapType(dynamic t) {
    final v = t is num ? t.toInt() : int.tryParse(t?.toString() ?? '');
    switch (v) {
      case 1:
        return SourceType.audiobook;
      case 2:
        return SourceType.comic;
      case 3:
        return SourceType.book;
      case 4:
        return SourceType.video;
      case 0:
      default:
        return SourceType.novel;
    }
  }

  /// ruleSearch 兼容 dict 与 [dict]（部分站点导出为数组包裹）。
  Map<String, dynamic>? _asRuleMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is List && raw.isNotEmpty && raw.first is Map<String, dynamic>) {
      return raw.first as Map<String, dynamic>;
    }
    return null;
  }

  /// 取搜索必需规则，并仅对该字段做不支持语法检查。
  String _requiredRule(Map<String, dynamic> ruleSearch, String key) {
    final v = ruleSearch[key];
    if (v is! String || v.isEmpty) {
      throw LegadoUnsupportedException('缺少 ruleSearch.$key');
    }
    _checkSupported(v, 'ruleSearch.$key');
    return v;
  }

  /// 取可选规则：缺失或含不支持语法时返回 null（由调用方兜底），不抛错。
  String? _optionalRule(Map<String, dynamic> ruleSearch, String key) {
    final v = ruleSearch[key];
    if (v is! String || v.isEmpty) return null;
    for (final marker in _unsupportedMarkers) {
      if (v.contains(marker)) return null; // 可选字段不支持 → 降级，不连坐整源
    }
    return v;
  }

  /// 检查单条规则是否使用本适配器尚不支持的语法。
  void _checkSupported(String rule, String path) {
    for (final marker in _unsupportedMarkers) {
      if (rule.contains(marker)) {
        throw LegadoUnsupportedException('$path 使用不支持语法 "$marker"');
      }
    }
  }

  /// 尾部属性正则：只匹配末尾的 `@attr`（attr 为合法属性名）。
  /// 不能用 split('@').first —— 那会把 `//div[@class='x']`、`a[href*='/read/']`
  /// 这类选择器中间/内部的 @ 当成属性分隔符而截断（实测快眼看书被切成 `//div[`）。
  static final _tailAttr = RegExp(r'@([A-Za-z][\w:-]*)$');

  /// 解析 Legado 规则为本引擎 CSS 选择器。
  /// 支持 "@css:sel" / "sel"（默认 JSoup 语法子集）。
  String _parseSelector(String rule) {
    var s = rule.trim();
    if (s.startsWith('@css:')) {
      s = s.substring(5);
    } else if (s.startsWith('@json:')) {
      s = s.substring(6);
    }
    final m = _tailAttr.firstMatch(s);
    if (m != null) s = s.substring(0, m.start);
    s = s.trim();
    // Legado 用 JSoup 风格的 `class.box`（等价于 CSS 的 `.box`），
    // 直接传给 querySelectorAll 是非法选择器。
    s = s.replaceAllMapped(
      RegExp(r'(^|[\s>~+,(\[])class\.'),
      (mm) => '${mm.group(1) ?? ''}.',
    );
    // XPath（Legado 里非常常见）：Dart 的 html 包只认 CSS，需要转换。
    // 不转换会直接抛 FormatException，整个源报废。
    if (_isXPath(s)) return _xpathToCss(s);
    // 属性选择器规范化：`[href*=/voddetail/]` → `[href*="/voddetail/"]`。
    // html 包（csslib）要求属性值带引号；Legado 源普遍写成不带引号，
    // 值里含 `/` 时会被判为非法选择器并抛异常 → 该字段取不到值
    // （实测奈飞工厂标题正常、url 全为 null，最终整源判为无结果）。
    return s.replaceAllMapped(
      RegExp(r"""\[\s*([\w-]+)\s*([*^$~|]?=)\s*([^"'\]]+?)\s*\]"""),
      (m) => '[${m.group(1)}${m.group(2)}"${m.group(3)!.trim()}"]',
    );
  }

  /// XPath 特征：`//tag`、`/tag` 开头，或含 `[@attr='v']` 谓词。
  static bool _isXPath(String s) =>
      s.startsWith('//') ||
      s.startsWith('/') ||
      RegExp(r'\[@[\w-]+\s*=').hasMatch(s);

  /// XPath 子集 → CSS。覆盖 Legado 书源最常见的写法：
  /// `//div[@class='list']/ul/li` → `div.list > ul > li`
  /// `//ul[@class="a b"]/li`      → `ul.a.b > li`
  /// `//a/@title`                 → `a`（属性由 _extractAttr 单独处理）
  /// 超出子集的写法会退化成尽力而为的结果，由调用方容错。
  static String _xpathToCss(String xp) {
    var s = xp.trim();
    s = s.replaceAll(RegExp(r'/text\(\)\s*$'), ''); // XPath 的 text() 即 CSS 文本
    s = s.replaceAll(RegExp(r'/node\(\)\s*$'), '');
    final buf = StringBuffer();
    var i = 0;
    while (i < s.length) {
      if (s[i] == '/') {
        var j = i;
        while (j < s.length && s[j] == '/') {
          j++;
        }
        // `//` 表示任意后代（空格），单个 `/` 表示直接子级（>）
        if (buf.isNotEmpty) buf.write(j - i >= 2 ? ' ' : ' > ');
        i = j;
        continue;
      }
      // 读一个节点，遇到"括号外"的 / 停（[@class='a/b'] 里的 / 不算）
      var j = i;
      var depth = 0;
      while (j < s.length) {
        final c = s[j];
        if (c == '[') {
          depth++;
        } else if (c == ']') {
          depth--;
        } else if (c == '/' && depth <= 0) {
          break;
        }
        j++;
      }
      final node = _xpathNode(s.substring(i, j).trim());
      if (node.isNotEmpty) buf.write(node);
      i = j;
    }
    return buf.toString().trim();
  }

  /// 单个 XPath 节点 → CSS：`tag[@class='a b'][@id='x']` → `tag.x.a.b`
  static String _xpathNode(String node) {
    if (node.isEmpty || node == '*') return '';
    final bi = node.indexOf('[');
    final tag = bi >= 0 ? node.substring(0, bi).trim() : node;
    final pred = bi >= 0 ? node.substring(bi) : '';
    final cls = <String>[];
    final attrs = <String>[];
    String id = '';
    for (final m
        in RegExp(r"""\[@([\w-]+)\s*=\s*['"]([^'"]*)['"]\]""").allMatches(pred)) {
      final k = m.group(1)!;
      final v = m.group(2)!;
      if (k == 'class') {
        cls.addAll(v.split(RegExp(r'\s+')).where((e) => e.isNotEmpty));
      } else if (k == 'id') {
        id = '#$v';
      } else {
        attrs.add('[$k="$v"]');
      }
    }
    final sb = StringBuffer();
    if (tag.isNotEmpty && tag != '*') sb.write(tag);
    sb.write(id);
    for (final c in cls) {
      sb.write('.$c');
    }
    for (final a in attrs) {
      sb.write(a);
    }
    return sb.toString();
  }

  /// 提取属性：@text → text（默认）、@href → href、@html → html，
  /// 其余按 HTML 属性名原样使用（@src/@title/@data-src …）。
  /// 只认**末尾**的属性标记，避免误判选择器内部的 @。
  String _extractAttr(String rule) {
    final m = _tailAttr.firstMatch(rule.trim());
    final a = m?.group(1);
    if (a == null || a == 'text') return 'text';
    return a;
  }
}
