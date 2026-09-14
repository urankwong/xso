import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:data/data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/home_shell.dart';
import 'providers/builtin_sources.dart';
import 'providers/engine_providers.dart';
import 'providers/plugin_store.dart';
import 'widgets/update_dialog.dart';
import 'theme.dart';

/// 底部导航当前 tab：首页(0) / 搜索(1) / 下载(2) / 我的(3)
final homeTabIndexProvider = StateProvider<int>((ref) => 0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 后台播放/锁屏控制：必须在任何 AudioPlayer 使用前初始化。
  // 失败（如低版本 ROM 权限异常）不应让 App 起不来，退回前台播放即可。
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.xso.media.channel',
      androidNotificationChannelName: '汇搜播放',
      androidNotificationOngoing: true,
    );
  } catch (_) {}
  final container = ProviderContainer();
  // 插件存储（登录态/Cookie）必须先载入：JS 侧 env.storage 走同步通道读取
  await container.read(pluginStoreProvider.future);
  await _ensureBuiltinSources(container);
  runApp(
    UncontrolledProviderScope(container: container, child: const MyApp()),
  );
}

/// 同步内置源：清单变化时才重新导入，并清理"曾内置、现已移除"的源。
///
/// 原实现用一次性布尔标记，导致**升级安装后新增的内置源永远进不来**
/// （实测：内置 11 个 legado 源，首页只统计到 2 个书籍源）。
/// 现改为比对清单指纹；清理只针对曾内置过的 id，不动用户自行导入的源。
Future<void> _ensureBuiltinSources(ProviderContainer container) async {
  const kSig = 'builtin_sources_sig';
  const kIds = 'builtin_sources_ids';
  try {
    final prefs = await SharedPreferences.getInstance();
    final sig = BuiltinSources.manifestSignature();
    if (prefs.getString(kSig) == sig) return; // 清单没变，无需处理
    final repoPath = await container.read(sourceRepositoryPathProvider.future);
    final repo = SourceRepository(repoPath);
    final res = await BuiltinSources.importDetailed(repo);

    // 清理已从内置清单移除的源（只删上次记录过、本次清单里已无的 id）
    final last = prefs.getStringList(kIds) ?? const <String>[];
    final now = res.manifestIds.toSet();
    for (final id in last) {
      if (now.contains(id)) continue;
      try {
        await repo.delete(id);
      } catch (_) {}
    }

    await prefs.setString(kSig, sig);
    await prefs.setStringList(kIds, res.manifestIds);
    if (res.imported > 0) {
      debugPrint('[内置源] 新增 ${res.imported} 个');
    }
  } catch (_) {
    // 导入失败不阻塞启动，用户仍可手动导入
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: '汇搜',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      home: const UpdateGate(child: HomeShell()),
    );
  }
}
