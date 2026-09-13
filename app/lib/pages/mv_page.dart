import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../providers/data_providers.dart';
import '../providers/downloads.dart';
import '../providers/mv_service.dart';
import '../providers/plugin_store.dart';
import '../widgets/download_confirm.dart';

/// MV 播放页：解析 B 站视频直链并用视频内核播放，支持清晰度切换、
/// 横屏全屏与下载（落到 Movies 目录，带 Referer）。
class MvPage extends ConsumerStatefulWidget {
  final String bvid;
  final String? title;
  const MvPage({super.key, required this.bvid, this.title});

  @override
  ConsumerState<MvPage> createState() => _MvPageState();
}

class _MvPageState extends ConsumerState<MvPage> {
  MvInfo? _info;
  String? _error;
  VideoPlayerController? _player;
  int _qn = 32;
  bool _landscape = false;
  /// 是否拿到了 B 站 Cookie（决定清晰度上限提示要不要显示）
  bool _hasCookie = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  /// 取已配置的 B站 Cookie（源管理里配过的），有则解锁高清晰度
  Future<String?> _biliCookie() async {
    try {
      final store = await ref.read(pluginStoreProvider.future);
      // 优先取「收藏与喜欢」里登录保存的平台 Cookie
      final account = store.userVars('account.bilibili')['cookie'];
      if (account != null && account.isNotEmpty) return account;
      final sources = await ref.read(searchableSourcesProvider.future);
      for (final s in sources) {
        final n = s.meta.name.toLowerCase();
        if (!(n.contains('哔哩') || n.contains('bilibili'))) continue;
        final c = store.userVars(s.meta.id)['biliCookie'];
        if (c != null && c.isNotEmpty) return c;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _resolve() async {
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      final cookie = await _biliCookie();
      if (mounted) setState(() => _hasCookie = cookie != null);
      final info = await ref
          .read(mvServiceProvider)
          .resolve(widget.bvid,
              fallbackTitle: widget.title,
              cookie: cookie,
              qn: cookie != null ? 80 : 32);
      await _attach(info);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _attach(MvInfo info, {Duration startAt = Duration.zero}) async {
    await _player?.dispose();
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(info.urlFor(_qn)),
      httpHeaders: info.headers,
    );
    try {
      await controller.initialize();
      // 切换清晰度时接着原来的位置播，不要把用户拉回片头
      if (startAt > Duration.zero && startAt < controller.value.duration) {
        await controller.seekTo(startAt);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '视频加载失败：$e');
      return;
    }
    controller.addListener(_onTick);
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _info = info;
      _player = controller;
    });
    await controller.play();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleLandscape() async {
    final next = !_landscape;
    setState(() => _landscape = next);
    await SystemChrome.setPreferredOrientations([
      if (next) DeviceOrientation.landscapeLeft
      else
        DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(
        next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  Future<void> _download() async {
    final info = _info;
    if (info == null) return;
    final currentQ = info.qualities
        .firstWhere((q) => q.qn == _qn, orElse: () => info.qualities.first);
    var label = currentQ.label;
    if (await downloadConfirmEnabled()) {
      if (!mounted) return;
      final picked = await showDownloadConfirm(
        context,
        kind: DownloadKind.movie,
        title: info.title,
        artist: info.artist,
        initial: currentQ.label,
        qualities: [
          for (final q in info.qualities) (id: '${q.qn}', name: q.label),
        ],
      );
      if (picked == null) return;
      label = picked;
    }
    final qn = info.qualities
        .firstWhere((q) => q.label == label, orElse: () => currentQ)
        .qn;
    final ok = await ref.read(downloadsProvider).enqueue(
          url: info.urlFor(qn),
          title: info.title,
          artist: info.artist,
          cover: info.cover,
          qualityLabel: label,
          subDir: 'Movies',
          headers: info.headers,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? '已加入下载队列（Movies 目录）' : '该任务已在队列中')));
  }

  @override
  void dispose() {
    _player?.removeListener(_onTick);
    _player?.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final info = _info;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(info?.title ?? widget.title ?? 'MV',
            overflow: TextOverflow.ellipsis),
        actions: [
          if (info != null)
            PopupMenuButton<int>(
              icon: const Icon(Icons.hd),
              onSelected: (qn) async {
                if (qn == _qn) return;
                final pos = _player?.value.position ?? Duration.zero;
                setState(() => _qn = qn);
                await _attach(info, startAt: pos);
              },
              itemBuilder: (_) => [
                for (final q in info.qualities)
                  PopupMenuItem(value: q.qn, child: Text(q.label)),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: '下载 MV',
            onPressed: info == null ? null : _download,
          ),
          IconButton(
            icon: Icon(_landscape ? Icons.fullscreen_exit : Icons.fullscreen),
            tooltip: '横屏',
            onPressed: info == null ? null : _toggleLandscape,
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: scheme.error, size: 36),
                    const SizedBox(height: 10),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _resolve,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          : info == null || _player == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    AspectRatio(
                      aspectRatio: _player!.value.aspectRatio,
                      child: VideoPlayer(_player!),
                    ),
                    VideoProgressIndicator(
                      _player!,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                          playedColor: Color(0xFF2BD4B4),
                          bufferedColor: Colors.white24,
                          backgroundColor: Colors.white12),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              _player!.value.isPlaying
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled,
                              color: Colors.white,
                              size: 40,
                            ),
                            onPressed: () => _player!.value.isPlaying
                                ? _player!.pause()
                                : _player!.play(),
                          ),
                          const SizedBox(width: 8),
                          Text(_fmt(_player!.value.position),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          const Spacer(),
                          Text(
                            info.qualities
                                .firstWhere((q) => q.qn == _qn,
                                    orElse: () => info.qualities.first)
                                .label,
                            style:
                                const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          const SizedBox(width: 8),
                          Text(_fmt(_player!.value.duration),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        // 已登录时不再显示「未登录」，否则用户会以为登录没生效。
                        // 页面背景恒为黑色，不能用 scheme.onSurfaceVariant：
                        // 浅色主题下它是深灰，黑底上几乎不可见。
                        '上传：${info.artist}'
                        '${_hasCookie ? '' : '  ·  未登录最高 480P，登录后可切更高清晰度'}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }
}
