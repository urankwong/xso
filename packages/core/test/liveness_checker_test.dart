import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('失效页返回 dead=true', () async {
    final checker = LivenessChecker(
      fetcher: (url) async => '分享已被删除',
    );
    expect(await checker.check('https://pan.baidu.com/s/1x'), isTrue);
  });

  test('正常页返回 dead=false', () async {
    final checker = LivenessChecker(
      fetcher: (url) async => '文件列表 文件名 大小 下载',
    );
    expect(await checker.check('https://pan.baidu.com/s/1x'), isFalse);
  });

  test('网络失败按 dead 处理（保守，提示用户）', () async {
    final checker = LivenessChecker(
      fetcher: (url) async => throw Exception('net'),
    );
    expect(await checker.check('https://pan.baidu.com/s/1x'), isTrue);
  });
}
