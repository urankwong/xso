import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../net/lan_server.dart';
import '../theme.dart';
import 'favorites_hub_page.dart';
import 'history_page.dart';
import 'lan_page.dart';
import 'playlist_page.dart';
import 'source_manage_page.dart';
import 'settings_page.dart';

/// 我的：功能入口行列表 + 设置分组
class MinePage extends ConsumerWidget {
  const MinePage({super.key});

  void _push(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  /// 关于内容原本只存在于「设置」页底部，从「我的 → 关于」进来却只能
  /// 收到一条「即将上线」，属于死路。这里直接给出完整的关于信息。
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
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('外观'),
        children: [
          // RadioListTile 的 groupValue/onChanged 已废弃，
          // 改由 RadioGroup 祖先统一管理选中值
          RadioGroup<ThemeMode>(
            groupValue: current,
            onChanged: (mode) => Navigator.pop(dialogContext, mode),
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
        ],
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

    Widget row({
      required IconData icon,
      required String title,
      String? subtitle,
      Widget? trailing,
      VoidCallback? onTap,
    }) {
      return Card(
        child: ListTile(
          leading: Icon(icon, color: scheme.primary),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: trailing ?? chevron,
          onTap: onTap,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          row(
            icon: Icons.star_outline,
            title: '收藏与喜欢',
            subtitle: '本应用收藏 + 网易云/QQ/B站 账号收藏',
            onTap: () => _push(context, const FavoritesHubPage()),
          ),
          row(
            icon: Icons.history,
            title: '搜索历史',
            subtitle: '最近搜索过的关键词',
            onTap: () => _push(context, const HistoryPage()),
          ),
          row(
            icon: Icons.extension,
            title: '源管理',
            subtitle: '音乐/网盘/磁力/书籍 各类源统一管理',
            onTap: () => _push(context, const SourceManagePage()),
          ),
          row(
            icon: Icons.queue_music,
            title: '音乐歌单',
            subtitle: '粘贴公开歌单链接解析整单播放/下载',
            onTap: () => _push(context, const PlaylistPage()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 16, 4),
            child: Text('设置',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary, fontWeight: FontWeight.w600)),
          ),
          row(
            icon: Icons.palette_outlined,
            title: '外观',
            subtitle: ThemeModeNotifier.label(themeMode),
            onTap: () => _pickThemeMode(context, ref),
          ),
          row(
            icon: Icons.devices,
            // 入口名与落地页标题保持一致（落地页 AppBar 标题是「设置」）
            title: '设置',
            subtitle: '下载保存位置、浏览器标识等',
            onTap: () => _push(context, const SettingsPage()),
          ),
          row(
            icon: Icons.lan_outlined,
            title: '局域网助手',
            subtitle: 'PC 导入/管理源 · 查看日志',
            trailing: Text(
              lanRunning ? '已开启' : '已关闭',
              style: TextStyle(
                  fontSize: 12,
                  color: lanRunning ? scheme.primary : scheme.onSurfaceVariant),
            ),
            onTap: () => _push(context, const LanPage()),
          ),
          row(
            icon: Icons.info_outline,
            title: '关于',
            subtitle: '汇搜 v0.1',
            onTap: () => _showAbout(context),
          ),
        ],
      ),
    );
  }
}
