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
  /// POST 请求体。Legado 源的 `java.post(url, body, headers)` 走重放协议
  /// （见 [_evalBookHook]）时需要真发 POST —— 很多源的**目录**就是靠
  /// POST 一个 JSON 接口拿的（实测部分爱下类电子书站），没有它这
  /// 类源会直接报"无法获取章节目录"。
  String? body,
});

/// 源引擎：编排"钩子→请求→解析→归一化"完整流程。
class SourceEngine {
  final JsRuntime jsRuntime;
  final Fetcher fetcher;
  static const hookTimeout = Duration(seconds: 5);
  static const searchTimeout = Duration(seconds: 10);

  /// 正文/目录串页的保护性上限：正常章节不会超过几十页分页，
  /// 超限视为站点异常（无限分页/翻页死循环），截断保命。
  ///
  /// 正文上限从 50 收到 20：50 页 × 每页千余字 ≈ 7 万字，早已超出任何
  /// 单章长度，实际上只在"翻页链路走错"时才会撞到（实测某小说站把后续
  /// 数章串进第一章，正好打满 50）。正常章节 20 页足够（3 万字级别）。
  static const maxContentPages = 20;
  static const maxTocPages = 50;

  /// 配不到标题时的占位文案。定义为常量以便重排时识别、把它们压到最后。
  static const untitled = '(无标题)';

  /// 是否对搜索结果做相关性重排（完全/前缀命中优先）。
  /// 默认为 true —— 站点自身的排序与用户输入无关，不重排时
  /// "诡秘之主"这类词的正主常被同人/模糊匹配项挤到后面。
  final bool rerankSearch;

  /// 用户自定义的正文替换规则（全局，作用于所有源）。
  ///
  /// 站点广告千奇百怪，内置规则永远追不上 —— 留给用户自己加一条，
  /// 才是这类问题的终局解法。由 App 层在规则变更时注入。
  List<ContentFilterRule> contentFilters;

  SourceEngine({
    required this.jsRuntime,
    required this.fetcher,
    this.rerankSearch = true,
    List<ContentFilterRule> contentFilters = const [],
  }) : contentFilters = List.of(contentFilters) {
    // 沙箱 API 白名单注册：JS 只能通过这些与外界交互
    jsRuntime.registerHostFunction('log', (args) async => null);
  }

  /// 更新用户替换规则（App 设置页改动后调用）
  void setContentFilters(List<ContentFilterRule> rules) {
    contentFilters = List.of(rules);
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
      final results = usable
          .map((row) => _toResult(source, row, needsDetail: twoPhase))
          .toList();
      // 站点返回的顺序是它自己的排序口径（更新时间/热度/推广位），
      // 与用户输入的关键词基本无关 —— 实测搜"诡秘之主"时，某电子书站把正主
      // 排在第 4（前三条是同人），黄金屋首条干脆是《拯救世界？抱歉，我妈是
      // 深渊之主》（站点按分词"之主"做的模糊匹配）。这里补一轮相关性重排。
      return _rerankByRelevance(results, query.keyword);
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
      title: row['title'] ?? untitled,
      url: absUrl,
      extractCode: row['code'],
      extra: extra.map((k, v) => MapEntry(k, v ?? '')),
      needsDetail: needsDetail,
    );
  }

  // ── 相关性重排 ────────────────────────────────────────────────────

  /// 把与关键词更贴近的结果排到前面。
  ///
  /// 站点返回的顺序是它自己的口径（更新时间/热度/推广位），跟用户输入
  /// 没关系。对本引擎而言后果很直接：站点按分词做模糊匹配时，"诡秘之主"
  /// 这类词的正主会被一堆同人甚至完全无关的书挤到后面。
  ///
  /// 这里只对**已解析出的这一批结果**调整先后位置：不增删条目、
  /// 不改写任何字段、也不改变源的筛选逻辑，纯粹是展示顺序的优化。
  List<SearchResult> _rerankByRelevance(
      List<SearchResult> list, String keyword) {
    final kw = _normalizeForMatch(keyword);
    if (!rerankSearch || kw.isEmpty || list.length < 2) return list;

    final scored = <_RelevanceScored>[];
    for (var i = 0; i < list.length; i++) {
      scored.add(_RelevanceScored(list[i], _matchScore(list[i].title, kw), i));
    }
    // Dart 的 List.sort 不保证稳定：同分时显式用原始下标兜底，
    // 保证站点自身的排序在组内被完整保留。
    scored.sort((a, b) {
      final c = a.score.compareTo(b.score);
      return c != 0 ? c : a.index.compareTo(b.index);
    });
    return scored.map((e) => e.result).toList();
  }

  /// 匹配分值：完全命中 › 前缀命中 › 包含 › 无关 › 兜底占位标题
  int _matchScore(String title, String kw) {
    // 标题解析失败时 [untitled] 往往一次出现几十条，让它们垫底，
    // 免得占着前排位置把有效结果挤到看不见的地方。
    if (title == untitled) return 4;
    final t = _normalizeForMatch(title);
    if (t.isEmpty) return 4;
    if (t == kw) return 0;
    if (t.startsWith(kw)) return 1;
    if (t.contains(kw)) return 2;
    return 3;
  }

  /// 归一化：抹掉空白与常见标点符号后再比对。
  ///
  /// 站点标题普遍带《》、全角标点或形如 `诡秘之主 ` 的尾随空格，
  /// 用户输入的关键词则通常不带 —— 不归一化会让精确命中几乎永不成立。
  static String _normalizeForMatch(String s) => s
      .replaceAll(RegExp(r'[\s　]+'), '')
      // 引号只能用 \u0022/\u0027 表示：Dart 的 raw string 不支持转义，
      // 直接写引号会提前终止字符串（这里由 RegExp 引擎去解释 \uXXXX）。
      .replaceAll(
          RegExp(
              r"[《》<>「」『』\[\]【】()（）:：,，.。、!！?？;；~～\-—_…·\u0022\u0027`，]"),
          '')
      .toLowerCase();

  /// 在线阅读链路：详情 → 目录 → 正文 ────────────────────────────────

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
    final base = _baseOf(source);
    try {
      final body = await _get(bookUrl, source).timeout(searchTimeout);
      if (hook != null) {
        try {
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
            intro: _cleanMetaText(s('intro')),
            kind: _cleanMetaText(s('kind')),
            lastChapter: _cleanMetaText(s('lastChapter')),
            wordCount: s('wordCount'),
          );
        } catch (_) {
          // JS 钩子失败 → 降级静态规则
          if (rule == null) return const BookInfo();
        }
      }
      String? f(FieldRule? r) => r == null ? null : extractField(body, r);
      return BookInfo(
        cover: _abs(f(rule!.cover), base),
        intro: _cleanMetaText(f(rule.intro)),
        kind: _cleanMetaText(f(rule.kind)),
        lastChapter: _cleanMetaText(f(rule.lastChapter)),
        wordCount: f(rule.wordCount),
      );
    } catch (_) {
      // 详情页整体抓取失败 → 返回空 BookInfo，不让详情页崩掉
      // （上层会从 search result 的 extra 里兜一些字段）
      return const BookInfo();
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
    final base = _baseOf(source);
    if (hook != null) {
      // JS 钩子路径：整段目录交给 JS（当前不支持钩子型目录分页）
      // 钩子失败时返回空而非抛错，不让详情页整体崩掉
      try {
        final body = await _get(bookUrl, source).timeout(searchTimeout);
        // 走 _evalBookHook：注入 Legado 运行环境（baseUrl/source/java…）
        // 并支持 java.ajax/post 重放协议。直接 evaluate 会让依赖宿主对象的
        // 目录钩子（如 baseUrl.match）第一行就抛错，目录恒为空。
        final raw = await _evalBookHook(hook, body, bookUrl, source);
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
      } catch (_) {
        return const [];
      }
    }
    final out = <Chapter>[];
    final seen = <String>{};
    final visited = <String>{bookUrl};
    var pageUrl = bookUrl;
    try {
      var pageBody = await _get(bookUrl, source).timeout(searchTimeout);
      for (var page = 0; page < maxTocPages && pageUrl.isNotEmpty; page++) {
        try {
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
          pageBody = await _get(pageUrl, source).timeout(searchTimeout);
        } catch (_) {
          // 单页目录解析失败 → 截断，已有章节返回
          break;
        }
      }
    } catch (_) {
      // 目录首页就失败 → 返回空（详情页显示「目录加载失败」提示）
    }
    return out;
  }

  /// 正文。支持三种分页来源，统一串页拼接为完整章节：
  /// 1. 静态 `nextUrl`/`nextContentUrl` 规则（每页解析"下一页"链接）；
  /// 2. JS 动态下一页钩子（`bookHooks.nextPage`，可返回单个 URL 或 URL 数组）；
  /// 3. 无分页规则（单页章节，直接返回）。
  ///
  /// 防护：visited 集合防环路、[maxContentPages] 上限防异常站点、
  /// 页与页之间以空行分隔避免段落粘连。
  ///
  /// [siblingChapterUrls] 是同一本书**其他章节**的 URL 集合（可选）。
  /// 传它是为了拦住一类很常见的站点行为：章节末页的"下一页"链接直接指向
  /// 下一章。无条件跟随时引擎会一路串下去 —— 实测某小说站第一章串了 50 页
  /// （打满上限）、正文 7 万字、耗时 17 秒，内容里混进了后面好几章。
  /// 只要"下一页"命中兄弟章节，就说明本章已结束，立即收尾。
  Future<String> fetchContent(Source source, String chapterUrl,
      {Set<String>? siblingChapterUrls, String? bookKey}) async {
    final hook = source.bookHooks?.content;
    final rule = source.content;
    if (hook == null && rule == null) return '';
    final base = _baseOf(source);
    // 预先归一化兄弟章节 URL：串页循环每轮都要比对，
    // 1451 章的书写逐次归一化整个集合是白白的重复开销。
    final siblingKeys = siblingChapterUrls
        ?.map(_normalizeUrlKey)
        .where((e) => e.isNotEmpty)
        .toSet();
    final buf = StringBuffer();
    final visited = <String>{chapterUrl};
    final pending = <String>[chapterUrl];
    var pages = 0;
    var consecutiveFailures = 0;
    while (pending.isNotEmpty && pages < maxContentPages) {
      final url = pending.removeAt(0);
      pages++;
      try {
        final pageBody = await _get(url, source).timeout(searchTimeout);
        consecutiveFailures = 0;

        // 提取本页正文：JS 钩子优先，但钩子失败时 fallback 到静态规则
        String raw = '';
        if (hook != null) {
          try {
            raw = stripTags(
                await _evalBookHook(hook, pageBody, url, source));
          } catch (_) {
            // JS 钩子失败 → 降级静态规则，不让整页丢失
            if (rule != null) {
              raw = extractFieldAll(pageBody, rule.content) ?? '';
            }
          }
        } else if (rule != null) {
          raw = extractFieldAll(pageBody, rule.content) ?? '';
          // 规则写成 `xxx@html` 时拿到的是元素 innerHtml —— 标签会原样
          // 落进正文，而阅读页是纯文本渲染，于是整章可见 <p>/<a href=...>，
          // 排版全乱（部分小说站实测如此）。
          // JS 钩子那条路径已经 stripTags 过，静态路径必须做同样处理。
          if (rule.content.attr == 'html') raw = stripTags(raw);
        }
        // 如果规则完全没命中，尝试用 body 全文本作为最后兜底
        if (raw.trim().isEmpty) {
          raw = _extractBodyFallback(pageBody);
        }
        final text = raw.trim();
        if (text.isNotEmpty) {
          if (buf.isNotEmpty) buf.write('\n\n');
          buf.write(text);
        }
        // 解析下一页链接（单页失败不影响串页）
        try {
          final nexts =
              await _resolveNextPages(source, pageBody, url, base);
          var crossedChapter = false;
          for (final n in nexts) {
            if (visited.contains(n)) continue;
            // 跨章保护：站点在章节末页把"下一页"指向下一章，跟着走会把
            // 后续章节的内容并进本章（实测某小说站串 50 页、正文 7 万字）。
            // 命中兄弟章节 → 本章结束，停止串页。
            if (siblingKeys != null &&
                siblingKeys.contains(_normalizeUrlKey(n))) {
              crossedChapter = true;
              break;
            }
            visited.add(n);
            pending.add(n);
          }
          if (crossedChapter) break;
        } catch (_) {
          // 下一页解析失败 → 截断分页，已有内容保留
        }
      } catch (_) {
        // 单页获取/解析失败 → 跳过，继续下一页
        consecutiveFailures++;
        if (consecutiveFailures >= 3) break; // 连续 3 页失败视为异常站点
      }
    }
    // 全局正文清洗（广告过滤 + 空白规范化 + 用户自定义替换）
    // sourceKey 用来筛选"仅本源"的规则；bookKey 由 App 侧传入（本书标识）。
    return sanitizeContent(
      buf.toString(),
      filters: contentFilters,
      bookKey: bookKey,
      sourceKey: source.meta.id,
    );
  }

  /// 详情页文本字段的标签清洗。
  ///
  /// `ruleBookInfo` 常写成 `xxx@html`，取到的是 innerHtml，标签会原样显示
  /// 在详情页简介里（实测某小说站简介满屏 `<br/>`、`&quot;未知&quot;`）。
  ///
  /// 只在**确实含标签**时才剥离：简介里出现孤立的 `<` 或 `>` 是可能的
  /// （数学式、颜文字），无脑 stripTags 会把后面的内容一起吃掉。
  static String? _cleanMetaText(String? s) {
    if (s == null) return null;
    final t = RegExp(r'<[a-zA-Z/][^>]*>').hasMatch(s) ? stripTags(s) : s.trim();
    return t.isEmpty ? null : t;
  }

  /// URL 归一化键：用于判断两个地址是否指向同一章节。
  ///
  /// 去 fragment、去末尾斜杠、统一小写。之所以要归一化而不是直接字符串
  /// 比较：目录 URL 由 chapterUrl 规则拼出、"下一页"链接由 nextContentUrl
  /// 规则拼出，两者可能只差一个末尾斜杠或大小写。**漏判的代价是跨章串页**
  /// （把后面几章并进本章，实测某小说站 7 万字），所以宁可匹配得宽松些。
  static String _normalizeUrlKey(String u) {
    var s = u.trim();
    final hash = s.indexOf('#');
    if (hash >= 0) s = s.substring(0, hash);
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s.toLowerCase();
  }

  /// [extractFieldAll] 完全没命中任何选择器时的最后兜底：
  /// 直接从 <body> 提取纯文本，移除导航/页脚/script/style 等噪音。
  String _extractBodyFallback(String html) {
    try {
      var s = html
          .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '') // HTML 注释
          .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<nav[\s\S]*?</nav>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<footer[\s\S]*?</footer>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<header[\s\S]*?</header>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<aside[\s\S]*?</aside>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<iframe[\s\S]*?</iframe>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<noscript[\s\S]*?</noscript>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<form[\s\S]*?</form>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'</div\s*>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), '');
      return _decodeEntities(s).trim();
    } catch (_) {
      return '';
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

  /// 带重放协议的钩子求值（java.ajax / java.post 支持）。
  ///
  /// 背景：QuickJS 是同步引擎、Dart 无法提供同步网络，而 Legado 源里
  /// `java.ajax(url)` / `java.post(url, body, headers)` 是同步语义
  /// （Rhino 靠 Continuation 挂起实现）。采用「重放」协议在纯同步
  /// evaluate 内模拟：
  /// 1. 第 1 轮执行钩子，缺失的请求登记到 `__ajaxNeed` 并返回空占位；
  /// 2. 引擎发现待取列表 → 异步抓取（按登记的 method/body）→
  ///    写入 `__ajaxCache`；
  /// 3. 重放钩子，本轮命中缓存。链式请求由多轮重放天然支持。
  ///
  /// 登记项兼容两种形态：字符串（旧 ajax 协议的裸 URL，当作 GET），
  /// 或 `{method, url, body, key}` 对象（新协议，支持 POST）。
  ///
  /// [hookAjaxRounds] 上限防"每轮都产生新请求"的非确定钩子死循环。
  /// 缺点：钩子每轮重复执行（副作用 API 重复调用，可接受）。
  static const hookAjaxRounds = 4;

  /// 钩子运行环境前导脚本。
  ///
  /// 目录/正文的 JS 钩子直接使用 Legado 的宿主对象 —— 实测某电子书站的
  /// `ruleToc.chapterList` 第一行就是 `baseUrl.match(/read\/(\d+)/)`，接着用
  /// `java.post(source.getKey()+"/novel/clist/", "bid="+bid, {})` 取目录 JSON。
  /// 而 [fetchChapters] 原来只注入 `(function(body){...})`，`baseUrl`/`source`/
  /// `java` 全部未定义 → 第一行就 ReferenceError → 目录恒为空，
  /// 详情页只能提示"暂时无法获取章节目录"。
  ///
  /// 这里给出钩子真正用得到的最小集合（含 java.ajax/post 的重放协议）。
  /// 注：与 adapter 的 `_hostRuntime` 有意重叠一部分 —— 后者还带 cheerio/Jsoup
  /// shim，属于规则求值专用；两者后续可抽成公共模块。
  /// [base]   = 当前页地址（Legado 钩子里的 `baseUrl`，如书页 URL）
  /// [sourceKey] = 书源根地址（`source.getKey()` / `source.bookSourceUrl`）
  ///
  /// **两者必须分开**：目录钩子常用 `baseUrl.match(/read\/(\d+)/)` 提书号，
  /// 再用 `source.getKey() + "/novel/clist/"` 拼接口。混成一个值会拼出
  /// `https://站/read/191976//novel/clist/` 这种多一段的错误地址，
  /// 接口拿不到数据，目录就永远是空的。
  String _hookPrelude(String base, String sourceKey) => '''
var baseUrl = ${jsonEncode(base)};
var key = '';
var source = {
  bookSourceUrl: ${jsonEncode(sourceKey)},
  bookSourceName: '', bookSourceType: 0, lang: 'zh',
  getKey: function(){ return ${jsonEncode(sourceKey)}; },
  getVariable: function(){ return globalThis.__legadoVar || '{}'; },
  setVariable: function(v){ globalThis.__legadoVar = v; },
  putVariable: function(v){ globalThis.__legadoVar = v; },
  put: function(){}, get: function(){ return ''; },
  getUserAgent: function(){ return ''; },
  getLoginInfoMap: function(){ return {}; },
  getHeaderMap: function(){ return {}; }
};
var cookie = { getCookie: function(){ return ''; }, setCookie: function(){}, removeCookie: function(){} };
var cache = { get: function(){ return ''; }, put: function(){}, delete: function(){}, clear: function(){} };
var java = {
  ajax: function(url){
    var k = String(url == null ? '' : url);
    var c = (globalThis.__ajaxCache = globalThis.__ajaxCache || {});
    var n = (globalThis.__ajaxNeed = globalThis.__ajaxNeed || {});
    if (k in c) return c[k];
    n[k] = { method: 'GET', url: k, key: k };
    return '';
  },
  post: function(url, postBody){
    var k = String(url == null ? '' : url);
    var b = (postBody == null ? '' : String(postBody));
    var kk = 'POST\\u0001' + k + '\\u0001' + b;
    var c = (globalThis.__ajaxCache = globalThis.__ajaxCache || {});
    var n = (globalThis.__ajaxNeed = globalThis.__ajaxNeed || {});
    var resp = function(t, ok){ return {
      body: function(){ return t; }, code: function(){ return ok ? 200 : 0; },
      message: function(){ return ok ? 'OK' : ''; }, headers: function(){ return {}; },
      header: function(){ return ''; }, isSuccessful: function(){ return !!ok; } }; };
    if (kk in c) return resp(c[kk], true);
    n[kk] = { method: 'POST', url: k, body: b, key: kk };
    return resp('', false);
  }
};
''';

  Future<String> _evalBookHook(
      String hook, String body, String? url, Source source) async {
    final params = 'body, url';
    final args = '(${jsonEncode(body)}, ${jsonEncode(url ?? '')})';
    final prelude = _hookPrelude(url ?? _baseOf(source), _baseOf(source));
    // 重放缓存放在 Dart 侧：JS 运行时的 globalThis **不跨 evaluate 保留**
    // （每次 evaluate 都是干净上下文），上一轮抓回的响应若不重新注入，
    // 下一轮就会重新发请求、重放永远不收敛 —— 实测 4 轮跑完仍返回空目录。
    final ajaxCache = <String, String>{};
    for (var round = 0; round < hookAjaxRounds; round++) {
      final cacheSeed = StringBuffer();
      ajaxCache.forEach((k, v) {
        cacheSeed.write(
            '(globalThis.__ajaxCache = globalThis.__ajaxCache || {})'
            '[${jsonEncode(k)}] = ${jsonEncode(v)};\n');
      });
      final script = '$prelude\n'
          '$cacheSeed'
          'globalThis.__ajaxNeed = {};\n'
          'var __out = null, __err = null;\n'
          // 钩子必须在 try 里跑：重放协议第 1 轮给 java.ajax/post 返回的是
          // 空占位，而钩子往往紧接着就 `JSON.parse(resp.body())` —— 空串
          // 解析会立刻抛异常，异常冒到 evaluate 之外就等于**放弃这一轮**，
          // 于是永远走不到第 2 轮重放（目录恒为空的真凶）。
          // 用 JS 内部 catch 兜住：请求已登记就正常进入下一轮。
          'try { __out = (function($params){ $hook })$args; } catch (e) { __err = String(e); }\n'
          'var __keys = Object.keys(globalThis.__ajaxNeed);\n'
          // 传**值**而不是键：POST 的键里含 body（用于区分同址不同表单体），
          // 直接当 URL 用会拼出 "POST\u0001https://…\u0001bid=191976"。
          'if (__keys.length > 0) { JSON.stringify({ __need: __keys.map(function(k){ return globalThis.__ajaxNeed[k]; }) }); }\n'
          // 不能 String(__out)：目录钩子返回的是数组，String() 会得到
          // "[object Object],…" 而丢掉全部数据。交给 JSON.stringify 处理。
          'else { JSON.stringify({ __result: (__out == null ? null : __out), __err: __err }); }';
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
          for (final item in need) {
            // 从登记项解出请求参数
            String target = '';
            var method = 'GET';
            String? reqBody;
            String cacheKey = '';
            if (item is String) {
              target = item;
              cacheKey = item;
            } else if (item is Map) {
              target = item['url']?.toString() ?? '';
              method = (item['method']?.toString() ?? 'GET').toUpperCase();
              reqBody = item['body']?.toString();
              cacheKey = item['key']?.toString() ?? target;
            }
            if (target.isEmpty) continue;
            String pageBody = '';
            try {
              if (method == 'POST') {
                pageBody = await fetcher(
                  target,
                  method: 'POST',
                  headers: {
                    // 源没指定就以表单提交（Legado 源的 POST 绝大多数是表单式）
                    'Content-Type': 'application/x-www-form-urlencoded',
                    ..._headersOf(source),
                  },
                  body: reqBody ?? '',
                ).timeout(searchTimeout);
              } else {
                pageBody = await _get(target, source);
              }
            } catch (e) {
              // 单个请求失败不炸整条钩子：写空串让 JS 走它的失败分支
              print('[引擎] 钩子内请求失败 $method $target: $e');
            }
            ajaxCache[cacheKey] = pageBody; // 存 Dart 侧，下一轮随 script 注入
          }
          continue; // 重放
        }
        final result = decoded['__result'];
        if (result == null) {
          final err = decoded['__err'];
          if (err != null && err.toString().trim().isNotEmpty) {
            // 不是"缺数据"而是钩子自身出错 —— 打出来便于定位源规则问题
            print('[引擎] 钩子执行报错: $err');
          }
          return '';
        }
        // 字符串（正文钩子）直接返回；数组/对象（目录钩子）序列化回 JSON
        return result is String ? result : jsonEncode(result);
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
/// 补充处理 HTML 注释、iframe/noscript/form 等噪音标签。
String stripTags(String html) {
  var s = html
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '') // HTML 注释（广告/统计常写在注释里）
      .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<iframe[\s\S]*?</iframe>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<noscript[\s\S]*?</noscript>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<form[\s\S]*?</form>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</div\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</tr\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</h[1-6]\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  s = _decodeEntities(s);
  return _normalizeWhitespace(s);
}

/// HTML entities 解码：覆盖命名实体 + 十进制/十六进制数字实体。
/// 命名实体表比原版本大幅扩展，覆盖网文站点常见的特殊符号。
String _decodeEntities(String s) {
  // 先处理数字实体（&#12345; / &#xABCD;）
  s = s.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (m) {
        final code = int.tryParse(m.group(1)!);
        return code == null ? m.group(0)! : String.fromCharCode(code);
      });
  s = s.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (m) {
        final code = int.tryParse(m.group(1)!, radix: 16);
        return code == null ? m.group(0)! : String.fromCharCode(code);
      });
  // 再处理命名实体（覆盖常见中文标点 + 标准符号）
  const entities = {
    // 基础
    '&nbsp;': ' ', '&ensp;': ' ', '&emsp;': ' ', '&thinsp;': ' ',
    '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'",
    // 引号/标点
    '&ldquo;': '"', '&rdquo;': '"', '&lsquo;': ''', '&rsquo;': ''',
    '&laquo;': '«', '&raquo;': '»', '&lsaquo;': '‹', '&rsaquo;': '›',
    '&sbquo;': '"', '&bdquo;': '"',
    // 短横线/连接线
    '&ndash;': '–', '&mdash;': '—', '&horbar;': '―',
    '&oline;': '‾', '&lowbar;': '_', '&commat;': '@',
    // 斜杠
    '&sol;': '/', '&bsol;': '\\',
    // 省略号
    '&hellip;': '…', '&ctdot;': '⋯', '&vellip;': '⋮', '&lowast;': '*',
    // 数学符号
    '&minus;': '−', '&plusmn;': '±', '&times;': '×', '&divide;': '÷',
    '&equal;': '=', '&ne;': '≠', '&le;': '≤', '&ge;': '≥',
    '&asymp;': '≈', '&equiv;': '≡', '&infin;': '∞', '&radic;': '√',
    // 箭头
    '&larr;': '←', '&rarr;': '→', '&uarr;': '↑', '&darr;': '↓',
    '&harr;': '↔', '&crarr;': '↵',
    // 几何
    '&bull;': '•', '&circ;': '○', '&loz;': '◊',
    // 货币
    '&yen;': '¥', '&euro;': '€', '&pound;': '£', '&cent;': '¢', '&dollar;': '\$',
    // 版权/商标
    '&copy;': '©', '&reg;': '®', '&trade;': '™',
    // 常用数字
    '&frac12;': '½', '&frac14;': '¼', '&frac34;': '¾',
    // 空格变体
    '&zwj;': '', '&zwnj;': '', '&lrm;': '', '&rlm;': '',
  };
  entities.forEach((k, v) => s = s.replaceAll(k, v));
  return s;
}

/// 正文全局清洗管道：移除广告、清理异常空白、保留阅读友好的格式。
///
/// 在多页拼接完成后统一调用，避免每页单独处理的重复开销。
/// 按"正则匹配 → 行过滤 → 空白规范化"三步流水线执行。
String sanitizeContent(
  String raw, {
  List<ContentFilterRule> filters = const [],
  String? bookKey,
  String? sourceKey,
}) {
  if (raw.isEmpty) return '';
  var s = raw;

  // 第 1 步：移除常见网文广告/噪音文本（多行段匹配）
  s = _stripAdBlocks(s);

  // 第 2 步：按行过滤广告短句
  final lines = s.split('\n');
  final kept = <String>[];
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      kept.add('');
      continue;
    }
    if (_isAdLine(trimmed)) continue;
    kept.add(_stripPagingMarks(line));
  }
  s = kept.join('\n');

  // 第 3 步：空白规范化
  s = _normalizeWhitespace(s);

  // 第 4 步：移除章节头尾的常见导航/版权短句
  s = _stripChapterFraming(s);

  // 第 5 步：应用用户自定义替换规则（在最后 —— 用户看到的是已去过
  // 广告的文本，写规则时不必考虑原始 HTML 与站点模板）
  s = applyContentFilters(s, filters, bookKey: bookKey, sourceKey: sourceKey);

  return s.trim();
}

/// 应用用户自定义的正文替换规则。
///
/// 只跑**作用范围匹配得上**的规则：[bookKey]/[sourceKey] 为空时仅放行全局
/// 规则 —— 宁可不生效，也不要拿"限定在某本书"的规则去改别的书。
///
/// 单条规则出错（非法正则、替换串里的 `$` 引用越界）一律跳过，
/// 绝不让一条坏规则毁掉整章正文 —— 与源级 `##` 替换同一原则。
String applyContentFilters(
  String text,
  List<ContentFilterRule> rules, {
  String? bookKey,
  String? sourceKey,
}) {
  if (text.isEmpty || rules.isEmpty) return text;
  var s = text;
  for (final r in rules) {
    if (!r.enabled || r.pattern.trim().isEmpty) continue;
    if (!r.appliesTo(bookKey: bookKey, sourceKey: sourceKey)) continue;
    try {
      s = s.replaceAll(RegExp(r.pattern), r.replacement);
    } catch (_) {
      // 非法正则 / 非法替换串 → 跳过该条
    }
  }
  return s;
}

/// 多行广告块移除：匹配段落级别的广告模板。
/// 用 RegExp caseSensitive: false 做宽松匹配。
String _stripAdBlocks(String s) {
  // 「本章未完，点击下一页继续阅读」类 → 但要小心真的分页！
  // 这里只移除明显是广告/引导的模板，"点击下一页"可能是正常分页文案，
  // 留在 _stripChapterFraming 里做更精确的位置判断。

  // 移除"本书首发"类宣传块（跨多行的情况）
  s = s.replaceAllMapped(
      RegExp(
          r'(本书|首发|首发站|首发网站|独家首发|全文字|最新章节|无弹窗|无广告|广告位|广告招租)[^\n]{0,30}(请访问|访问|请百度|请搜索|手机用户|下载|扫码|阅读)[^\n]{0,30}',
          caseSensitive: false),
      (_) => '');

  // 移除链接残留（[xxx](http://...) / 裸 http://）
  s = s.replaceAll(RegExp(r'\[[^\]]+\]\([^)]+\)'), '');
  s = s.replaceAll(RegExp(r'https?://[^\s\u4e00-\u9fff，。！？、；：""''（）()]+'), '');

  // 移除星号/等号/下划线堆砌的分隔线（纯装饰）
  s = s.replaceAll(RegExp(r'^[\s*=_-]{3,}$', multiLine: true), '');

  return s;
}

/// 分页标记清洗：站点会把分页器文字混在正文里。
///
/// 实测某小说站正文首行是 `第一章 祂 (第1/3页)` —— 分页串页是引擎自己的事，
/// 这个标记对读者毫无意义，却会紧跟在章节标题后面显示出来。
///
/// 只删标记本身，**保留同一行的其余内容**（标题要留着）。
String _stripPagingMarks(String line) {
  var s = line;
  // (第1/3页) / （第 1 / 3 页） / [1/3] / (1/3)
  s = s.replaceAll(
      RegExp(r'[（(\[【]\s*(?:第\s*)?\d+\s*/\s*\d+\s*(?:页)?\s*[）)\]】]'),
      '');
  // 行尾孤立的 "第N页" / "N/M页"
  s = s.replaceAll(RegExp(r'[（(\[【]?\s*第\s*\d+\s*页\s*[）)\]】]?\s*$'), '');
  return s.trimRight();
}

/// 单行广告短句判断：命中任一模式的行直接丢弃。
/// 覆盖网文站点最常见的广告模板（经验归纳）。
bool _isAdLine(String line) {
  final patterns = [
    // 站点推广/下载类
    r'^(手机用户|下载|扫码|关注公众号|关注我)[^\n]{0,10}(下载|阅读|继续|访问|看|追)',
    r'^(推荐|收藏|加入书架|加入书架|记得收藏|别忘了收藏|点击收藏)',
    r'(请收藏|请记住|请继续|请访问|请关注|请转发|请点击)(本书|本站|本页|下载)',
    r'(最新网址|最新域名|本站新域名|官方网址|官方网站|更新最快|地址发布)',
    // "天才一秒记住本站地址：[某站]最快更新！无广告！" —— 实测这类小说站
    // 最常见的整行广告。原规则只认「最新网址/官方网址」开头，
    // 覆盖不到"记住本站地址"这种写法。
    r'(记住本站|一秒记住|收藏本站|记住本书|最快更新|无弹窗)',
    // 举报/纠错入口（正文里嵌的链接文字，纯噪音）
    r'(章节错误|内容错误|点此举报|举报本章|举报此章)',
    // 站点自己的分节/分页标记，被当成正文抓了进来。
    // 实测黄金屋：正文里混着"第1节（第1-50行）"；其目录项甚至就是
    // "第1页（第1行起）"这种分页导航。只匹配**带括号的完整标记形式**，
    // 避免误伤正文里正常出现的"第N节"。
    r'^第\s*\d+\s*节\s*[（(]第?\s*\d+\s*[-–~]\s*\d+\s*行[）)]$',
    r'^第\s*\d+\s*页\s*[（(]第?\s*\d+\s*行起[）)]$',
    r'(打赏|投月票|投推荐票|求月票|求推荐|求收藏|求打赏|求打赏|求评论)',
    r'(月票|推荐票|打赏|红包|抽奖|签到|积分)[^\n]{0,10}(排行|榜|领取|送|开始)',
    // 版权/免责声明（极短的行）
    r'^本章.*未完[，,]?\s*点击下一页',
    r'^本章.*继续阅读',
    r'^翻页后继续',
    r'^点击下一页',
    r'^下一[页章].*继续',
    r'^上一[页章].*返回',
    r'^（.*下一页.*）$',
    // 导航元素
    r'^(目录|返回|上一页|下一页|上一章|下一章|加入书架|投诉|举报|反馈|换源)$',
    r'^[【\[](.*推荐|热门书单|分类|排行|搜索|热门)[】\]]',
    // 特殊链接形式
    r'^[(\[（](查|看|搜|下|阅).*(续|全|完)[)\]）]$',
  ];
  for (final p in patterns) {
    if (RegExp(p, caseSensitive: false).hasMatch(line)) return true;
  }
  // 行太短（<=3 字）且只由数字/符号/空白组成 → 多半是分页器或导航噪音
  // （如 "1"、"[2]"、"--"）。
  //
  // **必须排除中文**：Dart 的 `\W` 匹配的是"非 [A-Za-z0-9_]"，
  // 而**中文属于 \W**！原写法会把 "甲"、"前半"、"尾字" 这类短中文正文
  // 当成噪音整行删掉 —— 实测小说分页正文只剩空串。
  if (line.length <= 3 &&
      !RegExp(r'[一-鿿぀-ヿ가-힯]').hasMatch(line) &&
      RegExp(r'^[\s\d\W]+$').hasMatch(line)) {
    return true;
  }
  return false;
}

/// 章节头尾的"装饰"短句移除。
/// 章节标题后的"第XX章"、章节末尾的"— 本章完 —"等阅读友好保留。
String _stripChapterFraming(String s) {
  final out = <String>[];
  final paragraphs = s.split('\n\n');
  for (var i = 0; i < paragraphs.length; i++) {
    final p = paragraphs[i].trim();
    if (p.isEmpty) continue;

    // 章节末尾"— 本章完 —"类装饰保留（阅读节奏需要）
    // 但如果是广告式的"未完，点击下一页 → "就去掉
    if (i == paragraphs.length - 1) {
      // 最后一段的尾巴清理
      var cleaned = p;
      cleaned = cleaned.replaceAllMapped(
          RegExp(r'(未完|待续|未完待续)[^\n]{0,20}(点击|请|继续|访问)',
              caseSensitive: false),
          (_) => '');
      cleaned = cleaned.replaceAllMapped(
          RegExp(r'(点击|请)[^\n]{0,10}下一页[^\n]{0,20}(继续|阅读)?',
              caseSensitive: false),
          (_) => '');
      if (cleaned.trim().isNotEmpty) out.add(cleaned);
    } else {
      out.add(p);
    }
  }
  return out.join('\n\n');
}

/// 全局空白规范化：零宽字符 → 空、全角空格 → 半角、
/// 行首尾空白清理、连续 3+ 换行压缩为 2。
String _normalizeWhitespace(String s) {
  // 零宽字符 & BOM
  s = s.replaceAll(RegExp(r'[\u200B\u200C\u200D\uFEFF\u2060]'), '');
  // 全角空格
  s = s.replaceAll('\u3000', ' ');
  // 制表符/回车 → 换行
  s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  // 行首缩进保留（中文网文习惯），但行尾空格清掉
  s = s.replaceAllMapped(RegExp(r'[ \t]+$', multiLine: true), (_) => '');
  // 连 3+ 空白行 → 2 行（标准段落间距）
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  // 段落内的连续空格压缩
  s = s.replaceAll(RegExp(r'  +'), ' ');
  return s;
}

/// 相关性重排的中间载体：结果 + 分值 + 原始下标。
///
/// 带上原始下标是因为 Dart 的 [List.sort] 不保证稳定性，
/// 同分条目要靠它才能维持站点原本的先后顺序。
class _RelevanceScored {
  final SearchResult result;
  final int score;
  final int index;
  const _RelevanceScored(this.result, this.score, this.index);
}
