import 'dart:async';

import 'package:core/core.dart';

import 'player_provider.dart';
import 'source_assembly.dart';

/// 只削掉"带版本含义"的括号段（现场版 / Taylor's Version / 伴奏…）。
/// 不能对所有括号连内容一起删：《平凡之路》会被削成空串，反而永远匹配不上。
final _versionTag = RegExp(
    r'\s*[(（\[【《〈<][^()（）\[\]【】《》〉>]{0,20}?'
    r'(现场|live|version|remaster|acoustic|伴奏|纯音乐|翻唱|demo|电台版|版)'
    r'[^()（）\[\]【】《》〉>]{0,20}[)）\]】》〉>]\s*');

/// 标题归一化：只保留汉字与小写字母数字，其余符号（空白、连字符、
/// 各类中英文引号与括号）一律不参与比较。
String normalizeTitle(String s) {
  final kept = StringBuffer();
  for (final r in s.toLowerCase().replaceAll(_versionTag, ' ').runes) {
    final isDigitOrLatin = (r >= 0x30 && r <= 0x39) || (r >= 0x61 && r <= 0x7a);
    final isCjk = r >= 0x4e00 && r <= 0x9fff;
    if (isDigitOrLatin || isCjk) kept.writeCharCode(r);
  }
  return kept.toString();
}

/// 从一次跨源搜索结果里挑出"同一首歌"的其他来源候选，并排序。
///
/// 排序很关键：换个来源不是换首歌听。跨源搜索会带回大量同名近似、
/// 现场版、翻唱与纯音乐，必须让最像原曲的排在前面。
List<SearchResult> rankSameSongCandidates({
  required List<SearchResult> found,
  required String title,
  String artist = '',
  String? excludeSourceId,
  int limit = 8,
}) {
  final want = normalizeTitle(title);
  if (want.isEmpty) return const [];
  final wantArtist = normalizeTitle(artist);

  final scored = <({SearchResult item, int score})>[];
  for (final r in found) {
    if (r.type != SourceType.music) continue;
    if (excludeSourceId != null && r.sourceId == excludeSourceId) continue;
    final got = normalizeTitle(r.title);
    if (got.isEmpty) continue;

    int score;
    if (got == want) {
      score = 100;
    } else if (got.contains(want) || want.contains(got)) {
      score = 60;
    } else {
      continue; // 连包含关系都没有，视为另一首歌
    }
    // 歌手一致加分；明确不一致扣分（翻唱/现场版常见）
    final who = normalizeTitle(r.extra?['artist'] ?? '');
    if (wantArtist.isNotEmpty && who.isNotEmpty) {
      score += who == wantArtist ? 20 : -15;
    }
    // 已经有直链的源优先（省一次解析，也说明该源给了实际可播地址）
    if (r.url.startsWith('http')) score += 10;
    scored.add((item: r, score: score));
  }
  scored.sort((a, b) => b.score.compareTo(a.score));
  return [for (final s in scored.take(limit)) s.item];
}

/// 边搜边收：命中足够多候选或超时/搜完就停，避免为换源把全部源都等一遍
Future<List<SearchResult>> _collectUntil({
  required Stream<SearchEvent> events,
  required bool Function(SearchResult) matches,
  int stopAfter = 4,
  Duration maxWait = const Duration(seconds: 10),
}) async {
  final out = <SearchResult>[];
  final done = Completer<void>();
  void finish() {
    if (!done.isCompleted) done.complete();
  }

  final timer = Timer(maxWait, finish);
  late final StreamSubscription<SearchEvent> sub;
  sub = events.listen((ev) {
    if (ev is SourceResultsEvent) {
      out.addAll(ev.results.where(matches));
      if (out.length >= stopAfter) finish();
    }
  }, onDone: finish, onError: (_) => finish());

  await done.future;
  timer.cancel();
  await sub.cancel();
  return out;
}

/// 为一个放不出来的条目找其他来源，并验证真能解析出可播地址。
///
/// 只做"看起来同名"是不够的：替代源同样可能解析失败或返回占位地址，
/// 所以候选要逐个解析，拿到第一个 http 地址才返回，否则宁可不换。
Future<QueueItem?> findPlayableAlternative({
  required List<SearchableSource> sources,
  required SourceAssembler assembler,
  required SearchOrchestrator orchestrator,
  required QueueItem failed,
  int maxSources = 10,
}) async {
  // 只挑有限个其他音乐源：全量源会把几十套 QuickJS 插件全装起来，
  // 换一次源等到天荒地老
  final pool = [
    for (final s in sources)
      if (s.meta.type == SourceType.music && s.meta.id != failed.sourceId) s,
  ].take(maxSources).toList();
  if (pool.isEmpty) return null;

  final keyword = [failed.artist, failed.title]
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .join(' ');
  if (keyword.isEmpty) return null;

  final want = normalizeTitle(failed.title);
  final found = await _collectUntil(
    events: orchestrator.search(pool, SearchQuery(keyword: keyword)),
    matches: (r) {
      final got = normalizeTitle(r.title);
      return got == want || got.contains(want) || want.contains(got);
    },
  );
  if (found.isEmpty) return null;

  for (final cand in rankSameSongCandidates(
    found: found,
    title: failed.title,
    artist: failed.artist,
    excludeSourceId: failed.sourceId,
  )) {
    try {
      final url = await assembler.resolveMedia(cand.sourceId, cand);
      if (!url.startsWith('http')) continue;
      return QueueItem(
        title: cand.title,
        artist: cand.extra?['artist'] ?? '',
        cover: cand.extra?['cover'] ?? '',
        url: url,
        sourceName: cand.sourceName,
        sourceId: cand.sourceId,
        extra: cand.extra,
        headers: playbackHeaders(cand.extra),
      );
    } catch (_) {
      continue; // 该候选解析失败，试下一个
    }
  }
  return null;
}
