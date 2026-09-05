import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_providers.dart';
import 'search_page.dart';
import 'source_manage_page.dart';
import 'favorites_page.dart';
import 'history_page.dart';
import 'settings_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _pages = const [
    SearchPage(),
    SourceManagePage(),
    FavoritesPage(),
    HistoryPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _MiniPlayerBar(),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
              NavigationDestination(icon: Icon(Icons.extension), label: '源'),
              NavigationDestination(icon: Icon(Icons.star), label: '收藏'),
              NavigationDestination(icon: Icon(Icons.history), label: '历史'),
              NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniPlayerBar extends ConsumerWidget {
  const _MiniPlayerBar();

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                IconButton(
                  onPressed: () => player.stop(),
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
}
