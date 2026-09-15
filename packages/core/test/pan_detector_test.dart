import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('识别百度网盘链接 + 上下文提取码', () {
    const text = '下载地址: https://pan.baidu.com/s/1abcDEF 密码: xk3a 请保存';
    final links = detectPanLinks(text);
    expect(links, hasLength(1));
    expect(links[0].provider, PanProvider.baidu);
    expect(links[0].url, 'https://pan.baidu.com/s/1abcDEF');
    expect(links[0].extractCode, 'xk3a');
  });

  test('识别夸克与123网盘，无提取码', () {
    const text = 'https://pan.quark.cn/s/xyz123 或 https://www.123pan.com/s/abc-456';
    final links = detectPanLinks(text);
    expect(links.map((l) => l.provider),
        containsAll([PanProvider.quark, PanProvider.pan123]));
    expect(links.every((l) => l.extractCode == null), isTrue);
  });

  test('多个提取码写法都识别', () {
    for (final marker in ['提取码：xx9z', '提取码: xx9z', '密码：xx9z', '密码: xx9z']) {
      final links = detectPanLinks('https://pan.baidu.com/s/1abc $marker');
      expect(links.first.extractCode, 'xx9z', reason: marker);
    }
  });

  test('失效页特征检测（活性检测用）', () {
    expect(isPanLinkDead(PanProvider.baidu, '页面不存在 该分享已被删除'), isTrue);
    expect(isPanLinkDead(PanProvider.baidu, '文件列表 文件名 大小'), isFalse);
  });

  test('识别 115/天翼/UC/移动/蓝奏/文叔叔网盘链接', () {
    const cases = [
      ('https://pan.115.com/s/abc123def', PanProvider.pan115),
      ('https://115.com/s/abc123def', PanProvider.pan115),
      ('https://cloud.189.cn/t/abc123', PanProvider.tianyi),
      ('https://e.189.cn/t/abc123', PanProvider.tianyi),
      ('https://drive.uc.cn/s/xyz-456', PanProvider.uc),
      ('https://yun.139.com/w/abc123', PanProvider.yidong),
      ('https://wwm.lanzoui.com/iabcdefg', PanProvider.lanzou),
      ('https://lanzoux.com/defghi', PanProvider.lanzou),
      ('https://wenshushu.cn/s/abc123', PanProvider.wenshushu),
    ];
    for (final (url, expected) in cases) {
      final links = detectPanLinks(url);
      expect(links.any((l) => l.provider == expected), isTrue, reason: url);
    }
  });

  test('URL 参数提取码（?pwd=xxxx）', () {
    const text = 'https://pan.baidu.com/s/1abcDEF?pwd=xk3a';
    final links = detectPanLinks(text);
    expect(links, hasLength(1));
    expect(links[0].extractCode, 'xk3a');
  });

  test('提取码 4-6 位均识别', () {
    for (final code in ['ab12', 'abc123', 'a1b2c3']) {
      final links = detectPanLinks('https://pan.baidu.com/s/1abc 密码: $code');
      expect(links.first.extractCode, code, reason: code);
    }
  });

  test('扩充的失效特征', () {
    expect(isPanLinkDead(PanProvider.lanzou, '文件不存在'), isTrue);
    expect(isPanLinkDead(PanProvider.pan115, '分享已过期'), isTrue);
    expect(isPanLinkDead(PanProvider.baidu, '正常的文件列表'), isFalse);
  });
}
