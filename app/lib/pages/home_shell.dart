import 'dart:async';
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart' show homeTabIndexProvider;
import '../providers/data_providers.dart';
import '../providers/engine_providers.dart';
import '../providers/play_failover.dart';
import '../providers/player_providers.dart';
import 'now_playing_page.dart';
import '../providers/lyric.dart';
import 'home_page.dart';
import 'search_page.dart';
import 'downloads_page.dart';
import 'mine_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  final _pages = const [
    HomePage(),
    SearchPage(),
    DownloadsPage(),
    MinePage(),
  ];

  DateTime? _lastBackPressed;

  /// 换源注入是否已设置。initState 完成前不得依赖 InheritedWidget（
  /// Flutter 报 dependOnInheritedWidgetOfExactType 崩溃），
  /// 所以放到 didChangeDependencies，首次执行一次即可。
  bool _failoverInjected = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_failoverInjected) return;
    _failoverInjected = true;

    // 换源实现注入给播放器：控制器本身不该依赖源装配与搜索编排，
    // 但"这个源放不出来就换个源"必须能在播放失败时自动发生
    final container = ProviderScope.containerOf(context);
    ref.read(playerProvider).failoverResolver = (failed) async {
      return findPlayableAlternative(
        sources: await container.read(searchableSourcesProvider.future),
        assembler: await container.read(sourceAssemblerProvider.future),
        orchestrator: container.read(orchestratorProvider),
        failed: failed,
      );
    };
  }

  /// 首页按返回键会直接退出 App。Android 惯例是「再按一次退出」，
  /// 避免误触丢掉正在播放 / 下载的状态。
  void _onPopInvoked(bool didPop) {
    if (didPop) return;
    unawaited(_handleBack());
  }

  Future<void> _handleBack() async {
    final now = DateTime.now();
    final shouldExit = _lastBackPressed != null &&
        now.difference(_lastBackPressed!) < const Duration(seconds: 2);
    _lastBackPressed = now;
    if (shouldExit) {
      await SystemNavigator.pop();
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('再按一次退出')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(homeTabIndexProvider);
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onPopInvoked(didPop),
      child: Scaffold(
        body: IndexedStack(index: index, children: _pages),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 迷你播放器的出现/消失会改变底部高度，用动画过渡，
            // 否则开始播放或点关闭时内容区会瞬间跳动一下
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: const _MiniPlayerBar(),
            ),
            NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) =>
                  ref.read(homeTabIndexProvider.notifier).state = i,
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.explore_outlined),
                    selectedIcon: Icon(Icons.explore),
                    label: '首页'),
                NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
                NavigationDestination(
                    icon: Icon(Icons.download_outlined),
                    selectedIcon: Icon(Icons.download),
                    label: '下载'),
                NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: '我的'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniPlayerBar extends ConsumerStatefulWidget {
  const _MiniPlayerBar();

  @override
  ConsumerState<_MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends ConsumerState<_MiniPlayerBar> {
  /// 按封面 URL 缓存**字节结果**。原先在 build() 里直接创建 Future，
  /// 播放进度每秒刷新都会重建，同一张封面被反复下载，缩略图会闪。
  ///
  /// 注意缓存的必须是 `Uint8List` 而不是 `List<int>`：
  /// `Image.memory` 用的是 `MemoryImage`，其相等性基于 bytes 实例，
  /// 若在 build 里写 `Uint8List.fromList(b)` 每次都新建实例，
  /// 会被判定成"换了新图"→ 重新解码并上传纹理 → 视觉上持续闪烁。
  final Map<String, Future<Uint8List>> _coverFutures = {};

  Future<Uint8List> _cover(String url) => _coverFutures.putIfAbsent(
      url,
      () async => Uint8List.fromList(
          await ref.read(lyricProvider).fetchImage(url)));

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider);
    return ValueListenableBuilder(
      valueListenable: player.state,
      builder: (context, st, __) {
        if (!st.active) return const SizedBox.shrink();
        final dur = st.duration ?? Duration.zero;
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (st.duration != null && st.duration!.inMilliseconds > 0)
              LinearProgressIndicator(
                value: (st.position.inMilliseconds / st.duration!.inMilliseconds)
                    .clamp(0.0, 1.0),
                minHeight: 2,
              ),
            if (st.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(st.error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12)),
                ),
              ),
            Row(
              children: [
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: (st.cover != null && st.cover!.isNotEmpty)
                      ? FutureBuilder<Uint8List>(
                          future: _cover(st.cover!),
                          builder: (context, snap) {
                            if (snap.connectionState != ConnectionState.done) {
                              return _barCoverPlaceholder(context);
                            }
                            final b = snap.data;
                            if (snap.hasError || b == null || b.isEmpty) {
                              return _barCoverPlaceholder(context);
                            }
                            return Image.memory(b,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                // 换封面时保留上一帧，避免出现空白闪烁
                                gaplessPlayback: true);
                          },
                        )
                      : _barCoverPlaceholder(context),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: st.loading ? null : () => player.toggle(),
                  icon: st.loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(st.playing ? Icons.pause : Icons.play_arrow),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          fullscreenDialog: true,
                          builder: (_) => const NowPlayingPage()),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          st.title ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          '${_fmt(st.position)} / ${_fmt(dur)}'
                          '${st.artist != null && st.artist!.isNotEmpty ? ' · ${st.artist}' : ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('停止播放？'),
                        content: Text(st.title?.isNotEmpty == true
                            ? '将停止「${st.title}」并清空播放队列'
                            : '将停止播放并清空播放队列'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('停止'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted) {
                      await player.stop();
                    }
                  },
                  icon: const Icon(Icons.close),
                  tooltip: '停止',
                ),
              ],
            ),
          ]),
        );
      },
    );
  }

  Widget _barCoverPlaceholder(BuildContext context) => Container(
        width: 44,
        height: 44,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.music_note,
            size: 22, color: Theme.of(context).colorScheme.outline),
      );
}
