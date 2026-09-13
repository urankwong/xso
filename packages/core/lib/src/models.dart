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
