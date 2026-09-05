import 'dart:convert';
import 'package:core/core.dart';
import 'package:source_engine/src/js_runtime.dart';

/// 洛雪音乐源适配器：模拟其全局环境（on/事件机制），
/// 把 musicSearch 事件桥接为内部 SearchableSource。
class LxAdapter {
  final JsRuntime jsRuntime;
  LxAdapter({required this.jsRuntime});

  static const _bootstrap = r'''
    globalThis.__lxHandlers = {};
    globalThis.on = function(event, handler) {
      globalThis.__lxHandlers[event] = handler;
    };
    globalThis.lx = {
      request: function(opts) { return __hostFetch(opts); },
      utils: { buffer: {}, crypto: {} },
      on: globalThis.on,
    };
  ''';

  static const _bridge = r'''
    globalThis.__lxSearch = function(keyword) {
      return new Promise(function(resolve) {
        var h = globalThis.__lxHandlers['musicSearch'];
        h(keyword, function(data) { resolve(JSON.stringify(data)); });
      });
    };
  ''';

  Future<LxSource> wrap(String lxJs, {String name = '洛雪源'}) async {
    await jsRuntime.evaluate(_bootstrap);
    await jsRuntime.evaluate(lxJs);
    await jsRuntime.evaluate(_bridge);
    return LxSource._(jsRuntime, name);
  }
}

class LxSource implements SearchableSource {
  final JsRuntime _js;
  @override
  late final SourceMeta meta;

  LxSource._(this._js, String name) {
    meta = SourceMeta(
      id: 'lx://${name.hashCode}',
      name: name,
      type: SourceType.music,
      version: 1,
      origin: 'lx',
    );
  }

  @override
  Future<List<SearchResult>> search(SearchQuery query) async {
    final raw = await _js.evaluate(
      '__lxSearch(${jsonEncode(query.keyword)})',
      timeout: const Duration(seconds: 10),
    );
    final data = jsonDecode(raw) as List;
    return data.map((e) {
      final m = e as Map<String, dynamic>;
      return SearchResult(
        sourceId: meta.id,
        sourceName: meta.name,
        type: SourceType.music,
        title: m['title']?.toString() ?? '(无标题)',
        url: m['url']?.toString() ?? '',
        extra: {
          if (m['artist'] != null) 'artist': m['artist'].toString(),
        },
      );
    }).toList();
  }
}
