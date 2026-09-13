import 'dart:convert';

import 'package:core/core.dart';
import 'package:source_engine/source_engine.dart';
import 'package:test/test.dart';

/// 真实洛雪源形态：lx.on('request') + lx.request
const lxJs = '''
  const EVENT_NAMES = { request: 'request', inited: 'inited' };
  lx.on(EVENT_NAMES.request, function({ source, action, info }) {
    return new Promise(function(resolve) {
      lx.request('https://api.example.com/search?kw=' + info.searchText, { method: 'GET' }, function(err, resp) {
        if (err) return resolve({ isEnd: true, list: [] });
        resolve({ isEnd: true, list: [{ name: info.searchText + '-LX', singer: 'a', url: 'https://lx.com/1.mp3' }] });
      });
    });
  });
  lx.send(EVENT_NAMES.inited, { status: true, sources: [] });
''';

void main() {
  test('适配器包装洛雪脚本为内部 SearchableSource', () async {
    final js = FakeJsRuntime(scriptResults: {
      '__lxSearchTake':
          '{"isEnd":true,"list":[{"name":"测试词-LX","singer":"a","url":"https://lx.com/1.mp3"}]}',
    });
    final adapter = LxAdapter(jsRuntime: js);
    final source = await adapter.wrap(lxJs, name: '洛雪测试源');

    expect(source.meta.type, SourceType.music);
    expect(source.meta.origin, 'lx');

    final results = await source.search(SearchQuery(keyword: '测试词'));
    expect(results, hasLength(1));
    expect(results[0].title, '测试词-LX');
  });

  test('搜索结果带上取地址句柄与源自带歌词', () async {
    final js = FakeJsRuntime(scriptResults: {
      '__lxSearchTake':
          '{"isEnd":true,"list":[{"name":"某首歌","singer":"歌手","_lyrText":"[00:01.00]第一行"}]}',
    });
    final source = await LxAdapter(jsRuntime: js).wrap(lxJs, name: '洛雪句柄源');
    final r = (await source.search(SearchQuery(keyword: '某首歌'))).single;

    // 洛雪 action=musicUrl 要求把原 musicInfo 整体传回，缺句柄该源就无法点播
    expect(r.extra?['__lxItem'], contains('"name":"某首歌"'));
    // 源已经给了词，就不该再去第三方库按歌名撞
    expect(r.extra?['lyric'], contains('[00:01.00]第一行'));
  });

  test('resolveMedia 走 musicUrl 拿到直链', () async {
    final js = FakeJsRuntime(scriptResults: {
      '__lxSearchTake':
          '{"isEnd":true,"list":[{"name":"某首歌","singer":"歌手"}]}',
      '__lxInvokeTake':
          '{"data":"https://cdn.example.com/song.mp3?sign=abc"}',
    });
    final source = await LxAdapter(jsRuntime: js).wrap(lxJs, name: '洛雪点播源');
    final track = (await source.search(SearchQuery(keyword: '某首歌'))).single;
    // 该源 search 不给直链，只能靠 musicUrl
    expect(track.url, isEmpty);

    expect(await source.resolveMedia(track),
        'https://cdn.example.com/song.mp3?sign=abc');
  });

  test('resolveMedia 回传 {url, headers} 时写入播放请求头', () async {
    final js = FakeJsRuntime(scriptResults: {
      '__lxSearchTake': '{"isEnd":true,"list":[{"name":"需 Referer 的歌"}]}',
      '__lxInvokeTake':
          '{"data":{"url":"https://cdn.example.com/x.mp3","headers":{"Referer":"https://music.example.com/"}}}',
    });
    final source = await LxAdapter(jsRuntime: js).wrap(lxJs, name: '洛雪带头源');
    final track = (await source.search(SearchQuery(keyword: '需'))).single;

    expect(await source.resolveMedia(track), 'https://cdn.example.com/x.mp3');
    // 不带 Referer 时播放器对该 CDN 只会报 Source error，头必须随地址一起交付
    expect(track.extra?['__headers'], contains('music.example.com'));
  });

  test('音质档位映射到洛雪的 type', () async {
    final requested = <String>[];
    final js = _RecordingLxRuntime(requested);
    final source = await LxAdapter(jsRuntime: js).wrap(lxJs, name: '洛雪档位源');
    final track = SearchResult(
      sourceId: 'lx://t',
      sourceName: 't',
      type: SourceType.music,
      title: 'x',
      url: '',
      extra: {'__lxItem': '{"name":"x","source":"kw"}'},
    );

    await source.resolveMedia(track, quality: 'standard');
    await source.resolveMedia(track, quality: 'higher');
    await source.resolveMedia(track, quality: 'super');

    expect(requested, ['128k', '320k', 'flac']);
  });
}

/// 记录 musicUrl 请求里的音质字段，其余走 FakeJsRuntime 的预置逻辑
class _RecordingLxRuntime extends FakeJsRuntime {
  final List<String> captured;
  _RecordingLxRuntime(this.captured)
      : super(scriptResults: {
          '__lxInvokeTake': '{"data":"https://cdn.example.com/x.mp3"}',
        });

  @override
  Future<String> evaluate(String script, {Duration? timeout}) {
    final m = RegExp(r'^__lxInvoke\((.*)\)$').firstMatch(script.trim());
    if (m != null) {
      // 参数被 jsonEncode 转义过一层，须逐层解码才能看到 info.type
      final request = jsonDecode(jsonDecode(m.group(1)!) as String);
      final type = ((request as Map)['info'] as Map?)?['type']?.toString();
      if (type != null) captured.add(type);
    }
    return super.evaluate(script, timeout: timeout);
  }
}
