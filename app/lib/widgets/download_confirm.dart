import 'package:flutter/material.dart';

import '../providers/downloads.dart';

/// 统一的「下载确认」底部面板：类型徽章 + 标题/艺人 + 音质单选 + 取消/下载。
///
/// 返回选中的音质标签（String）；用户取消或点空白关闭返回 null。
/// [qualities] 为空时仅展示「默认音质」并提示该源未提供档位——
/// 这正是原实现「0/1 档源点击即秒下、无任何确认」的修复点。
Future<String?> showDownloadConfirm(
  BuildContext context, {
  required DownloadKind kind,
  required String title,
  String? artist,
  List<({String id, String name})> qualities = const [],
  String? initial,
}) {
  final choices = qualities.isEmpty
      ? const <({String id, String name})>[(id: '_default', name: '默认音质')]
      : qualities;
  var selected = (initial != null && choices.any((q) => q.name == initial))
      ? initial
      : choices.first.name;
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        downloadKindBadge(ctx, kind),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15)),
                        ),
                      ],
                    ),
                    if ((artist ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(artist!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (qualities.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text('该源未提供其他音质档位',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final q in choices)
                        ListTile(
                          title: Text(q.name),
                          selected: q.name == selected,
                          trailing: q.name == selected
                              ? Icon(Icons.check_circle,
                                  color: scheme.primary, size: 20)
                              : null,
                          onTap: () => setSheet(() => selected = q.name),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, selected),
                        child: const Text('下载'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 资源类型徽章（音乐 / 有声 / 视频 / 书籍）
Widget downloadKindBadge(BuildContext context, DownloadKind kind) {
  final scheme = Theme.of(context).colorScheme;
  final c = downloadKindColor(scheme, kind);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(6),
    ),
    child:
        Text(downloadKindLabel(kind), style: TextStyle(fontSize: 11, color: c)),
  );
}

String downloadKindLabel(DownloadKind k) => switch (k) {
      DownloadKind.music => '音乐',
      DownloadKind.audiobook => '有声',
      DownloadKind.movie => '视频',
      DownloadKind.book => '书籍',
    };

IconData downloadKindIcon(DownloadKind k) => switch (k) {
      DownloadKind.music => Icons.music_note,
      DownloadKind.audiobook => Icons.podcasts,
      DownloadKind.movie => Icons.movie_outlined,
      DownloadKind.book => Icons.menu_book,
    };

Color downloadKindColor(ColorScheme s, DownloadKind k) => switch (k) {
      DownloadKind.music => s.primary,
      DownloadKind.audiobook => Color.lerp(s.secondary, s.tertiary, 0.4)!,
      DownloadKind.movie => s.tertiary,
      DownloadKind.book => Color.lerp(s.tertiary, s.primary, 0.45)!,
    };
