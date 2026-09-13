import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data/data.dart';
import 'package:core/core.dart';
import 'package:source_engine/source_engine.dart';
import '../providers/data_providers.dart';
import '../providers/engine_providers.dart';

/// 源调试器：选源试搜，显示结果/错误，辅助写源排查
class SourceDebugPage extends ConsumerStatefulWidget {
  final StoredSource stored;
  const SourceDebugPage({super.key, required this.stored});
  @override
  ConsumerState<SourceDebugPage> createState() => _SourceDebugPageState();
}

class _SourceDebugPageState extends ConsumerState<SourceDebugPage> {
  final _kw = TextEditingController();
  List<SearchResult> _results = [];
  String? _error;
  bool _running = false;

  @override
  void dispose() {
    _kw.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _results = [];
    });
    try {
      final path = await ref.read(sourceRepositoryPathProvider.future);
      final raw = await SourceRepository(path).readRaw(widget.stored.id);
      final engine = ref.read(sourceEngineProvider);
      List<SearchResult> results;
      switch (widget.stored.format) {
        case 'own':
          results = await engine.search(
              parseSource(raw), SearchQuery(keyword: _kw.text));
        case 'legado':
          results = await engine.search(
              LegadoAdapter().translate(raw), SearchQuery(keyword: _kw.text));
        default:
          // MusicFree/LX 源走适配器装配路径
          final assembler = await ref.read(sourceAssemblerProvider.future);
          final sources = await assembler.loadEnabled();
          final match = sources.where((s) =>
              s.meta.id == widget.stored.id ||
              s.meta.id.startsWith('${widget.stored.format}://'));
          if (match.isEmpty) {
            throw Exception('该 JS 源装配失败或未启用');
          }
          results = await match.first.search(SearchQuery(keyword: _kw.text));
      }
      setState(() => _results = results);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('调试：${widget.stored.id}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _kw,
                  textInputAction: TextInputAction.search,
                  // 支持回车提交：输入完不用把手从键盘移到播放按钮上
                  onSubmitted: (_) => _running ? null : _run(),
                  decoration: const InputDecoration(hintText: '测试关键词'),
                ),
              ),
              IconButton(
                  onPressed: _running ? null : _run,
                  icon: const Icon(Icons.play_arrow)),
            ]),
          ),
          if (_running) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: ListView(
              children: _results
                  .map((r) => ListTile(
                        title: Text(r.title),
                        subtitle: Text(r.url),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
