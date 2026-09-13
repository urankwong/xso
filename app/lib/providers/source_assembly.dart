import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:source_engine/source_engine.dart';

/// 装配器：源仓库 → 运行时可搜索源列表
class SourceAssembler {
  final SourceEngine engine;
  final String repoPath;

  /// JS 源（musicfree/lx）每个都用独立 QuickJS 实例：
  /// 插件脚本用 const 声明全局，共享同一 runtime 会在重复装配时
  /// 触发 redeclaration 错误，且相互污染全局作用域。
  final JsRuntime Function() jsRuntimeFactory;
  final List<JsRuntime> _ownedRuntimes = [];

  /// 已解析的两段式源（id → Source），供详情页二次请求
  final Map<String, Source> _ownSources = {};

  /// MusicFree 适配源（id → 实例）：有声播客专辑两段式 / 播放地址解析
  final Map<String, MusicFreeSource> _musicFreeSources = {};

  /// 洛雪适配源（id → 实例）：播放地址（action=musicUrl）与歌词（action=lyric）
  final Map<String, LxSource> _lxSources = {};

  /// 懒装配缓存（仓库 id → 已包装的 JS 源）
  final Map<String, SearchableSource> _jsWrapped = {};

  /// 取某源的用户变量（B站 Cookie 等），装配时注入插件 env.getUserVariables()
  final Map<String, String> Function(String sourceId)? userVariablesOf;

  /// 内置源的 HTTP 取文本实现（app 层用 dio 注入）。
  /// 为 null 时不注册内置源，保持「纯仓库加载」的既有行为。
  final HttpTextGetter? builtinHttpGet;

  SourceAssembler({
    required this.engine,
    required this.repoPath,
    required this.jsRuntimeFactory,
    this.userVariablesOf,
    this.builtinHttpGet,
  });

  Future<List<SearchableSource>> loadEnabled() async {
    // 重新装配前释放上一批 JS runtime（自有源 parse 钩子用的 engine.jsRuntime 除外）
    for (final rt in _ownedRuntimes) {
      rt.dispose();
    }
    _ownedRuntimes.clear();
    _ownSources.clear();
    _musicFreeSources.clear();
    _lxSources.clear();
    _jsWrapped.clear();

    final repo = SourceRepository(repoPath);
    final stored = await repo.list();
    final result = <SearchableSource>[];

    for (final s in stored.where((e) => e.enabled)) {
      // JS 源懒装配：此处不起 QuickJS，首次搜索时才包装该源。
      // 否则 26 个 JS 源要串行装完才出第一条结果，首搜极慢。
      if (s.format == 'musicfree' || s.format == 'lx') {
        result.add(_LazyJsSource(this, s));
        continue;
      }
      final raw = await repo.readRaw(s.id);
      try {
        switch (s.format) {
          case 'own':
            final parsed = parseSource(raw);
            _ownSources[s.id] = parsed;
            result.add(_EngineSource(engine, parsed));
          case 'legado':
            final translated = LegadoAdapter().translate(raw);
            _ownSources[s.id] = translated;
            result.add(_EngineSource(engine, translated));
          default:
            continue; // 未知格式跳过（不炸全局）
        }
      } catch (e, stack) {
        // 单源损坏不影响其他源装配（源级隔离从装配开始）
        assert(() {
          // ignore: avoid_print
          print('[SourceAssembler] 装配失败 ${s.id} (${s.format}): $e\n$stack');
          return true;
        }());
        continue;
      }
    }

    // 内置「歌名即直链」源：不依赖源仓库，把关键词一步换成可播放直链
    // （oiapi.net，免 key）。与逐源搜索并行，作为「想听就播」的快速兜底。
    if (builtinHttpGet != null) {
      try {
        result.add(await OiapiAdapter(httpGet: builtinHttpGet!).wrap());
      } catch (e) {
        assert(() {
          // ignore: avoid_print
          print('[SourceAssembler] 内置 oiapi 源装配失败: $e');
          return true;
        }());
      }
    }
    return result;
  }

  static SourceType typeOfStored(StoredSource s) =>
      SourceType.values.firstWhere((t) => t.name == s.type,
          orElse: () => SourceType.music);

  /// 按需包装 JS 源（该源首次搜索时调用），按仓库 id 登记供两段式复用
  Future<SearchableSource> wrapJsSource(StoredSource s) async {
    final cached = _jsWrapped[s.id];
    if (cached != null) return cached;
    final raw = await SourceRepository(repoPath).readRaw(s.id);
    final rt = jsRuntimeFactory();
    _ownedRuntimes.add(rt);
    final SearchableSource src;
    if (s.format == 'musicfree') {
      final mf = await MusicFreeAdapter(jsRuntime: rt).wrap(
        raw,
        name: s.name,
        type: typeOfStored(s),
        storageKey: s.id,
        userVariables: userVariablesOf?.call(s.id) ?? const {},
      );
      _musicFreeSources[s.id] = mf;
      src = mf;
    } else {
      final lx = await LxAdapter(jsRuntime: rt).wrap(raw, name: s.name);
      _lxSources[s.id] = lx;
      src = lx;
    }
    _jsWrapped[s.id] = src;
    return src;
  }

  /// 某源声明的用户变量（B站 Cookie 等）；未装配时按需装配一次
  Future<List<Map<String, dynamic>>> userVariableSpec(String sourceId) async {
    final mf = await _mfOf(sourceId);
    return mf?.userVariableSpec ?? const [];
  }

  /// 两段式：优先 MusicFree 有声播客专辑（拉曲目列表），否则走规则源详情页提网盘链接
  Future<List<SearchResult>> fetchDetail(
      String sourceId, SearchResult item) async {
    // 走 _mfOf：懒装配下该源可能尚未包装（如重启后直接进详情）
    final mf = await _mfOf(sourceId);
    if (mf != null && mf.meta.type == SourceType.audiobook) {
      return mf.fetchAlbumTracks(item);
    }
    final source = _ownSources[sourceId];
    if (source == null) {
      throw Exception('两段式源未装配: $sourceId');
    }
    return engine.fetchDetail(source, item);
  }

  /// 解析曲目的播放地址（点播时按需调用）。
  /// MusicFree 走 getMediaSource，洛雪走 action=musicUrl；
  /// 两者都拿不到时退回结果自带 url（部分源 search 就直接给直链）。
  Future<String> resolveMedia(String sourceId, SearchResult track,
      {String quality = 'standard'}) async {
    final mf = await _mfOf(sourceId);
    if (mf != null) return mf.resolveMedia(track, quality: quality);
    final lx = await _lxOf(sourceId);
    if (lx != null) return lx.resolveMedia(track, quality: quality);
    return track.url;
  }

  /// 取歌词：优先源自身（洛雪 action=lyric / 结果内联歌词 / 插件给的歌词地址），
  /// 拿不到再交由上层退回第三方歌词库
  Future<String?> fetchLyric(String sourceId, SearchResult track) async {
    final lx = await _lxOf(sourceId);
    if (lx != null) return lx.fetchLyric(track);
    final inline = track.extra?['lyric'];
    return (inline == null || inline.isEmpty) ? null : inline;
  }

  /// 取已装配的洛热源；懒装配下若尚未包装则按仓库记录即时装配一次
  Future<LxSource?> _lxOf(String sourceId) async {
    final cached = _lxSources[sourceId];
    if (cached != null) return cached;
    final stored = await SourceRepository(repoPath).list();
    final s = stored.firstWhere(
      (e) => e.id == sourceId && e.enabled && e.format == 'lx',
      orElse: () => const StoredSource(
          id: '', format: '', name: '', type: '', enabled: false, file: ''),
    );
    if (s.id.isEmpty) return null;
    await wrapJsSource(s);
    return _lxSources[sourceId];
  }

  /// 该源是否支持专辑检索（MusicFree 插件实现 search type='album' + getAlbumInfo）
  bool supportsAlbum(String sourceId) => _musicFreeSources.containsKey(sourceId);

  /// 取已装配的 MusicFree 源；懒装配下若尚未包装（如直接从歌单页进入），
  /// 按仓库记录即时装配一次。
  Future<MusicFreeSource?> _mfOf(String sourceId) async {
    final cached = _musicFreeSources[sourceId];
    if (cached != null) return cached;
    final stored = await SourceRepository(repoPath).list();
    final s = stored.firstWhere(
      (e) => e.id == sourceId && e.enabled && e.format == 'musicfree',
      orElse: () => const StoredSource(
          id: '', format: '', name: '', type: '', enabled: false, file: ''),
    );
    if (s.id.isEmpty) return null;
    await wrapJsSource(s);
    return _musicFreeSources[sourceId];
  }

  /// 按专辑名搜专辑条目（结果带 __item，可直接喂给 albumTracks）
  Future<List<SearchResult>> searchAlbums(String sourceId, String albumName) async {
    final mf = await _mfOf(sourceId);
    if (mf == null) throw Exception('该源不支持专辑检索');
    return mf.searchAlbums(albumName);
  }

  /// 拉取指定专辑的曲目列表
  Future<List<SearchResult>> albumTracks(String sourceId, SearchResult album) async {
    final mf = await _mfOf(sourceId);
    if (mf == null) throw Exception('该源不支持专辑曲目');
    return mf.fetchAlbumTracks(album);
  }

  /// 按歌单 id 拉曲目（公开歌单免登录，走插件 getMusicSheetInfo）
  Future<List<SearchResult>> sheetTracks(String sourceId, String sheetId,
      {int page = 1}) async {
    final mf = await _mfOf(sourceId);
    if (mf == null) throw Exception('该源不支持歌单解析');
    return mf.fetchSheetTracks(sheetId, page: page);
  }
}

/// 自有/Legado 格式的运行时包装
class _EngineSource implements SearchableSource {
  final SourceEngine _engine;
  final Source _source;
  _EngineSource(this._engine, this._source);

  @override
  SourceMeta get meta => _source.meta;

  @override
  Future<List<SearchResult>> search(SearchQuery query) =>
      _engine.search(_source, query);
}

/// JS 源（musicfree/lx）的懒包装代理：meta 直接取自仓库记录（同步可得，
/// 供编排器发状态事件与 UI 分组），首次 search() 时才真正起 QuickJS 装配插件。
class _LazyJsSource implements SearchableSource {
  final SourceAssembler _owner;
  final StoredSource _stored;
  SearchableSource? _inner;
  Future<SearchableSource>? _wrapping;

  _LazyJsSource(this._owner, this._stored);

  @override
  SourceMeta get meta => SourceMeta(
        id: _stored.id,
        name: _stored.name.isEmpty ? _stored.id : _stored.name,
        type: SourceAssembler.typeOfStored(_stored),
        version: 1,
        origin: _stored.format,
      );

  @override
  Future<List<SearchResult>> search(SearchQuery query) async {
    final inner = _inner ??= await (_wrapping ??= _owner.wrapJsSource(_stored));
    final results = await inner.search(query);
    // 归一归属：插件内部 id 与仓库 id 不同，统一按仓库源标注，
    // 以便两段式详情/播放地址解析按同一 id 找到该源。
    return [
      for (final r in results)
        SearchResult(
          sourceId: meta.id,
          sourceName: meta.name,
          type: r.type,
          title: r.title,
          url: r.url,
          extractCode: r.extractCode,
          extra: r.extra,
          needsDetail: r.needsDetail,
        )
    ];
  }
}
