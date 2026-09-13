import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:source_engine/source_engine.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/data_providers.dart';
import '../providers/engine_providers.dart';
import '../providers/source_loader.dart';
import 'reader_page.dart';

/// 书籍/小说详情页。
///
/// 两种来源、两种形态：
/// - **小说**（Legado 文本型源）：拉 `ruleBookInfo` + `ruleToc`，
///   展示封面/分类/简介/章节数，并提供**内置阅读器**入口；
/// - **电子书文件**（zlib / 安娜档案馆等）：展示能拿到的元信息
///   （封面、文件大小、格式、出版社…）与下载/打开入口。
///
/// 拿不到的信息显示「—」而不是留空，避免用户以为界面坏了。
class BookDetailPage extends ConsumerStatefulWidget {
  final SearchResult result;
  const BookDetailPage({super.key, required this.result});

  @override
  ConsumerState<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends ConsumerState<BookDetailPage> {
  Source? _source;
  BookInfo? _info;
  List<Chapter> _chapters = const [];
  bool _loading = true;
  String? _error;
  bool _fav = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = widget.result;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final src = await ref.read(sourceByIdProvider(r.sourceId).future);
      if (!mounted) return;
      _source = src;
      if (src != null) {
        // 详情页本身也是目录页（Legado 主流写法），一次请求拿回
        // 元信息与目录，避免连发两次同一页面
        try {
          final engine = ref.read(sourceEngineProvider);
          final info = await engine.fetchBookInfo(src, r.url);
          final toc = src.canRead
              ? await engine.fetchChapters(src, r.url)
              : const <Chapter>[];
          if (!mounted) return;
          setState(() {
            _info = info;
            _chapters = toc;
            _loading = false;
          });
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _error = '详情抓取失败：${e.toString().split('\n').first}';
            _loading = false;
          });
        }
      } else {
        setState(() => _loading = false);
      }
      _checkFav();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _checkFav() async {
    try {
      final dao = ref.read(appDbProvider).favoriteDao;
      final list = await dao.all();
      if (!mounted) return;
      setState(() => _fav = list.any((f) => f.url == widget.result.url));
    } catch (_) {}
  }

  Future<void> _toggleFav() async {
    final dao = ref.read(appDbProvider).favoriteDao;
    try {
      if (_fav) {
        final list = await dao.all();
        final hit = list.where((f) => f.url == widget.result.url).firstOrNull;
        if (hit != null) await dao.remove(hit.id);
        if (mounted) setState(() => _fav = false);
      } else {
        await dao.add(widget.result, code: widget.result.extractCode);
        if (mounted) setState(() => _fav = true);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_fav ? '已加入收藏' : '已取消收藏')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('收藏失败：$e')));
      }
    }
  }

  Future<void> _openUrl() async {
    final uri = Uri.tryParse(widget.result.url);
    if (uri == null) return;
    final ok = await canLaunchUrl(uri);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开该链接')));
      }
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _startReading({int index = -1}) {
    final src = _source;
    if (src == null || _chapters.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReaderPage(
        bookTitle: widget.result.title,
        source: src,
        chapters: _chapters,
        progressKey: widget.result.url,
        startIndex: index,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('详情')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _header(scheme),
                const SizedBox(height: 16),
                _actions(scheme),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(color: scheme.error, fontSize: 12)),
                ],
                const SizedBox(height: 20),
                _metaSection(scheme),
                const SizedBox(height: 20),
                _introSection(scheme),
                if (_chapters.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _tocSection(scheme),
                ],
                const SizedBox(height: 24),
                _linkRow(scheme),
              ],
            ),
    );
  }

  /// 封面 + 标题 + 作者/来源
  Widget _header(ColorScheme scheme) {
    final r = widget.result;
    // extra 可空：源不返回任何附加字段时就是 null
    final e = r.extra ?? const <String, String>{};
    final cover = _info?.cover ?? e['cover'] ?? e['coverUrl'];
    final author = e['author'] ?? e['artist'];
    final kind = _info?.kind ?? e['kind'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 92,
            height: 128,
            child: (cover != null && cover.isNotEmpty)
                ? Image.network(
                    cover,
                    fit: BoxFit.cover,
                    // 封面拉不到就用占位，不要显示破图
                    errorBuilder: (_, __, ___) => _coverPlaceholder(scheme),
                  )
                : _coverPlaceholder(scheme),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (author != null && author.isNotEmpty)
                Text(author,
                    style: TextStyle(
                        fontSize: 13, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text('来源：${r.sourceName}',
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, children: [
                _tag(scheme, _typeLabel(r.type), scheme.primary),
                if (kind != null && kind.isNotEmpty)
                  _tag(scheme, kind, scheme.tertiary),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _coverPlaceholder(ColorScheme scheme) => Container(
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.menu_book, color: scheme.onSurfaceVariant, size: 36),
      );

  Widget _tag(ColorScheme scheme, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: color)),
      );

  Widget _actions(ColorScheme scheme) {
    final canRead = _source?.canRead == true && _chapters.isNotEmpty;
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        if (canRead)
          FilledButton.icon(
            onPressed: () => _startReading(),
            icon: const Icon(Icons.menu_book, size: 18),
            label: const Text('开始阅读'),
          ),
        OutlinedButton.icon(
          onPressed: _toggleFav,
          icon: Icon(_fav ? Icons.star : Icons.star_border, size: 18),
          label: Text(_fav ? '已收藏' : '收藏'),
        ),
        OutlinedButton.icon(
          onPressed: _openUrl,
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('打开原网页'),
        ),
      ],
    );
  }

  /// 元信息：小说看字数/最新章节；电子书看大小/格式等（取自源返回的字段）
  Widget _metaSection(ColorScheme scheme) {
    final rows = <(String, String)>[];
    void add(String k, String? v) {
      if (v != null && v.trim().isNotEmpty) rows.add((k, v.trim()));
    }

    add('字数', _info?.wordCount);
    add('最新章节', _info?.lastChapter);
    // 电子书类信息：源在搜索结果里返回的字段（extra 可能为 null）
    final e = widget.result.extra ?? const <String, String>{};
    add('文件大小', e['size'] ?? e['filesize'] ?? e['fileSize']);
    add('格式', e['format'] ?? e['ext'] ?? e['extension']);
    add('出版社', e['publisher']);
    add('出版年', e['year'] ?? e['publishYear']);
    add('语言', e['language'] ?? e['lang']);
    add('ISBN', e['isbn']);
    if (_chapters.isNotEmpty) add('章节数', '${_chapters.length} 章');

    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('书籍信息',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              for (final (k, v) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(k,
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                      ),
                      Expanded(
                        child: Text(v,
                            style: const TextStyle(fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _introSection(ColorScheme scheme) {
    final intro = _info?.intro;
    if (intro == null || intro.trim().isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('简介',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Text(intro.trim(),
            style: const TextStyle(fontSize: 14, height: 1.6)),
      ],
    );
  }

  Widget _tocSection(ColorScheme scheme) {
    const preview = 12;
    final shown = _chapters.take(preview).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('目录',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant)),
            const Spacer(),
            Text('共 ${_chapters.length} 章',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < shown.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(shown[i].title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _startReading(index: i),
          ),
        if (_chapters.length > preview)
          TextButton(
            onPressed: () => _startReading(index: 0),
            child: Text('查看全部 ${_chapters.length} 章'),
          ),
      ],
    );
  }

  Widget _linkRow(ColorScheme scheme) => SelectableText(
        widget.result.url,
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      );

  String _typeLabel(SourceType t) => switch (t) {
        SourceType.novel => '小说',
        SourceType.book => '书籍',
        SourceType.comic => '漫画',
        SourceType.video => '影视',
        SourceType.audiobook => '有声',
        SourceType.music => '音乐',
        SourceType.pan => '网盘',
        SourceType.magnet => '磁力',
        SourceType.ed2k => '电驴',
        SourceType.game => '游戏',
      };
}
