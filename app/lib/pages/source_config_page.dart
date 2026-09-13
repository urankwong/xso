import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/data_providers.dart';
import '../providers/plugin_store.dart';
import 'account_login_page.dart';

/// 源配置页：渲染插件声明的 userVariables（B站 Cookie 等），
/// 可用应用内 WebView 登录自动抓取，也可手动粘贴。
class SourceConfigPage extends ConsumerStatefulWidget {
  final String sourceId;
  final String sourceName;
  const SourceConfigPage(
      {super.key, required this.sourceId, required this.sourceName});

  @override
  ConsumerState<SourceConfigPage> createState() => _SourceConfigPageState();
}

class _SourceConfigPageState extends ConsumerState<SourceConfigPage> {
  List<Map<String, dynamic>> _spec = const [];
  final Map<String, TextEditingController> _fields = {};
  bool _loading = true;
  String? _error;
  LoginPlatform? _platform;
  TextEditingController? _accountCtl;
  String? _accountCookie;

  /// 有未保存改动：返回时拦截确认，避免粘贴完 Cookie 直接退出导致静默丢失
  bool _dirty = false;

  void _markDirty() {
    if (_dirty || !mounted) return;
    setState(() => _dirty = true);
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃修改？'),
        content: const Text('当前有未保存的配置，离开后修改将丢失。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('继续编辑')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('放弃')),
        ],
      ),
    );
    return ok == true;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final assembler = await ref.read(sourceAssemblerProvider.future);
      final spec = await assembler.userVariableSpec(widget.sourceId);
      final store = await ref.read(pluginStoreProvider.future);
      final saved = store.userVars(widget.sourceId);
      for (final v in spec) {
        final key = v['key']?.toString() ?? '';
        if (key.isEmpty) continue;
        _fields[key] ??= TextEditingController(text: saved[key] ?? '');
      }
      if (!mounted) return;
      setState(() {
        _spec = spec;
        _loading = false;
      });
      if (spec.isEmpty) {
        final p = _guessPlatform();
        if (p != null) {
          final saved = store.userVars('account.${p.id}')['cookie'];
          if (mounted) {
            setState(() {
              _platform = p;
              _accountCookie = saved;
            });
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 按源名猜测平台，猜不到则弹选择
  Future<LoginPlatform?> _pickPlatform() async {
    final name = widget.sourceName.toLowerCase();
    final hit = kLoginPlatforms.where((p) {
      final keys = {
        'bilibili': ['b站', '哔哩', 'bilibili'],
        'netease': ['网易', 'netease'],
        'qqmusic': ['qq', '腾讯'],
        'kugou': ['酷狗'],
      }[p.id]!;
      return keys.any((k) => name.contains(k));
    }).toList();
    if (hit.length == 1) return hit.first;
    if (!mounted) return null;
    return showModalBottomSheet<LoginPlatform>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('选择登录平台', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final p in (hit.isEmpty ? kLoginPlatforms : hit))
              ListTile(
                leading: const Icon(Icons.login),
                title: Text(p.label),
                onTap: () => Navigator.pop(ctx, p),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _loginFill(String key) async {
    final platform = await _pickPlatform();
    if (platform == null) return;
    if (!mounted) return;
    final cookie = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => AccountLoginPage(platform: platform)),
    );
    if (cookie != null && cookie.isNotEmpty) {
      setState(() {
        (_fields[key] ??= TextEditingController()).text = cookie;
        _dirty = true; // 抓到 Cookie 后仍需点保存
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已获取 ${platform.label} Cookie，记得保存')));
      }
    }
  }

  Future<void> _save() async {
    final store = await ref.read(pluginStoreProvider.future);
    for (final e in _fields.entries) {
      await store.setUserVar(widget.sourceId, e.key, e.value.text.trim());
    }
    // 重新装配以注入新的用户变量
    ref.invalidate(sourceAssemblerProvider);
    ref.invalidate(searchableSourcesProvider);
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存，重新装配生效')));
  }

  /// 插件未声明用户变量时，仍允许按平台保存登录 Cookie（供账号收藏/MV 高清用）
  LoginPlatform? _guessPlatform() {
    final name = widget.sourceName.toLowerCase();
    for (final p in kLoginPlatforms) {
      final keys = {
        'bilibili': ['哔哩', 'bilibili'],
        'netease': ['网易', 'netease'],
        'qqmusic': ['qq', '腾讯'],
        'kugou': ['酷狗'],
      }[p.id]!;
      if (keys.any((k) => name.contains(k))) return p;
    }
    return null;
  }

  Widget _accountOnlyBody(ColorScheme scheme) {
    final platform = _platform ??= _guessPlatform();
    if (platform == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('该源无需用户配置',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      );
    }
    final ctl = _accountCtl ??= TextEditingController(text: _accountCookie ?? '');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${platform.label} 登录',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text('登录后 Cookie 仅存本机，用于读取你的收藏与解锁高清晰度',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        TextField(
          controller: ctl,
          // 注意：Flutter 断言要求 obscureText 必须配合 maxLines == 1
          obscureText: true,
          maxLines: 1,
          onChanged: (_) => _markDirty(),
          decoration: const InputDecoration(labelText: 'Cookie'),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              final cookie = await Navigator.push<String>(
                context,
                MaterialPageRoute(
                    builder: (_) => AccountLoginPage(platform: platform)),
              );
              if (cookie != null && cookie.isNotEmpty) {
                setState(() {
                  ctl.text = cookie;
                  _dirty = true;
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已获取 Cookie，记得保存')));
                }
              }
            },
            icon: const Icon(Icons.login, size: 18),
            label: const Text('应用内登录自动获取'),
          ),
        ),
        FilledButton(
          onPressed: () async {
            final store = await ref.read(pluginStoreProvider.future);
            await store
                .setUserVar('account.${platform.id}', 'cookie', ctl.text.trim());
            if (!mounted) return;
            setState(() => _dirty = false);
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('已保存')));
          },
          child: const Text('保存登录信息'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _accountCtl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope<Object?>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text('配置 · ${widget.sourceName}', overflow: TextOverflow.ellipsis),
        actions: [
          if (_dirty) const Center(child: Text('未保存')),
          if (!_loading && (_spec.isNotEmpty || _platform != null))
            TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('读取插件配置失败：$_error',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.error)),
                  ),
                )
              : _spec.isEmpty
                  ? _accountOnlyBody(scheme)
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final v in _spec)
                          Builder(builder: (_) {
                            final key = v['key'].toString();
                            final label = (v['name'] ?? key).toString();
                            final isPwd = (v['type'] ?? '') == 'password';
                            final desc = (v['description'] ?? '').toString();
                            // 「应用内登录」只对 Cookie 类变量有意义，
                            // 给 API Key 之类的字段也挂登录按钮会误导用户
                            final isCookieLike =
                                isPwd || key.toLowerCase().contains('cookie');
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  if (desc.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(desc,
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              color: scheme.onSurfaceVariant)),
                                    ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _fields[key],
                                    obscureText: isPwd,
                                    maxLines: isPwd ? 1 : 3,
                                    onChanged: (_) => _markDirty(),
                                    decoration: InputDecoration(
                                      hintText: isPwd ? '粘贴或点下方登录自动获取' : '值',
                                    ),
                                  ),
                                  if (isCookieLike)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: () => _loginFill(key),
                                        icon: const Icon(Icons.login, size: 18),
                                        label: const Text('应用内登录自动获取'),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
      ),
    );
  }
}
