import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// B 站视频的一条清晰度
class MvQuality {
  final int qn; // B 站清晰度编码
  final String label;
  const MvQuality(this.qn, this.label);
}

/// 解析结果：可播放的 mp4 直链（含音视频，免 DASH 合并）
class MvInfo {
  final String bvid;
  final int cid;
  final String title;
  final String artist;
  final String cover;
  final List<MvQuality> qualities;
  final Map<int, String> urls; // qn → mp4 直链
  final Map<String, String> headers; // 播放/下载需带的 Referer/UA

  const MvInfo({
    required this.bvid,
    required this.cid,
    required this.title,
    required this.artist,
    required this.cover,
    required this.qualities,
    required this.urls,
    required this.headers,
  });

  String urlFor(int qn) => urls[qn] ?? urls.values.first;
}

/// B 站 MV/视频解析：view 取 cid 与元信息，playurl 取 mp4 直链。
/// 未登录最高 360P（480P 以上需 Cookie），此处按免登录可用清晰度请求。
class MvService {
  MvService(this._dio);
  final Dio _dio;

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      'Chrome/125.0 Safari/537.36';
  static const _referer = 'https://www.bilibili.com/';

  static const _labels = {
    16: '1080P 高码率(需登录)',
    32: '480P 清晰',
    161: '1080P 高帧率(需登录)',
    74: '720P 60帧(需登录)',
    64: '720P 准高清(需登录)',
    321: '480P',
    2: '480P 清晰',
    1: '360P 流畅',
    0: '360P 流畅',
  };

  Future<MvInfo> resolve(String bvid,
      {String? fallbackTitle, String? cookie, int qn = 32}) async {
    final headers = {
      'User-Agent': _ua,
      'Referer': _referer,
      if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
    };
    final view = await _dio.get<dynamic>(
      'https://api.bilibili.com/x/web-interface/view',
      queryParameters: {'bvid': bvid},
      options: Options(headers: headers, responseType: ResponseType.json),
    );
    final vd = (view.data as Map?)?['data'] as Map?;
    if (vd == null) throw Exception('B 站视频信息获取失败');
    final cid = (vd['pages'] as List?)?.first?['cid'] ?? vd['cid'];
    final title = (vd['title'] ?? fallbackTitle ?? bvid).toString();
    final artist = (vd['owner']?['name'] ?? '').toString();
    final cover = (vd['pic'] ?? '').toString();

    final play = await _dio.get<dynamic>(
      'https://api.bilibili.com/x/player/playurl',
      queryParameters: {
        'bvid': bvid,
        'cid': cid,
        'qn': qn, // 带 Cookie 时可取 720P/1080P
        'fnval': 1, // 只要 mp4（durl），避免 DASH 音视频分离
        'fourier': 'lsid',
      },
      options: Options(headers: headers, responseType: ResponseType.json),
    );
    final pd = (play.data as Map?)?['data'] as Map?;
    final durl = (pd?['durl'] as List?)?.whereType<Map>().toList() ?? const [];
    if (durl.isEmpty) throw Exception('未取到可播放地址（可能需要登录）');

    final accept = ((pd?['accept_quality'] as List?) ?? const [])
        .whereType<int>()
        .toList();
    final qualities = <MvQuality>[
      for (final q in (accept.isEmpty ? [pd?['quality']] : accept))
        if (q != null)
          MvQuality(q as int, _labels[q] ?? '${q}P'),
    ];
    // 免登录只下发一条实际地址，其余清晰度按同一条兜底
    final urls = <int, String>{
      for (final q in qualities) q.qn: durl.first['url'].toString(),
    };

    return MvInfo(
      bvid: bvid,
      cid: cid is int ? cid : int.tryParse('$cid') ?? 0,
      title: title,
      artist: artist,
      cover: cover,
      qualities: qualities.isEmpty
          ? [MvQuality((pd?['quality'] as int?) ?? 32, '默认')]
          : qualities,
      urls: urls.isEmpty ? {32: durl.first['url'].toString()} : urls,
      headers: headers,
    );
  }
}

final mvServiceProvider = Provider<MvService>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    validateStatus: (s) => s != null && s < 500,
  ));
  return MvService(dio);
});
