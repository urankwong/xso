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
}
