import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/id3_tags.dart';
import '../providers/lyric.dart';
import '../providers/metadata.dart';

/// 持久化开关键：下载时写入音频标签
const kWriteTagsKey = 'writeTags';

/// 歌曲信息面板：查看/自动匹配元数据 + 歌词状态 + 写标签开关
class SongInfoPage extends ConsumerStatefulWidget {
  final String title;
  final String? artist;
  final String? sourceCover; // 源透传封面（extra['cover']）
  final String? album; // 源透传专辑（extra['album']）
  final String url;
  final Map<String, String>? extra;

  const SongInfoPage({
    super.key,
    required this.title,
    this.artist,
    this.sourceCover,
    this.album,
    this.url = '',
    this.extra,
  });

  @override
  ConsumerState<SongInfoPage> createState() => _SongInfoPageState();
}

class _SongInfoPageState extends ConsumerState<SongInfoPage> {
  bool _writeTags = true;
  bool _matching = false;
  SongMatch _match = SongMatch.empty;
  Future<Uint8List?>? _coverFuture;

  /// 歌词：null=加载中；空列表=无
  List<LyricLine>? _lines;
  bool _embedded = false; // 本地文件标签内嵌歌词

  @override
  void initState() {
    super.initState();
    unawaited(_loadPrefs());
    _reloadCover();
    unawaited(_loadLyric());
  }

  Future<void> _loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    if (mounted) setState(() => _writeTags = sp.getBool(kWriteTagsKey) ?? true);
  }

  void _reloadCover() {
    _coverFuture = ref.read(metadataProvider).coverBytes(
          sourceCover: widget.sourceCover,
          title: widget.title,
          artist: widget.artist,
          album: _match.album ?? widget.album,
        );
  }

  Future<void> _loadLyric() async {
    // 本地 mp3：优先读标签内嵌歌词
    final uri = Uri.tryParse(widget.url);
    if (uri != null && uri.isScheme('file')) {
      try {
        final tags = readMp3Tags(uri.toFilePath());
        final lrc = tags?.lyrics;
        if (lrc != null && lrc.isNotEmpty) {
          final lines = ref.read(lyricProvider).parseLrc(lrc);
          if (mounted) {
            setState(() {
              _embedded = true;
              _lines = lines;
            });
          }
          return;
        }
      } catch (_) {}
    }
    try {
      final lines = await ref
          .read(lyricProvider)
          .fetch(title: widget.title, artist: widget.artist ?? '');
      if (mounted) setState(() => _lines = lines);
    } catch (_) {
      if (mounted) setState(() => _lines = const []);
    }
  }

  Future<void> _autoMatch() async {
    if (_matching) return;
    setState(() => _matching = true);
    final meta = ref.read(metadataProvider);
    final m = await meta.match(
        title: widget.title, artist: widget.artist, album: widget.album);
    if (!mounted) return;
    setState(() {
      _matching = false;
      _match = m;
    });
    _reloadCover();
    if (mounted) setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m.coverUrl != null || m.album != null
            ? '已完成在线匹配（${m.source}）'
            : '未能匹配到在线元数据')));
  }

  Future<void> _setWriteTags(bool v) async {
    setState(() => _writeTags = v);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(kWriteTagsKey, v);
  }

  @override
  Widget build(BuildContext context) {
    final qualities = parseQualities(widget.extra);
    final scheme = Theme.of(context).colorScheme;
    final album = _nonEmpty(_match.album) ?? _nonEmpty(widget.album);
    final year = _match.year;
    final lyricState = _lines == null
        ? '查询中…'
        : _lines!.isEmpty
            ? '无'
            : (_embedded ? '内嵌歌词' : 'lrclib 匹配');

    return Scaffold(
      appBar: AppBar(
        title: const Text('歌曲信息'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 顶部封面 + 歌名/歌手
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: FutureBuilder<Uint8List?>(
                    future: _coverFuture,
                    builder: (context, snap) {
                      final b = snap.data;
                      if (snap.connectionState != ConnectionState.done ||
                          b == null ||
                          b.isEmpty) {
                        return Container(
                          color: scheme.surfaceContainerHighest,
                          child: Icon(Icons.music_note,
                              color: scheme.onSurfaceVariant),
                        );
                      }
                      return Image.memory(b,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              color: scheme.surfaceContainerHighest,
                              child: Icon(Icons.music_note,
                                  color: scheme.onSurfaceVariant)));
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(_nonEmpty(_match.artist) ?? widget.artist ?? '未知艺术家',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton.filledTonal(
                icon: _matching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 18),
                tooltip: '自动匹配元数据',
                onPressed: _matching ? null : _autoMatch,
              ),
            ],
          ),
          if (_match.source.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                visualDensity: VisualDensity.compact,
                label: Text('来自在线匹配（${_match.source}）',
                    style: const TextStyle(fontSize: 11)),
              ),
            ),
          ],
          const Divider(height: 32),
          _FieldRow(label: '标题', value: widget.title),
          _FieldRow(
              label: '艺术家',
              value: _nonEmpty(_match.artist) ?? widget.artist ?? '—'),
          _FieldRow(label: '专辑', value: album ?? '—'),
          _FieldRow(label: '年份', value: year ?? '—'),
          _FieldRow(
              label: '音质',
              value: qualities.isEmpty
                  ? '默认'
                  : qualities.map((q) => q.name).join(' / ')),
          _FieldRow(label: '歌词状态', value: lyricState),
          const Divider(height: 32),
          const Text('歌词', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_lines == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (_lines!.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('暂无匹配歌词',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            )
          else
            for (final l in _lines!.take(4))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(l.text.isEmpty ? '♪' : l.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              ),
          const SizedBox(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _writeTags,
            onChanged: _setWriteTags,
            title: const Text('下载时写入音频标签'),
            subtitle: const Text('为下载完成的 MP3 写入标题/艺术家/专辑/年份/封面/歌词；FLAC 标签写入待支持',
                style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  static String? _nonEmpty(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();
}

/// 字段行：左标签右值
class _FieldRow extends StatelessWidget {
  final String label;
  final String value;
  const _FieldRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 76,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
