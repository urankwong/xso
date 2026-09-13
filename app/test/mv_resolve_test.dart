import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/providers/mv_service.dart';

/// MV 解析实测：B 站 view + playurl 是否真能拿到可播 mp4 直链。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('B 站 MV 直链解析', () async {
    final svc = MvService(Dio());
    final info = await svc.resolve('BV1BdYQ6aEXv');
    // ignore: avoid_print
    print('[MV] ${info.title} | 上传 ${info.artist} | cid ${info.cid}');
    // ignore: avoid_print
    print('[MV] 清晰度 ${info.qualities.map((q) => q.label).join(' / ')}');
    // ignore: avoid_print
    print('[MV] 直链 ${info.urlFor(32).substring(0, 80)}...');
    expect(info.urlFor(32), startsWith('https://'));
    expect(info.headers['Referer'], isNotNull);
  }, timeout: const Timeout(Duration(seconds: 40)));
}
