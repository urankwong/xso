import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/update_service.dart';

/// 挂在 HomeShell 外层：启动后延迟做「每日一次」静默检查，
/// 有新版才弹更新框（网络失败/已跳过该版本则完全静默）。
class UpdateGate extends StatefulWidget {
  final Widget child;
  const UpdateGate({super.key, required this.child});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    // 首帧后再查：既避开启动关键路径（内置源导入/插件装配），
    // 也保证拿到的 context 在 Navigator 之下、可以弹对话框。
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLater());
  }

  Future<void> _checkLater() async {
    if (_fired) return;
    _fired = true;
    // 稍等一拍，让首页动画/首屏加载先完成，不打断用户
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    final res = await UpdateService.startupCheck(abiHint: await UpdateService.deviceAbi());
    if (res == null || !mounted) return;
    await showUpdateDialog(context, res);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 设置页里的「检查更新」条目：显示当前版本，点击手动检查并弹框。
class UpdateCheckTile extends StatefulWidget {
  const UpdateCheckTile({super.key});

  @override
  State<UpdateCheckTile> createState() => _UpdateCheckTileState();
}

class _UpdateCheckTileState extends State<UpdateCheckTile> {
  String _version = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    UpdateService.currentVersion().then((v) {
      if (mounted) setState(() => _version = v?.display ?? '未知');
    });
  }

  Future<void> _tap() async {
    if (_checking) return;
    setState(() => _checking = true);
    final res = await UpdateService.check(abiHint: await UpdateService.deviceAbi());
    await UpdateService.markChecked();
    if (!mounted) return;
    setState(() => _checking = false);
    switch (res.status) {
      case UpdateStatus.available:
        await showUpdateDialog(context, res);
      case UpdateStatus.upToDate:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('已是最新版本 v${res.current?.display ?? _version}')));
      case UpdateStatus.failed:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('检查失败：${res.error ?? "未知错误"}（可在项目页手动下载）')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _checking
          ? const SizedBox(
              width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
          : const Icon(Icons.system_update_alt),
      title: const Text('检查更新'),
      subtitle: Text(
        _version.isEmpty ? '正在读取版本…' : '当前版本 v$_version，从 GitHub Releases 获取更新',
        style: const TextStyle(fontSize: 12),
      ),
      onTap: _tap,
    );
  }
}

Future<void> showUpdateDialog(BuildContext context, UpdateCheckResult res) {
  return showDialog(
    context: context,
    builder: (_) => _UpdateDialog(result: res),
  );
}

/// 更新对话框：说明 + 「立即更新」（应用内下载并拉起安装器），
/// 同时保留「浏览器下载 / 复制直链」两条退路（围场网络下直连常失败）。
class _UpdateDialog extends StatefulWidget {
  final UpdateCheckResult result;
  const _UpdateDialog({required this.result});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

enum _Phase { idle, downloading, installing, failed }

class _UpdateDialogState extends State<_UpdateDialog> {
  _Phase _phase = _Phase.idle;
  int _received = 0;
  int _total = 0;
  String _error = '';
  CancelToken _token = CancelToken();
  DownloadedApk? _apk;

  @override
  void dispose() {
    _token.cancel('页面关闭');
    super.dispose();
  }

  ReleaseInfo? get _release => widget.result.release;
  AppVersion? get _latest => widget.result.latest;

  Future<void> _startDownload() async {
    final asset = widget.result.asset;
    if (asset == null) {
      setState(() {
        _phase = _Phase.failed;
        _error = '该版本没有可用的安装包';
      });
      return;
    }
    setState(() {
      _phase = _Phase.downloading;
      _received = 0;
      _total = asset.size;
      _error = '';
    });
    _token = CancelToken();
    // 先清掉上一次的残留包（几百 MB 一个，不能攒）
    await UpdateService.cleanDownloads();
    final res = await UpdateService.download(
      asset,
      (received, total) {
        if (!mounted) return;
        setState(() {
          _received = received;
          if (total > 0) _total = total;
        });
      },
      cancelToken: _token,
    );
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _phase = _Phase.failed;
        _error = res.error ?? '下载失败';
        _apk = res;
      });
      return;
    }
    setState(() {
      _apk = res;
      _phase = _Phase.installing;
    });
    await _launchInstaller(res);
  }

  Future<void> _launchInstaller(DownloadedApk apk) async {
    final path = apk.file?.path ?? '';
    final r = await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
    if (!mounted) return;
    if (r.type != ResultType.done) {
      // 最常见原因是用户没给「安装未知应用」权限，或 ROM 拦截了缓存目录 intent
      final hint = switch (r.type) {
        ResultType.permissionDenied => '请先在系统设置里允许汇搜「安装未知应用」。',
        ResultType.noAppToOpen => '本机没有可安装 APK 的程序（如安装了纯净模式/安装器被禁用）。',
        _ => '',
      };
      setState(() {
        _phase = _Phase.failed;
        _error = '未能自动打开安装器：${r.message}\n$hint\n可点「浏览器下载」拿安装包后手动安装。';
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _copyLink() async {
    final url = _apk?.sourceUrl.isNotEmpty == true
        ? _apk!.sourceUrl
        : (widget.result.asset?.url ?? _release?.pageUrl ?? UpdateService.releasePage);
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('下载地址已复制，可粘贴到浏览器/下载工具')));
  }

  Future<void> _openInBrowser() async {
    final url = widget.result.asset?.url ?? _release?.pageUrl;
    if (url == null) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  String _mb(int b) => (b / 1024 / 1024).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cur = widget.result.current;
    final asset = widget.result.asset;
    final busy = _phase == _Phase.downloading || _phase == _Phase.installing;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.rocket_launch_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('发现新版本 ${_latest?.display ?? ''}',
                style: const TextStyle(fontSize: 17)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              cur == null
                  ? '版本 ${_release?.tagName ?? ''}'
                  : '当前 v${cur.display} → 最新 v${_latest?.display ?? ''}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            if ((_release?.changelog ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Text(
                    _release!.changelog.trim(),
                    style: const TextStyle(fontSize: 13, height: 1.45),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_phase == _Phase.downloading) ...[
              LinearProgressIndicator(
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
                value: _total > 0 ? (_received / _total).clamp(0.0, 1.0) : null,
              ),
              const SizedBox(height: 6),
              Text(
                _total > 0
                    ? '下载中 ${_mb(_received)} / ${_mb(_total)} MB'
                    : '下载中 ${_mb(_received)} MB',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ] else if (_phase == _Phase.installing) ...[
              const Text('下载完成，正在唤起系统安装器…', style: TextStyle(fontSize: 12)),
            ] else if (_phase == _Phase.failed) ...[
              Text(_error,
                  style: TextStyle(fontSize: 12, color: scheme.error)),
            ] else if (asset != null) ...[
              Text(
                '安装包 ${asset.name}（约 ${_mb(asset.size)} MB）\n'
                '直连 GitHub 失败会自动改用加速镜像。',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ] else ...[
              Text('该 Release 未找到匹配本机的安装包，可用浏览器打开 Release 页手动下载。',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        if (_phase == _Phase.downloading)
          TextButton(
            onPressed: () {
              _token.cancel('用户取消');
              setState(() => _phase = _Phase.idle);
            },
            child: const Text('取消'),
          )
        else if (_phase != _Phase.installing)
          TextButton(
            onPressed: () async {
              final tag = _release?.tagName;
              if (tag != null) await UpdateService.skipVersion(tag);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('跳过此版本'),
          ),
        TextButton(onPressed: _copyLink, child: const Text('复制地址')),
        TextButton(onPressed: _openInBrowser, child: const Text('浏览器下载')),
        FilledButton(
          onPressed: busy ? null : _startDownload,
          child: Text(switch (_phase) {
            _Phase.downloading => '下载中…',
            _Phase.installing => '安装中…',
            _Phase.failed => '重试下载',
            _Phase.idle => '立即更新',
          }),
        ),
      ],
    );
  }
}
