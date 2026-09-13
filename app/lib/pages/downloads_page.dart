import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import '../providers/downloads.dart';
import '../widgets/download_confirm.dart';

/// 下载页：按状态分档的任务卡列表（进行中 / 已完成 / 失败）
class DownloadsPage extends ConsumerStatefulWidget {
  const DownloadsPage({super.key});
  @override
  ConsumerState<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<DownloadsPage> {
  DownloadStatus? _filter;
  DownloadKind? _typeFilter;

  /// 清除是不可恢复操作，且实际会一并清掉失败/已取消的任务，
  /// 所以在文案和确认里都把范围说清楚，避免用户误删还想重试的记录。
  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(downloadsProvider);
    final n = controller.tasks.length - controller.activeCount;
    if (n == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除已结束的任务'),
        content: Text('将移除 $n 条记录（含已完成、失败、已取消）。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清除')),
        ],
      ),
    );
    if (ok == true) controller.clearFinished();
  }

  int _count(List<DownloadTask> tasks, DownloadStatus? f) {
    if (f == null) return tasks.length;
    if (f == DownloadStatus.running) {
      return tasks
          .where((t) =>
              t.status == DownloadStatus.running ||
              t.status == DownloadStatus.queued)
          .length;
    }
    return tasks.where((t) => t.status == f).length;
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(downloadsProvider);
    final scheme = Theme.of(context).colorScheme;
    final tasks = controller.tasks;

    if (!controller.loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('下载')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    bool matchStatus(DownloadTask t) {
      if (_filter == null) return true;
      if (_filter == DownloadStatus.running) {
        return t.status == DownloadStatus.running ||
            t.status == DownloadStatus.queued;
      }
      return t.status == _filter;
    }

    // 状态 × 类型 双维度筛选（AND）
    final visible = tasks
        .where((t) =>
            matchStatus(t) && (_typeFilter == null || t.kind == _typeFilter))
        .toList();

    Widget chip(String label, DownloadStatus? value, {IconData? icon}) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          avatar: icon == null ? null : Icon(icon, size: 16),
          label: Text(label),
          selected: _filter == value,
          onSelected: (_) => setState(() => _filter = value),
          showCheckmark: false,
        ),
      );
    }

    Widget kindChip(DownloadKind? value) {
      final n = value == null
          ? tasks.length
          : tasks.where((t) => t.kind == value).length;
      final label = value == null ? '全部' : downloadKindLabel(value);
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          avatar: value == null
              ? null
              : Icon(downloadKindIcon(value),
                  size: 16, color: downloadKindColor(scheme, value)),
          label: Text('$label $n'),
          selected: _typeFilter == value,
          onSelected: (_) => setState(() => _typeFilter = value),
          showCheckmark: false,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载'),
        actions: [
          if (controller.activeCount > 0)
            TextButton(
              onPressed: controller.cancelAll,
              child: const Text('全部取消'),
            ),
          TextButton(
            onPressed: tasks.isEmpty ? null : () => _confirmClear(context, ref),
            child: const Text('清除已结束'),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                chip('全部 ${tasks.length}', null, icon: Icons.download_outlined),
                chip('进行中 ${_count(tasks, DownloadStatus.running)}',
                    DownloadStatus.running,
                    icon: Icons.downloading),
                chip('已完成 ${_count(tasks, DownloadStatus.done)}',
                    DownloadStatus.done,
                    icon: Icons.check_circle_outline),
                chip('失败 ${_count(tasks, DownloadStatus.failed)}',
                    DownloadStatus.failed,
                    icon: Icons.error_outline),
              ],
            ),
          ),
          // 第二行：资源类型筛选（音乐/有声/视频/书籍），与状态筛选按 AND 组合
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                kindChip(null),
                kindChip(DownloadKind.music),
                kindChip(DownloadKind.audiobook),
                kindChip(DownloadKind.movie),
                kindChip(DownloadKind.book),
              ],
            ),
          ),
          // 队列整体进度：串行下载时只有第一条在跑，
          // 没有这行用户无法判断还剩多少、以为卡住了
          if (controller.activeCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '未完成 ${controller.activeCount} 个 · 已完成 ${controller.finishedCount} 个'
                      '${controller.activeCount > 1 ? '（按顺序逐个下载）' : ''}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.download_for_offline_outlined,
                            size: 60, color: scheme.outline),
                        const SizedBox(height: 12),
                        const Text('暂无下载任务，去搜索页找音乐吧'),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: visible.length,
                    itemBuilder: (context, i) =>
                        _TaskCard(task: visible[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends ConsumerWidget {
  final DownloadTask task;
  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(downloadsProvider);
    final scheme = Theme.of(context).colorScheme;
    final status = task.status;

    // 副行状态描述
    String desc;
    var descColor = scheme.onSurfaceVariant;
    switch (status) {
      case DownloadStatus.queued:
        desc = '排队中';
      case DownloadStatus.running:
        desc = '${_fmt(task.progress)} · 下载中';
      case DownloadStatus.done:
        desc = task.savedPath ?? '已完成';
      case DownloadStatus.failed:
        desc = task.error ?? '未知错误';
        descColor = scheme.error;
      case DownloadStatus.canceled:
        desc = '已取消';
    }
    final failedRetryNote = (status == DownloadStatus.failed && task.retries > 0)
        ? '（已重试 ${task.retries} 次）'
        : null;

    Widget? action;
    switch (status) {
      case DownloadStatus.running:
        action = OutlinedButton(
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: const StadiumBorder(),
          ),
          onPressed: () => controller.cancel(task.id),
          child: const Text('取消'),
        );
      case DownloadStatus.queued || DownloadStatus.canceled:
        action = TextButton(
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          onPressed: () => controller.remove(task.id),
          child: const Text('移除'),
        );
      case DownloadStatus.done:
        action = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 次要动作：复制路径（原来是主按钮，现在降级为图标，
            // 因为用户要的是"打开文件"而不是"拿到一个路径字符串"）
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '复制路径',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () async {
                final path = task.savedPath;
                if (path == null || path.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('未记录保存路径')));
                  return;
                }
                await Clipboard.setData(ClipboardData(text: path));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制文件路径')));
                }
              },
            ),
            const SizedBox(width: 4),
            // 主按钮：唤起系统应用打开（音频→音乐播放器、epub/pdf→阅读器…）
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: const StadiumBorder(),
              ),
              onPressed: () => openDownloadedFile(context, task.savedPath),
              child: const Text('打开'),
            ),
          ],
        );
      case DownloadStatus.failed:
        action = FilledButton.tonal(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: const StadiumBorder(),
            foregroundColor: scheme.error,
            backgroundColor: scheme.error.withValues(alpha: 0.10),
          ),
          onPressed: () => controller.retry(task.id),
          child: const Text('重试'),
        );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧类型图标（音乐 / 有声 / 视频 / 书籍）
            Builder(builder: (_) {
              final kc = downloadKindColor(scheme, task.kind);
              return Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: kc.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(downloadKindIcon(task.kind), size: 24, color: kc),
              );
            }),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // 资源类型徽章（音乐/有声/视频/书籍）
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: downloadKindColor(scheme, task.kind)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(downloadKindLabel(task.kind),
                            style: TextStyle(
                                fontSize: 11,
                                color: downloadKindColor(scheme, task.kind))),
                      ),
                      const SizedBox(width: 6),
                      // 音质/格式徽章
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(task.qualityLabel,
                            style: TextStyle(
                                fontSize: 11,
                                color: scheme.onPrimaryContainer)),
                      ),
                      const SizedBox(width: 6),
                      if (task.fileSize > 0)
                        Text(_fmtSize(task.fileSize),
                            style: TextStyle(
                                fontSize: 11, color: scheme.onSurfaceVariant)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          failedRetryNote == null
                              ? desc
                              : '$desc$failedRetryNote',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: descColor),
                        ),
                      ),
                    ],
                  ),
                  if (status == DownloadStatus.running) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                          value: task.progress, minHeight: 4),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            action,
          ],
        ),
      ),
    );
  }

  static String _fmt(double p) => '${(p * 100).toStringAsFixed(0)}%';

  static String _fmtSize(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double v = bytes.toDouble();
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    final digits = (i == 0 || v >= 100) ? 0 : 1;
    return '${v.toStringAsFixed(digits)} ${units[i]}';
  }
}

/// 用系统应用打开已下载的文件。
///
/// 按扩展名推断 MIME，交给 `open_filex` 唤起对应程序：
/// 音频 → 系统音乐播放器、epub/pdf/txt → 阅读器、视频 → 播放器。
///
/// 用的是**本地 vendor 版** open_filex（`packages/open_filex_local`）：
/// 上游 4.7.0 的 android/build.gradle 自带 AGP 8.1.0 与项目 AGP 9.1 冲突，
/// vendor 版只改了构建配置，源码未动。
///
/// **重要限制**：当「下载保存位置」是 `app`（应用私有目录）时，文件位于
/// `Android/data/<包名>/files/`，**外部应用无权读取**，打开会失败。
/// 这种情况必须明确告诉用户怎么解决，而不是只说"打开失败"。
Future<void> openDownloadedFile(BuildContext context, String? path) async {
  final messenger = ScaffoldMessenger.of(context);
  if (path == null || path.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('未记录保存路径')));
    return;
  }
  if (!File(path).existsSync()) {
    messenger.showSnackBar(
        const SnackBar(content: Text('文件不存在（可能已被移动或删除）')));
    return;
  }
  try {
    final res = await OpenFilex.open(path, type: _mimeOf(path));
    if (res.type == ResultType.done) return;
    messenger.showSnackBar(SnackBar(
      content: Text('无法打开：${res.message}\n'
          '若文件在应用私有目录，请到「设置 → 下载保存位置」改为「系统下载」后重新下载'),
      duration: const Duration(seconds: 6),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('打开失败：$e')));
  }
}

/// 按扩展名推断 MIME；未知类型交给系统自行选择
String _mimeOf(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  switch (ext) {
    case 'mp3':
      return 'audio/mpeg';
    case 'm4a':
    case 'aac':
      return 'audio/mp4';
    case 'flac':
      return 'audio/flac';
    case 'wav':
      return 'audio/wav';
    case 'ogg':
      return 'audio/ogg';
    case 'mp4':
      return 'video/mp4';
    case 'mkv':
      return 'video/x-matroska';
    case 'epub':
      return 'application/epub+zip';
    case 'pdf':
      return 'application/pdf';
    case 'txt':
      return 'text/plain';
    default:
      return '*/*';
  }
}
