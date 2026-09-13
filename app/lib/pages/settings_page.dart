import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/player_providers.dart';
import '../providers/downloads.dart';
import '../providers/ua_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _ua = TextEditingController();
  String _saveLoc = 'app';
  bool _downloadConfirm = true;
  UaMode _uaMode = UaPresets.defaultMode;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      _ua.text = p.getString('ua') ?? '';
      _saveLoc = p.getString('saveLocation') ?? 'app';
      _downloadConfirm = p.getBool('downloadConfirm') ?? true;
      // 老数据兼容：只填过 ua、没存过 uaMode 时按「自定义」回显
      final mk = p.getString('uaMode');
      _uaMode = (mk == null || mk.isEmpty)
          ? (_ua.text.trim().isEmpty ? UaPresets.defaultMode : UaMode.custom)
          : UaModeX.fromKey(mk);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ua.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // 浏览器标识（UA）：**兜底项**。
          // 绝大多数书源自带 header（含站点专用 UA/Cookie），会优先生效；
          // 这里只影响"源没带 header"的请求。默认桌面浏览器即可覆盖大多数
          // 场景，小白无需理解 UA 是什么 —— 故收进高级折叠项，不占首屏。
          _UaSection(controller: _ua, mode: _uaMode),
          const Divider(height: 1),
          ListTile(
            title: const Text('下载保存位置'),
            subtitle: const Text('应用目录 / 系统下载 / 每次询问',
                style: TextStyle(fontSize: 12)),
            trailing: DropdownButton<SaveLocation>(
              value: switch (_saveLoc) {
                'media' => SaveLocation.media,
                'custom' => SaveLocation.custom,
                _ => SaveLocation.app,
              },
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(
                    value: SaveLocation.app, child: Text('应用目录')),
                DropdownMenuItem(
                    value: SaveLocation.media, child: Text('系统下载')),
                DropdownMenuItem(
                    value: SaveLocation.custom, child: Text('每次询问')),
              ],
              onChanged: (SaveLocation? v) async {
                if (v == null) return;
                setState(() => _saveLoc = switch (v) {
                      SaveLocation.media => 'media',
                      SaveLocation.custom => 'custom',
                      SaveLocation.app => 'app',
                    });
                await ProviderScope.containerOf(context)
                    .read(downloadsProvider)
                    .setSaveLocation(v);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '「应用目录」在 Android 11+ 对用户不可见（文件管理器/系统下载都看不到）；'
              '选「系统下载」后文件落到手机 Download/Xso 且可被扫描；'
              '选「每次询问」则每次弹系统保存框，由你指定目录与文件名。',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: _downloadConfirm,
            title: const Text('下载前先确认音质'),
            subtitle: const Text(
                '开启后每次下载都会先弹出确认面板（可选音质档位）；'
                '关闭则直接加入下载队列。',
                style: TextStyle(fontSize: 12)),
            onChanged: (v) async {
              setState(() => _downloadConfirm = v);
              final p = await SharedPreferences.getInstance();
              await p.setBool('downloadConfirm', v);
            },
          ),
          const Divider(height: 1),
          // 开关状态以播放器为准：它内部负责持久化，
          // 设置页另存一份会出现"改了但当前这次运行不生效"
          Consumer(
            builder: (context, ref, _) {
              final player = ref.watch(playerProvider);
              return ValueListenableBuilder<bool>(
                valueListenable: player.autoFailover,
                builder: (context, on, _) => SwitchListTile(
                  value: on,
                  title: const Text('来源放不出来时自动换源'),
                  subtitle: const Text(
                      '开启后遇到失效直链会搜索同名曲目并切到其他来源续播；\n'
                      '关闭时仍可在播放页点「换个来源」手动切。',
                      style: TextStyle(fontSize: 12)),
                  onChanged: (v) => player.setAutoFailover(v),
                ),
              );
            },
          ),
          const ListTile(
            title: Text('关于'),
            subtitle: Text('汇搜 v0.1\n已内置音乐/网盘/磁力等源，可在源管理中停用或删除'),
            isThreeLine: true,
          ),
        ],
      ),
    );
  }
}

/// 浏览器标识（UA）设置 —— 高级项，默认折叠。
///
/// 定位是**兜底**：多数书源自带 header（站点专用 UA/Cookie），请求时会优先
/// 使用源自带值；本项只影响"源没带 header"的请求。默认桌面浏览器已能覆盖
/// 绝大多数场景，普通用户无需展开。
class _UaSection extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final UaMode mode;
  const _UaSection({required this.controller, required this.mode});

  @override
  ConsumerState<_UaSection> createState() => _UaSectionState();
}

class _UaSectionState extends ConsumerState<_UaSection> {
  late UaMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
  }

  Future<void> _save({bool notify = true}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('uaMode', _mode.key);
    await p.setString('ua', widget.controller.text);
    // 立即生效：不必重启 App（旧实现只写不读，且提示"重启生效"）
    ref.invalidate(userAgentProvider);
    ref.invalidate(uaModeProvider);
    if (mounted && notify) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存，立即生效')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: const Text('浏览器标识（高级）'),
      subtitle: const Text(
        '源未自带时使用；默认桌面浏览器，通常无需修改',
        style: TextStyle(fontSize: 12),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButton<UaMode>(
                value: _mode,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: UaMode.values
                    .map((m) =>
                        DropdownMenuItem<UaMode>(value: m, child: Text(m.label)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _mode = v);
                  _save();
                },
              ),
              if (_mode == UaMode.custom) ...[
                TextField(
                  controller: widget.controller,
                  decoration: const InputDecoration(
                    labelText: '自定义 User-Agent',
                    hintText: '留空则回退为桌面浏览器',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                    onPressed: () => _save(), child: const Text('保存')),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
