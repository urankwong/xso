import 'dart:convert';
import 'package:core/core.dart';

class SourceSchemaException implements Exception {
  final String message;
  SourceSchemaException(this.message);
  @override
  String toString() => 'SourceSchemaException: $message';
}

/// 源文件完整模型（自有格式）
class Source {
  final SourceMeta meta;
  final SearchRule? search;
  final DetailRule? detail;
  final HooksRule? hooks;

  /// 书籍详情元信息（Legado `ruleBookInfo`）：封面/简介/分类/最新章节…
  final BookMetaRule? bookMeta;

  /// 目录规则（Legado `ruleToc`）
  final TocRule? toc;

  /// 正文规则（Legado `ruleContent`）
  final ContentRule? content;

  /// 阅读相关规则的 JS 钩子。
  ///
  /// 当详情/目录/正文规则里出现静态路径无法求值的语法
  /// （`@js:`、`<js>`、`&&` 管道链）时，改用钩子把这些字段的求值
  /// 交给 JS 运行时；一次 evaluate 返回整组字段，避免逐字段多次求值。
  final BookHooks? bookHooks;

  /// 是否具备「在线阅读」能力：目录 + 正文都齐了才行
  /// （静态规则或 JS 钩子任一形式都可）
  bool get canRead =>
      (toc != null || (bookHooks?.toc != null)) &&
      (content != null || (bookHooks?.content != null));

  const Source({
    required this.meta,
    this.search,
    this.detail,
    this.hooks,
    this.bookMeta,
    this.toc,
    this.content,
    this.bookHooks,
  });
}

/// 阅读规则的 JS 钩子：脚本形如 `(function(body){ … })`，
/// 返回 JSON 字符串（正文钩子返回纯文本）。
class BookHooks {
  /// 返回 JSON：`{coverUrl,intro,kind,lastChapter,wordCount}`
  final String? bookInfo;

  /// 返回 JSON：`[{title,url}]`
  final String? toc;

  /// 返回纯文本正文
  final String? content;

  /// 动态求值"下一页 URL"（正文分页）。
  ///
  /// 当 `nextContentUrl` 规则含 `<js>`/`@js:`（如黄金屋用 JS 从当前页
  /// 页码生成全部后续分页 URL）时，静态路径无法求值，改由此钩子在
  /// 运行时计算。调用约定：引擎以 `(function(body, url){ hook })(pageBody,
  /// pageUrl)` 双参注入——body 是当前页 HTML，url 是当前页地址（钩子内
  /// baseUrl 已被覆盖为当前页地址，与 Legado 语义一致）。
  /// 返回值经 JSON.stringify 归一：字符串（单下一页）或数组（批量后续页）。
  final String? nextPage;

  const BookHooks({this.bookInfo, this.toc, this.content, this.nextPage});

  bool get isEmpty =>
      bookInfo == null && toc == null && content == null && nextPage == null;
}

/// 书籍详情元信息规则。字段全部可选：不同站点能提供的信息差异很大，
/// 缺哪个就少显示哪个，不影响其余字段。
class BookMetaRule {
  final FieldRule? cover; // 封面图片地址
  final FieldRule? intro; // 简介
  final FieldRule? kind; // 分类/标签
  final FieldRule? lastChapter; // 最新章节
  final FieldRule? wordCount; // 字数
  final FieldRule? status; // 连载状态
  const BookMetaRule({
    this.cover,
    this.intro,
    this.kind,
    this.lastChapter,
    this.wordCount,
    this.status,
  });

  bool get isEmpty =>
      cover == null &&
      intro == null &&
      kind == null &&
      lastChapter == null &&
      wordCount == null &&
      status == null;
}

/// 目录规则：从目录页取出章节列表
class TocRule {
  /// 章节列表容器（相对目录页）
  final String list;

  /// 章节名（相对列表项）
  final FieldRule name;

  /// 章节链接（相对列表项）
  final FieldRule url;

  /// 下一页目录链接（Legado `nextTocUrl`）：目录分页站点用，
  /// 引擎据此自动串页拼接完整章节列表
  final FieldRule? nextUrl;

  const TocRule({
    required this.list,
    required this.name,
    required this.url,
    this.nextUrl,
  });
}

/// 正文规则：从章节页取出正文
class ContentRule {
  /// 正文选择器（相对章节页）；attr=html 时取 innerHtml
  final FieldRule content;

  /// 下一页链接（可选，长文分页的站点用）
  final FieldRule? nextUrl;

  const ContentRule({required this.content, this.nextUrl});
}

class SearchRule {
  final RequestRule request;
  final ResultRule? result;
  const SearchRule({required this.request, this.result});
}

class DetailRule {
  final RequestRule request;
  final String content; // 正文 CSS 选择器
  final List<String> extractors; // 启用的网盘识别器
  const DetailRule({
    required this.request,
    required this.content,
    this.extractors = const ['baidu', 'quark', 'aliyun', '123pan'],
  });
}

class RequestRule {
  final String url;
  final String method;
  final Map<String, String> headers;
  final String charset;
  const RequestRule({
    required this.url,
    this.method = 'GET',
    this.headers = const {},
    this.charset = 'utf-8',
  });
}

class ResultRule {
  final String? container;
  final Map<String, FieldRule>? fields;
  final String? jsonPath;
  const ResultRule({this.container, this.fields, this.jsonPath});
}

class FieldRule {
  /// 首选选择器
  final String selector;

  /// 取哪个属性：text | href | html | title | src | 其它 HTML 属性名
  final String attr;

  /// 兜底选择器链（Legado `||` 语义）：首选未命中或取到空值时依次尝试
  final List<String> fallbackSelectors;

  /// 提取结果的可选正则替换（Legado `##` 语义）：
  /// 命中 replaceRegex 的部分替换为 replacement（缺省空串 = 删除）。
  final String? replaceRegex;
  final String? replacement;

  const FieldRule({
    required this.selector,
    this.attr = 'text',
    this.fallbackSelectors = const [],
    this.replaceRegex,
    this.replacement,
  });

  /// 完整候选链：首选 + 兜底
  List<String> get candidates => [selector, ...fallbackSelectors];

  /// JSON 模式下 selector 表示字段路径（jsonPath），与候选链语义不同
  bool get hasReplace => replaceRegex != null && replaceRegex!.isNotEmpty;
}

class HooksRule {
  final String? buildRequest;
  final String? parse;
  const HooksRule({this.buildRequest, this.parse});
}

/// 解析并校验源 JSON。任何结构问题都抛 SourceSchemaException。
Source parseSource(String json) {
  Map<String, dynamic> root;
  try {
    root = jsonDecode(json) as Map<String, dynamic>;
  } catch (_) {
    throw SourceSchemaException('源不是合法 JSON');
  }

  final meta = _parseMeta(root);
  final search = _parseSearch(root);
  final detail = _parseDetail(root);
  final hooks = _parseHooks(root);
  if (search == null) {
    throw SourceSchemaException('自有格式源必须包含 search 段');
  }
  return Source(
    meta: meta,
    search: search,
    detail: detail,
    hooks: hooks,
    bookMeta: _parseBookMeta(root),
    toc: _parseTocRule(root),
    content: _parseContentRule(root),
  );
}

/// 单个字段规则：`{"selector": "…", "attr": "text|href|html|src"}`
FieldRule? _fieldFrom(dynamic raw, String path) {
  if (raw == null) return null;
  final m = _asMap(raw, path);
  final sel = m['selector'];
  if (sel is! String || sel.isEmpty) return null;
  return FieldRule(selector: sel, attr: m['attr'] as String? ?? 'text');
}

BookMetaRule? _parseBookMeta(Map<String, dynamic> root) {
  if (root['bookMeta'] == null) return null;
  final m = _asMap(root['bookMeta'], 'bookMeta');
  final r = BookMetaRule(
    cover: _fieldFrom(m['cover'], 'bookMeta.cover'),
    intro: _fieldFrom(m['intro'], 'bookMeta.intro'),
    kind: _fieldFrom(m['kind'], 'bookMeta.kind'),
    lastChapter: _fieldFrom(m['lastChapter'], 'bookMeta.lastChapter'),
    wordCount: _fieldFrom(m['wordCount'], 'bookMeta.wordCount'),
    status: _fieldFrom(m['status'], 'bookMeta.status'),
  );
  return r.isEmpty ? null : r;
}

TocRule? _parseTocRule(Map<String, dynamic> root) {
  if (root['toc'] == null) return null;
  final m = _asMap(root['toc'], 'toc');
  final list = _reqStr(m, 'list', 'toc.list');
  final name = _fieldFrom(m['name'], 'toc.name');
  final url = _fieldFrom(m['url'], 'toc.url');
  if (name == null || url == null) {
    throw SourceSchemaException('toc.name 与 toc.url 必填');
  }
  return TocRule(
      list: list,
      name: name,
      url: url,
      nextUrl: _fieldFrom(m['nextTocUrl'], 'toc.nextTocUrl'));
}

ContentRule? _parseContentRule(Map<String, dynamic> root) {
  if (root['content'] == null) return null;
  final m = _asMap(root['content'], 'content');
  final c = _fieldFrom(m['content'], 'content.content');
  if (c == null) {
    throw SourceSchemaException('content.content 必填');
  }
  // 分页字段：Legado 标准名是 nextContentUrl，`nextUrl` 是历史别名
  return ContentRule(
      content: c,
      nextUrl: _fieldFrom(m['nextContentUrl'], 'content.nextContentUrl') ??
          _fieldFrom(m['nextUrl'], 'content.nextUrl'));
}

SourceMeta _parseMeta(Map<String, dynamic> root) {
  final meta = _asMap(root['meta'], 'meta');
  final id = _reqStr(meta, 'id', 'meta.id');
  final name = _reqStr(meta, 'name', 'meta.name');
  final typeStr = _reqStr(meta, 'type', 'meta.type');
  final type = SourceType.values.where((t) => t.name == typeStr).firstOrNull;
  if (type == null) {
    throw SourceSchemaException('meta.type "$typeStr" 不受支持');
  }
  return SourceMeta(
    id: id,
    name: name,
    type: type,
    version: (meta['version'] as num?)?.toInt() ?? 1,
    engine: meta['engine'] as String? ?? 'script',
    updateUrl: meta['updateUrl'] as String?,
  );
}

SearchRule? _parseSearch(Map<String, dynamic> root) {
  if (root['search'] == null) return null;
  final search = _asMap(root['search'], 'search');
  final req = _asMap(search['request'], 'search.request');
  final url = _reqStr(req, 'url', 'search.request.url');
  final headers = <String, String>{};
  (req['headers'] as Map<String, dynamic>?)
      ?.forEach((k, v) => headers[k] = v.toString());
  final result = _parseResult(search['result']);
  return SearchRule(
    request: RequestRule(
      url: url,
      method: req['method'] as String? ?? 'GET',
      headers: headers,
      charset: req['charset'] as String? ?? 'utf-8',
    ),
    result: result,
  );
}

ResultRule? _parseResult(dynamic raw) {
  if (raw == null) return null;
  final result = _asMap(raw, 'search.result');
  final container = result['container'] as String?;
  final jsonPath = result['jsonPath'] as String?;
  if (container != null && jsonPath != null) {
    throw SourceSchemaException('container 与 jsonPath 互斥，只能选一个');
  }
  Map<String, FieldRule>? fields;
  final rawFields = result['fields'] as Map<String, dynamic>?;
  if (rawFields != null) {
    fields = {};
    rawFields.forEach((name, rule) {
      final m = _asMap(rule, 'search.result.fields.$name');
      fields![name] = FieldRule(
        selector: _reqStr(m, 'selector', 'fields.$name.selector'),
        attr: m['attr'] as String? ?? 'text',
      );
    });
  }
  return ResultRule(container: container, fields: fields, jsonPath: jsonPath);
}

DetailRule? _parseDetail(Map<String, dynamic> root) {
  if (root['detail'] == null) return null;
  final detail = _asMap(root['detail'], 'detail');
  final req = _asMap(detail['request'], 'detail.request');
  final content = _reqStr(detail, 'content', 'detail.content');
  final extractors = (detail['extractors'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ??
      const ['baidu', 'quark', 'aliyun', '123pan'];
  return DetailRule(
    request: RequestRule(url: _reqStr(req, 'url', 'detail.request.url')),
    content: content,
    extractors: extractors,
  );
}

HooksRule? _parseHooks(Map<String, dynamic> root) {
  if (root['hooks'] == null) return null;
  final hooks = _asMap(root['hooks'], 'hooks');
  return HooksRule(
    buildRequest: hooks['buildRequest'] as String?,
    parse: hooks['parse'] as String?,
  );
}

Map<String, dynamic> _asMap(dynamic v, String path) {
  if (v is! Map<String, dynamic>) {
    throw SourceSchemaException('$path 必须是对象');
  }
  return v;
}

String _reqStr(Map<String, dynamic> m, String key, String path) {
  final v = m[key];
  if (v is! String || v.isEmpty) {
    throw SourceSchemaException('$path 必填且为非空字符串');
  }
  return v;
}
