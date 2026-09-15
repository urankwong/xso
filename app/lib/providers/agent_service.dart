import 'dart:async';

import 'package:core/core.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pages/book_detail_page.dart';
import 'data_providers.dart';
import 'engine_providers.dart';
import 'player_providers.dart';


/// 全局导航 key：动作层（AI 对话 / 外部 Agent）跨页跳转用。
/// MaterialApp 关联此 key 后，任何持有 [appNavigatorKey] 的代码都能
/// 通过 `appNavigatorKey.currentState?.push(...)` 导航，不依赖 BuildContext。
final appNavigatorKey = GlobalKey<NavigatorState>();

/// AI 动作服务：把 App 的业务动作封装为可被对话工具 / 外部 Agent 调用的方法。
///
/// 设计原则：
/// - 原子化：每个方法做一件事，返回领域对象或 bool，不处理候选确认（留给对话层）
/// - 无副作用导航：openBook 通过全局 navigatorKey，不依赖 UI 上下文
/// - 复用现成链路：playTrack 走 SourceAssembler.resolveMedia + PlayerController.play，
///   与播放页 / LAN handler 完全一致
class AgentService {
  final Ref _ref;
  AgentService(this._ref);

  AppDb get _db => _ref.read(appDbProvider);

  // ---------- 查询 ----------

  /// 最近使用记录（kind: 'read' | 'play'），按时间倒序。
  Future<List<RecentItem>> getRecent({String? kind, int limit = 5}) =>
      _db.recentDao.recent(kind: kind, limit: limit);

  /// 收藏列表。type 为空时返回全部，否则按源类型过滤。
  Future<List<Favorite>> getFavorites({String? type, int limit = 10}) async {
    final all = await _db.favoriteDao.all();
    final list =
        type == null ? all : all.where((f) => f.type == type).toList();
    return list.take(limit).toList();
  }

  /// 聚合搜索：供 AI「搜歌 / 搜书」用。返回跨源合并结果。
  Future<List<SearchResult>> search(
    String keyword, {
    String? type,
    int page = 1,
  }) async {
    final all = await _ref.read(searchableSourcesProvider.future);
    final sources =
        type == null ? all : all.where((s) => s.meta.type.name == type).toList();
    final out = <SearchResult>[];
    final completer = Completer<void>();
    late final StreamSubscription sub;
    sub = _ref
        .read(orchestratorProvider)
        .search(sources, SearchQuery(keyword: keyword, page: page))
        .listen((event) {
      if (event is SourceResultsEvent) out.addAll(event.results);
    }, onDone: () {
      sub.cancel();
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
    return out;
  }

  // ---------- 动作 ----------

  /// 打开书：导航到详情页。详情页自动加载章节/封面，阅读器续读零成本
  /// （reader_page._restore 会读回 `read_pos_{url}`）。
  ///
  /// [type] 为源类型名（novel/book/comic/...），仅用于初始 SearchResult 构造；
  /// 详情页内部会按 sourceId 反查真实 Source，以反查结果为准。
  Future<bool> openBook({
    required String sourceId,
    required String sourceName,
    required String title,
    required String url,
    String? extractCode,
    String type = 'novel',
  }) async {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return false;
    final result = SearchResult(
      sourceId: sourceId,
      sourceName: sourceName,
      type: _parseType(type),
      title: title,
      url: url,
      extractCode: extractCode,
    );
    nav.push(MaterialPageRoute(builder: (_) => BookDetailPage(result: result)));
    return true;
  }

  /// 播放曲目：解析直链后交给 PlayerController。
  /// 与播放页 / LAN handler 走完全相同的链路（resolveMedia → play）。
  Future<bool> playTrack({
    required String sourceId,
    required String sourceName,
    required String title,
    required String url,
    String? artist,
    String? cover,
    Map<String, String>? extra,
    String quality = 'standard',
  }) async {
    try {
      final assembler = await _ref.read(sourceAssemblerProvider.future);
      final result = SearchResult(
        sourceId: sourceId,
        sourceName: sourceName,
        type: SourceType.music,
        title: title,
        url: url,
        extra: extra,
      );
      final directUrl = await assembler.resolveMedia(sourceId, result,
          quality: quality);
      await _ref.read(playerProvider).play(
            url: directUrl,
            title: title,
            artist: artist,
            cover: cover,
            extra: extra,
            sourceName: sourceName,
          );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------- 辅助 ----------

  SourceType _parseType(String s) {
    switch (s) {
      case 'music':
        return SourceType.music;
      case 'audiobook':
        return SourceType.audiobook;
      case 'book':
        return SourceType.book;
      case 'comic':
        return SourceType.comic;
      case 'video':
        return SourceType.video;
      case 'pan':
        return SourceType.pan;
      case 'magnet':
        return SourceType.magnet;
      case 'ed2k':
        return SourceType.ed2k;
      case 'game':
        return SourceType.game;
      default:
        return SourceType.novel;
    }
  }
}

final agentServiceProvider = Provider<AgentService>((ref) => AgentService(ref));