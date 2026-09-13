import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data/data.dart';
import 'package:source_engine/source_engine.dart';

import 'engine_providers.dart';

/// 按源 id 从仓库读出原始内容并解析为引擎可用的 [Source]。
///
/// 详情页 / 阅读器 / 收藏页都需要"从一条搜索结果反查到它的源"，
/// 逻辑集中在这里，避免各处重复实现（也避免格式判断写错）。
///
/// 返回 null 表示源不存在、已删除或解析失败 —— 调用方应降级处理
/// （例如只展示搜索结果里已有的字段），而不是抛错中断页面。
final sourceByIdProvider =
    FutureProvider.family<Source?, String>((ref, sourceId) async {
  try {
    final path = await ref.watch(sourceRepositoryPathProvider.future);
    final repo = SourceRepository(path);
    final all = await repo.list();
    final hit = all.where((s) => s.id == sourceId).firstOrNull;
    if (hit == null) return null;
    final raw = await repo.readRaw(sourceId);
    switch (hit.format) {
      case 'own':
        return parseSource(raw);
      case 'legado':
        return LegadoAdapter().translate(raw);
      default:
        // MusicFree / LX 是 JS 源，走装配路径（详情页暂不涉及）
        return null;
    }
  } catch (_) {
    return null;
  }
});
