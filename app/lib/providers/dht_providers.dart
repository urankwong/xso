import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// DHT 客户端（App 级单例）。
///
/// 引导（DNS + find_node 找节点）只做一次并缓存在实例里；
/// 每次查询都 new 一个的话，每次都要重新引导 —— 慢，而且首次
/// 引导失败就会直接给出"已询问 0 个节点"的错误结论。
///
/// 创建时立刻后台预热：DHT 路由表靠查询过程逐步积累，不预热的话
/// 用户第一次点查询很可能只问到几个节点就被判成"暂无做种"。
final dhtClientProvider = Provider<DhtClient>((ref) {
  final client = DhtClient();
  unawaited(client.warmUp());
  ref.onDispose(client.dispose);
  return client;
});
