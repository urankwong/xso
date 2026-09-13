import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/account_service.dart';
import '../providers/data_providers.dart';
import '../providers/plugin_store.dart';
import 'account_login_page.dart';
import 'favorites_page.dart';
import 'mv_page.dart';
import 'sheet_tracks_page.dart';

/// 平台账号在 PluginStore 中的命名空间与源匹配词
const _platformSources = {
  'netease': ['网易', 'netease'],
  'qqmusic': ['qq', '腾讯'],
  'bilibili': ['哔哩', 'bilibili'],
};

/// 收藏与喜欢 Hub：本应用收藏 + 各平台账号收藏/歌单统一入口
class FavoritesHubPage extends ConsumerStatefulWidget {
  const FavoritesHubPage({super.key});

  @override
  ConsumerState<FavoritesHubPage> createState() => _FavoritesHubPageState();
}

/// 平台歌单 / 收藏夹条目
typedef _SheetItem = ({String title, String subtitle, VoidCallback onTap});
typedef _SheetLoader = Future<List<_SheetItem>> Function(String cookie);

class _FavoritesHubPageState extends ConsumerState<FavoritesHubPage> {
  PluginStore? _store;

  /// 缓存各平台的加载 Future。
  /// 原先在 build 里直接调用 loader(cookie)，任何一次父级重建都会重新打一次
  /// 平台接口；缓存后只在 cookie 变化或用户点重试时才重新请求。
  final Map<String, Future<List<_SheetItem>>> _loadFutures = {};

  Future<List<_SheetItem>> _loadFor(
      String platformId, String cookie, _SheetLoader loader) {
    final key = '$platformId-${cookie.hashCode}';
    return _loadFutures.putIfAbsent(key, () => loader(cookie));
  }

  void _reload(String platformId, String cookie) {
    setState(() => _loadFutures.remove('$platformId-${cookie.hashCode}'));
  }

  /// 退出登录：清除本机 Cookie（setUserVar 传空串即删除该项）
  Future<void> _logout(String platformId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('将清除本机保存的登录信息。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('退出')),
        ],
      ),
    );
    if (ok != true) return;
    final PluginStore loaded;
    final current = _store;
    if (current != null) {
      loaded = current;
    } else {
      loaded = await ref.read(pluginStoreProvider.future);
    }
    // setUserVar 传空串即删除该项
    await loaded.setUserVar('account.$platformId', 'cookie', '');
    if (mounted) {
      setState(() {
        _store = loaded;
        _loadFutures.removeWhere((k, _) => k.startsWith('$platformId-'));
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已退出登录')));
    }
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final store = await ref.read(pluginStoreProvider.future);
    try {
      final sources = await ref.read(searchableSourcesProvider.future);
      for (final s in sources) {
        _cachedSourceIds[s.meta.name] = s.meta.id;
      }
    } catch (_) {}
    if (mounted) setState(() => _store = store);
  }

  String? _cookieOf(String platformId) {
    final store = _store;
    if (store == null) return null;
    final direct = store.userVars('account.$platformId')['cookie'];
    if (direct != null && direct.isNotEmpty) return direct;
    return null;
  }

  Future<void> _login(String platformId) async {
    final platform = kLoginPlatforms.firstWhere((p) => p.id == platformId);
    final cookie = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => AccountLoginPage(platform: platform)),
    );
    if (cookie == null || cookie.isEmpty) return;
    final PluginStore resolved;
    final current = _store;
    if (current != null) {
      resolved = current;
    } else {
      resolved = await ref.read(pluginStoreProvider.future);
    }
    await resolved.setUserVar('account.$platformId', 'cookie', cookie);
    if (mounted) {
      setState(() {
        _store = resolved;
        // cookie 变了，旧的加载结果作废
        _loadFutures.removeWhere((k, _) => k.startsWith('$platformId-'));
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${platform.label} 登录信息已保存')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('收藏与喜欢')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _tile(
            icon: Icons.star,
            title: '本应用收藏',
            subtitle: '搜索时收藏的资源（音乐/小说/书籍/漫画/网盘/磁力）',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const FavoritesPage())),
          ),
          Divider(height: 24, color: scheme.outlineVariant),
          Text('平台账号',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: scheme.primary)),
          const SizedBox(height: 6),
          _accountSection(
            platformId: 'netease',
            label: '网易云音乐',
            icon: Icons.cloud_outlined,
            loader: (cookie) async {
              final list =
                  await ref.read(accountServiceProvider).neteasePlaylists(cookie);
              return list
                  .map((c) => (
                        title: c.title,
                        subtitle: '${c.count ?? '?'} 首${c.isLiked ? ' · 红心' : ''}',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SheetTracksPage(
                              sourceId: _sourceIdFor('netease') ?? '',
                              sourceName: '网易云音乐',
                              sheetId: c.id,
                              title: c.title,
                            ),
                          ),
                        ),
                      ))
                  .toList();
            },
          ),
          _accountSection(
            platformId: 'qqmusic',
            label: 'QQ音乐',
            icon: Icons.queue_music_outlined,
            loader: (cookie) async {
              final list =
                  await ref.read(accountServiceProvider).qqPlaylists(cookie);
              return list
                  .map((c) => (
                        title: c.title,
                        subtitle: '${c.count ?? '?'} 首${c.isLiked ? ' · 我喜欢' : ''}',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SheetTracksPage(
                              sourceId: _sourceIdFor('qqmusic') ?? '',
                              sourceName: 'QQ音乐',
                              sheetId: c.id,
                              title: c.title,
                            ),
                          ),
                        ),
                      ))
                  .toList();
            },
          ),
          _accountSection(
            platformId: 'bilibili',
            label: '哔哩哔哩',
            icon: Icons.smart_display_outlined,
            loader: (cookie) async {
              final svc = ref.read(accountServiceProvider);
              final nav = await svc.bilibiliNav(cookie);
              final mid = (nav['mid'] as num).toInt();
              final folders = await svc.bilibiliFolders(cookie, mid);
              return [
                for (final f in folders)
                  (
                    title: f.title,
                    subtitle: '${f.count ?? '?'} 个视频',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BilibiliFolderPage(
                            mediaId: f.id, title: f.title, cookie: cookie),
                      ),
                    ),
                  ),
              ];
            },
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '酷狗 / 酷我的收藏接口需平台签名，暂不支持账号收藏；'
              '可在「音乐歌单」里粘贴公开歌单链接解析整单。',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  /// 找到该平台已启用的音乐源 id（用于走插件通道拉曲目）
  String? _sourceIdFor(String platformId) {
    final keys = _platformSources[platformId] ?? const [];
    for (final s in _cachedSourceIds.entries) {
      if (keys.any((k) => s.key.toLowerCase().contains(k))) return s.value;
    }
    return null;
  }

  final Map<String, String> _cachedSourceIds = {};

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: scheme.primary),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
      onTap: onTap,
    );
  }

  Widget _accountSection({
    required String platformId,
    required String label,
    required IconData icon,
    required _SheetLoader loader,
  }) {
    final cookie = _cookieOf(platformId);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          leading: Icon(icon, size: 20, color: scheme.primary),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: cookie == null
              ? FilledButton.tonal(
                  onPressed: () => _login(platformId),
                  child: const Text('登录'),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 原先登录后只能「重新登录」，无法解除绑定
                    TextButton(
                      onPressed: () => _logout(platformId),
                      child: const Text('退出'),
                    ),
                    TextButton(
                      onPressed: () => _login(platformId),
                      child: const Text('重新登录'),
                    ),
                  ],
                ),
        ),
        if (cookie == null)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text('未登录',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          )
        else
          FutureBuilder<List<_SheetItem>>(
            key: ValueKey('$platformId-${cookie.hashCode}'),
            future: _loadFor(platformId, cookie, loader),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                );
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('读取失败：${snap.error}',
                            style:
                                TextStyle(fontSize: 12, color: scheme.error)),
                      ),
                      // 失败后原本只能绕道「重新登录」再试一次
                      TextButton(
                        onPressed: () => _reload(platformId, cookie),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                );
              }
              final items = snap.data ?? const [];
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 8),
                  child: Text('暂无内容',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                );
              }
              return Column(
                children: [
                  for (final it in items)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 32),
                      title: Text(it.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(it.subtitle,
                          style: const TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: it.onTap,
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// B站收藏夹内容页：视频条目点入 MV 播放
class BilibiliFolderPage extends ConsumerStatefulWidget {
  final String mediaId;
  final String title;
  final String cookie;
  const BilibiliFolderPage(
      {super.key,
      required this.mediaId,
      required this.title,
      required this.cookie});

  @override
  ConsumerState<BilibiliFolderPage> createState() => _BilibiliFolderPageState();
}

class _BilibiliFolderPageState extends ConsumerState<BilibiliFolderPage> {
  List<FavVideo> _videos = const [];
  bool _loading = true;
  String? _error;

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
      final list = await ref
          .read(accountServiceProvider)
          .bilibiliFolderContents(widget.cookie, widget.mediaId);
      if (!mounted) return;
      setState(() {
        _videos = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text('读取失败：$_error',
                      style: TextStyle(color: scheme.error)))
              : ListView.builder(
                  itemCount: _videos.length,
                  itemBuilder: (context, i) {
                    final v = _videos[i];
                    return ListTile(
                      leading: const Icon(Icons.play_circle_outline),
                      title: Text(v.title,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(v.uploader ?? ''),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                MvPage(bvid: v.bvid, title: v.title)),
                      ),
                    );
                  },
                ),
    );
  }
}
