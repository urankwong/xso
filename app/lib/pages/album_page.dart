import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../providers/data_providers.dart';
import '../providers/downloads.dart';
import '../providers/lyric.dart' show parseQualities;
import '../providers/player_provider.dart';
import '../providers/player_providers.dart';
import '../widgets/download_confirm.dart';

/// 专辑页：按专辑名搜到专辑条目 → 拉曲目列表 → 播放全部 / 下载全部。
/// 入口：搜索页音乐条目的专辑名。
class AlbumPage extends ConsumerStatefulWidget {
  final String sourceId;
  final String sourceName;
  final String albumName;
  final String? artist;
  const AlbumPage({
    super.key,
    required this.sourceId,
    required this.sourceName,
    required this.albumName,
    this.artist,
  });

  @override
  ConsumerState<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends ConsumerState<AlbumPage> {
  bool _loading = true;
  String? _error;
  SearchResult? _album;
  List<SearchResult> _tracks = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final assembler = await ref.read(sourceAssemblerProvider.future);
      final found = await assembler.searchAlbums(widget.sourceId, widget.albumName);
      if (found.isEmpty) {
        throw Exception('未在该源找到专辑「${widget.albumName}」');
      }
      // 优先取名称完全一致者，否则取第一条
      String norm(String s) => s
          .replaceAll(RegExp(r'[\s《》「」【】\(\)（）]'), '')
          .toLowerCase();
      final album = found.firstWhere(
        (a) => norm(a.title) == norm(widget.albumName),
        orElse: () => found.first,
      );
      final tracks = await assembler.albumTracks(widget.sourceId, album);
      if (!mounted) return;
      setState(() {
        _album = album;
        _tracks = tracks.where((t) => t.url.isNotEmpty || t.needsDetail).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  static bool _isDirect(String url) => url.startsWith('http');

  /// 解析出可播放地址。插件来源必须现解析：曲目列表里的 url 常常是
  /// 页面地址或占位值（实测网易云即是），直接播会报 Source error。
  Future<String?> _resolvePlayable(SearchResult t) async {
    final fromPlugin = (t.extra?['__item'] ?? '').isNotEmpty;
    if (!fromPlugin) return _isDirect(t.url) ? t.url : null;
    try {
      final assembler = await ref.read(sourceAssemblerProvider.future);
      final url = await assembler.resolveMedia(widget.sourceId, t);
      return _isDirect(url) ? url : null;
    } catch (_) {
      return null;
    }
  }

  /// 解析整张专辑后播放，并从第 [fromTrack] 首开始。
  /// 统一走这一条路径，索引不会因为过滤掉解析失败的曲目而错位。
  Future<void> _playFrom(int fromTrack) async {
    if (_tracks.isEmpty) return;
    _tip('正在解析播放地址…');
    final items = <QueueItem>[];
    var start = 0;
    for (var i = 0; i < _tracks.length; i++) {
      final t = _tracks[i];
      final url = await _resolvePlayable(t);
      if (url == null) continue;
      if (i == fromTrack) start = items.length;
      items.add(QueueItem(
        title: t.title,
        artist: t.extra?['artist'] ?? widget.artist ?? '',
        cover: t.extra?['cover'] ?? '',
        url: url,
        sourceName: widget.sourceName,
        sourceId: widget.sourceId,
        extra: t.extra,
        headers: playbackHeaders(t.extra),
      ));
    }
    if (items.isEmpty) {
      _tip('未能解析出可播放的曲目');
      return;
    }
    await ref.read(playerProvider).playQueue(items, startIndex: start);
  }

  Future<void> _playAll() => _playFrom(0);

  Future<void> _downloadAll() async {
    final items = _tracks
        .where((t) => t.url.startsWith('http'))
        .map((t) => (
              url: t.url,
              title: t.title,
              artist: t.extra?['artist'] ?? widget.artist,
            ))
        .toList();
    if (items.isEmpty) {
      _tip('没有可下载的直链曲目');
      return;
    }
    if (await downloadConfirmEnabled()) {
      if (!mounted) return;
      final label = await showDownloadConfirm(
        context,
        kind: DownloadKind.music,
        title: widget.albumName.isEmpty ? '全部曲目' : widget.albumName,
        artist: widget.artist,
        qualities: [(id: '${items.length}', name: '共 ${items.length} 首')],
      );
      if (label == null) return;
    }
    final n = await ref.read(downloadsProvider).enqueueAll(items);
    _tip('已加入下载队列 $n 首');
  }

  void _tip(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_album?.title ?? widget.albumName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '复制专辑名',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.albumName));
              _tip('已复制专辑名');
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      _header(scheme),
                      _actions(scheme),
                      const Divider(height: 1),
                      if (_tracks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text('该专辑暂无曲目',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                        )
                      else
                        for (var i = 0; i < _tracks.length; i++)
                          _trackTile(i, _tracks[i], scheme),
                    ],
                  ),
                ),
    );
  }

  Widget _header(ColorScheme scheme) {
    final cover = _album?.extra?['cover'];
    final desc = _album?.extra?['desc'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cover(cover, 96, scheme),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_album?.title ?? widget.albumName,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '${_album?.extra?['artist'] ?? widget.artist ?? ''} · ${_tracks.length} 首 · ${widget.sourceName}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (desc != null && desc.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(desc,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cover(String? url, double size, ColorScheme scheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: (url != null && url.startsWith('http'))
            ? Image.network(url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _coverPlaceholder(scheme, size))
            : _coverPlaceholder(scheme, size),
      ),
    );
  }

  Widget _coverPlaceholder(ColorScheme scheme, double size) => Container(
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.album, size: size * 0.4, color: scheme.onSurfaceVariant),
      );

  Widget _actions(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            // 与歌单页 / 曲目页保持同一按钮样式
            child: FilledButton.tonalIcon(
              onPressed: _tracks.isEmpty ? null : _playAll,
              icon: const Icon(Icons.play_arrow, size: 20),
              label: const Text('播放全部'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _tracks.isEmpty ? null : _downloadAll,
              icon: const Icon(Icons.download, size: 20),
              label: const Text('下载全部'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trackTile(int index, SearchResult t, ColorScheme scheme) {
    final playable = t.url.startsWith('http');
    // 插件来源即使没有直链也能现解析，按钮不应被判为不可用
    final canPlay = playable || (t.extra?['__item'] ?? '').isNotEmpty;
    final player = ref.read(playerProvider);
    return ValueListenableBuilder<PlayerStateX>(
      valueListenable: player.state,
      builder: (context, st, _) {
        final isCurrent = st.url.isNotEmpty && st.url == t.url;
        return ListTile(
      dense: true,
      selected: isCurrent,
      leading: SizedBox(
        width: 26,
        child: isCurrent
            ? Icon(Icons.graphic_eq, size: 18, color: scheme.primary)
            : Text('${index + 1}',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
      ),
      title: Text(t.title, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          t.extra?['artist'] ?? widget.artist ?? '',
          if (t.extra?['qualities'] != null) '多音质',
          if (!playable) '需解析',
        ].where((s) => s.isNotEmpty).join(' · '),
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(canPlay ? Icons.play_arrow : Icons.hourglass_empty,
                size: 22),
            tooltip: canPlay ? '播放' : '无法播放',
            onPressed: canPlay ? () => _playFrom(index) : null,
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined, size: 22),
            tooltip: '下载',
            onPressed: canPlay
                ? () async {
                    // 先解析真实地址，否则下载到的是无效内容
                    final url = await _resolvePlayable(t);
                    if (url == null) {
                      _tip('该曲目没有可下载的直链');
                      return;
                    }
                    var label = '默认音质';
                    if (await downloadConfirmEnabled()) {
                      if (!mounted) return;
                      final picked = await showDownloadConfirm(
                        context,
                        kind: DownloadKind.music,
                        title: t.title,
                        artist: t.extra?['artist'] ?? widget.artist,
                        qualities: parseQualities(t.extra),
                      );
                      if (picked == null) return;
                      label = picked;
                    }
                    final ok = await ref.read(downloadsProvider).enqueue(
                          url: url,
                          title: t.title,
                          artist: t.extra?['artist'] ?? widget.artist,
                          qualityLabel: label,
                          headers: playbackHeaders(t.extra),
                        );
                    if (ok) _tip('已加入下载队列：${t.title}');
                  }
                : null,
          ),
        ],
      ),
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.error_outline, size: 40, color: scheme.error),
        const SizedBox(height: 12),
        Text('专辑加载失败',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重试'),
          ),
        ),
      ],
    );
  }
}
