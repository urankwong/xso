import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data_providers.dart';
import 'player_provider.dart';

final playerProvider = Provider<PlayerController>((ref) {
  final controller = PlayerController();
  // 播放历史埋点：最近播放列表与 AI 对话「播放我最近听的歌」都靠它
  controller.onTrackPlayed = (item) async {
    try {
      await ref.read(appDbProvider).recentDao.record(
            sourceId: item.sourceId,
            sourceName: item.sourceName,
            kind: 'play',
            title: item.title,
            url: item.url,
          );
    } catch (_) {
      // 埋点失败不影响播放
    }
  };
  ref.onDispose(controller.dispose);
  return controller;
});