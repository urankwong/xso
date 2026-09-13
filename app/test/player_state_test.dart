import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/providers/player_provider.dart';

/// 播放状态数据层的契约：失败重试与换源都依赖这几项，
/// 一旦"换地址不换头"或"句柄丢失"，重新解析就会再次失败。
void main() {
  QueueItem item({String url = 'https://a.com/x.mp3'}) => QueueItem(
        title: '某首歌',
        artist: '歌手',
        url: url,
        sourceName: '洛雪源',
        sourceId: 'src-lx-1',
        extra: {
          '__lxItem': '{"name":"某首歌"}',
          '__headers': jsonEncode({'Referer': 'https://old.example.com/'}),
        },
      );

  test('换播放地址必须同步换请求头', () {
    final it = item();
    // 重新解析时插件把新的 Referer/Cookie 写进 extra['__headers']，
    // 沿用旧头会让刚解析出来的地址再次取流失败
    final swapped = it.withUrl('https://cdn.new/y.mp3');
    expect(swapped.headers!['Referer'], 'https://old.example.com/');

    final withFresh = QueueItem(
      title: it.title,
      url: it.url,
      extra: {...?it.extra, '__headers': '{"Referer":"https://new.ref/"}'},
      headers: const {'Referer': 'https://stale.ref/'},
    ).withUrl('https://cdn.new/z.mp3');
    expect(withFresh.headers!['Referer'], 'https://new.ref/');
  });

  test('换地址保留来源与解析句柄', () {
    final swapped = item().withUrl('https://cdn.new/y.mp3');
    // 丢了 sourceId / __lxItem 就无法再次回源解析，失败后只能放弃
    expect(swapped.sourceId, 'src-lx-1');
    expect(swapped.sourceName, '洛雪源');
    expect(swapped.extra?['__lxItem'], contains('某首歌'));
  });

  test('队列条目可还原为带句柄的搜索结果', () {
    final r = item(url: '').toSearchResult();
    expect(r.sourceId, 'src-lx-1');
    expect(r.title, '某首歌');
    expect(r.url, isEmpty);
    expect(r.extra?['__lxItem'], isNotNull);
  });

  test('同曲缓存键稳定，切歌即失效', () {
    const a = TrackInfo(
        title: '某首歌', artist: '歌手', extra: {'album': '某专辑'});
    const same = TrackInfo(
        title: '某首歌', artist: '歌手', extra: {'album': '某专辑'});
    expect(a.cacheKey, same.cacheKey);
    // 封面/歌词 Future 以该键缓存，键不稳就会反复重新请求
    expect(a.copyWith(url: 'https://other/z.mp3').cacheKey, a.cacheKey);
    expect(
        const TrackInfo(title: '另一首', artist: '歌手').cacheKey,
        isNot(a.cacheKey));
    expect(a.toSearchResult().title, '某首歌');
  });
}
