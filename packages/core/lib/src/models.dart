/// 源类型开放枚举：新增内容类型=新增枚举值，搜索机制不变
///
/// comic / video 对应 Legado 的图片型（bookSourceType=2，漫画）与
/// 视频型（bookSourceType=4，影视）书源 —— 阅读生态里这两类是一等公民，
/// 此前缺失会把它们错误归类为 book。
///
/// novel 对应 Legado 的文本型书源（bookSourceType=0，**网文/小说**）。
/// 它与 book（电子书**文件**，如 zlib / 安娜档案馆的 epub/pdf）是两种东西：
/// 小说是"追更阅读"的内容，书籍是"下载文件"的资源。此前共用 book
/// 导致两类结果混排在同一个列表里，用户无法区分也无法分别筛选。
/// 追加在末尾以避免依赖枚举序号的持久化逻辑受影响。
enum SourceType {
  pan,
  magnet,
  ed2k,
  book,
  music,
  game,
  audiobook,
  comic,
  video,
  novel,
}

/// 一次搜索请求
class SearchQuery {
  final String keyword;
  final int page;
  const SearchQuery({required this.keyword, this.page = 1});
}

/// 归一化搜索结果：所有源（含适配器包装的外来源）统一为此结构
class SearchResult {
  final String sourceId;
  final String sourceName;
  final SourceType type;
  final String title;

  /// 最终链接（magnet:/ed2k:/https:）或两段式源的详情页 URL
  final String url;

  /// 网盘提取码（pan 类型常见）
  final String? extractCode;

  /// 源附加字段：size/date/author 等，原样透传
  final Map<String, String>? extra;

  /// 是否需要二次请求详情页（两段式源为 true）
  final bool needsDetail;

  const SearchResult({
    required this.sourceId,
    required this.sourceName,
    required this.type,
    required this.title,
    required this.url,
    this.extractCode,
    this.extra,
    this.needsDetail = false,
  });
}

/// 源元信息（引擎/适配器共用的注册信息）
class SourceMeta {
  final String id;
  final String name;
  final SourceType type;
  final int version;
  final String engine; // script | native(预留)
  final String? origin; // 自有格式为 null；musicfree/lx/legado
  final String? updateUrl;
  const SourceMeta({
    required this.id,
    required this.name,
    required this.type,
    required this.version,
    this.engine = 'script',
    this.origin,
    this.updateUrl,
  });
}

/// 净化规则的作用范围。
///
/// 参考 Legado「替换净化」的做法：只有"全局"是不够的 —— 一条针对某站点
/// 广告的规则拿到别的书上跑，轻则无效、重则误删正常文字。所以要能限定
/// 到"这本书"或"这个书源"。
enum FilterScope {
  /// 全局：所有源的所有书（默认，兼容旧数据）
  global,

  /// 仅本源：同书源下的所有书（站点级广告用这个）
  source,

  /// 仅本书：只对当前这本书生效（最安全，选中即净化时的默认）
  book,
}

/// 正文净化规则：一条正则替换（等价于 Legado 的「替换净化」）。
///
/// 站点广告千奇百怪，内置规则永远追不上；用户自己能加一条规则，
/// 才是这类问题的终局解法。规则在正文清洗**之后**应用，
/// 所以用户看到的是"已经去过广告"的文本，写规则时不必考虑原始 HTML。
class ContentFilterRule {
  /// 匹配用的正则（Dart RegExp 语法）
  final String pattern;

  /// 替换成什么。空串 = 删除命中内容（最常见的用法）。
  final String replacement;

  /// 规则名，仅用于展示；空则 UI 直接显示 [pattern]
  final String? label;

  final bool enabled;

  /// 作用范围
  final FilterScope scope;

  /// 范围键：scope 为 [FilterScope.book] 时是书的标识，
  /// [FilterScope.source] 时是书源 id；[FilterScope.global] 忽略。
  final String? scopeKey;

  const ContentFilterRule({
    required this.pattern,
    this.replacement = '',
    this.label,
    this.enabled = true,
    this.scope = FilterScope.global,
    this.scopeKey,
  });

  /// 这条规则是否作用于给定的书/源。
  ///
  /// [bookKey] / [sourceKey] 为空时（调用方没提供标识）只放行全局规则 ——
  /// 宁可不生效，也不要拿限定范围的规则去改别的书。
  bool appliesTo({String? bookKey, String? sourceKey}) {
    switch (scope) {
      case FilterScope.global:
        return true;
      case FilterScope.source:
        return scopeKey != null &&
            scopeKey!.isNotEmpty &&
            scopeKey == sourceKey;
      case FilterScope.book:
        return scopeKey != null && scopeKey!.isNotEmpty && scopeKey == bookKey;
    }
  }

  /// 作用范围的中文短标签（列表/提示用）
  String get scopeLabel => switch (scope) {
        FilterScope.global => '全局',
        FilterScope.source => '本源',
        FilterScope.book => '本书',
      };

  ContentFilterRule copyWith({
    String? pattern,
    String? replacement,
    String? label,
    bool? enabled,
    FilterScope? scope,
    String? scopeKey,
  }) =>
      ContentFilterRule(
        pattern: pattern ?? this.pattern,
        replacement: replacement ?? this.replacement,
        label: label ?? this.label,
        enabled: enabled ?? this.enabled,
        scope: scope ?? this.scope,
        scopeKey: scopeKey ?? this.scopeKey,
      );

  Map<String, dynamic> toJson() => {
        'pattern': pattern,
        'replacement': replacement,
        if (label != null) 'label': label,
        'enabled': enabled,
        'scope': scope.name,
        if (scopeKey != null) 'scopeKey': scopeKey,
      };

  /// 容错解析：坏数据不抛异常（规则列表损坏不该让整个设置页打不开）
  static ContentFilterRule? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final p = raw['pattern'];
    if (p is! String || p.trim().isEmpty) return null;
    final scopeName = raw['scope']?.toString();
    final scope = FilterScope.values.firstWhere(
      (s) => s.name == scopeName,
      orElse: () => FilterScope.global, // 老数据没有 scope 字段 → 全局
    );
    return ContentFilterRule(
      pattern: p,
      replacement: raw['replacement']?.toString() ?? '',
      label: raw['label']?.toString(),
      enabled: raw['enabled'] as bool? ?? true,
      scope: scope,
      scopeKey: raw['scopeKey']?.toString(),
    );
  }

  /// 正则是否合法（保存前校验，避免写下一条永远不生效的规则）
  bool get isValidRegExp {
    try {
      RegExp(pattern);
      return true;
    } catch (_) {
      return false;
    }
  }
}
