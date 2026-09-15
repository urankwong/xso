import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../net/lan_server.dart';
import '../theme.dart';
import '../widgets/update_dialog.dart';
import 'content_filter_page.dart';
import 'favorites_hub_page.dart';
import 'history_page.dart';
import 'lan_page.dart';
import 'now_playing_page.dart';
import 'playlist_page.dart';
import 'source_manage_page.dart';
import 'settings_page.dart';

/// 我的：应用信息卡 + 分组功能入口（内容 / 工具 / 设置）
class MinePage extends ConsumerWidget {
  const MinePage({super.key});

  void _push(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AboutDialog(
        applicationName: '汇搜',
        applicationVersion: 'v0.1',
        applicationIcon: const Icon(Icons.travel_explore),
        children: const [
          Text(
            'App 本体不内置任何搜索源，导入源脚本（JSON 规则 + JS 钩子）后使用，'
            '兼容 MusicFree 插件 / 洛雪音乐源 / Legado 简单书源导入。',
          ),
        ],
      ),
    );
  }

  Future<void> _pickThemeMode(BuildContext context, WidgetRef ref) async {
    final current = ref.read(themeModeProvider);
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('外观',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            RadioGroup<ThemeMode>(
              groupValue: current,
              onChanged: (mode) => Navigator.pop(sheetCtx, mode),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final mode in const [
                    ThemeMode.system,
                    ThemeMode.light,
                    ThemeMode.dark,
                  ])
                    RadioListTile<ThemeMode>(
                      value: mode,
                      title: Text(ThemeModeNotifier.label(mode)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null) {
      await ref.read(themeModeProvider.notifier).set(selected);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final lanRunning = ref.watch(lanServerProvider).running;
    final chevron = Icon(Icons.chevron_right, color: scheme.onSurfaceVariant);

    Widget sectionHeader(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 16, 4),
          child: Text(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.primary, fontWeight: FontWeight.w600)),
        );

    Widget tile({
      required IconData icon,
      required String title,
      String? subtitle,
      Widget? trailing,
      VoidCallback? onTap,
    }) {
      return ListTile(
        leading: Icon(icon, color: scheme.primary),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: trailing ?? chevron,
        onTap: onTap,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // 顶部应用信息卡片
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: scheme.primaryContainer,
                        ),
                        child: Icon(Icons.travel_explore,
                            size: 32, color: scheme.primary),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('汇搜',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            Text('v0.1 · 多源聚合搜索',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 内容分组
              sectionHeader('内容'),
              Card(
                child: Column(
                  children: [
                    tile(
                      icon: Icons.star_outline,
                      title: '收藏与喜欢',
                      subtitle: '本应用收藏 + 网易云/QQ/B站 账号收藏',
                      onTap: () =>
                          _push(context, const FavoritesHubPage()),
                    ),
                    const Divider(height: 1),
                    tile(
                      icon: Icons.history,
                      title: '搜索历史',
                      subtitle: '最近搜索过的关键词',
                      onTap: () => _push(context, const HistoryPage()),
                    ),
                    const Divider(height: 1),
                    tile(
                      icon: Icons.queue_music,
                      title: '音乐歌单',
                      subtitle: '粘贴公开歌单链接解析整单播放/下载',
                      onTap: () => _push(context, const PlaylistPage()),
                    ),
                    const Divider(height: 1),
                    tile(
                      icon: Icons.playlist_play,
                      title: '正在播放',
                      subtitle: '进入播放页查看队列与歌词',
                      onTap: () => _push(context, const NowPlayingPage()),
                    ),
                  ],
                ),
              ),
              // 工具分组
              sectionHeader('工具'),
              Card(
                child: Column(
                  children: [
                    tile(
                      icon: Icons.extension,
                      title: '源管理',
                      subtitle: '音乐/网盘/磁力/书籍 各类源统一管理',
                      onTap: () =>
                          _push(context, const SourceManagePage()),
                    ),
                    const Divider(height: 1),
                    tile(
                      icon: Icons.auto_fix_high_outlined,
                      title: '正文净化',
                      subtitle: '自定义正则替换 · 去广告 / 改词',
                      onTap: () => _push(context, const ContentFilterPage()),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading:
                          Icon(Icons.lan_outlined, color: scheme.primary),
                      title: const Text('局域网助手'),
                      subtitle: const Text('PC 导入/管理源 · 查看日志'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: lanRunning
                              ? scheme.primary.withValues(alpha: 0.15)
                              : scheme.outlineVariant
                                  .withValues(alpha: 0.3),
                        ),
                        child: Text(
                          lanRunning ? '已开启' : '已关闭',
                          style: TextStyle(
                            fontSize: 11,
                            color: lanRunning
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      onTap: () => _push(context, const LanPage()),
                    ),
                  ],
                ),
              ),
              // 设置分组
              sectionHeader('设置'),
              Card(
                child: Column(
                  children: [
                    tile(
                      icon: Icons.palette_outlined,
                      title: '外观',
                      subtitle: ThemeModeNotifier.label(themeMode),
                      onTap: () => _pickThemeMode(context, ref),
                    ),
                    const Divider(height: 1),
                    tile(
                      icon: Icons.devices,
                      title: '设置',
                      subtitle: '下载保存位置、浏览器标识等',
                      onTap: () => _push(context, const SettingsPage()),
                    ),
                    const Divider(height: 1),
                    const UpdateCheckTile(),
                    const Divider(height: 1),
                    tile(
                      icon: Icons.info_outline,
                      title: '关于',
                      subtitle: '汇搜 v0.1',
                      onTap: () => _showAbout(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
