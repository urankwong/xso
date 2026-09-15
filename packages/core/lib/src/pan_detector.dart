/// 内置网盘识别器（App 级能力）：所有源共用，
/// App 更新识别器全局生效。源作者无需自己写网盘正则。
///
/// 覆盖网盘：百度 / 夸克 / 阿里 / 123 / 迅雷 / 115 / 天翼 / UC / 移动 / 蓝奏 / 文叔叔。
/// 枚举追加在末尾，避免影响按序号持久化的数据（extra 存 .name 字符串，但仍保持习惯）。
enum PanProvider {
  baidu,
  quark,
  aliyun,
  pan123,
  xunlei,
  pan115,
  tianyi,
  uc,
  yidong,
  lanzou,
  wenshushu,
}

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
  // 115 网盘：pan.115.com 或 115.com/s/
  PanProvider.pan115: RegExp(r'https?://(?:pan\.)?115\.com/s/[\w-]+'),
  // 天翼云盘：cloud.189.cn/t/ 或 e.189.cn/t/
  PanProvider.tianyi: RegExp(r'https?://(?:cloud|e)\.189\.cn/t/[\w]+'),
  // UC 网盘
  PanProvider.uc: RegExp(r'https?://drive\.uc\.cn/s/[\w-]+'),
  // 移动云盘：yun.139.com/w/
  PanProvider.yidong: RegExp(r'https?://yun\.139\.com/w/[\w!-]+'),
  // 蓝奏云：多域名（lanzoui/x/j/p/e/t/b/m/y/k/w/f/g/h/n/l/a/c/d/o/q/r/s/u/v/z）
  // 分享链接形如 https://wwm.lanzoui.com/iabcdefg
  PanProvider.lanzou: RegExp(r'https?://[\w.]*lanzou\w*\.com/[\w-]{4,}'),
  // 文叔叔
  PanProvider.wenshushu: RegExp(r'https?://wenshushu\.(?:cn|com)/[\w/-]+'),
};

/// 提取码文本匹配：支持"提取码/密码/访问码/code/pwd"等前缀，4-6 位字母数字。
/// 窗口从 60 扩大到 120 字符，适配"链接在正文、码在评论区"的排版。
final _extractCodePattern = RegExp(
    r'(?:提取码|提取密码|密码|访问码|访问密码|code|pwd|password)[：:\s=]*([A-Za-z0-9]{4,6})');

/// 从 URL query 参数提取提取码（?pwd=xxxx / ?password=xxxx / ?code=xxxx / ?p=xxxx）
final _urlCodePattern =
    RegExp(r'[?&](?:pwd|password|code|p)=([A-Za-z0-9]{4,6})');

/// 从任意文本（详情页正文/分享页文本）提取网盘链接及提取码
List<PanLink> detectPanLinks(String text) {
  final results = <PanLink>[];
  _panPatterns.forEach((provider, pattern) {
    for (final match in pattern.allMatches(text)) {
      final url = match.group(0)!;
      // 提取码优先从 URL 参数提取（?pwd=xxxx 等）
      var code = _urlCodePattern.firstMatch(url)?.group(1);
      if (code == null) {
        // 否则在链接后 120 字符窗口找文本提取码
        final windowStart = match.end;
        final windowEnd = (windowStart + 120).clamp(0, text.length);
        final codeMatch =
            _extractCodePattern.firstMatch(text.substring(windowStart, windowEnd));
        code = codeMatch?.group(1);
      }
      results.add(PanLink(
        provider: provider,
        url: url,
        extractCode: code,
      ));
    }
  });
  return results;
}

/// 失效特征检测：失效页是网盘官网行为，特征由本识别器维护。
/// 各网盘失效文案有差异，这里收录通用 + 已知各盘特征。
bool isPanLinkDead(PanProvider provider, String pageText) {
  const deadMarkers = [
    // 通用
    '链接不存在', '分享已被删除', '分享已取消', '页面不存在',
    '文件已被删除', '你访问的页面不存在', '分享的文件已经被取消',
    // 扩充：更多常见失效文案
    '分享已过期', '该分享不存在', '链接已失效', '资源不存在',
    '文件已删除', '分享内容不存在', '此分享已失效',
    // 蓝奏云特有
    '文件不存在', '文件已过期',
    // 115/天翼/UC 特有
    '任务不存在', '已删除的文件',
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
