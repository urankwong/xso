import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/providers/play_failover.dart';

/// 换源不是"换首歌听"：跨源搜索会带回大量同名近似、现场版、翻唱与纯音乐，
/// 排序错了就会把用户原想听的歌换成另一首。
SearchResult _r(String title,
        {String source = 's1', String artist = '', String url = ''}) =>
    SearchResult(
      sourceId: source,
      sourceName: source,
      type: SourceType.music,
      title: title,
      url: url,
      extra: {if (artist.isNotEmpty) 'artist': artist},
    );

void main() {
  test('标题归一化忽略括号后缀与标点', () {
    expect(normalizeTitle('Love Story (Taylor\'s Version)'), 'lovestory');
    expect(normalizeTitle('《平凡之路》'), '平凡之路');
    expect(normalizeTitle('QQ 音乐 - 正式版'), 'qq音乐正式版');
  });

  test('同名优先、其次包含关系，明确不同名的不入选', () {
    final ranked = rankSameSongCandidates(
      found: [
        _r('另一首歌', source: 'x'),
        _r('某首歌 Live', source: 'live'),
        _r('某首歌', source: 'exact'),
      ],
      title: '某首歌',
    );
    expect(ranked.map((e) => e.sourceName), ['exact', 'live']);
  });

  test('歌手一致的候选排到前面', () {
    final ranked = rankSameSongCandidates(
      found: [
        _r('某首歌', source: 'cover', artist: '别人唱'),
        _r('某首歌', source: 'right', artist: '原唱'),
      ],
      title: '某首歌',
      artist: '原唱',
    );
    expect(ranked.first.sourceName, 'right');
  });

  test('排除失败的那个来源，带直链的加分', () {
    final ranked = rankSameSongCandidates(
      found: [
        _r('某首歌', source: 'dead'),
        _r('某首歌', source: 'direct', url: 'https://cdn/a.mp3'),
      ],
      title: '某首歌',
      excludeSourceId: 'dead',
    );
    expect(ranked.map((e) => e.sourceName), ['direct']);
  });

  test('空标题不产生任何候选', () {
    expect(
        rankSameSongCandidates(found: [_r('某首歌')], title: '   '), isEmpty);
  });
}
