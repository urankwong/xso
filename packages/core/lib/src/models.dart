/// 源类型开放枚举：新增内容类型=新增枚举值，搜索机制不变
enum SourceType { pan, magnet, ed2k, book, music, game }

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
