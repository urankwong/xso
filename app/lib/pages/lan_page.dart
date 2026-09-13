import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../net/lan_server.dart';

/// 局域网助手设置页（对照设计稿⑩）
class LanPage extends ConsumerWidget {
  const LanPage({super.key});

  void _copy(BuildContext context, String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$what已复制到剪贴板')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final server = ref.watch(lanServerProvider);
    final running = server.running;
    final notifier = ref.read(lanServerProvider.notifier);

    final qrData = server.ip == null
        ? ''
        : (server.requireToken && server.token.isNotEmpty
            ? '${server.url}/?token=${server.token}'
            : server.url);

    Widget sectionTitle(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 4),
          child: Text(t,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.primary, fontWeight: FontWeight.w600)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('局域网助手')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ---- 总开关 ----
          Card(
            child: SwitchListTile(
              secondary: Icon(Icons.lan, color: scheme.primary),
              title: const Text('局域网服务'),
              subtitle: const Text('同 WiFi 下用电脑浏览器批量导入/管理源、看日志、调用 API'),
              value: running,
              onChanged: (v) => v ? notifier.start() : notifier.stop(),
            ),
          ),
          if (running && server.ip != null) ...[
            sectionTitle('访问地址'),
            _AddressCard(
              server: server,
              onCopyUrl: () => _copy(context, server.url, '地址 '),
              onCopyToken: () => _copy(context, server.token, '令牌 '),
            ),
            if (qrData.isNotEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: QrImageView(
                      data: qrData,
                      size: 180,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
          ] else if (running && server.ip == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(server.lastError ?? '未检测到局域网 IP',
                  style: TextStyle(color: scheme.error)),
            ),
          // ---- 权限分组 ----
          sectionTitle('权限'),
          _perm(scheme,
              icon: Icons.file_download_outlined,
              title: '允许导入源',
              sub: 'PC 端可批量粘贴/URL 导入源',
              value: server.allowImport,
              enabled: running,
              onChanged: notifier.setAllowImport),
          _perm(scheme,
              icon: Icons.tune,
              title: '允许管理源',
              sub: 'PC 端可启用/停用/删除已有源',
              value: server.allowManage,
              enabled: running,
              onChanged: notifier.setAllowManage),
          _perm(scheme,
              icon: Icons.article_outlined,
              title: '允许读取日志',
              sub: 'PC 端可查看实时运行日志（SSE）',
              value: server.allowReadLog,
              enabled: running,
              onChanged: notifier.setAllowReadLog),
          _perm(scheme,
              icon: Icons.code,
              title: '开放 API 接口',
              sub: '搜索 / 下载投递等接口供脚本与 AI 调用',
              value: server.allowApi,
              enabled: running,
              onChanged: notifier.setAllowApi),
          // ---- 令牌 ----
          sectionTitle('访问令牌'),
          Card(
            child: SwitchListTile(
              secondary: Icon(Icons.vpn_key, color: scheme.primary),
              title: const Text('需要令牌访问'),
              subtitle: Text(running
                  ? '开启后 /api/* 需携带 4 位令牌'
                  : '开启服务后可设置'),
              value: server.requireToken,
              onChanged: running ? notifier.setRequireToken : null,
            ),
          ),
          // ---- 已连接设备 ----
          sectionTitle('已连接设备'),
          if (server.clients.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
              child: Text('暂无设备连接',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            )
          else
            ...server.clients.map((c) => Card(
                  child: ListTile(
                    leading: Icon(
                      c.blocked ? Icons.portable_wifi_off : Icons.devices_other,
                      color: c.blocked ? scheme.outline : scheme.primary,
                    ),
                    title: Text(c.ip),
                    subtitle: Text(
                      '${c.ua} · ${_fmt(c.lastSeen)}'
                      '${c.blocked ? ' · 已断开' : ''}',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                    trailing: c.blocked
                        ? null
                        : TextButton(
                            onPressed: () => notifier.disconnect(c.ip),
                            child: const Text('断开')),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _perm(
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    required String sub,
    required bool value,
    required bool enabled,
    required void Function(bool) onChanged,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: IgnorePointer(
        ignoring: !enabled,
        child: SwitchListTile(
          secondary: Icon(icon, color: scheme.primary),
          title: Text(title),
          subtitle: Text(sub,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }

  static String _fmt(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

/// 地址卡片：URL 复制 + 令牌展示/复制
class _AddressCard extends StatelessWidget {
  final LanServer server;
  final VoidCallback onCopyUrl;
  final VoidCallback onCopyToken;
  const _AddressCard(
      {required this.server,
      required this.onCopyUrl,
      required this.onCopyToken});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(
                    server.url,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                    onPressed: onCopyUrl,
                    tooltip: '复制地址',
                    icon: const Icon(Icons.copy, size: 18)),
              ],
            ),
            if (server.requireToken && server.token.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.vpn_key, size: 18, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text('令牌 ',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                  Text(server.token,
                      style: const TextStyle(
                          fontSize: 16,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                      onPressed: onCopyToken,
                      tooltip: '复制令牌',
                      icon: const Icon(Icons.copy, size: 18)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
