import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/data_providers.dart';
import '../providers/downloads.dart';
import '../providers/player_provider.dart';
import '../providers/player_providers.dart';
import '../widgets/download_confirm.dart';

/// 音乐歌单页：粘贴公开歌单链接/ID → 解析曲目 → 播放全部 / 下载全部。
/// 走 MusicFree 插件标准的 getMusicSheetInfo，无需账号登录。
class PlaylistPage extends ConsumerStatefulWidget {
  const PlaylistPage({super.key});

  @override
  ConsumerState<PlaylistPage> createState() => _PlaylistPageState();
}

class _SavedSheet {
  final String sourceId;
  final String sheetId;
  final String title;
  const _SavedSheet(this.sourceId, this.sheetId, this.title);

  Map<String, dynamic> toJson() =>
      {'sourceId': sourceId, 'sheetId': sheetId, 'title': title};

  factory _SavedSheet.fromJson(Map j) => _SavedSheet(
      j['sourceId'] as String? ?? '', j['sheetId'] as String? ?? '',
      j['title'] as String? ?? '');
}

class _PlaylistPageState extends ConsumerState<PlaylistPage> {
  static const _kSaved = 'saved_sheets';
  final _input = TextEditingController();

  List<SearchableSource> _musicSources = const [];
  String? _sourceId;
  List<_SavedSheet> _saved = const [];

  bool _loading = false;
  String? _error;
  String? _sheetTitle;
  List<SearchResult> _tracks = const [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final all = await ref.read(searchableSourcesProvider.future);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kSaved) ?? const [];
    if (!mounted) return;
    setState(() {
      _musicSources =
          all.where((s) => s.meta.type == SourceType.music).toList();
      _sourceId = _musicSources.isEmpty ? null : _musicSources.first.meta.id;
      _saved = raw
          .map((e) {
            try {
              return _SavedSheet.fromJson(jsonDecode(e) as Map);
            } catch (_) {
              return null;
            }
          })
          .whereType<_SavedSheet>()
          .toList();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// 从链接或裸 ID 提取歌单 id
  static String? extractSheetId(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    final patterns = [
      RegExp(r'playlist/(\d+)'), // 163.com/playlist/12345
      RegExp(r'playlist/([A-Za-z0-9]+)'), // y.qq.com/n/ryqq/playlist/XXX
      RegExp(r'[?&]id=([A-Za-z0-9]+)'), // playlist?id=12345
      RegExp(r'\[id=([A-Za-z0-9]+)\]'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(s);
      if (m != null) return m.group(1);
    }
    if (RegExp(r'^[A-Za-z0-9_-]{5,}$').hasMatch(s)) return s;
    return null;
  }

  Future<void> _load(String link) async {
    final sourceId = _sourceId;
    if (sourceId == null) {
      setState(() => _error = '请先在源管理中启用一个音乐源');
      return;
    }
    final sheetId = extractSheetId(link);
    if (sheetId == null) {
      setState(() => _error = '无法识别歌单链接或 ID');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _tracks = const [];
      _sheetTitle = null;
    });
    try {
      final assembler = await ref.read(sourceAssemblerProvider.future);
      final tracks = await assembler
          .sheetTracks(sourceId, sheetId)
          .timeout(const Duration(seconds: 45));
      if (!mounted) return;
      final srcName = _musicSources
          .firstWhere((s) => s.meta.id == sourceId, orElse: () => _musicSources.first)
          .meta;
      setState(() {
        _tracks = tracks;
        _sheetTitle = '歌单 $sheetId（${srcName.name}）';
        _loading = false;
      });
      await _remember(sourceId, sheetId, sheetId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _remember(String sourceId, String sheetId, String title) async {
    final prefs = await SharedPreferences.getInstance();
    final next = [
      _SavedSheet(sourceId, sheetId, title),
      ..._saved.where((s) => !(s.sourceId == sourceId && s.sheetId == sheetId)),
    ].take(20).toList();
    setState(() => _saved = next);
    await prefs.setStringList(
        _kSaved, next.map((e) => jsonEncode(e.toJson())).toList());
  }

  Future<void> _clearSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSaved);
    if (!mounted) return;
    setState(() => _saved = const []);
  }

  /// 解析出可播放地址；插件来源必须现解析（列表里的 url 常常不可用）
  Future<String?> _resolvePlayable(String sourceId, SearchResult t) async {
    final fromPlugin = (t.extra?['__item'] ?? '').isNotEmpty;
    if (!fromPlugin) return t.url.startsWith('http') ? t.url : null;
    try {
      final assembler = await ref.read(sourceAssemblerProvider.future);
      final url = await assembler.resolveMedia(sourceId, t);
      return url.startsWith('http') ? url : null;
    } catch (_) {
      return null;
    }
  }

  /// 解析整张歌单后播放，并从第 [fromTrack] 首开始
  Future<void> _playFrom(int fromTrack) async {
    final sourceId = _sourceId;
    if (sourceId == null || _tracks.isEmpty) return;
    _tip('正在解析播放地址…');
    final items = <QueueItem>[];
    var start = 0;
    for (var i = 0; i < _tracks.length; i++) {
      final t = _tracks[i];
      final url = await _resolvePlayable(sourceId, t);
      if (url == null) continue;
      if (i == fromTrack) start = items.length;
      items.add(QueueItem(
        title: t.title,
        artist: t.extra?['artist'] ?? '',
        cover: t.extra?['cover'] ?? '',
        url: url,
        sourceName: t.sourceName,
        sourceId: sourceId,
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
        title: '全部曲目',
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
      appBar: AppBar(title: const Text('音乐歌单')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_musicSources.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('还没有可用的音乐源，请先到「源管理」导入或启用音乐源',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _sourceId,
              decoration: const InputDecoration(labelText: '解析源'),
              items: [
                for (final s in _musicSources)
                  DropdownMenuItem(
                      value: s.meta.id, child: Text(s.meta.name)),
              ],
              onChanged: (v) => setState(() => _sourceId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _input,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '粘贴歌单链接或 ID',
                hintText: '如 https://music.163.com/#/playlist?id=xxxxx\n或 y.qq.com/n/ryqq/playlist/xxxxx',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : () => _load(_input.text),
                    icon: const Icon(Icons.search, size: 20),
                    label: const Text('解析歌单'),
                  ),
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
              ],
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: TextStyle(color: scheme.error, fontSize: 12.5)),
            ),
          if (_saved.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text('最近解析',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                TextButton(onPressed: _clearSaved, child: const Text('清空')),
              ],
            ),
            for (final s in _saved)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.queue_music, size: 20),
                title: Text(s.title.isEmpty ? s.sheetId : s.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('ID ${s.sheetId}', style: const TextStyle(fontSize: 11.5)),
                onTap: () {
                  setState(() => _sourceId = s.sourceId);
                  _input.text = s.sheetId;
                  _load(s.sheetId);
                },
              ),
          ],
          if (_sheetTitle != null) ...[
            const SizedBox(height: 18),
            Text(_sheetTitle!, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
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
            const SizedBox(height: 6),
            for (var i = 0; i < _tracks.length; i++)
              ValueListenableBuilder<PlayerStateX>(
                valueListenable: ref.read(playerProvider).state,
                builder: (context, st, _) {
                  final t = _tracks[i];
                  final playable = t.url.startsWith('http');
                  final isCurrent = st.url.isNotEmpty && st.url == t.url;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    selected: isCurrent,
                    leading: isCurrent
                        ? Icon(Icons.graphic_eq, size: 18, color: scheme.primary)
                        : Text('${i + 1}',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                    title: Text(t.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      [
                        t.extra?['artist'] ?? '',
                        if (!playable) '需解析',
                      ].where((e) => e.isNotEmpty).join(' · '),
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.play_arrow, size: 22),
                      tooltip: playable ? '播放' : '解析后播放',
                      // 插件来源即使没有直链也能现解析
                      onPressed:
                          playable || (t.extra?['__item'] ?? '').isNotEmpty
                              ? () => _playFrom(i)
                              : null,
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}
