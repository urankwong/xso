import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/providers/lyric.dart';

/// 歌词来源优先级：源自身给的词优先于第三方歌词库。
/// 此前只查第三方库，播放条明明带了词也会显示"暂无歌词"。
void main() {
  group('LyricService.fromSource', () {
    final svc = LyricService(Dio());

    test('内联 LRC 文本直接可用并带时间轴', () async {
      final lines = await svc
          .fromSource('[00:12.34]第一句\n[00:18.00]第二句');
      expect(lines, hasLength(2));
      expect(lines!.first.text, '第一句');
      expect(lines.first.time, const Duration(seconds: 12, milliseconds: 340));
    });

    test('没有歌词字段时返回 null 交给上层退回第三方库', () async {
      expect(await svc.fromSource(null), isNull);
      expect(await svc.fromSource('   '), isNull);
    });

    test('纯文本歌词（无时间戳）也算有词，不再判为无歌词', () async {
      final lines = await svc.fromSource('歌手：某人不配\n作词：也不配\n\n副歌部分');
      expect(lines, isNotNull);
      expect(lines!.first.time, isNull);
      expect(lines.map((l) => l.text), contains('副歌部分'));
    });
  });
}
