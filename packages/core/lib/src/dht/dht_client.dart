import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'bencode.dart';

/// BitTorrent DHT（Mainline，BEP 5）节点
class DhtNode {
  final InternetAddress address;
  final int port;
  final Uint8List id;

  const DhtNode(this.address, this.port, this.id);

  @override
  bool operator ==(Object other) =>
      other is DhtNode && other.address == address && other.port == port;

  @override
  int get hashCode => Object.hash(address, port);
}

/// get_peers 查询结果
class PeerLookup {
  /// 去重后的 peer 数量（即当前有多少个 IP:Port 在下载/做种）
  final int peerCount;

  /// 实际成功响应的节点数（0 表示本次查询没连上任何节点，结果不可信）
  final int respondedNodes;

  const PeerLookup({required this.peerCount, required this.respondedNodes});

  static const PeerLookup empty = PeerLookup(peerCount: 0, respondedNodes: 0);

  /// 连上过节点但一个 peer 都没有 —— 说明这个 infohash 大概率没人做种了
  bool get isDead => respondedNodes > 0 && peerCount == 0;

  /// 一个节点都没响应 —— 网络不通，结论未知
  bool get unknown => respondedNodes == 0;
}

/// 从磁力链接解析 btih infohash（20 字节）。
/// 支持 40 字符十六进制与 32 字符 base32 两种编码。
Uint8List? infoHashFromMagnet(String url) {
  final m = RegExp(
    r'xt=urn:btih:([A-Za-z0-9]{32,40})',
    caseSensitive: false,
  ).firstMatch(url);
  if (m == null) return null;
  final s = m.group(1)!;
  if (s.length == 40) {
    final bytes = <int>[];
    for (var i = 0; i < 40; i += 2) {
      final v = int.tryParse(s.substring(i, i + 2), radix: 16);
      if (v == null) return null;
      bytes.add(v);
    }
    return Uint8List.fromList(bytes);
  }
  if (s.length == 32) return _base32Decode(s);
  return null;
}

const String _b32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// Base32 解码（RFC 4648，无填充）；磁力链的第二常见编码
Uint8List? _base32Decode(String input) {
  final s = input.toUpperCase();
  var bits = 0;
  var value = 0;
  final out = <int>[];
  for (var i = 0; i < s.length; i++) {
    final idx = _b32Alphabet.indexOf(s[i]);
    if (idx < 0) return null;
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      out.add((value >> (bits - 8)) & 0xFF);
      bits -= 8;
    }
  }
  return out.isEmpty ? null : Uint8List.fromList(out);
}

/// 极简 Mainline DHT 客户端。
///
/// 只实现「按 infohash 查 peer 数」这一件事 —— DHT 协议本身**没有关键词搜索**
/// 能力，只能围绕 infohash 做 find_node / get_peers，所以这里用来做链接热度
/// 与活性判断，而不是拿来搜资源。
class DhtClient {
  DhtClient({Random? random}) : _random = random ?? Random.secure() {
    _nodeId = _randomId();
  }

  static const List<String> bootstrapHosts = [
    'router.bittorrent.com:6881',
    'dht.transmissionbt.com:6881',
    'router.utorrent.com:6881',
  ];

  final Random _random;
  late final Uint8List _nodeId;

  RawDatagramSocket? _socket;
  // 不写 RawDatagramSocketEvent：该类型在 Dart 3.13 已移除，
  // 用 dynamic + 循环 receive() 读取即可（无数据时 receive() 返回 null）
  StreamSubscription<dynamic>? _sub;
  bool _booted = false;
  final List<DhtNode> _routing = <DhtNode>[];
  final Map<String, Completer<Map<String, Object?>?>> _pending =
      <String, Completer<Map<String, Object?>?>>{};

  Uint8List _randomId() {
    final b = Uint8List(20);
    for (var i = 0; i < 20; i++) {
      b[i] = _random.nextInt(256);
    }
    return b;
  }

  String _hex(Uint8List b) =>
      b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  /// 首次使用时建 socket + 引导节点；失败不影响调用方（返回 empty）
  Future<void> _ensureStarted() async {
    if (_booted) return;
    _booted = true;
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _sub = _socket!.listen((_) => _onEvent());
      await _bootstrap();
    } catch (_) {
      // 无网络 / UDP 被拦：保持 _booted，后续查询直接返回 unknown
    }
  }

  /// 收到任意 socket 事件就把接收缓冲区读空
  void _onEvent() {
    final socket = _socket;
    if (socket == null) return;
    while (true) {
      final dg = socket.receive();
      if (dg == null) break;
      _handleMessage(dg.data);
    }
  }

  void _handleMessage(Uint8List data) {
    Map<String, Object?> msg;
    try {
      final decoded = Bencode.decode(data);
      if (decoded is! Map) return;
      msg = decoded.cast<String, Object?>();
    } catch (_) {
      return; // 非 KRPC 流量（或畸形包）直接忽略
    }
    final t = msg['t'];
    if (t is Uint8List) {
      _pending.remove(_hex(t))?.complete(msg);
    }
  }

  Future<void> _bootstrap() async {
    final tasks = bootstrapHosts.map((hp) async {
      final i = hp.lastIndexOf(':');
      if (i <= 0) return;
      final host = hp.substring(0, i);
      final port = int.tryParse(hp.substring(i + 1));
      if (port == null) return;
      InternetAddress? addr;
      try {
        final looked = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 5));
        // **必须优先取 IPv4**：socket 绑的是 anyIPv4，DNS 若先返回 IPv6
        // （Android 上很常见），send() 会直接失败 → 引导不到任何节点，
        // 表现为"已询问 0 个节点"。
        final v4 = looked.where(
            (a) => a.type == InternetAddressType.IPv4);
        addr = v4.isNotEmpty
            ? v4.first
            : (looked.isNotEmpty ? looked.first : null);
      } catch (_) {
        return;
      }
      if (addr == null) return;
      final r = await _query(
        DhtNode(addr, port, Uint8List(20)),
        'find_node',
        {'id': _nodeId, 'target': _nodeId},
        timeout: const Duration(seconds: 3),
      );
      if (r != null) _routing.addAll(_parseNodes(r['r']));
    });
    await Future.wait(tasks);
  }

  /// 预热：引导 + 把路由表填起来。
  ///
  /// DHT 的路由表是靠查询响应里带回的 nodes 逐步积累的，刚启动时
  /// 只有 bootstrap 拿到的寥寥几个节点。实测此时查询会出现
  /// 「只问到 3 个节点就报无做种」的误判，第二次才有几百个 peer。
  /// App 启动时调一次，等用户真正点查询时路由表已经够用。
  Future<void> warmUp() async {
    try {
      await _ensureStarted();
      if (_routing.isEmpty) await _bootstrap();
      // 用随机 target 做几轮 find_node，快速扩大节点面
      for (var i = 0; i < 3; i++) {
        final target = _randomId();
        final batch = _closest(_routing, target, 8);
        if (batch.isEmpty) break;
        final found = await _fanOut(
          candidates: batch,
          query: 'find_node',
          args: {'target': target},
          eachTimeout: const Duration(milliseconds: 1500),
        );
        if (found.isEmpty) break;
        for (final r in found) {
          for (final n in _parseNodes(r['r'])) {
            if (!_routing.contains(n)) _routing.add(n);
          }
        }
      }
    } catch (_) {
      // 预热失败不影响后续查询（查询里还会自己补一次引导）
    }
  }

  /// 当前路由表节点数（诊断用）
  int get routingSize => _routing.length;

  /// 查询某个 infohash 当前有多少 peer
  Future<PeerLookup> getPeers(Uint8List infoHash) async {
    await _ensureStarted();

    // 实测：进程内第一次查询常因 UDP 路径未热 / 引导超时而返回
    // 「响应节点 0」，重试一次就能拿到几百个 peer。这里自动补一次引导 + 重查，
    // 避免把「还没热起来」误报成「网络不通」。
    if (_routing.isEmpty) await _bootstrap();
    if (_routing.isEmpty) {
      return const PeerLookup(peerCount: 0, respondedNodes: 0);
    }

    var result = await _iterate(infoHash);
    if (result.respondedNodes == 0) {
      await _bootstrap();
      if (_routing.isNotEmpty) result = await _iterate(infoHash);
    }
    return result;
  }

  Future<PeerLookup> _iterate(Uint8List infoHash) async {
    try {
      // 标准迭代式 get_peers：每轮向「最近的、还没问过的」节点发查询，
      // 用响应里的 nodes 继续逼近，直到没有更近的节点或到轮数上限。
      //
      // 之前是「先 find_node 逼近 2 轮，再一次性 get_peers」—— 对热门种子
      // 往往还没走到持有该 infohash 的节点就停了，会误报「无做种」。
      final peers = <String>{};
      final queried = <DhtNode>{};
      var responded = 0;
      var shortlist = _closest(_routing, infoHash, 16);

      for (var round = 0; round < 5 && shortlist.isNotEmpty; round++) {
        final batch = shortlist
            .where((n) => !queried.contains(n))
            .take(8)
            .toList();
        if (batch.isEmpty) break;
        queried.addAll(batch);

        final found = await _fanOut(
          candidates: batch,
          query: 'get_peers',
          args: {'info_hash': infoHash},
          eachTimeout: const Duration(milliseconds: 2000),
        );

        final next = <DhtNode>[];
        for (final r in found) {
          responded++;
          peers.addAll(_parsePeers(r['r']));
          next.addAll(_parseNodes(r['r']));
        }
        if (next.isEmpty) break;
        for (final n in next) {
          if (!_routing.contains(n)) _routing.add(n);
        }
        shortlist = _closest([...next, ..._routing], infoHash, 16)
            .where((n) => !queried.contains(n))
            .toList();
      }

      return PeerLookup(peerCount: peers.length, respondedNodes: responded);
    } catch (_) {
      return const PeerLookup(peerCount: 0, respondedNodes: 0);
    }
  }

  /// 并发向多个节点发同一个查询，返回所有成功响应
  Future<List<Map<String, Object?>>> _fanOut({
    required List<DhtNode> candidates,
    required String query,
    required Map<String, Object?> args,
    required Duration eachTimeout,
  }) async {
    final results = await Future.wait(
      candidates.map((n) => _query(
            n,
            query,
            {'id': _nodeId, ...args},
            timeout: eachTimeout,
          )),
    );
    return results.whereType<Map<String, Object?>>().toList();
  }

  Future<Map<String, Object?>?> _query(
    DhtNode node,
    String q,
    Map<String, Object?> args, {
    required Duration timeout,
  }) async {
    final socket = _socket;
    if (socket == null) return null;
    final tid = Uint8List.fromList([
      _random.nextInt(256),
      _random.nextInt(256),
    ]);
    final key = _hex(tid);
    final completer = Completer<Map<String, Object?>?>();
    _pending[key] = completer;
    try {
      socket.send(
        Bencode.encode({'t': tid, 'y': 'q', 'q': q, 'a': args}),
        node.address,
        node.port,
      );
    } catch (_) {
      _pending.remove(key);
      return null;
    }
    try {
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } finally {
      _pending.remove(key);
    }
  }

  /// 按 XOR 距离取最近的 [k] 个节点
  List<DhtNode> _closest(List<DhtNode> nodes, Uint8List target, int k) {
    final sorted = nodes.toList()
      ..sort((a, b) => _compareDistance(a.id, b.id, target));
    return sorted.take(k).toList();
  }

  /// 比较 a、b 谁离 target 更近（-1 表示 a 更近）
  static int _compareDistance(Uint8List a, Uint8List b, Uint8List target) {
    final len = min(a.length, min(b.length, target.length));
    for (var i = 0; i < len; i++) {
      final da = a[i] ^ target[i];
      final db = b[i] ^ target[i];
      if (da != db) return da.compareTo(db);
    }
    return 0;
  }

  /// 解析 nodes 字段：每个节点 26 字节（20 id + 4 ip + 2 port）
  static List<DhtNode> _parseNodes(Object? r) {
    final out = <DhtNode>[];
    if (r is! Map) return out;
    final nodes = r['nodes'];
    if (nodes is! Uint8List) return out;
    for (var i = 0; i + 26 <= nodes.length; i += 26) {
      final id = Uint8List.fromList(nodes.sublist(i, i + 20));
      final addr = InternetAddress.tryParse(
        nodes.sublist(i + 20, i + 24).join('.'),
      );
      if (addr == null) continue;
      final port = (nodes[i + 24] << 8) | nodes[i + 25];
      if (port <= 0) continue;
      out.add(DhtNode(addr, port, id));
    }
    return out;
  }

  /// 解析 values 字段：每个 peer 6 字节（4 ip + 2 port）
  static Set<String> _parsePeers(Object? r) {
    final out = <String>{};
    if (r is! Map) return out;
    final values = r['values'];
    if (values is! List) return out;
    for (final v in values) {
      if (v is! Uint8List || v.length < 6) continue;
      final ip = v.sublist(0, 4).join('.');
      final port = (v[4] << 8) | v[5];
      out.add('$ip:$port');
    }
    return out;
  }

  void dispose() {
    _sub?.cancel();
    _socket?.close();
    _socket = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pending.clear();
  }
}
