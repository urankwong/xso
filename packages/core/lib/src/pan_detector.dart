/// 内置网盘识别器（App 级能力）：所有源共用，
/// App 更新识别器全局生效。源作者无需自己写网盘正则。
enum PanProvider { baidu, quark, aliyun, pan123, xunlei }

class PanLink {
  final PanProvider provider;
  final String url;
  final String? extractCode;
  const PanLink({required this.provider, required this.url, this.extractCode});
}

final _panPatterns = <PanProvider, RegExp>{
  PanProvider.baidu: RegExp(r'https?://pan\.baidu\.com/s/[\w-]+'),
  PanProvider.quark: RegExp(r'https?://pan\.quark\.cn/s/[\w-]+'),
  PanProvider.aliyun: RegExp(r'https?://www\.aliyundrive\.com/s/[\w]+'),
  PanProvider.pan123: RegExp(r'https?://(?:www\.)?123pan\.com/s/[\w-]+'),
  PanProvider.xunlei: RegExp(r'https?://pan\.xunlei\.com/s/[\w-]+'),
};

final _extractCodePattern =
    RegExp(r'(?:提取码|密码)[：:\s]*([A-Za-z0-9]{4})');

/// 从任意文本（详情页正文/分享页文本）提取网盘链接及提取码
List<PanLink> detectPanLinks(String text) {
  final results = <PanLink>[];
  _panPatterns.forEach((provider, pattern) {
    for (final match in pattern.allMatches(text)) {
      final url = match.group(0)!;
      // 提取码在链接后 60 字符窗口内找
      final windowStart = match.end;
      final windowEnd = (windowStart + 60).clamp(0, text.length);
      final codeMatch =
          _extractCodePattern.firstMatch(text.substring(windowStart, windowEnd));
      results.add(PanLink(
        provider: provider,
        url: url,
        extractCode: codeMatch?.group(1),
      ));
    }
  });
  return results;
}

/// 失效特征检测：失效页是网盘官网行为，特征由本识别器维护
bool isPanLinkDead(PanProvider provider, String pageText) {
  const deadMarkers = [
    '链接不存在', '分享已被删除', '分享已取消', '页面不存在',
    '文件已被删除', '你访问的页面不存在', '分享的文件已经被取消',
  ];
  return deadMarkers.any(pageText.contains);
}

/// 供活性检测器复用：URL → 网盘提供方
PanProvider? providerOfUrl(String url) {
  for (final e in _panPatterns.entries) {
    if (e.value.hasMatch(url)) return e.key;
  }
  return null;
}
