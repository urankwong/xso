import 'dart:convert';
import 'package:core/core.dart';

/// 宿主 HTTP 取文本能力。
///
/// 依赖倒置：source_engine 保持「纯 Dart」定位（不引入 dio / http 依赖），
/// 由 app 层注入具体实现（app 已有 dio）。
typedef HttpTextGetter = Future<String> Function(
  String url, {
  Map<String, String>? headers,
  Duration? timeout,
});

/// oiapi「歌名即直链」适配源。
///
/// ## 定位
/// 不同于「先搜索拿到 songmid、再调源解析直链」的两段式链路，
/// 本源**一步到位**：把 `歌名[ 歌手]` 直接换成可播放直链。
/// 用于「想听就播」的快速兜底，与逐源搜索并行工作、互不干扰。
///
/// ## 后端
/// `https://oiapi.net/api/Kuwo`（「溯音」系列聚合 API，**免 API key**，实测可用）
/// 语义：`msg=<关键词>&n=1&br=1` → 返回最匹配一首的直链。
///
/// 响应形如：
/// ```json
/// {"code":1,"message":"±img=<封面URL>±\n歌名：晴天\n歌手：周杰伦\n音乐链接：http://kw-er.kuwo.cn/.../x.flac?..."}`
/// ```
/// 直链为无损 FLAC（bitrate 2000），带时效签名，需即时使用。
///
/// ## 注意
/// - `n=1` 只返回最匹配的一首，本源的搜索结果因此只有 1 条 —— 这是设计取舍，非缺陷。
/// - 直链有时效性，**不适合持久化**；需要稳定地址时应走两段式源。
/// - 若单条不满足「选歌」需求，可把 `n` 调大后解析多条（后端支持性未逐一验证）。
class OiapiAdapter {
  /// 免 key 的酷我「歌名→直链」端点
  static const String kuwoEndpoint = 'https://oiapi.net/api/Kuwo';

  final HttpTextGetter httpGet;
  OiapiAdapter({required this.httpGet});

  Future<OiapiSource> wrap({
    String url = kuwoEndpoint,
    String name = '歌名直链',
  }) async =>
      OiapiSource._(httpGet, url, name);
}

class OiapiSource implements SearchableSource {
  final HttpTextGetter _httpGet;
  final String _endpoint;

  @override
  final SourceMeta meta;

  OiapiSource._(this._httpGet, this._endpoint, String name)
      : meta = SourceMeta(
          id: 'oiapi://${Uri.parse(_endpoint).host}',
          name: name,
          type: SourceType.music,
          version: 1,
          origin: 'oiapi',
        );

  @override
  Future<List<SearchResult>> search(SearchQuery query) async {
    final keyword = query.keyword.trim();
    if (keyword.isEmpty) return const [];
    final url =
        '$_endpoint?msg=${Uri.encodeComponent(keyword)}&n=1&br=1';
    final raw = await _httpGet(
      url,
      headers: const {'Accept': 'application/json'},
      timeout: const Duration(seconds: 15),
    );
    final one = parse(raw, sourceId: meta.id, sourceName: meta.name);
    return one == null ? const [] : [one];
  }

  /// 解析 oiapi 响应为可直接播放的搜索结果。
  ///
  /// 兼容三种返回形态：
  /// 1. `{code:1, message:"…歌名：…\n歌手：…\n音乐链接：<url>"}`（oiapi 实测形态）
  /// 2. `{url: "…"}` / `{data:{url:"…"}}`（同类聚合 API 的常见形态）
  /// 3. 纯文本直链
  ///
  /// 返回 null 表示无可用结果（非成功码 / 无直链）。
  static SearchResult? parse(
    String body, {
    String sourceId = 'oiapi://kuwo',
    String sourceName = '歌名直链',
  }) {
    final text = body.trim();
    if (text.isEmpty) return null;

    // 形态 1/2：JSON
    Map<String, dynamic>? json;
    if (text.startsWith('{')) {
      try {
        json = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        json = null;
      }
    }

    final code = json?['code'];
    // 明确失败码直接放弃（oiapi 成功为 1，溯音系列为 200）
    if (code != null && code != 1 && code != 200) return null;

    final message = (json?['message'] ?? json?['msg'] ?? '').toString();

    // 直链：优先结构化字段，其次从 message 文本里取「音乐链接：」
    String url = '';
    final direct = json?['url'] ??
        (json?['data'] is Map ? (json!['data'] as Map)['url'] : null);
    if (direct != null) url = direct.toString();
    if (url.isEmpty && message.isNotEmpty) {
      final m = RegExp(r'音乐链接[：:]\s*(\S+)').firstMatch(message);
      if (m != null) url = m.group(1)!;
    }
    // 形态 3：整体就是一条直链
    if (url.isEmpty && (text.startsWith('http://') || text.startsWith('https://'))) {
      url = text.split(RegExp(r'\s')).first;
    }
    if (!url.startsWith('http')) return null;

    // 元信息：从 message 的结构化文本中提取（oiapi 无独立字段）
    final source = message.isNotEmpty ? message : text;
    String pick(String label) {
      final m = RegExp('$label[：:]\\s*([^\\n]+)').firstMatch(source);
      return m?.group(1)?.trim() ?? '';
    }

    final title = pick('歌名');
    final singer = pick('歌手');
    final cover = RegExp(r'±img=([^±]+)±').firstMatch(source)?.group(1)?.trim() ?? '';

    return SearchResult(
      sourceId: sourceId,
      sourceName: sourceName,
      type: SourceType.music,
      title: title.isEmpty ? sourceName : title,
      url: url, // ★ 已经是可播放直链，无需二次解析
      extra: {
        if (singer.isNotEmpty) 'artist': singer,
        if (cover.isNotEmpty) 'cover': cover,
        // 标记来源，便于 UI/排查区分「一步到位」与两段式结果
        'oiapi': '1',
      },
    );
  }
}
