import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/net/lan_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 局域网助手冒烟：起服务 → 打 /api/status 与 / → 关服务。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues({'lan.enable': true});

  test('局域网服务起停与接口可达', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final server = container.read(lanServerProvider);
    await server.start();
    // ignore: avoid_print
    print('[LAN] running=${server.running} url=${server.url} port=${server.port}');
    expect(server.running, isTrue);

    final client = HttpClient();
    Future<(int, String)> get(String path) async {
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:${server.port}$path'))
          .timeout(const Duration(seconds: 5));
      final resp = await req.close().timeout(const Duration(seconds: 5));
      final body = await resp.transform(utf8.decoder).join();
      return (resp.statusCode, body);
    }

    final (status, body) = await get('/api/status');
    // ignore: avoid_print
    print('[LAN] /api/status -> $status ${body.length > 200 ? body.substring(0, 200) : body}');
    expect(status, 200);
    expect(jsonDecode(body)['enabled'], true);

    final (code, html) = await get('/');
    // ignore: avoid_print
    print('[LAN] / -> $code len=${html.length}');
    expect(code, 200);
    expect(html.length, greaterThan(500));

    // 未开权限时写接口应被拒
    final req = await client
        .postUrl(Uri.parse('http://127.0.0.1:${server.port}/api/sources/import'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'raw': '{}'}));
    final resp = await req.close().timeout(const Duration(seconds: 5));
    final body3 = await resp.transform(utf8.decoder).join();
    // ignore: avoid_print
    print('[LAN] 未授权导入 -> ${resp.statusCode} $body3');
    expect(resp.statusCode, 403);

    client.close(force: true);
    await server.stop();
    expect(server.running, isFalse);
  });
}
