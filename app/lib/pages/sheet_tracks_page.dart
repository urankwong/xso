import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../providers/data_providers.dart';
import '../providers/downloads.dart';
import '../providers/player_provider.dart';
import '../providers/player_providers.dart';
import '../widgets/download_confirm.dart';

/// 歌单/专辑曲目页：按源 id + 歌单 id 拉曲目，支持整单播放与下载。
class SheetTracksPage extends ConsumerStatefulWidget {
  final String sourceId;
  final String sourceName;
  final String sheetId;
  final String title;
  const SheetTracksPage({
    super.key,
    required this.sourceId,
    required this.sourceName,
    required this.sheetId,
    required this.title,
  });

  @override
  ConsumerState<SheetTracksPage> createState() => _SheetTracksPageState();
}

class _SheetTracksPageState extends ConsumerState<SheetTracksPage> {
  List<SearchResult> _tracks = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final assembler = await ref.read(sourceAssemblerProvider.future);
      final tracks = await assembler
          .sheetTracks(widget.sourceId, widget.sheetId)
          .timeout(const Duration(seconds: 60));
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
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

  /// 解析出可播放地址；插件来源必须现解析（列表里的 url 常常不可用）
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

  /// 解析整张歌单后播放，并从第 [fromTrack] 首开始
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
        artist: t.extra?['artist'] ?? '',
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
    final list = _tracks
        .where((t) => t.url.startsWith('http'))
        .map((t) =>
            (url: t.url, title: t.title, artist: t.extra?['artist']))
        .toList();
    if (list.isEmpty) {
      _tip('没有可下载的直链曲目');
      return;
    }
    if (await downloadConfirmEnabled()) {
      if (!mounted) return;
      final label = await showDownloadConfirm(
        context,
        kind: DownloadKind.music,
        title: widget.title.isEmpty ? '全部曲目' : widget.title,
        qualities: [(id: '${list.length}', name: '共 ${list.length} 首')],
      );
      if (label == null) return;
    }
    final n = await ref.read(downloadsProvider).enqueueAll(list);
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
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('曲目获取失败：$_error',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.error, fontSize: 13)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: _tracks.isEmpty ? null : _playAll,
                                icon: const Icon(Icons.play_arrow, size: 20),
                                label: Text('播放全部 (${_tracks.length})'),
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
                      ),
                      Expanded(
                        child: _tracks.isEmpty
                            ? Center(
                                child: Text('该歌单暂无曲目',
                                    style:
                                        TextStyle(color: scheme.onSurfaceVariant)),
                              )
                            : ListView.builder(
                                itemCount: _tracks.length,
                                itemBuilder: (context, i) {
                                  final t = _tracks[i];
                                  final playable = t.url.startsWith('http');
                                  return ValueListenableBuilder<PlayerStateX>(
                                    valueListenable:
                                        ref.read(playerProvider).state,
                                    builder: (context, st, _) {
                                      final isCurrent =
                                          st.url.isNotEmpty && st.url == t.url;
                                      return ListTile(
                                    dense: true,
                                    selected: isCurrent,
                                    leading: isCurrent
                                        ? Icon(Icons.graphic_eq,
                                            size: 18, color: scheme.primary)
                                        : Text('${i + 1}',
                                            style: TextStyle(
                                                color: scheme.onSurfaceVariant)),
                                    title: Text(t.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text(
                                      [
                                        t.extra?['artist'] ?? '',
                                        if (!playable) '需解析',
                                      ].where((e) => e.isNotEmpty).join(' · '),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.play_arrow),
                                      tooltip: '播放',
                                      // 插件来源即使没有直链也能现解析
                                      onPressed: playable ||
                                              (t.extra?['__item'] ?? '')
                                                  .isNotEmpty
                                          ? () => _playFrom(i)
                                          : null,
                                    ),
                                      );
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
