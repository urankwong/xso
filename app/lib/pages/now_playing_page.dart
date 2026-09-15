import 'dart:async';
import 'dart:math' show pi;

import 'dart:typed_data' show Uint8List;
import 'dart:ui' show ImageFilter;

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/data_providers.dart';
import '../providers/downloads.dart';
import '../providers/lyric.dart';
import '../providers/metadata.dart';
import '../providers/player_provider.dart'
    show PlayMode, PlayModeX, ProgressInfo, QueueItem, TrackInfo;
import '../providers/player_providers.dart';
import 'song_info_page.dart';

String _fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString();
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

String _speedLabel(double v) =>
    v % 1 == 0 ? '${v.toStringAsFixed(1)}x' : '${v}x';

const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

const _lyricLineHeight = 52.0;

/// 全屏正在播放页（深色沉浸式）：封面/歌词双页 + 队列 + 播放模式 + 音质/倍速
class NowPlayingPage extends ConsumerStatefulWidget {
  const NowPlayingPage({super.key});

  @override
  ConsumerState<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends ConsumerState<NowPlayingPage> {
  final PageController _pageController = PageController();
  final ScrollController _lyricScroll = ScrollController();
  double? _dragValue;
  bool _vinylEffect = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      _vinylEffect = p.getBool('vinylEffect') ?? false;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _lyricScroll.dispose();
    super.dispose();
  }

  void _flipPage(int target) {
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF141518),
      // 只订阅曲目标识：position 每 200ms 心跳一次，若在这里订阅 state，
      // 背景/封面/歌词会被连带重建，画面持续闪烁
      body: ValueListenableBuilder<TrackInfo>(
        valueListenable: player.track,
        builder: (context, tk, _) {
          if (!tk.active) {
            return const Center(
                child: Text('当前没有播放中的歌曲',
                    style: TextStyle(color: Colors.white70)));
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(child: _Backdrop(tk: tk)),
              SafeArea(
                child: Column(
                  children: [
                    _TopBar(tk: tk, onShare: () => _copyLink(tk)),
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        children: [
                          _CoverPage(
                              tk: tk,
                              onTap: () => _flipPage(1),
                              vinyl: _vinylEffect),
                          _LyricPage(
                            tk: tk,
                            scrollController: _lyricScroll,
                          ),
                        ],
                      ),
                    ),
                    _ErrorBanner(onReparse: _retryCurrent, onSwitch: _switchSource),
                    _FunctionRow(
                      tk: tk,
                      onQualityTap: () => _showQualitySheet(tk),
                      onMoreTap: () => _showMoreSheet(tk),
                      // 下载就下载，不再复用音质弹窗
                      onDownloadTap: () => _download(
                          context, tk.url, _qualityLabelOf(tk),
                          closeSheet: false),
                    ),
                    _ProgressRow(
                      dragValue: _dragValue,
                      onDrag: (v) => setState(() => _dragValue = v),
                      onSeekEnd: (v) {
                        setState(() => _dragValue = null);
                        final dur = player.progress.value.duration;
                        if (dur != null && dur.inMilliseconds > 0) {
                          player.seek(dur * v);
                        }
                      },
                    ),
                    _ControlRow(),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _copyLink(TrackInfo tk) async {
    await Clipboard.setData(ClipboardData(text: tk.url));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制链接')));
    }
  }

  /// 失败重试：带源句柄的条目重新解析一次地址再播。
  /// 直链多为临时签名地址，沿用旧地址重试只会再次失败，
  /// 所以这里必须回源要新地址，而不是简单地再 play 一遍。
  Future<void> _retryCurrent() async {
    final player = ref.read(playerProvider);
    if (player.queueIndex.value < 0) return;
    final assembler = await ref.read(sourceAssemblerProvider.future);
    await player.reparseCurrent((item) async {
      if (item.sourceId.isEmpty) return item.url;
      try {
        return await assembler.resolveMedia(item.sourceId, item.toSearchResult());
      } catch (_) {
        return item.url; // 解析失败时退回原地址，失败态由控制器统一给出
      }
    });
  }

  /// 手动换个来源播放（同名曲目跨源搜索 + 逐个解析验证）
  Future<void> _switchSource() async {
    final player = ref.read(playerProvider);
    final ok = await player.switchSourceManually();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      final name = player.track.value.sourceName;
      messenger.showSnackBar(SnackBar(
          content: Text(name.isEmpty ? '已换到其他来源播放' : '已切到「$name」继续播放')));
    } else {
      messenger.showSnackBar(
          const SnackBar(content: Text('没找到能播出声音的其他来源')));
    }
  }

  // ---------- 音质 ----------

  /// extra 里找该音质对应的播放地址
  String? _qualityUrl(Map<String, String>? extra, String id) {
    for (final key in [id, 'url_$id', '${id}Url', '${id}_url']) {
      final v = extra?[key];
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// 解析指定音质的播放地址：优先 extra 预存，否则回源 resolveMedia(quality)
  Future<String> _resolveQualityUrl(TrackInfo tk, String qualityId) async {
    if (tk.sourceId.isEmpty) return tk.url;
    try {
      final assembler = await ref.read(sourceAssemblerProvider.future);
      return await assembler.resolveMedia(
          tk.sourceId, tk.toSearchResult(), quality: qualityId);
    } catch (_) {
      return tk.url;
    }
  }

  Future<void> _showQualitySheet(TrackInfo tk) async {
    final qualities = parseQualities(tk.extra);
    final player = ref.read(playerProvider);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('选择音质', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (qualities.isEmpty)
              ListTile(
                leading: const Icon(Icons.high_quality),
                title: const Text('默认音质'),
                subtitle: const Text('源未提供其他音质档位'),
                trailing: IconButton(
                  icon: const Icon(Icons.download_outlined),
                  tooltip: '下载',
                  onPressed: () => _download(sheetCtx, tk.url, '默认音质'),
                ),
              ),
            for (final q in qualities)
              () {
                final cachedUrl = _qualityUrl(tk.extra, q.id);
                return ListTile(
                  leading: const Icon(Icons.high_quality),
                  title: Text(q.name),
                  subtitle: Text(
                      cachedUrl != null ? '可在线播放' : '点击切换音质',
                      style: const TextStyle(fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.download_outlined),
                    tooltip: '下载',
                    onPressed: () async {
                      Navigator.pop(sheetCtx);
                      final url =
                          cachedUrl ?? await _resolveQualityUrl(tk, q.id);
                      _download(context, url, q.name);
                    },
                  ),
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    final url =
                        cachedUrl ?? await _resolveQualityUrl(tk, q.id);
                    if (url.startsWith('http')) {
                      player.switchCurrentUrl(url);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已切换至${q.name}')),
                        );
                      }
                    } else if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('无法获取${q.name}地址')),
                      );
                    }
                  },
                );
              }(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 当前音质名（下载按钮直接沿用，无需再弹一次音质选择）
  String _qualityLabelOf(TrackInfo tk) {
    final qualities = parseQualities(tk.extra);
    return qualities.isEmpty ? '默认音质' : qualities.first.name;
  }

  Future<void> _download(BuildContext sheetCtx, String url, String label,
      {bool closeSheet = true}) async {
    final tk = ref.read(playerProvider).track.value;
    final added = await ref.read(downloadsProvider).enqueue(
          url: url,
          title: tk.title,
          artist: tk.artist,
          cover: tk.extra?['cover'],
          album: tk.extra?['album'],
          qualityLabel: label,
        );
    if (closeSheet && sheetCtx.mounted) {
      Navigator.pop(sheetCtx);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(added
              ? '已加入下载队列（"下载"页可看进度）'
              : '该文件已在下载队列中')));
    }
  }

  // ---------- 更多 ----------

  Future<void> _showMoreSheet(TrackInfo tk) async {
    final source = tk.sourceName;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('歌曲信息'),
              subtitle: const Text('查看/匹配元数据与写标签设置'),
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SongInfoPage(
                      title: tk.title,
                      artist: tk.artist,
                      sourceCover: tk.extra?['cover'],
                      album: tk.extra?['album'],
                      url: tk.url,
                      extra: tk.extra,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('复制链接'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                await Clipboard.setData(ClipboardData(text: tk.url));
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('已复制链接')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.source_outlined),
              title: const Text('查看来源'),
              subtitle: source.isEmpty ? const Text('未知来源') : Text(source),
              onTap: () {
                Navigator.pop(sheetCtx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(source.isEmpty ? '未知来源' : '来源：$source')));
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ================= 背景 =================

/// 封面模糊暗化背景；封面为空时用主题色渐变兜底
///
/// Future 必须缓存在 State 里：背景原先每次重建都调 coverBytes 拿一个新 Future，
/// FutureBuilder 检测到 future 变化就把快照退回兜底态，于是整片背景一闪一闪。
class _Backdrop extends ConsumerStatefulWidget {
  final TrackInfo tk;
  const _Backdrop({required this.tk});

  @override
  ConsumerState<_Backdrop> createState() => _BackdropState();
}

class _BackdropState extends ConsumerState<_Backdrop> {
  Future<Uint8List?>? _future;
  String _key = '';

  @override
  void initState() {
    super.initState();
    _syncFuture();
  }

  @override
  void didUpdateWidget(covariant _Backdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFuture();
  }

  /// 同一首歌的重复重建不重新取图；切歌才换 Future
  void _syncFuture() {
    final key = '${widget.tk.cacheKey}|${widget.tk.cover}';
    if (key == _key && _future != null) return;
    _key = key;
    _future = ref.read(metadataProvider).coverBytes(
        sourceCover: widget.tk.cover,
        title: widget.tk.title,
        artist: widget.tk.artist,
        album: widget.tk.extra?['album']);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        final bytes = snap.data;
        if (snap.connectionState != ConnectionState.done ||
            snap.hasError ||
            bytes == null ||
            bytes.isEmpty) {
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.primary.withValues(alpha: 0.35),
                  const Color(0xFF141518)
                ],
              ),
            ),
          );
        }
        return ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            // gaplessPlayback：新图就位前继续显示旧图，避免切换瞬间清空成黑底
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
              filterQuality: FilterQuality.none,
            ),
          ),
        );
      },
    );
  }
}

// ================= 顶栏 =================

class _TopBar extends StatelessWidget {
  final TrackInfo tk;
  final VoidCallback onShare;
  const _TopBar({required this.tk, required this.onShare});

  /// 艺人 · 专辑 拼接（专辑为空时只显示艺人）
  static String _artistAlbumText(TrackInfo tk) {
    final album = tk.extra?['album'];
    if (album != null && album.isNotEmpty) {
      return tk.artist.isEmpty ? album : '${tk.artist} · $album';
    }
    return tk.artist;
  }

  @override
  Widget build(BuildContext context) {
    final source = tk.sourceName;
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
          tooltip: '收起',
          onPressed: () => Navigator.pop(context),
        ),
        Expanded(
          child: Column(
            children: [
              Text(tk.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      _artistAlbumText(tk),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ),
                  if (source.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(source,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 10)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        IconButton(
          // 实际行为是复制链接，不是调起系统分享面板：图标和文案必须与行为一致
          icon: const Icon(Icons.link, color: Colors.white),
          tooltip: '复制链接',
          onPressed: onShare,
        ),
      ],
    );
  }
}

// ================= 封面页 =================

class _CoverPage extends ConsumerStatefulWidget {
  final TrackInfo tk;
  final VoidCallback onTap;
  final bool vinyl;
  const _CoverPage(
      {required this.tk, required this.onTap, this.vinyl = false});

  @override
  ConsumerState<_CoverPage> createState() => _CoverPageState();
}

class _CoverPageState extends ConsumerState<_CoverPage> {
  Future<Uint8List?>? _future;
  String _key = '';

  @override
  void initState() {
    super.initState();
    _syncFuture();
  }

  @override
  void didUpdateWidget(covariant _CoverPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFuture();
  }

  /// 只有换歌（或换封面源）才重新取图；同曲重建复用同一 Future，
  /// 否则 FutureBuilder 每次重建都退回转圈态
  void _syncFuture() {
    final tk = widget.tk;
    final key = '${tk.cacheKey}|${tk.cover}';
    if (key == _key && _future != null) return;
    _key = key;
    _future = ref.read(metadataProvider).coverBytes(
        sourceCover: tk.cover,
        title: tk.title,
        artist: tk.artist,
        album: tk.extra?['album']);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.vinyl) {
      return _VinylCover(tk: widget.tk, onTap: widget.onTap);
    }
    final size = MediaQuery.of(context).size.shortestSide - 64.0;
    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: size,
              height: size,
              child: FutureBuilder<Uint8List?>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2));
                  }
                  final bytes = snap.data;
                  if (snap.hasError || bytes == null || bytes.isEmpty) {
                    return _placeholder(context);
                  }
                  return Image.memory(bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => _placeholder(context));
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) => Container(
        color: Colors.white.withValues(alpha: 0.08),
        child: Icon(Icons.music_note,
            size: 72, color: Colors.white.withValues(alpha: 0.4)),
      );
}

/// 黑胶唱片旋转封面：播放时匀速旋转，暂停时停止（保留当前角度）。
/// 封面圆形裁剪居中，外圈暗色底盘 + 纹理环 + 中心圆点。
/// 旋转由 AnimationController 驱动，仅监听 playing 状态变化启停，
/// 不受 progress 200ms 心跳影响。
class _VinylCover extends ConsumerStatefulWidget {
  final TrackInfo tk;
  final VoidCallback onTap;
  const _VinylCover({required this.tk, required this.onTap});

  @override
  ConsumerState<_VinylCover> createState() => _VinylCoverState();
}

class _VinylCoverState extends ConsumerState<_VinylCover>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Future<Uint8List?>? _future;
  String _key = '';
  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    _syncFuture();
    final player = ref.read(playerProvider);
    player.progress.addListener(_onProgressChanged);
    _onProgressChanged();
  }

  @override
  void didUpdateWidget(covariant _VinylCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFuture();
  }

  void _syncFuture() {
    final tk = widget.tk;
    final key = '${tk.cacheKey}|${tk.cover}';
    if (key == _key && _future != null) return;
    _key = key;
    _future = ref.read(metadataProvider).coverBytes(
        sourceCover: tk.cover,
        title: tk.title,
        artist: tk.artist,
        album: tk.extra?['album']);
  }

  /// 仅在 playing 状态真正变化时启停旋转，心跳频繁但不产生开销
  void _onProgressChanged() {
    final pg = ref.read(playerProvider).progress.value;
    final isPlaying = pg.playing && !pg.failed;
    if (isPlaying == _wasPlaying) return;
    _wasPlaying = isPlaying;
    if (isPlaying) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    ref.read(playerProvider).progress.removeListener(_onProgressChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.shortestSide - 64.0;
    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.rotate(
              angle: _controller.value * 2 * pi,
              child: child,
            ),
            child: _buildVinyl(size),
          ),
        ),
      ),
    );
  }

  Widget _buildVinyl(double size) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1A1A1A),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
          ),
          for (final r in const [0.62, 0.68, 0.74, 0.8, 0.86, 0.92])
            Container(
              width: size * r,
              height: size * r,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.04),
                  width: 0.5,
                ),
              ),
            ),
          ClipOval(
            child: SizedBox(
              width: size * 0.55,
              height: size * 0.55,
              child: FutureBuilder<Uint8List?>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2));
                  }
                  final bytes = snap.data;
                  if (snap.hasError || bytes == null || bytes.isEmpty) {
                    return _placeholder(context);
                  }
                  return Image.memory(bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => _placeholder(context));
                },
              ),
            ),
          ),
          Container(
            width: size * 0.08,
            height: size * 0.08,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF333333),
            ),
          ),
          Container(
            width: size * 0.025,
            height: size * 0.025,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF666666),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context) => Container(
        color: Colors.white.withValues(alpha: 0.08),
        child: Icon(Icons.music_note,
            size: 48, color: Colors.white.withValues(alpha: 0.4)),
      );
}

// ================= 歌词页 =================

class _LyricPage extends ConsumerStatefulWidget {
  final TrackInfo tk;
  final ScrollController scrollController;

  const _LyricPage({
    required this.tk,
    required this.scrollController,
  });

  @override
  ConsumerState<_LyricPage> createState() => _LyricPageState();
}

class _LyricPageState extends ConsumerState<_LyricPage> {
  /// 歌词请求 Future：切歌才重建。
  /// 此前写在 build 里（future: lyricService.fetch(...)），
  /// 每次心跳重建都会新建一个 Future 并重新发请求，FutureBuilder 永远停在
  /// 加载态——这就是"歌词从来不显示"的直接原因。
  Future<List<LyricLine>>? _future;
  String _key = '';

  /// 当前高亮行：由 progress 心跳驱动，供自动滚动判断
  int _activeIdx = -1;

  /// 用户手动拖动歌词后暂停自动跟随，5 秒无操作再恢复。
  /// 原先只要当前行变化就 animateTo，用户永远无法翻看前后歌词。
  bool _followPaused = false;
  Timer? _followTimer;

  @override
  void initState() {
    super.initState();
    _syncFuture();
  }

  @override
  void didUpdateWidget(covariant _LyricPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tk.cacheKey != oldWidget.tk.cacheKey) {
      _activeIdx = -1; // 换歌后从头跟随，避免沿用上次的行号
    }
    _syncFuture();
  }

  void _syncFuture() {
    final key = widget.tk.cacheKey;
    if (key == _key && _future != null) return;
    _key = key;
    _future = _loadLyric(widget.tk);
  }

  /// 两级歌词链：① 源自身（洛雪 action=lyric / 内联歌词 / 插件给的歌词地址）
  /// ② 第三方歌词库按歌名歌手匹配。
  /// 以前只有第 ② 级，源明明带了词也会显示"暂无歌词"。
  Future<List<LyricLine>> _loadLyric(TrackInfo tk) async {
    final lyricService = ref.read(lyricProvider);
    try {
      if (tk.sourceId.isNotEmpty) {
        final assembler = await ref.read(sourceAssemblerProvider.future);
        final raw =
            await assembler.fetchLyric(tk.sourceId, tk.toSearchResult());
        final fromSource = await lyricService.fromSource(raw);
        if (fromSource != null) return fromSource;
      }
    } catch (_) {
      // 源取词失败（无该动作/网络问题）不打断播放，继续走第三方库
    }
    return lyricService.fetch(title: tk.title, artist: tk.artist);
  }

  @override
  void dispose() {
    _followTimer?.cancel();
    super.dispose();
  }

  void _pauseFollow() {
    _followTimer?.cancel();
    if (!_followPaused) setState(() => _followPaused = true);
    _followTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _followPaused = false);
    });
  }

  void _autoScroll(int activeIdx) {
    if (_followPaused) return;
    final scroll = widget.scrollController;
    if (!scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      final max = scroll.position.maxScrollExtent;
      final target = (activeIdx * _lyricLineHeight -
              scroll.position.viewportDimension / 3)
          .clamp(0.0, max);
      scroll.animateTo(target,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 去掉整片区域的单击切页手势：用户想选中/翻看歌词时，
    // 一次轻点就被翻回封面页。切页交给 PageView 的左右滑动。
    return FutureBuilder<List<LyricLine>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
              child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
          return Center(
            child: Text('暂无歌词',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 15)),
          );
        }
        final lines = snap.data!;
        final hasTimes = lines.any((l) => l.time != null);
        // 纯文本歌词（无时间轴）：居中静态展示，不滚动
        if (!hasTimes) {
          return SingleChildScrollView(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
              child: Column(
                children: [
                  for (final line in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        line.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }
        // 带时间轴歌词：滚动跟随 + 当前行高亮 + 距离衰减透明度
        final player = ref.read(playerProvider);
        return ValueListenableBuilder<ProgressInfo>(
          valueListenable: player.progress,
          builder: (context, pg, _) {
            var activeIdx = -1;
            for (var i = 0; i < lines.length; i++) {
              final t = lines[i].time;
              if (t != null && t <= pg.position) activeIdx = i;
            }
            if (activeIdx != _activeIdx) {
              _activeIdx = activeIdx;
              if (activeIdx >= 0) _autoScroll(activeIdx);
            }
            return NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollStartNotification && n.dragDetails != null) {
                  _pauseFollow();
                }
                return false;
              },
              child: ListView.builder(
                controller: widget.scrollController,
                padding: EdgeInsets.symmetric(
                    horizontal: 32, vertical: _lyricLineHeight * 2),
                itemCount: lines.length,
                itemExtent: _lyricLineHeight,
                itemBuilder: (context, i) {
                  final active = i == activeIdx;
                  final distance = (i - activeIdx).abs();
                  final opacity = active
                      ? 1.0
                      : switch (distance) {
                          1 => 0.85,
                          2 => 0.55,
                          3 => 0.35,
                          _ => 0.20,
                        };
                  final line = lines[i];
                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: line.time != null
                        ? () => ref.read(playerProvider).seek(line.time!)
                        : null,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            line.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: active ? 17 : 14.5,
                              fontWeight: active
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: active
                                  ? const Color(0xFF2BD4B4)
                                  : Colors.white.withValues(alpha: opacity),
                            ),
                          ),
                          if (active &&
                              line.translation != null &&
                              line.translation!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                line.translation!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

// ================= 功能行 =================

class _FunctionRow extends ConsumerWidget {
  final TrackInfo tk;
  final VoidCallback onQualityTap;
  final VoidCallback onMoreTap;
  final VoidCallback onDownloadTap;
  const _FunctionRow({
    required this.tk,
    required this.onQualityTap,
    required this.onMoreTap,
    required this.onDownloadTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final db = ref.watch(appDbProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // 收藏
          Expanded(
            child: StreamBuilder<List<Favorite>>(
              stream: db.favoriteDao.watchAll(),
              builder: (context, snap) {
                final favs = snap.data ?? const [];
                final isFav = favs.any((f) => f.url == tk.url);
                return IconButton(
                  icon: Icon(
                    isFav ? Icons.favorite : Icons.favorite_border,
                    color: isFav ? const Color(0xFFEC407A) : Colors.white70,
                  ),
                  tooltip: '收藏',
                  onPressed: () => _toggleFavorite(context, ref, isFav),
                );
              },
            ),
          ),
          // 音质胶囊
          Expanded(
            child: Center(child: _pill(context, _qualityLabel(), onTap: onQualityTap)),
          ),
          // 倍速胶囊：弹出可选列表，而不是盲切到下一个档位
          Expanded(
            child: Center(
              child: ValueListenableBuilder(
                valueListenable: player.speed,
                builder: (context, sp, _) => _pill(context, _speedLabel(sp),
                    onTap: () => _showSpeedMenu(context, ref, sp)),
              ),
            ),
          ),
          // 下载
          Expanded(
            child: IconButton(
              icon: const Icon(Icons.download_outlined, color: Colors.white70),
              tooltip: '下载',
              onPressed: onDownloadTap,
            ),
          ),
          // 更多
          Expanded(
            child: IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white70),
              tooltip: '更多',
              onPressed: onMoreTap,
            ),
          ),
        ],
      ),
    );
  }

  String _qualityLabel() {
    final qualities = parseQualities(tk.extra);
    if (qualities.isEmpty) return '音质';
    return qualities.first.name;
  }

  Widget _pill(BuildContext context, String text, {required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ),
    );
  }

  Future<void> _toggleFavorite(
      BuildContext context, WidgetRef ref, bool isFav) async {
    if (isFav) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已在收藏中')));
      return;
    }
    final db = ref.read(appDbProvider);
    final source = tk.extra?['source'] ?? '';
    await db.favoriteDao.add(SearchResult(
      sourceId: 'local-player',
      sourceName: source.isNotEmpty
          ? source
          : (tk.sourceName.isNotEmpty ? tk.sourceName : '播放器'),
      type: SourceType.music,
      title: tk.title,
      url: tk.url,
      extra: tk.extra,
    ));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已收藏')));
    }
  }

  /// 倍速选择：列出全部档位并标注当前值。
  /// 原来是点击盲循环到下一档，用户既看不到当前档位也预判不到下一个，
  /// 只能靠 SnackBar 事后确认，想回到 1.0x 要连点好几下。
  static Future<void> _showSpeedMenu(
      BuildContext context, WidgetRef ref, double cur) async {
    final v = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child:
                  Text('播放倍速', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final s in _speeds)
              ListTile(
                title: Text(_speedLabel(s)),
                trailing: (s - cur).abs() < 0.001
                    ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (v == null) return;
    await ref.read(playerProvider).setSpeed(v);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('倍速已切换至 ${_speedLabel(v)}')));
    }
  }
}

// ================= 失败提示条 =================

/// 取流失败提示：说明原因并给一个能真正救活的入口。
/// 原先只弹一条两秒消失的 SnackBar，之后播放按钮变回可点状态，
/// 用户反复点只是在重播同一个失效地址，看起来像"点了没反应"。
class _ErrorBanner extends ConsumerWidget {
  final Future<void> Function() onReparse;
  final Future<void> Function() onSwitch;
  const _ErrorBanner({required this.onReparse, required this.onSwitch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    return ValueListenableBuilder<ProgressInfo>(
      valueListenable: player.progress,
      builder: (context, pg, _) {
        if (!pg.failed) return const SizedBox.shrink();
        // 找替代来源要跨源搜索并逐个解析，几秒内必须让按钮显出"在做事"，
        // 否则用户会以为没响应而反复点
        return ValueListenableBuilder<bool>(
          valueListenable: player.failingOver,
          builder: (context, finding, _) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    size: 16, color: Color(0xFFFF8A80)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    finding ? '正在寻找其他来源…' : (pg.error ?? '这一来源没能放出声音'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFFFFB4AB), fontSize: 12),
                  ),
                ),
                if (!finding) ...[
                  TextButton(
                    onPressed: onSwitch,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF2BD4B4),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('换个来源'),
                  ),
                  TextButton(
                    onPressed: () => onReparse(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('重新解析'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ================= 进度条 =================

class _ProgressRow extends ConsumerWidget {
  final double? dragValue;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onSeekEnd;

  const _ProgressRow({
    required this.dragValue,
    required this.onDrag,
    required this.onSeekEnd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 高频进度只订阅在这里：重建范围限于进度条，不再牵连封面与歌词
    final player = ref.watch(playerProvider);
    return ValueListenableBuilder<ProgressInfo>(
      valueListenable: player.progress,
      builder: (context, pg, _) {
        final dur = pg.duration ?? Duration.zero;
        final progress = dur.inMilliseconds == 0
            ? 0.0
            : (pg.position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text(_fmt(pg.position),
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.5,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: dragValue ?? progress,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white24,
                    onChanged: dur.inMilliseconds == 0 ? null : onDrag,
                    onChangeEnd: dur.inMilliseconds == 0 ? null : onSeekEnd,
                  ),
                ),
              ),
              Text(_fmt(dur),
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        );
      },
    );
  }
}


/// 播放队列/章节列表：打开时自动滚动定位到当前播放条目
class _QueueListView extends StatefulWidget {
  final List<QueueItem> items;
  final int current;
  final bool isChapter;
  final ColorScheme scheme;
  final ValueChanged<int> onPick;

  const _QueueListView({
    required this.items,
    required this.current,
    required this.isChapter,
    required this.scheme,
    required this.onPick,
  });

  @override
  State<_QueueListView> createState() => _QueueListViewState();
}

class _QueueListViewState extends State<_QueueListView> {
  final ScrollController _controller = ScrollController();

  static const _rowExtent = 52.0;

  @override
  void initState() {
    super.initState();
    if (widget.current > 2) {
      // 打开面板时定位到当前条目（上下留 2 行上下文）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) {
          _controller.jumpTo(
              ((widget.current - 2) * _rowExtent)
                  .clamp(0.0, _controller.position.maxScrollExtent));
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _QueueListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 章节模式切集（自动连播）时跟随滚动
    if (widget.current != oldWidget.current && _controller.hasClients) {
      final target = ((widget.current - 2) * _rowExtent)
          .clamp(0.0, _controller.position.maxScrollExtent);
      if ((target - _controller.offset).abs() > _rowExtent * 4) {
        _controller.animateTo(target,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.items;
    final cur = widget.current;
    return ListView.builder(
      controller: _controller,
      itemCount: q.length,
      padding: const EdgeInsets.only(bottom: 16),
      itemBuilder: (context, i) {
        final item = q[i];
        final active = i == cur;
        return ListTile(
          dense: true,
          leading: widget.isChapter
              ? SizedBox(
                  width: 34,
                  child: Text(
                    active ? '▶' : '${i + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                      color: active ? widget.scheme.primary : Colors.white38,
                    ),
                  ),
                )
              : active
                  ? Icon(Icons.graphic_eq, color: widget.scheme.primary)
                  : const Icon(Icons.music_note, color: Colors.white38),
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? widget.scheme.primary : widget.scheme.onSurface,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: item.artist.isEmpty
              ? null
              : Text(item.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
          onTap: () => widget.onPick(i),
        );
      },
    );
  }
}

// ================= 控制行 =================

class _ControlRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final scheme = Theme.of(context).colorScheme;

    final q = player.queue.value;
    final cur = player.queueIndex.value;
    final isChapter = isChapterMode(q, cur);
    return ValueListenableBuilder<ProgressInfo>(
      valueListenable: player.progress,
      builder: (context, pg, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // 播放模式
            ValueListenableBuilder(
              valueListenable: player.playMode,
              builder: (context, mode, _) => IconButton(
                icon: Icon(_modeIcon(mode), color: Colors.white70),
                tooltip: mode.label,
                onPressed: () => player.cyclePlayMode(),
              ),
            ),
            // 上一首/上一集
            IconButton(
              icon: const Icon(Icons.skip_previous, color: Colors.white),
              iconSize: 36,
              tooltip: isChapter ? '上一集' : '上一首',
              onPressed: pg.loading ? null : () => player.previous(),
            ),
            // 播放/暂停
            SizedBox(
              width: 56,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                ),
                onPressed: pg.loading ? null : () => player.toggle(),
                child: pg.loading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: scheme.onPrimary))
                    : pg.failed
                        ? const Icon(Icons.error_outline, size: 30)
                        : Icon(pg.playing ? Icons.pause : Icons.play_arrow,
                            size: 32),
              ),
            ),
            // 下一首/下一集
            IconButton(
              icon: const Icon(Icons.skip_next, color: Colors.white),
              iconSize: 36,
              tooltip: isChapter ? '下一集' : '下一首',
              onPressed: pg.loading ? null : () => player.next(),
            ),
            // 播放队列/章节列表
            IconButton(
              icon: Icon(
                  isChapter ? Icons.format_list_bulleted : Icons.queue_music,
                  color: Colors.white70),
              tooltip: isChapter ? '章节列表' : '播放队列',
              onPressed: () => _showQueueSheet(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  IconData _modeIcon(PlayMode mode) => switch (mode) {
        PlayMode.sequence => Icons.format_list_numbered,
        PlayMode.loopList => Icons.repeat,
        PlayMode.loopOne => Icons.repeat_one,
        PlayMode.shuffle => Icons.shuffle,
      };

  /// 章节模式判定：当前条目为有声播客章节
  static bool isChapterMode(List<QueueItem> q, int cur) =>
      cur >= 0 && cur < q.length && q[cur].extra?['chapter'] == '1';

  Future<void> _showQueueSheet(BuildContext context, WidgetRef ref) async {
    final player = ref.watch(playerProvider);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      builder: (sheetCtx) => SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([player.queue, player.queueIndex]),
          builder: (context, _) {
            final q = player.queue.value;
            final cur = player.queueIndex.value;
            if (q.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('播放队列为空')),
              );
            }
            // 有声播客章节模式：当前条目带 chapter 标记时按章节呈现
            final isChapter = cur >= 0 &&
                cur < q.length &&
                q[cur].extra?['chapter'] == '1';
            final scheme = Theme.of(context).colorScheme;
            return SizedBox(
              height: MediaQuery.of(sheetCtx).size.height * 0.65,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                        isChapter
                            ? '章节列表（${q.length}）'
                            : '播放队列（${q.length}）',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Flexible(
                    child: _QueueListView(
                      items: q,
                      current: cur,
                      isChapter: isChapter,
                      scheme: scheme,
                      onPick: (i) {
                        Navigator.pop(sheetCtx);
                        player.playAt(i);
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
