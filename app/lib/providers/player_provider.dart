import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart'
    show MediaItem;
import 'package:shared_preferences/shared_preferences.dart';

/// 从 SearchResult.extra 取出解析阶段写入的播放请求头（Referer / Cookie 等）。
/// 部分源（网易云）的 CDN 必须带上才能取流，否则播放器报 Source error。
Map<String, String>? playbackHeaders(Map<String, String>? extra) {
  final raw = extra?['__headers'];
  if (raw == null || raw.isEmpty) return null;
  try {
    final m = jsonDecode(raw);
    if (m is Map && m.isNotEmpty) {
      return m.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
  } catch (_) {
    // 解析失败就按无 headers 处理
  }
  return null;
}

/// 播放模式：顺序 / 列表循环 / 单曲循环 / 随机
enum PlayMode { sequence, loopList, loopOne, shuffle }

extension PlayModeX on PlayMode {
  String get label => switch (this) {
        PlayMode.sequence => '顺序播放',
        PlayMode.loopList => '列表循环',
        PlayMode.loopOne => '单曲循环',
        PlayMode.shuffle => '随机播放',
      };
}

/// 队列条目：来源一首可播放的音乐结果
@immutable
class QueueItem {
  final String title;
  final String artist;
  final String cover;
  final String url;
  final String sourceName;

  /// 仓库源 id（非插件内部 id）：失败重新解析、跨源换播都要靠它回查已装配的源
  final String sourceId;
  final Map<String, String>? extra; // 原 SearchResult.extra（音质/下载用）
  final Map<String, String>? headers; // 取流必需的请求头（Referer/Cookie）

  const QueueItem({
    required this.title,
    this.artist = '',
    this.cover = '',
    required this.url,
    this.sourceName = '',
    this.sourceId = '',
    this.extra,
    this.headers,
  });

  QueueItem withUrl(String newUrl) => QueueItem(
        title: title,
        artist: artist,
        cover: cover,
        url: newUrl,
        sourceName: sourceName,
        sourceId: sourceId,
        extra: extra,
        // 换地址必须同时换头：插件每次解析都往 extra['__headers'] 写新的
        // Referer/Cookie，沿用旧头会让刚解析出来的地址再次取流失败
        headers: playbackHeaders(extra) ?? headers,
      );

  /// 还原为可再次解析的搜索结果形态（extra 带 __item/__lxItem 句柄）
  SearchResult toSearchResult() => SearchResult(
        sourceId: sourceId,
        sourceName: sourceName,
        type: SourceType.music,
        title: title,
        url: url,
        extra: extra,
      );
}

/// 迷你播放器状态：当前曲目 + 播放状态 + 进度
@immutable
class PlayerStateX {
  final String? title;
  final String? artist;
  final String? cover;
  final String url;
  final Map<String, String>? extra; // 原 SearchResult.extra（音质/下载用）
  final bool playing;
  final bool loading;

  /// 当前条目取流失败（与 ProgressInfo.failed 同源，state 是派生基准，
  /// 否则下一次 position 心跳重建时失败态会被冲掉）
  final bool failed;
  final Duration position;
  final Duration? duration;
  final String? error;

  const PlayerStateX({
    this.title,
    this.artist,
    this.cover,
    this.url = '',
    this.extra,
    this.playing = false,
    this.loading = false,
    this.failed = false,
    this.position = Duration.zero,
    this.duration,
    this.error,
  });

  bool get active => title != null;
}

/// 曲目标识：仅在切歌（含解析失败换错误态）时变化。
///
/// 播放页的封面与歌词只依赖这里的信息。它们原先订阅 [PlayerStateX]，
/// 而 position 每 200ms 左右就刷新一次 state，导致封面/歌词子树被连带重建，
/// 内部 FutureBuilder 的 future 又是每次新建，于是画面持续闪烁。
@immutable
class TrackInfo {
  final String title;
  final String artist;
  final String cover;
  final String url;
  final String sourceName;
  final String sourceId;
  final Map<String, String>? extra;

  const TrackInfo({
    this.title = '',
    this.artist = '',
    this.cover = '',
    this.url = '',
    this.sourceName = '',
    this.sourceId = '',
    this.extra,
  });

  bool get active => title.isNotEmpty;

  TrackInfo copyWith({String? url, String? sourceName, String? sourceId}) =>
      TrackInfo(
        title: title,
        artist: artist,
        cover: cover,
        url: url ?? this.url,
        sourceName: sourceName ?? this.sourceName,
        sourceId: sourceId ?? this.sourceId,
        extra: extra,
      );

  /// 封面/歌词按此键取缓存，切歌时该键变化才重新拉取
  String get cacheKey =>
      '$title|${extra?['artist'] ?? artist}|${extra?['album'] ?? ''}';

  /// 还原为搜索结果形态（带 __item/__lxItem 句柄时可回源取地址/歌词）
  SearchResult toSearchResult() => SearchResult(
        sourceId: sourceId,
        sourceName: sourceName,
        type: SourceType.music,
        title: title,
        url: url,
        extra: extra,
      );
}

/// 播放进度与状态：高频变化，只喂给进度条与播放按钮。
@immutable
class ProgressInfo {
  final bool playing;
  final bool loading;

  /// 当前条目取流失败（区别于"用户主动暂停"）：
  /// 只有 playing=false 时分不清是暂停还是死掉，按钮会变成可点的播放键，
  /// 用户反复点都毫无反应。failed 用于显示明确的失败态与重试入口。
  final bool failed;
  final Duration position;
  final Duration? duration;
  final String? error;

  const ProgressInfo({
    this.playing = false,
    this.loading = false,
    this.failed = false,
    this.position = Duration.zero,
    this.duration,
    this.error,
  });
}

/// 播放器控制器：队列 + 播放模式 + 倍速 + seek
class PlayerController {
  final AudioPlayer _player = AudioPlayer();
  final ValueNotifier<PlayerStateX> state =
      ValueNotifier<PlayerStateX>(const PlayerStateX());

  /// 低频曲目标识：播放页的封面/歌词/顶栏订阅它，避免被进度心跳带着重建
  final ValueNotifier<TrackInfo> track =
      ValueNotifier<TrackInfo>(const TrackInfo());

  /// 高频进度与播放态：只喂给进度条、播放按钮与歌词当前行
  final ValueNotifier<ProgressInfo> progress =
      ValueNotifier<ProgressInfo>(const ProgressInfo());

  /// 播放队列与当前索引
  final ValueNotifier<List<QueueItem>> queue = ValueNotifier(const []);
  final ValueNotifier<int> queueIndex = ValueNotifier(-1);

  /// 播放模式（持久化 key: playMode）
  final ValueNotifier<PlayMode> playMode = ValueNotifier(PlayMode.sequence);

  /// 来源放不出来时是否自动换其他来源（持久化 key: playAutoFailover）
  final ValueNotifier<bool> autoFailover = ValueNotifier(false);

  /// 换源实现，由 App 层注入（跨源搜索 + 逐候选解析）。
  /// 返回 null 表示没有可用替代来源。
  Future<QueueItem?> Function(QueueItem failed)? failoverResolver;

  /// 播放历史埋点，由 App 层注入：用户主动点播/加入队列时回调。
  /// 用于「最近播放」列表与 AI 对话「播放我最近听的歌」。
  Future<void> Function(QueueItem item)? onTrackPlayed;

  /// 正在换源：让 UI 能显示"正在寻找其他来源"，而不是停在失败态发呆
  final ValueNotifier<bool> failingOver = ValueNotifier(false);

  /// 倍速 0.5~2.0（持久化 key: playSpeed）
  final ValueNotifier<double> speed = ValueNotifier(1.0);

  /// 加载序号：丢弃过期的 setUrl 结果，避免切歌竞态
  int _loadSeq = 0;

  PlayerController() {
    _player.playerStateStream.listen((ps) {
      if (ps.processingState == ProcessingState.completed) {
        // 播放自然结束才触发自动切歌；暂停后的 completed 快照忽略
        if (ps.playing) _autoNext();
        return;
      }
      _patch(
        playing: ps.playing,
        loading: ps.processingState == ProcessingState.loading ||
            ps.processingState == ProcessingState.buffering,
      );
    });
    _player.positionStream.listen((p) {
      _patch(position: p, duration: _player.duration);
    });
    _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e) {
        _patch(error: _friendlyError(e, url: state.value.url));
      },
    );
    _restorePrefs();
  }

  /// 源没给直链时的说明（洛雪等源的 url 是占位值，交给播放器只会得到含糊的 Source error）
  static const _noDirectLink =
      '这个来源不提供可播放的直链，换一首或换个来源';

  /// PlayerException 原文是 "(0) Source error" 这类技术描述，
  /// 用户看不懂也拿不到下一步动作，这里换成可操作的说法。
  /// [url] 用于区分"地址失效"与"该源根本不给直链"：
  /// 洛雪等源的 url 是占位值，交给播放器只会得到同样的 Source error，
  /// 但两者的下一步动作完全不同（前者换源、后者说明源不支持在线播）。
  static String _friendlyError(Object e, {String url = ''}) {
    final s = e.toString();
    if (url.isNotEmpty && !url.startsWith('http')) {
      return _noDirectLink;
    }
    if (s.contains('Source error')) {
      return '播放失败：地址已失效或需要登录，换个来源试试';
    }
    if (s.contains('Connection') || s.contains('timeout')) {
      return '播放失败：网络异常，请重试';
    }
    return '播放失败：$s';
  }

  void _patch({
    bool? playing,
    bool? loading,
    bool? failed,
    Duration? position,
    Duration? duration,
    String? error,
  }) {
    final s = state.value;
    final nextPlaying = playing ?? s.playing;
    final nextLoading = loading ?? s.loading;
    final nextFailed = failed ?? s.failed;
    final nextPosition = position ?? s.position;
    final nextDuration = duration ?? s.duration;
    final nextError = error ?? s.error;
    progress.value = ProgressInfo(
      playing: nextPlaying,
      loading: nextLoading,
      failed: nextFailed,
      position: nextPosition,
      duration: nextDuration,
      error: nextError,
    );
    state.value = PlayerStateX(
      title: s.title,
      artist: s.artist,
      cover: s.cover,
      url: s.url,
      extra: s.extra,
      playing: nextPlaying,
      loading: nextLoading,
      failed: nextFailed,
      position: nextPosition,
      duration: nextDuration,
      error: nextError,
    );
  }

  /// 切歌时一次性写入曲目标识、state 与进度基线。
  /// 三处 PlayerStateX 构造原先各写一份，字段漏改就会导致 state 与 track 不一致
  /// （歌词按 track 取到了上一首），这里收敛为单一入口。
  void _setTrack(QueueItem item,
      {bool loading = false,
      bool playing = false,
      bool failed = false,
      String? error,
      Duration? duration}) {
    // 同一首（URL 未变）重新加载时保持进度：解析失败若把进度写回 00:00，
    // 画面看起来就像还在播上一首，用户无法判断是"停了"还是"卡住了"
    final sameTrack = track.value.url == item.url;
    final position = sameTrack ? progress.value.position : Duration.zero;
    track.value = TrackInfo(
      title: item.title,
      artist: item.artist,
      cover: item.cover,
      url: item.url,
      sourceName: item.sourceName,
      sourceId: item.sourceId,
      extra: item.extra,
    );
    progress.value = ProgressInfo(
      playing: playing,
      loading: loading,
      failed: failed,
      position: position,
      duration: duration,
      error: error,
    );
    state.value = PlayerStateX(
      title: item.title,
      artist: item.artist.isEmpty ? null : item.artist,
      cover: item.cover.isEmpty ? null : item.cover,
      url: item.url,
      extra: item.extra,
      playing: playing,
      loading: loading,
      failed: failed,
      position: position,
      duration: duration,
      error: error,
    );
  }

  Future<void> _restorePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      playMode.value = switch (prefs.getString('playMode')) {
        'loopList' => PlayMode.loopList,
        'loopOne' => PlayMode.loopOne,
        'shuffle' => PlayMode.shuffle,
        _ => PlayMode.sequence,
      };
      autoFailover.value = prefs.getBool('playAutoFailover') ?? false;
      final sp = (prefs.getDouble('playSpeed') ?? 1.0).clamp(0.5, 2.0);
      speed.value = sp;
      await _player.setSpeed(sp);
    } catch (_) {}
  }

  /// 播放单曲（兼容旧调用：以单元素队列替换当前队列）
  Future<void> play({
    required String url,
    required String title,
    String? artist,
    String? cover,
    Map<String, String>? extra,
    String? sourceName,
  }) async {
    await playQueue([
      QueueItem(
        title: title,
        artist: artist ?? '',
        cover: cover ?? '',
        url: url,
        sourceName: sourceName ?? '',
        extra: extra,
        headers: playbackHeaders(extra),
      ),
    ]);
  }

  /// 播放队列：replace=false 时追加到队尾并从追加部分开始播
  Future<void> playQueue(
    List<QueueItem> items, {
    int startIndex = 0,
    bool replace = true,
  }) async {
    if (items.isEmpty) return;
    if (replace) {
      queue.value = List.unmodifiable(items);
      await _loadAt(startIndex);
    } else {
      final base = queue.value.length;
      queue.value = List.unmodifiable([...queue.value, ...items]);
      await _loadAt(base + startIndex.clamp(0, items.length - 1));
    }
    // 主动播放（而非自动切歌）才算"最近听过"，埋点在 playQueue 而非 _loadAt
    if (startIndex >= 0 && startIndex < items.length) {
      final cb = onTrackPlayed;
      if (cb != null) unawaited(cb(items[startIndex]));
    }
  }

  /// 播放队列中指定索引
  Future<void> playAt(int index) => _loadAt(index);

  /// 切换当前曲目的播放地址（音质切换），保留队列其余部分
  Future<void> switchCurrentUrl(String url) async {
    final i = queueIndex.value;
    final q = queue.value;
    if (i < 0 || i >= q.length || url.isEmpty) return;
    final newList = [...q];
    newList[i] = q[i].withUrl(url);
    queue.value = List.unmodifiable(newList);
    await _loadAt(i);
  }

  /// 重试当前条目（播放页失败态入口）。
  /// 直链多为临时签名地址，过期后再点同一首若沿用旧地址必然再失败，
  /// 因此入口应先按需重新解析地址、再调用本方法。
  Future<void> retryCurrent() async {
    final i = queueIndex.value;
    if (i < 0 || i >= queue.value.length) return;
    await _loadAt(i);
  }

  /// 重新解析当前条目地址后重试（由 UI 侧提供解析函数，控制器不依赖装配器）。
  Future<void> reparseCurrent(
      Future<String> Function(QueueItem item) resolve) async {
    final i = queueIndex.value;
    final q = queue.value;
    if (i < 0 || i >= q.length) return;
    try {
      final fresh = await resolve(q[i]);
      if (fresh.isNotEmpty && fresh != q[i].url) {
        await switchCurrentUrl(fresh);
        return;
      }
    } catch (_) {
      // 解析失败仍按原地址重试一次，错误态由 _loadAt 统一给出
    }
    await _loadAt(i);
  }

  /// 载入并播放队列中第 [rawIndex] 首。
  ///
  /// [seq] 用于丢弃过期的 setUrl 结果：快速连点两首时，先发起的加载不得
  /// 回过头把后一首的状态覆盖掉（含 loading，否则播放按钮会永远转圈）。
  Future<void> _loadAt(int rawIndex, {bool allowFailover = true}) async {
    final q = queue.value;
    if (q.isEmpty) return;
    final i = rawIndex.clamp(0, q.length - 1);
    final item = q[i];
    final seq = ++_loadSeq;
    queueIndex.value = i;
    try {
      // 源没给直链（洛雪等源的 url 是占位值）时不必丢给播放器：
      // 只会得到含糊的 Source error，直接走换源/失败分支更准确
      if (!item.url.startsWith('http')) {
        if (allowFailover &&
            autoFailover.value &&
            await _tryFailover(i, item)) {
          return;
        }
        _setTrack(item, failed: true, error: _noDirectLink);
        return;
      }
      _setTrack(item, loading: true);
      // tag 里的 MediaItem 由 just_audio_background 消费：
      // 缺了它就只是"后台能出声"，通知栏与锁屏上看不到曲名和控件
      await _player.setAudioSource(AudioSource.uri(
        Uri.parse(item.url),
        headers: item.headers,
        tag: MediaItem(
          id: item.url,
          title: item.title,
          artist: item.artist.isEmpty
              ? (item.sourceName.isEmpty ? null : item.sourceName)
              : item.artist,
          album: item.extra?['album'],
          artUri: item.cover.startsWith('http') ? Uri.parse(item.cover) : null,
        ),
      ));
      if (seq != _loadSeq) return;
      await _player.setSpeed(speed.value);
      await _player.play();
      if (seq != _loadSeq) return;
      _setTrack(item, playing: true, duration: _player.duration);
    } catch (e) {
      if (seq != _loadSeq) return;
      // setUrl 阶段失败走这里（多数 Source error 是这一步），
      // 同样要走友好文案，否则用户只看到 "(0) Source error"
      final msg = _friendlyError(e, url: item.url);
      if (allowFailover && autoFailover.value) {
        if (await _tryFailover(i, item)) return;
      }
      _setTrack(item, failed: true, error: msg);
    }
  }

  /// 换到其他来源并接管播放；成功返回 true（失败则调用方保持失败态）
  Future<bool> _tryFailover(int index, QueueItem failed) async {
    final resolver = failoverResolver;
    if (resolver == null) return false;
    // 记录"开始找替代时"的加载序号：找源要花几秒，期间若有新的加载（用户切歌）
    // 就该放弃。注意不能等到替换之后再判，那时 _loadAt 本身已递增序号。
    final seqAtStart = _loadSeq;
    failingOver.value = true;
    QueueItem? alt;
    try {
      alt = await resolver(failed);
    } catch (_) {
      alt = null;
    }
    failingOver.value = false;
    if (alt == null || seqAtStart != _loadSeq) return false;
    final updated = [...queue.value];
    if (index < 0 || index >= updated.length) return false;
    updated[index] = alt;
    queue.value = List.unmodifiable(updated);
    // 替换后的加载不再触发换源，避免两条来源互相踢皮球
    await _loadAt(index, allowFailover: false);
    return !state.value.failed;
  }

  /// 手动换个来源（不受"自动换源"开关约束）。
  /// 返回 false 表示没能找到可播的其他来源，维持原失败态。
  Future<bool> switchSourceManually() async {
    final i = queueIndex.value;
    final q = queue.value;
    if (i < 0 || i >= q.length) return false;
    return await _tryFailover(i, q[i]);
  }

  Future<void> next() => _skip(1);

  Future<void> previous() => _skip(-1);

  Future<void> _skip(int dir) async {
    final q = queue.value;
    if (q.isEmpty) return;
    final cur = queueIndex.value < 0 ? 0 : queueIndex.value;
    if (playMode.value == PlayMode.shuffle && q.length > 1) {
      var target = cur;
      while (target == cur) {
        target = Random().nextInt(q.length);
      }
      await _loadAt(target);
      return;
    }
    var target = cur + dir;
    if (target >= q.length) {
      if (playMode.value == PlayMode.loopList) {
        target = 0;
      } else {
        // 顺序播到队尾：回到开头并暂停
        await _player.seek(Duration.zero);
        await _player.pause();
        return;
      }
    }
    if (target < 0) {
      target = playMode.value == PlayMode.loopList ? q.length - 1 : 0;
    }
    await _loadAt(target);
  }

  /// 一曲播完后的自动续播（按播放模式）
  Future<void> _autoNext() async {
    if (queue.value.isEmpty) return;
    if (playMode.value == PlayMode.loopOne) {
      await _player.seek(Duration.zero);
      await _player.play();
    } else {
      await _skip(1);
    }
  }

  /// 循环切换播放模式并持久化
  Future<void> cyclePlayMode() async {
    final modes = PlayMode.values;
    final nextMode = modes[(playMode.value.index + 1) % modes.length];
    playMode.value = nextMode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'playMode', switch (nextMode) {
        PlayMode.sequence => 'sequence',
        PlayMode.loopList => 'loopList',
        PlayMode.loopOne => 'loopOne',
        PlayMode.shuffle => 'shuffle',
      });
    } catch (_) {}
  }

  /// 切换"来源放不出来时自动换源"并持久化
  Future<void> setAutoFailover(bool on) async {
    autoFailover.value = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('playAutoFailover', on);
    } catch (_) {}
  }

  /// 设置倍速（0.5~2.0）并持久化
  Future<void> setSpeed(double v) async {
    final sp = v.clamp(0.5, 2.0);
    speed.value = sp;
    try {
      await _player.setSpeed(sp);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('playSpeed', sp);
    } catch (_) {}
  }

  /// 拖动进度条定位
  Future<void> seek(Duration d) => _player.seek(d);

  Future<void> toggle() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> stop() async {
    await _player.stop();
    track.value = const TrackInfo();
    progress.value = const ProgressInfo();
    state.value = const PlayerStateX();
  }

  void dispose() {
    track.dispose();
    progress.dispose();
    autoFailover.dispose();
    failingOver.dispose();
    state.dispose();
    queue.dispose();
    queueIndex.dispose();
    playMode.dispose();
    speed.dispose();
    _player.dispose();
  }
}
