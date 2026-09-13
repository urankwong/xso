import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 平台登录配置：登录页地址 + 需要抓取的 Cookie 键 + 判定登录成功的键
class LoginPlatform {
  final String id;
  final String label;
  final String url;
  final List<String> cookieNames; // 全部要保存的 cookie
  final List<String> requiredNames; // 出现即视为已登录
  final String cookieDomain; // 取 cookie 的域

  const LoginPlatform({
    required this.id,
    required this.label,
    required this.url,
    required this.cookieNames,
    required this.requiredNames,
    required this.cookieDomain,
  });
}

const kLoginPlatforms = <LoginPlatform>[
  LoginPlatform(
    id: 'bilibili',
    label: '哔哩哔哩',
    url: 'https://www.bilibili.com/',
    cookieNames: ['SESSDATA', 'bili_jct', 'DedeUserID', 'buvid3', 'sid'],
    requiredNames: ['SESSDATA'],
    cookieDomain: '.bilibili.com',
  ),
  LoginPlatform(
    id: 'netease',
    label: '网易云音乐',
    url: 'https://music.163.com/',
    cookieNames: ['MUSIC_U', 'NMTID', 'MUSIC_A'],
    requiredNames: ['MUSIC_U'],
    cookieDomain: '.music.163.com',
  ),
  LoginPlatform(
    id: 'qqmusic',
    label: 'QQ音乐',
    url: 'https://y.qq.com/',
    cookieNames: ['musickey', 'Q_HD_VID', 'uin', 'skey', 'pgv_psi'],
    requiredNames: ['musickey'],
    cookieDomain: '.y.qq.com',
  ),
  LoginPlatform(
    id: 'kugou',
    label: '酷狗音乐',
    url: 'https://www.kugou.com/',
    cookieNames: ['kg_token', 'web_loginid', 'kg_uid'],
    requiredNames: ['web_loginid'],
    cookieDomain: '.kugou.com',
  ),
];

/// 应用内登录并抓取 Cookie：用户在 WebView 里扫码/输密，我们轮询目标域
/// 的 cookie，命中必需项后拼成 Cookie 字符串返回。
class AccountLoginPage extends StatefulWidget {
  final LoginPlatform platform;
  const AccountLoginPage({super.key, required this.platform});

  @override
  State<AccountLoginPage> createState() => _AccountLoginPageState();
}

class _AccountLoginPageState extends State<AccountLoginPage> {
  late final WebViewController _controller;
  Timer? _poll;
  String? _cookie;
  bool _detecting = false;
  double _progress = 0;
  /// 轮询超过 3 分钟仍未识别到登录，提示可手动获取
  bool _slowHint = false;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/125 Mobile Safari/537.36')
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p / 100),
        onPageFinished: (_) => _tryCapture(),
      ))
      ..loadRequest(Uri.parse(widget.platform.url));
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _tryCapture());
    // 一直轮询但不给任何反馈，用户不知道是没登录还是识别失败
    _hintTimer = Timer(const Duration(minutes: 3), () {
      if (mounted) setState(() => _slowHint = true);
    });
  }

  Future<List<WebViewCookie>> _readCookies() async {
    try {
      return await WebViewCookieManager()
          .getCookies(domain: Uri.parse(widget.platform.url));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _tryCapture() async {
    if (_detecting || _cookie != null) return;
    _detecting = true;
    try {
      final all = await _readCookies();
      final host = Uri.parse(widget.platform.cookieDomain.startsWith('.')
          ? 'https://x${widget.platform.cookieDomain}'
          : 'https://${widget.platform.cookieDomain}').host;
      final picked = <String, String>{};
      for (final c in all) {
        if (!widget.platform.cookieNames.contains(c.name)) continue;
        final cd = c.domain;
        if (host.endsWith(cd.replaceFirst('.', '')) ||
            cd.replaceFirst('.', '') == host.split('.').reversed.take(2).join('.')) {
          picked[c.name] = c.value;
        }
      }
      final ok = widget.platform.requiredNames.any(picked.containsKey);
      if (ok) {
        final value = picked.entries.map((e) => '${e.key}=${e.value}').join('; ');
        if (mounted) {
          _poll?.cancel();
          Navigator.pop(context, value);
        }
      }
    } finally {
      _detecting = false;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _hintTimer?.cancel();
    super.dispose();
  }

  Future<void> _manualCapture() async {
    final all = await _readCookies();
    final picked = <String, String>{};
    for (final c in all) {
      if (widget.platform.cookieNames.contains(c.name)) {
        picked[c.name] = c.value;
      }
    }
    if (picked.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('还没检测到登录信息，请先在页面上完成登录')));
      }
      return;
    }
    if (!mounted) return;
    Navigator.pop(
        context, picked.entries.map((e) => '${e.key}=${e.value}').join('; '));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('登录 ${widget.platform.label}'),
        bottom: _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress, minHeight: 2),
              )
            : null,
        actions: [
          // 登录流程往往有多步跳转，没有网页后退就只能在登录页里卡住
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '网页返回',
            onPressed: () async {
              if (await _controller.canGoBack()) {
                await _controller.goBack();
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已经是第一页')));
              }
            },
          ),
          TextButton(onPressed: _manualCapture, child: const Text('我已登录')),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: _slowHint
                ? Theme.of(context).colorScheme.tertiaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _slowHint
                    ? '仍未自动识别到登录信息？可点右上角「我已登录」手动获取。'
                    : '在页面内扫码或输入账号登录，成功后自动获取 Cookie（仅存本机）',
                style: TextStyle(
                    fontSize: 12,
                    color: _slowHint
                        ? Theme.of(context).colorScheme.onTertiaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
