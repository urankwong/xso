import 'dart:async';
import 'dart:convert';
import 'package:core/core.dart';
import 'package:source_engine/src/js_runtime.dart';
import 'package:source_engine/src/rule_interpreter.dart';
import 'package:source_engine/src/schema.dart';
import 'package:source_engine/src/url_template.dart';

class SourceExecutionException implements Exception {
  final String sourceId;
  final String message;
  SourceExecutionException(this.sourceId, this.message);
  @override
  String toString() => 'SourceExecutionException($sourceId): $message';
}

/// 网络层抽象：由 app 层提供 dio 实现；引擎测试用假实现。
/// charset 处理 GBK 站点（app 层 dio + gbk 解码器负责）。
typedef Fetcher = Future<String> Function(
  String url, {
  String method,
  Map<String, String> headers,
  String charset,
});

/// 源引擎：编排"钩子→请求→解析→归一化"完整流程。
class SourceEngine {
  final JsRuntime jsRuntime;
  final Fetcher fetcher;
  static const hookTimeout = Duration(seconds: 5);
  static const searchTimeout = Duration(seconds: 10);

  /// 正文/目录串页的保护性上限：正常章节不会超过几十页分页，
  /// 超限视为站点异常（无限分页/翻页死循环），截断保命。
  static const maxContentPages = 50;
  static const maxTocPages = 50;

  SourceEngine({required this.jsRuntime, required this.fetcher}) {
    // 沙箱 API 白名单注册：JS 只能通过这些与外界交互
    jsRuntime.registerHostFunction('log', (args) async => null);
  }

  /// 单段/两段式列表搜索，返回归一化结果
  Future<List<SearchResult>> search(Source source, SearchQuery query) async {
    try {
      final rule = source.search!;
      // buildRequest 钩子优先：Legado 的 @js:/<js> searchUrl 必须真跑 JS
      // 才能算出地址，静态模板渲染不了。
      String url;
      final buildHook = source.hooks?.buildRequest;
      if (buildHook != null && buildHook.isNotEmpty) {
        url = await _runBuildRequestHook(
          buildHook,
          keyword: query.keyword,
          page: query.page,
        );
      } else {
        url = renderUrlTemplate(
          rule.request.url,
          keyword: query.keyword,
          page: query.page,
        );
      }
      final body = await fetcher(
        url,
        method: rule.request.method,
        headers: rule.request.headers,
        charset: rule.request.charset,
      ).timeout(searchTimeout);
      final rows = await _parseRows(source, body, query);
      // 表头/占位行等没有 url 的条目直接丢弃（url 是结果的最低要求）
      final usable =
          rows.where((row) => (row['url'] ?? '').isNotEmpty).toList();
      final twoPhase = source.detail != null;
      return usable
          .map((row) => _toResult(source, row, needsDetail: twoPhase))
          .toList();
    } on SourceExecutionException {
      rethrow;
    } catch (e) {
      throw SourceExecutionException(source.meta.id, e.toString());
    }
  }

  /// 两段式：详情页二次请求 + 正文网盘识别
  Future<List<SearchResult>> fetchDetail(
      Source source, SearchResult item) async {
    try {
      final detail = source.detail!;
      final detailUrl = item.url; // 列表 fields.url 即 detailUrl
      final url = _resolveDetailUrl(detail.request.url, detailUrl);
      final body =
          await fetcher(url, headers: _headersOf(source)).timeout(searchTimeout);

      // 正文选择器切出正文文本
      final contentText = extractHtmlText(body, detail.content);

      // 内置网盘识别器提取（App 级能力，core 提供）
      final links = detectPanLinks(contentText);
      return links
          .map((l) => SearchResult(
                sourceId: source.meta.id,
                sourceName: source.meta.name,
                type: source.meta.type,
                title: item.title,
                url: l.url,
                extractCode: l.extractCode,
                extra: {'provider': l.provider.name},
              ))
          .toList();
    } catch (e) {
      throw SourceExecutionException(source.meta.id, e.toString());
    }
  }

  /// 规则解释：parse 钩子兜底 / jsonPath / container+fields
  Future<List<Map<String, String?>>> _parseRows(
      Source source, String body, SearchQuery query) async {
    final result = source.search!.result;
    // 1) parse 钩子兜底优先级最高（作者显式声明用 JS）
    final parseHook = source.hooks?.parse;
    if (parseHook != null && parseHook.isNotEmpty) {
      return _runParseHook(parseHook, body,
          keyword: query.keyword, page: query.page);
    }
    // 2) JSON API（fields 的 selector 在 JSON 模式下表示字段路径）
    if (result?.jsonPath != null) {
      return interpretJson(body,
          jsonPath: result!.jsonPath!, fields: result.fields);
    }
    // 3) HTML 规则
    if (result?.container != null) {
      return interpretHtml(body,
          container: result!.container!, fields: result.fields ?? {});
    }
    throw SourceExecutionException(source.meta.id, '源缺少可用的结果解析规则');
  }

  /// buildRequest 钩子：JS 返回搜索地址。
  /// Legado 约定返回值可为 "url" 或 "url,{options}"，此处只取 URL 部分。
  Future<String> _runBuildRequestHook(
    String hook, {
    required String keyword,
    required int page,
  }) async {
    final script =
        '(function(keyword, page){ $hook })(${jsonEncode(keyword)}, $page)';
    final raw = await jsRuntime.evaluate(script, timeout: hookTimeout);
    return _stripLegadoOptions(raw.trim());
  }

  /// 去掉 Legado "url,JSON选项" 里的选项部分，只留地址
  String _stripLegadoOptions(String raw) {
    final i = raw.indexOf(',');
    if (i > 0 && raw.substring(i + 1).trimLeft().startsWith('{')) {
      return raw.substring(0, i).trim();
    }
    return raw;
  }

  Future<List<Map<String, String?>>> _runParseHook(
    String hook,
    String body, {
    String keyword = '',
    int page = 1,
  }) async {
    // keyword/page 一并注入：Legado 的解析规则常引用 key/page
    final script =
        '(function(body, keyword, page){ $hook })(${jsonEncode(body)}, ${jsonEncode(keyword)}, $page)';
    final raw = await jsRuntime.evaluate(script, timeout: hookTimeout);
    return (jsonDecode(raw) as List)
        .map((e) =>
            (e as Map).map((k, v) => MapEntry(k.toString(), v?.toString())))
        .toList();
  }

  /// 解析详情页地址。
  ///
  /// 搜索结果的 url 现在已**绝对化**（见 `_toResult`），而不少源的 detail
  /// 模板是 `https://站点{{detailUrl}}` 这种"给相对路径加前缀"的写法 ——
  /// 直接渲染会拼出 `https://站点https://站点/xxx`。
  /// 因此当明细地址已经是绝对 URL、且模板正好是「http 前缀 + 占位符」时，
  /// 直接采用明细地址（模板带额外后缀/参数的情况仍走渲染，避免丢参）。
  String _resolveDetailUrl(String tpl, String detailUrl) {
    if (detailUrl.startsWith('http') &&
        RegExp(r'^https?://[^{]*\{\{detailUrl\}\}$').hasMatch(tpl)) {
      return detailUrl;
    }
    return renderUrlTemplate(tpl, detailUrl: detailUrl);
  }

  SearchResult _toResult(Source source, Map<String, String?> row,
      {required bool needsDetail}) {
    final extra = Map<String, String?>.from(row)
      ..remove('title')
      ..remove('url')
      ..remove('code');
    // 链接必须绝对化：Legado 源的 bookUrl 规则普遍是相对路径
    // （如 `a@href` → `/novel/44162`）。原样透传会让后续所有环节失败——
    // 详情页/阅读器请求 `/novel/44162` 直接 DioException（无 host），
    // 收藏里存的也是打不开的相对地址。
    final rawUrl = row['url'] ?? '';
    final absUrl = _abs(rawUrl, _baseOf(source)) ?? rawUrl;
    return SearchResult(
      sourceId: source.meta.id,
      sourceName: source.meta.name,
      type: source.meta.type,
      title: row['title'] ?? '(无标题)',
      url: absUrl,
      extractCode: row['code'],
      extra: extra.map((k, v) => MapEntry(k, v ?? '')),
      needsDetail: needsDetail,
    );
  }

  // ── 在线阅读链路：详情 → 目录 → 正文 ────────────────────────────────

  /// 书源统一请求头（Legado 的 header 被翻译存到 search.request.headers）
  Map<String, String> _headersOf(Source s) =>
      s.search?.request.headers ?? const {};

  /// 站点根地址：把相对链接补成绝对地址时用
  String _baseOf(Source s) {
    final id = s.meta.id;
    if (id.startsWith('legado://')) return id.substring('legado://'.length);
    final u = s.search?.request.url ?? '';
    final i = u.indexOf('://');
    if (i < 0) return '';
    final rest = u.substring(i + 3);
    final slash = rest.indexOf('/');
    return slash < 0 ? u : '${u.substring(0, i + 3)}${rest.substring(0, slash)}';
  }

  String? _abs(String? u, String base) {
    if (u == null) return null;
    final s = u.trim();
    if (s.isEmpty) return null;
    // 已自带协议的一律原样返回：http/https，以及 magnet: / ed2k: / thunder: 等。
    // 只判 `startsWith('http')` 会把 `magnet:?xt=1` 拼成
    // `https://站点/magnet:?xt=1`，磁力/电驴链接直接报废。
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:').hasMatch(s)) return s;
    if (s.startsWith('//')) return 'https:$s';
    if (base.isEmpty) return s;
    final b = base.replaceAll(RegExp(r'/+$'), '');
    return s.startsWith('/') ? '$b$s' : '$b/$s';
  }

  Future<String> _get(String url, Source s) =>
      fetcher(url, headers: _headersOf(s)).timeout(searchTimeout);

  /// 书籍详情元信息（封面/简介/分类/最新章节）。
  /// 规则含 JS/`&&` 时走 JS 钩子，否则走静态 CSS 解析。
  Future<BookInfo> fetchBookInfo(Source source, String bookUrl) async {
    final hook = source.bookHooks?.bookInfo;
    final rule = source.bookMeta;
    if (hook == null && rule == null) return const BookInfo();
    try {
      final body = await _get(bookUrl, source);
      final base = _baseOf(source);
      if (hook != null) {
        final raw = await jsRuntime.evaluate(
            '(function(body){ $hook })(${jsonEncode(body)})',
            timeout: hookTimeout);
        final m = jsonDecode(raw) as Map<String, dynamic>;
        String? s(String k) {
          final v = m[k];
          if (v == null) return null;
          final t = v.toString().trim();
          return t.isEmpty ? null : t;
        }

        return BookInfo(
          cover: _abs(s('coverUrl'), base),
          intro: s('intro'),
          kind: s('kind'),
          lastChapter: s('lastChapter'),
          wordCount: s('wordCount'),
        );
      }
      String? f(FieldRule? r) => r == null ? null : extractField(body, r);
      return BookInfo(
        cover: _abs(f(rule!.cover), base),
        intro: f(rule.intro),
        kind: f(rule.kind),
        lastChapter: f(rule.lastChapter),
        wordCount: f(rule.wordCount),
      );
    } on SourceExecutionException {
      rethrow;
    } catch (e) {
      throw SourceExecutionException(source.meta.id, e.toString());
    }
  }

  /// 目录。Legado 的目录多数就在详情页（bookUrl 指向的那个页面）里，
  /// 少数站点用独立的目录页 —— 后者由源把 ruleToc 的链接写在详情页里，
  /// 当前实现先覆盖"同页"这一主流情况。
  ///
  /// 支持目录分页（`nextTocUrl`）：目录页带"下一页"链接时自动串页拼接，
  /// 按 URL 去重防重复章节，[maxTocPages] 上限 + visited 集合防死循环。
  Future<List<Chapter>> fetchChapters(Source source, String bookUrl) async {
    final hook = source.bookHooks?.toc;
    final rule = source.toc;
    if (hook == null && rule == null) return const [];
    try {
      final base = _baseOf(source);
      if (hook != null) {
        // JS 钩子路径：整段目录交给 JS（当前不支持钩子型目录分页）
        final body = await _get(bookUrl, source);
        final raw = await jsRuntime.evaluate(
            '(function(body){ $hook })(${jsonEncode(body)})',
            timeout: hookTimeout);
        final list = jsonDecode(raw);
        if (list is! List) return const [];
        final out = <Chapter>[];
        for (final e in list) {
          if (e is! Map) continue;
          final t = e['title']?.toString() ?? '';
          final u = e['url']?.toString() ?? '';
          if (u.isEmpty) continue;
          out.add(Chapter(title: t, url: _abs(u, base) ?? u));
        }
        return out;
      }
      final out = <Chapter>[];
      final seen = <String>{};
      final visited = <String>{bookUrl};
      var pageUrl = bookUrl;
      var pageBody = await _get(bookUrl, source);
      for (var page = 0; page < maxTocPages && pageUrl.isNotEmpty; page++) {
        final items = selectAll(pageBody, rule!.list);
        for (final it in items) {
          final t = extractFieldIn(it, rule.name);
          final u = extractFieldIn(it, rule.url);
          if (t == null || u == null) continue;
          final abs = _abs(u, base) ?? u;
          if (!seen.add(abs)) continue;
          out.add(Chapter(title: t, url: abs));
        }
        final nextRule = rule.nextUrl;
        if (nextRule == null) break;
        final n = _abs(extractField(pageBody, nextRule), base);
        if (n == null || n == pageUrl || !visited.add(n)) break;
        pageUrl = n;
        pageBody = await _get(pageUrl, source);
      }
      return out;
    } on SourceExecutionException {
      rethrow;
    } catch (e) {
      throw SourceExecutionException(source.meta.id, e.toString());
    }
  }

  /// 正文。支持三种分页来源，统一串页拼接为完整章节：
  /// 1. 静态 `nextUrl`/`nextContentUrl` 规则（每页解析"下一页"链接）；
  /// 2. JS 动态下一页钩子（`bookHooks.nextPage`，可返回单个 URL 或 URL 数组）；
  /// 3. 无分页规则（单页章节，直接返回）。
  ///
  /// 防护：visited 集合防环路、[maxContentPages] 上限防异常站点、
  /// 页与页之间以空行分隔避免段落粘连。
  Future<String> fetchContent(Source source, String chapterUrl) async {
    final hook = source.bookHooks?.content;
    final rule = source.content;
    if (hook == null && rule == null) return '';
    try {
      final base = _baseOf(source);
      final buf = StringBuffer();
      final visited = <String>{chapterUrl};
      final pending = <String>[chapterUrl];
      var pages = 0;
      while (pending.isNotEmpty && pages < maxContentPages) {
        final url = pending.removeAt(0);

        final pageBody = await _get(url, source);
        pages++;
        // 提取本页正文：JS 钩子优先，否则静态规则（多元素聚合）
        final raw = hook != null
            ? stripTags(await _evalBookHook(hook, pageBody, url, source))
            : extractFieldAll(pageBody, rule!.content);
        final text = raw?.trim() ?? '';
        if (text.isNotEmpty) {
          if (buf.isNotEmpty) buf.write('\n\n');
          buf.write(text);
        }
        final nexts = await _resolveNextPages(source, pageBody, url, base);
        for (final n in nexts) {
          if (visited.contains(n)) continue;
          visited.add(n);
          pending.add(n);
        }
      }
      return buf.toString().trim();
    } on SourceExecutionException {
      rethrow;
    } catch (e) {
      throw SourceExecutionException(source.meta.id, e.toString());
    }
  }

  /// 求值当前页的"下一页"地址列表（0 个 = 无下一页）。
  ///
  /// JS 动态钩子（含 `<js>` 的 nextContentUrl）优先于静态规则；
  /// 钩子返回值可能是字符串（单个 URL）或数组（一次性列出全部后续页，
  /// 典型如黄金屋按当前页码生成第 2..N 页）。
  Future<List<String>> _resolveNextPages(
      Source source, String pageBody, String pageUrl, String base) async {
    final nextHook = source.bookHooks?.nextPage;
    if (nextHook != null && nextHook.isNotEmpty) {
      final raw = await _evalBookHook(nextHook, pageBody, pageUrl, source);
      return _parseNextUrls(raw, base);
    }
    final nextRule = source.content?.nextUrl;
    if (nextRule == null) return const [];
    final n = _abs(extractField(pageBody, nextRule), base);
    if (n == null || n == pageUrl) return const [];
    return [n];
  }

  /// 解析下一页钩子返回值 → 绝对 URL 列表（JSON 字符串或裸 URL 容错）
  List<String> _parseNextUrls(String raw, String base) {
    final out = <String>[];
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return out;
    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      decoded = null;
    }
    final items = switch (decoded) {
      List l => l,
      String s => [s],
      _ => [trimmed], // 非 JSON 输出当作单个 URL
    };
    for (final e in items) {
      final u = _abs(e?.toString(), base);
      if (u != null && u.isNotEmpty) out.add(u);
    }
    return out;
  }

  /// 带重放协议的钩子求值（java.ajax 支持）。
  ///
  /// 背景：QuickJS 是同步引擎、Dart 无法提供同步网络，而 Legado 源里
  /// `java.ajax(url)` 是同步语义（Rhino 靠 Continuation 挂起实现）。
  /// 采用「重放」协议在纯同步 evaluate 内模拟：
  /// 1. 第 1 轮执行钩子，`java.ajax` 把缺失 URL 登记到 `__ajaxNeed` 并返回 ''；
  /// 2. 引擎发现待取列表 → 异步抓取 → `evaluate` 写入 `__ajaxCache`；
  /// 3. 重放钩子，本轮命中缓存。链式 ajax 由多轮重放天然支持。
  ///
  /// [hookAjaxRounds] 上限防"每轮都产生新请求"的非确定钩子死循环。
  /// 缺点：钩子每轮重复执行（副作用 API 重复调用，可接受）。
  static const hookAjaxRounds = 4;

  Future<String> _evalBookHook(
      String hook, String body, String? url, Source source) async {
    final params = 'body, url';
    final args = '(${jsonEncode(body)}, ${jsonEncode(url ?? '')})';
    for (var round = 0; round < hookAjaxRounds; round++) {
      final script = 'globalThis.__ajaxNeed = {};\n'
          'var __out = (function($params){ $hook })$args;\n'
          'var __keys = Object.keys(globalThis.__ajaxNeed);\n'
          'if (__keys.length > 0) { JSON.stringify({ __need: __keys }); }\n'
          'else { JSON.stringify({ __result: (__out == null ? null : String(__out)) }); }';
      final raw = await jsRuntime.evaluate(script, timeout: hookTimeout);
      Object? decoded;
      try {
        decoded = jsonDecode(raw.trim());
      } catch (_) {
        // 非 JSON 输出：视为纯结果（容错旧式运行时）
        return raw;
      }
      if (decoded is Map) {
        final need = decoded['__need'];
        if (need is List && need.isNotEmpty) {
          for (final u in need) {
            final target = u?.toString() ?? '';
            if (target.isEmpty) continue;
            final pageBody = await _get(target, source);
            await jsRuntime.evaluate(
                'globalThis.__ajaxCache = globalThis.__ajaxCache || {};\n'
                'globalThis.__ajaxCache[${jsonEncode(target)}] = ${jsonEncode(pageBody)};\n'
                '1',
                timeout: hookTimeout);
          }
          continue; // 重放
        }
        final result = decoded['__result'];
        return result?.toString() ?? '';
      }
      return raw;
    }
    return '';
  }
}

/// 书籍详情元信息（字段皆可空：不同站点能提供的信息差异很大）
class BookInfo {
  final String? cover;
  final String? intro;
  final String? kind;
  final String? lastChapter;
  final String? wordCount;
  const BookInfo({
    this.cover,
    this.intro,
    this.kind,
    this.lastChapter,
    this.wordCount,
  });

  bool get isEmpty =>
      cover == null &&
      intro == null &&
      kind == null &&
      lastChapter == null &&
      wordCount == null;
}

/// 目录条目
class Chapter {
  final String title;
  final String url;
  const Chapter({required this.title, required this.url});
}

/// 去掉正文里的 HTML 标签，转成可阅读的纯文本。
/// 换行标签先转 \n 再整体剥标签，避免段落全糊成一行。
String stripTags(String html) {
  var s = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</div\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  const entities = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&ldquo;': '“',
    '&rdquo;': '”',
  };
  entities.forEach((k, v) => s = s.replaceAll(k, v));
  return s
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
