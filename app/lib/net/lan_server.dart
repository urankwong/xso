import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:data/data.dart';
import 'package:source_engine/source_engine.dart';

import '../providers/agent_service.dart';
import '../providers/data_providers.dart';
import '../providers/downloads.dart';
import '../providers/engine_providers.dart';
import 'log_bus.dart';

/// 已连接客户端记录
class LanClient {
  final String ip;
  String ua;
  DateTime lastSeen;
  bool blocked;
  LanClient(this.ip, this.ua, this.lastSeen) : blocked = false;

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'ua': ua,
        'lastSeen': lastSeen.toIso8601String(),
        'blocked': blocked,
      };
}

/// 局域网助手服务：在设备内起一个 dart:io HTTP 服务，
/// 让同 WiFi 下的电脑浏览器访问，用于 PC 批量导入/管理源、看日志、开放 REST API。
class LanServer extends ChangeNotifier {
  final Ref _ref;
  LanServer(this._ref) {
    _load();
  }

  // ---------- 持久化键 ----------
  static const _kEnable = 'lan.enable';
  static const _kImport = 'lan.allowImport';
  static const _kManage = 'lan.allowManage';
  static const _kLog = 'lan.allowReadLog';
  static const _kApi = 'lan.allowApi';
  static const _kTokenOn = 'lan.requireToken';
  static const _kToken = 'lan.token';

  static const int basePort = 9310;
  static const int _maxRetry = 5; // 端口占用向上重试次数

  HttpServer? _server;
  String? _ip;
  int _port = basePort;
  String? _lastError;
  final Random _rnd = Random();

  bool enableLan = false;
  bool allowImport = false;
  bool allowManage = false;
  bool allowReadLog = false;
  bool allowApi = false;
  bool requireToken = false;
  String token = '';

  final Map<String, LanClient> _clients = {};
  final List<void Function()> _sseClosers = [];

  bool get running => _server != null;
  String? get ip => _ip;
  int get port => _port;
  String? get lastError => _lastError;
  String get url => _ip == null ? '' : 'http://$_ip:$_port';
  List<LanClient> get clients => _clients.values.toList()
    ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
  int get connectedCount => _clients.values.where((c) => !c.blocked).length;

  Map<String, bool> get perms => {
        'allowImportSource': allowImport,
        'allowManageSource': allowManage,
        'allowReadLog': allowReadLog,
        'allowApi': allowApi,
      };

  // ---------- 设置加载 / 持久化 ----------

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<void> _load() async {
    final p = await _prefs();
    enableLan = p.getBool(_kEnable) ?? false;
    allowImport = p.getBool(_kImport) ?? false;
    allowManage = p.getBool(_kManage) ?? false;
    allowReadLog = p.getBool(_kLog) ?? false;
    allowApi = p.getBool(_kApi) ?? false;
    requireToken = p.getBool(_kTokenOn) ?? false;
    token = p.getString(_kToken) ?? '';
    notifyListeners();
    // 上次退出前是开启状态 → 自动拉起
    if (enableLan) {
      await _ensureStarted();
    }
  }

  // ---------- 权限子开关 ----------

  Future<void> setAllowImport(bool v) async {
    allowImport = v;
    (await _prefs()).setBool(_kImport, v);
    notifyListeners();
  }

  Future<void> setAllowManage(bool v) async {
    allowManage = v;
    (await _prefs()).setBool(_kManage, v);
    notifyListeners();
  }

  Future<void> setAllowReadLog(bool v) async {
    allowReadLog = v;
    (await _prefs()).setBool(_kLog, v);
    notifyListeners();
  }

  Future<void> setAllowApi(bool v) async {
    allowApi = v;
    (await _prefs()).setBool(_kApi, v);
    notifyListeners();
  }

  Future<void> setRequireToken(bool v) async {
    requireToken = v;
    final p = await _prefs();
    await p.setBool(_kTokenOn, v);
    if (v && token.isEmpty) {
      token = _genToken();
      await p.setString(_kToken, token);
    }
    notifyListeners();
  }

  // ---------- 启停 ----------

  Future<void>? _starting;

  Future<void> start() async {
    enableLan = true;
    (await _prefs()).setBool(_kEnable, true);
    notifyListeners();
    await _ensureStarted();
  }

  /// 串行化启动：_load() 的自动恢复与用户手动开启可能并发，
  /// 否则两个 _start() 会各自绑一个端口（孤儿服务）并互相覆盖 _port。
  Future<void> _ensureStarted() {
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    if (_server != null) return;
    _lastError = null;
    _clients.clear();
    _ip = await _localIp();
    if (_ip == null) {
      _lastError = '未检测到 WiFi / 局域网 IP，请连接 WiFi 后再开启';
      logBus.warn('lan', _lastError!);
      notifyListeners();
      return;
    }
    if (requireToken && token.isEmpty) {
      token = _genToken();
      (await _prefs()).setString(_kToken, token);
    }
    await _bind();
    if (_server != null) {
      logBus.info('lan', '局域网服务已启动 $url');
    }
    notifyListeners();
  }

  Future<void> _bind() async {
    if (_server != null) return; // 已有实例在监听，避免重复绑定
    for (var attempt = 0; attempt <= _maxRetry; attempt++) {
      final tryPort = basePort + attempt;
      try {
        _server =
            await HttpServer.bind(InternetAddress.anyIPv4, tryPort, shared: false);
        _port = tryPort;
        unawaited(_serve(_server!));
        return;
      } catch (e) {
        _server = null;
        _lastError = '端口 $tryPort 绑定失败：$e';
      }
    }
    _lastError = '端口 $basePort~${basePort + _maxRetry} 均被占用，启动失败';
    logBus.error('lan', _lastError!);
  }

  Future<void> stop() async {
    enableLan = false;
    (await _prefs()).setBool(_kEnable, false);
    await _close();
    logBus.info('lan', '局域网服务已停止');
    notifyListeners();
  }

  Future<void> _close() async {
    for (final c in _sseClosers.toList()) {
      try {
        c();
      } catch (_) {}
    }
    _sseClosers.clear();
    final s = _server;
    _server = null;
    if (s != null) {
      await s.close(force: true);
    }
  }

  /// 断开某客户端：拉黑后其后续请求返回 403
  void disconnect(String ip) {
    final c = _clients[ip];
    if (c != null) c.blocked = true;
    logBus.info('lan', '已断开设备 $ip');
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_close());
    super.dispose();
  }

  // ---------- 工具 ----------

  String _genToken() => List.generate(4, (_) => _rnd.nextInt(10)).join();

  Future<String?> _localIp() async {
    try {
      final ifaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      for (final i in ifaces) {
        for (final a in i.addresses) {
          if (!a.isLoopback) return a.address;
        }
      }
    } catch (_) {}
    return null;
  }

  void _touch(String ip, String? ua) {
    final now = DateTime.now();
    final c = _clients[ip];
    if (c != null) {
      c.lastSeen = now;
    } else {
      _clients[ip] = LanClient(ip, _shortUa(ua ?? ''), now);
      logBus.info('lan', '新设备接入：$ip');
      notifyListeners();
    }
  }

  String _shortUa(String ua) {
    if (ua.contains('Edg')) return 'Edge';
    if (ua.contains('OPR') || ua.contains('Opera')) return 'Opera';
    if (ua.contains('Firefox')) return 'Firefox';
    if (ua.contains('Chrome')) return 'Chrome';
    if (ua.contains('Safari')) return 'Safari';
    if (ua.isEmpty) return '未知客户端';
    return ua.length > 24 ? '${ua.substring(0, 24)}…' : ua;
  }

  Future<void> _serve(HttpServer server) async {
    await for (final req in server) {
      try {
        await _handle(req);
      } catch (e) {
        logBus.error('lan', '请求处理异常：$e');
        try {
          await _json(req.response, 500, {'ok': false, 'error': '$e'});
        } catch (_) {}
      }
    }
  }

  void _cors(HttpResponse res) {
    res.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET,POST,PATCH,DELETE,OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type,Authorization');
  }

  Future<void> _json(HttpResponse res, int code, Map body) async {
    res.statusCode = code;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    await res.close();
  }

  Future<void> _forbid(HttpResponse res, String what) => _json(
      res,
      403,
      {
        'ok': false,
        'error': '该能力未开启：$what（请在 App「局域网助手」页开启对应权限）',
      });

  Future<Map<String, dynamic>> _readJson(HttpRequest req) async {
    final raw = await utf8.decoder.bind(req).join();
    if (raw.trim().isEmpty) return {};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  bool _authed(HttpRequest req) {
    final q = req.uri.queryParameters['token'];
    if (q != null && q == token) return true;
    final auth = req.headers.value(HttpHeaders.authorizationHeader);
    if (auth != null) {
      final v =
          auth.startsWith('Bearer ') ? auth.substring(7).trim() : auth.trim();
      if (v == token) return true;
    }
    return false;
  }

  // ---------- 路由分发 ----------

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    _cors(res);
    if (req.method == 'OPTIONS') {
      res.statusCode = 204;
      await res.close();
      return;
    }
    final ip = req.connectionInfo?.remoteAddress.address ?? '?';
    _touch(ip, req.headers.value('user-agent'));
    final blocked = _clients[ip]?.blocked ?? false;
    if (blocked) {
      await _json(res, 403, {'ok': false, 'error': '该设备已被主机断开'});
      return;
    }

    // 只读欢迎页：不需要令牌
    if (req.method == 'GET' &&
        (req.uri.path == '/' || req.uri.path == '/index.html')) {
      return _serveHtml(res);
    }

    if (req.uri.path.startsWith('/api/')) {
      if (requireToken && !_authed(req)) {
        await _json(res, 403, {'ok': false, 'error': '缺少或错误的访问令牌'});
        return;
      }
      return _route(req, res);
    }

    await _json(res, 404, {'ok': false, 'error': '未找到 ${req.uri.path}'});
  }

  Future<void> _route(HttpRequest req, HttpResponse res) async {
    final segs = req.uri.pathSegments; // ['api', '<area>', ...]
    if (segs.length < 2 || segs[0] != 'api') {
      return _json(res, 404, {'ok': false, 'error': '未找到'});
    }
    final area = segs[1];
    final m = req.method;

    switch (area) {
      case 'status':
        return _json(res, 200, {
          'enabled': running,
          'ip': _ip,
          'port': _port,
          'requireToken': requireToken,
          'perms': perms,
          'connectedClients': connectedCount,
        });

      case 'sources':
        return _sources(req, res, m, segs);

      case 'search':
        if (m == 'GET') return _search(req, res);
        break;

      case 'download':
        if (m == 'POST') return _download(req, res);
        break;

      case 'downloads':
        if (m == 'GET') return _downloadsList(res);
        break;

      case 'logs':
        return _logs(req, res, segs);

      case 'agent':
        return _agent(req, res, m, segs);
    }
    return _json(res, 404, {'ok': false, 'error': '未找到 ${req.uri.path}'});
  }

  Future<void> _serveHtml(HttpResponse res) async {
    try {
      final html = await rootBundle.loadString('assets/web/lan.html');
      res.statusCode = 200;
      res.headers.contentType = ContentType('text', 'html', charset: 'utf-8');
      res.write(html);
      await res.close();
    } catch (e) {
      res.statusCode = 500;
      res.write('管理页加载失败：$e');
      await res.close();
    }
  }

  // ---------- 源管理 ----------

  Future<void> _sources(
      HttpRequest req, HttpResponse res, String m, List<String> segs) async {
    // GET /api/sources → 列表（读取元信息，管理页需要，仅需令牌）
    if (m == 'GET' && segs.length == 2) {
      final stored = await _listStored();
      return _json(res, 200, {
        'ok': true,
        'sources': stored
            .map((s) => {
                  'id': s.id,
                  'name': s.name,
                  'type': s.type,
                  'format': s.format,
                  'enabled': s.enabled,
                })
            .toList(),
      });
    }
    // POST /api/sources/import
    if (m == 'POST' && segs.length == 3 && segs[2] == 'import') {
      if (!allowImport) return _forbid(res, '允许导入源');
      return _importSources(req, res);
    }
    // PATCH / DELETE /api/sources/{id}
    if ((m == 'PATCH' || m == 'DELETE') && segs.length == 3) {
      if (!allowManage) return _forbid(res, '允许管理源');
      final id = Uri.decodeComponent(segs[2]);
      if (m == 'DELETE') {
        final repo = await _repo();
        await repo.delete(id);
        _invalidateSources();
        logBus.info('source', '删除源：$id');
        return _json(res, 200, {'ok': true, 'id': id, 'deleted': true});
      }
      final body = await _readJson(req);
      final enabled = body['enabled'];
      if (enabled is! bool) {
        return _json(res, 400, {'ok': false, 'error': 'enabled(bool) 必填'});
      }
      final repo = await _repo();
      await repo.setEnabled(id, enabled);
      _invalidateSources();
      logBus.info('source', '${enabled ? '启用' : '停用'}源：$id');
      return _json(res, 200, {'ok': true, 'id': id, 'enabled': enabled});
    }
    return _json(res, 404, {'ok': false, 'error': '未找到 ${req.uri.path}'});
  }

  Future<SourceRepository> _repo() async =>
      SourceRepository(await _ref.read(sourceRepositoryPathProvider.future));

  Future<List<StoredSource>> _listStored() async => (await _repo()).list();

  void _invalidateSources() {
    _ref.invalidate(sourceAssemblerProvider);
    _ref.invalidate(searchableSourcesProvider);
  }

  /// 复用 builtin_sources / source_manage 的导入思路：检测格式 → 解析 id/name/type → save
  Future<Map<String, dynamic>> _importRaw(String raw,
      {String? name}) async {
    final repo = await _repo();
    final format = detectSourceFormat(raw);
    String id;
    String nm;
    String type;
    switch (format) {
      case SourceFormat.own:
        final meta = parseSource(raw).meta;
        id = meta.id;
        nm = meta.name;
        type = meta.type.name;
      case SourceFormat.legado:
        final meta = LegadoAdapter().translate(raw).meta;
        id = meta.id;
        nm = meta.name;
        type = meta.type.name;
      case SourceFormat.musicfree:
      case SourceFormat.lx:
        id = '${format.name}-${raw.hashCode.abs()}';
        nm = '局域网导入的 ${format.name} 源';
        type = 'music';
    }
    if (name != null && name.trim().isNotEmpty) nm = name.trim();
    await repo.save(id, format: format.name, raw: raw, name: nm, type: type);
    _invalidateSources();
    logBus.info('source', '导入源：$nm（$id）');
    return {'id': id, 'name': nm, 'format': format.name};
  }

  Future<void> _importSources(HttpRequest req, HttpResponse res) async {
    final body = await _readJson(req);
    final raw = body['raw'] as String?;
    final urls = (body['urls'] as List?)?.whereType<String>().toList();
    if ((raw == null || raw.trim().isEmpty) && (urls == null || urls.isEmpty)) {
      return _json(res, 400, {'ok': false, 'error': '需提供 raw 或 urls'});
    }
    final imported = <Map<String, dynamic>>[];
    final errors = <String>[];
    try {
      if (raw != null && raw.trim().isNotEmpty) {
        imported.add(await _importRaw(raw, name: body['name'] as String?));
      }
      if (urls != null) {
        for (final u in urls) {
          try {
            final resp = await _ref.read(dioProvider).get<String>(u,
                options: Options(
                    responseType: ResponseType.plain,
                    validateStatus: (s) => s != null && s < 500));
            imported.add(await _importRaw(resp.data ?? ''));
          } catch (e) {
            errors.add('$u：$e');
          }
        }
      }
      return await _json(res, 200,
          {'ok': true, 'imported': imported, 'errors': errors});
    } on SourceFormatException catch (e) {
      logBus.warn('source', '导入失败：${e.message}');
      return _json(res, 400, {'ok': false, 'error': '无法识别：${e.message}'});
    } catch (e) {
      logBus.error('source', '导入失败：$e');
      return _json(res, 400, {'ok': false, 'error': '导入失败：$e'});
    }
  }

  // ---------- 搜索 ----------

  Future<void> _search(HttpRequest req, HttpResponse res) async {
    if (!allowApi) return _forbid(res, '开放 API 接口');
    final qp = req.uri.queryParameters;
    final kw = (qp['kw'] ?? qp['q'] ?? '').trim();
    if (kw.isEmpty) {
      return _json(res, 400, {'ok': false, 'error': 'kw（关键词）必填'});
    }
    final type = (qp['type'] ?? '').trim();
    final page = int.tryParse(qp['page'] ?? '1') ?? 1;
    logBus.info('search', '局域网发起搜索：$kw');

    final all = await _ref.read(searchableSourcesProvider.future);
    final sources = type.isEmpty
        ? all
        : all.where((s) => s.meta.type.name == type).toList();
    final completer = Completer<List<Map<String, dynamic>>>();
    final out = <Map<String, dynamic>>[];
    late final StreamSubscription sub;
    sub = _ref
        .read(orchestratorProvider)
        .search(sources, SearchQuery(keyword: kw, page: page))
        .listen((event) {
      if (event is SourceResultsEvent) {
        for (final r in event.results) {
          out.add(_normResult(r));
        }
      } else if (event is SourceStatusEvent &&
          event.status == SourceStatus.failed) {
        logBus.warn('search', '源 ${event.sourceId} 失败：${event.message ?? ''}');
      }
    }, onDone: () {
      sub.cancel();
      if (!completer.isCompleted) completer.complete(out);
    });
    final results = await completer.future;
    return _json(res, 200, {
      'ok': true,
      'keyword': kw,
      'count': results.length,
      'results': results,
    });
  }

  Map<String, dynamic> _normResult(SearchResult r) => {
        'sourceId': r.sourceId,
        'sourceName': r.sourceName,
        'type': r.type.name,
        'title': r.title,
        'url': r.url,
        'extractCode': r.extractCode,
        'extra': r.extra,
        'needsDetail': r.needsDetail,
      };

  // ---------- 下载 ----------

  Future<void> _download(HttpRequest req, HttpResponse res) async {
    if (!allowApi) return _forbid(res, '开放 API 接口');
    final body = await _readJson(req);
    final url = (body['url'] as String?)?.trim() ?? '';
    final title = (body['title'] as String?) ?? '';
    if (url.isEmpty) {
      return _json(res, 400, {'ok': false, 'error': 'url 必填'});
    }
    final c = _ref.read(downloadsProvider);
    final duplicate = c.tasks.any((t) => t.id == url);
    unawaited(c.enqueue(
      url: url,
      title: title,
      artist: body['artist'] as String?,
      qualityLabel: (body['qualityLabel'] as String?) ?? '默认音质',
    ));
    logBus.info('download', '局域网投递下载任务：${title.isEmpty ? url : title}');
    return _json(res, 200,
        {'ok': true, 'queued': !duplicate, 'duplicate': duplicate});
  }

  Future<void> _downloadsList(HttpResponse res) async {
    if (!allowApi) return _forbid(res, '开放 API 接口');
    final tasks = _ref.read(downloadsProvider).tasks.map((t) => t.toJson()).toList();
    return _json(res, 200, {'ok': true, 'tasks': tasks});
  }

  // ---------- Agent 动作（外部 AI / 脚本复用） ----------

  Future<void> _agent(
      HttpRequest req, HttpResponse res, String m, List<String> segs) async {
    if (!allowApi) return _forbid(res, '开放 API 接口');
    final svc = _ref.read(agentServiceProvider);
    final action = segs.length > 2 ? segs[2] : '';

    switch (action) {
      case 'recent':
        if (m == 'GET') {
          final qp = req.uri.queryParameters;
          final list = await svc.getRecent(
            kind: qp['kind'],
            limit: int.tryParse(qp['limit'] ?? '5') ?? 5,
          );
          return _json(res, 200, {
            'ok': true,
            'items': list
                .map((r) => {
                      'sourceId': r.sourceId,
                      'sourceName': r.sourceName,
                      'kind': r.kind,
                      'title': r.title,
                      'url': r.url,
                      'usedAt': r.usedAt.toIso8601String(),
                    })
                .toList(),
          });
        }
        break;

      case 'favorites':
        if (m == 'GET') {
          final qp = req.uri.queryParameters;
          final list = await svc.getFavorites(
            type: qp['type'],
            limit: int.tryParse(qp['limit'] ?? '10') ?? 10,
          );
          return _json(res, 200, {
            'ok': true,
            'items': list
                .map((f) => {
                      'sourceId': f.sourceId,
                      'sourceName': f.sourceName,
                      'type': f.type,
                      'title': f.title,
                      'url': f.url,
                      'createdAt': f.createdAt.toIso8601String(),
                    })
                .toList(),
          });
        }
        break;

      case 'open-book':
        if (m == 'POST') {
          final body = await _readJson(req);
          final ok = await svc.openBook(
            sourceId: (body['sourceId'] as String?) ?? '',
            sourceName: (body['sourceName'] as String?) ?? '',
            title: (body['title'] as String?) ?? '',
            url: (body['url'] as String?) ?? '',
            extractCode: body['extractCode'] as String?,
            type: (body['type'] as String?) ?? 'novel',
          );
          return _json(res, 200, {'ok': true, 'success': ok});
        }
        break;

      case 'play-track':
        if (m == 'POST') {
          final body = await _readJson(req);
          final ok = await svc.playTrack(
            sourceId: (body['sourceId'] as String?) ?? '',
            sourceName: (body['sourceName'] as String?) ?? '',
            title: (body['title'] as String?) ?? '',
            url: (body['url'] as String?) ?? '',
            artist: body['artist'] as String?,
            cover: body['cover'] as String?,
          );
          return _json(res, 200, {'ok': true, 'success': ok});
        }
        break;
    }
    return _json(res, 404, {'ok': false, 'error': '未找到 ${req.uri.path}'});
  }

  // ---------- 日志 ----------

  Future<void> _logs(HttpRequest req, HttpResponse res, List<String> segs) async {
    if (!allowReadLog) return _forbid(res, '允许读取日志');
    if (segs.length >= 3 && segs[2] == 'stream') {
      return _sse(res);
    }
    return _json(res, 200, {
      'ok': true,
      'logs': logBus.snapshot.map((e) => e.toJson()).toList(),
    });
  }

  Future<void> _sse(HttpResponse res) async {
    res.statusCode = HttpStatus.ok;
    res.headers
      ..set(HttpHeaders.contentTypeHeader, 'text/event-stream; charset=utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set('Connection', 'keep-alive');
    StreamSubscription<LogEntry>? sub;
    Timer? hb;
    var closed = false;
    void closer() {
      if (closed) return;
      closed = true;
      hb?.cancel();
      sub?.cancel();
      _sseClosers.remove(closer);
    }

    _sseClosers.add(closer);
    try {
      for (final e in logBus.snapshot) {
        res.write('data: ${jsonEncode(e.toJson())}\n\n');
      }
      await res.flush();
    } catch (_) {
      closer();
      return;
    }
    sub = logBus.watch().listen((e) {
      try {
        res.write('data: ${jsonEncode(e.toJson())}\n\n');
      } catch (_) {
        closer();
      }
    });
    hb = Timer.periodic(const Duration(seconds: 2), (_) {
      try {
        res.write(': ping\n\n');
        res.flush();
      } catch (_) {
        closer();
      }
    });
    await res.done.catchError((_) {});
    closer();
  }
}

/// 局域网服务单例（riverpod 暴露）
final lanServerProvider =
    ChangeNotifierProvider<LanServer>((ref) => LanServer(ref));
