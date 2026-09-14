import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 用 `releases.atom` 订阅最新 Release，绕开 REST API 的速率限制。
///
/// 为什么不直接用 `api.github.com/repos/.../releases/latest`：未认证请求的配额是
/// **60 次/小时/出口 IP**。手机走运营商 NAT、校园网或代理池时，成百上千台设备共用
/// 同一个出口 IP，配额几分钟就见底，普通用户点一下「检查更新」就看到
/// 「访问过于频繁(GitHub 限流)」——这对使用者是不可理解的失败。
///
/// atom 是网页端点（github.com/.../releases.atom），不吃 core 配额，实测连续请求
/// 全部 200。代价是它不列资产，所以安装包文件名按 CI 的命名规则推导 + HEAD 探测。
class ReleaseFeed {
  /// 极小请求：只要 feed 的头部信息，超时压短，避免在启动路径上拖住 UI
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    responseType: ResponseType.plain,
    headers: {
      // GitHub 对空 UA 的网页端点会 403
      'User-Agent': 'xso-android-app',
      'Accept': 'application/atom+xml, application/xml;q=0.9, */*;q=0.8',
    },
  ));

  static String feedUrl(String owner, String repo) =>
      'https://github.com/$owner/$repo/releases.atom';

  static String _downloadBase(String owner, String repo, String tag) =>
      'https://github.com/$owner/$repo/releases/download/${Uri.encodeComponent(tag)}';

  /// CI 产物命名：`app-<abi>-release.apk`（见 .github/workflows/build.yml）
  static List<String> apkNames({String? abiHint}) {
    final order = <String>[
      if (abiHint != null && abiHint.isNotEmpty) abiHint,
      'arm64-v8a',
      'armeabi-v7a',
      'x86_64',
      'armeabi-v7a',
    ];
    final seen = <String>{};
    return [
      for (final abi in order)
        if (seen.add('app-$abi-release.apk')) 'app-$abi-release.apk',
    ];
  }

  static String apkUrl(
          {required String owner, required String repo, required String tag, required String name}) =>
      '${_downloadBase(owner, repo, tag)}/$name';

  /// 拉取并解析最新一条 Release；拿不到（网络/改版/无 Release）返回 null，
  /// 由调用方决定是否回退到 API。
  static Future<FeedRelease?> fetch(
    String owner,
    String repo, {
    String? abiHint,
    Dio? dio,
  }) async {
    try {
      final resp = await (dio ?? _dio).get<String>(feedUrl(owner, repo));
      final raw = resp.data;
      if (raw == null) return null;
      final parsed = parse(raw);
      if (parsed == null) return null;
      // 资产名要靠推导，HEAD 探测挑出本机真正有包的那一个（老版本可能只发过 arm64）
      return parsed.copyWithAssetUrl(
        await _resolveAsset(owner, repo, parsed.tagName, abiHint, dio ?? _dio),
      );
    } catch (e) {
      debugPrint('[更新] atom 订阅失败: $e');
      return null;
    }
  }

  static Future<FeedAsset?> _resolveAsset(String owner, String repo, String tag,
      String? abiHint, Dio dio) async {
    for (final name in apkNames(abiHint: abiHint)) {
      final url = apkUrl(owner: owner, repo: repo, tag: tag, name: name);
      try {
        final r = await dio.head<dynamic>(url,
            options: Options(sendTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8)));
        if (r.statusCode == 200) {
          final len = r.headers.value('content-length');
          return FeedAsset(name, url, int.tryParse(len ?? '') ?? 0);
        }
      } catch (_) {
        // 该架构没包，继续试下一个
      }
    }
    return null;
  }

  /// 解析 feed 首个 entry。用正则而非引 XML 库：结构固定且只取三个字段。
  static FeedRelease? parse(String xml) {
    final entry = RegExp(r'<entry>([\s\S]*?)</entry>').firstMatch(xml);
    if (entry == null) return null;
    final e = entry.group(1)!;

    // tag 只在 <link href=".../releases/tag/v0.1.0%2B7"> 里是规范形式；
    // <id> 是 "tag:github.com,2008:Repository/<repoId>/v0.1.0+7"（不含 releases/tag/）。
    // 两者都要处理，且 href 里的 tag 是 URL 编码过的（+ → %2B）。
    final fromLink = RegExp(r'''releases/tag/([^"'<>\s]+)''').firstMatch(e)?.group(1);
    final fromId = RegExp(r'<id>[^<]*</id>')
        .firstMatch(e)
        ?.group(0)
        ?.replaceAll(RegExp(r'</?id>'), '')
        .split('/')
        .last;
    final fromLinkOk = fromLink != null && fromLink.trim().isNotEmpty;
    final rawTag = fromLinkOk ? fromLink.trim() : (fromId?.trim() ?? '');
    if (rawTag.isEmpty) return null;
    // 走 `<id>` 兜底时要求末段形如版本号，避免把仓库号之类的垃圾串当成 tag
    if (!fromLinkOk && !RegExp(r'^v?\d', caseSensitive: false).hasMatch(rawTag)) {
      return null;
    }
    final tagName = Uri.decodeComponent(rawTag);

    final published =
        RegExp(r'<published>([^<]+)</published>').firstMatch(e)?.group(1) ?? '';
    final updated = RegExp(r'<updated>([^<]+)</updated>').firstMatch(e)?.group(1) ?? '';

    // GitHub 把正文 HTML 再套一层实体转义（&lt;li&gt;），需先解一层再抽文本
    final rawContent =
        RegExp(r'<content[^>]*>([\s\S]*?)</content>').firstMatch(e)?.group(1) ?? '';
    final changelog = htmlToText(htmlUnescape(htmlUnescape(rawContent)));

    return FeedRelease(
      tagName: tagName,
      changelog: changelog,
      publishedAt: published.isEmpty ? updated : published,
    );
  }

  /// 实体反转义（覆盖 Release 正文里常见的几个，含无分号写法）
  static String htmlUnescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&middot;', '·')
      .replaceAll('&amp;', '&');

  /// HTML → 可读纯文本：列表项转「• 」，块级标签转换行，其余标签丢弃。
  static String htmlToText(String html) {
    var s = html;
    s = s.replaceAll(RegExp(r'<\s*(?:script|style)[\s\S]*?<\s*/\s*(?:script|style)\s*>',
        caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ');
    s = s.replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '');
    s = s.replaceAll(
        RegExp(r'<(?:br|p|div|ul|ol|h[1-6]|tr)\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    s = s
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'[ \t\u00a0]+'), ' ').trim())
        .where((l) => l.isNotEmpty)
        .join('\n');
    return s.trim();
  }
}

class FeedAsset {
  final String name;
  final String url;
  final int size;
  const FeedAsset(this.name, this.url, this.size);
}

class FeedRelease {
  final String tagName;
  final String changelog;
  final String publishedAt;
  final FeedAsset? asset;

  const FeedRelease({
    required this.tagName,
    required this.changelog,
    required this.publishedAt,
    this.asset,
  });

  FeedRelease copyWithAssetUrl(FeedAsset? a) => FeedRelease(
        tagName: tagName,
        changelog: changelog,
        publishedAt: publishedAt,
        asset: a,
      );
}
