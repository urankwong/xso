import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 一个可跳转的"收藏条目"：歌单/收藏夹，点入后按 kind 走不同链路
class FavCollection {
  final String kind; // netease_sheet | bilibili_fav | bilibili_audio_fav
  final String id;
  final String title;
  final String? cover;
  final int? count;
  final bool isLiked; // 网易云"我喜欢的音乐"这类特殊歌单

  const FavCollection({
    required this.kind,
    required this.id,
    required this.title,
    this.cover,
    this.count,
    this.isLiked = false,
  });
}

/// B站收藏夹里的视频条目（可直接进 MV 播放页）
class FavVideo {
  final String bvid;
  final String title;
  final String? cover;
  final String? uploader;
  const FavVideo(
      {required this.bvid, required this.title, this.cover, this.uploader});
}

/// 平台账号接口：全部依赖用户自己登录抓到的 Cookie，仅直连官方 Web API。
class AccountService {
  AccountService(this._dio);
  final Dio _dio;

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      'Chrome/125.0 Safari/537.36';

  Map<String, String> _h(String cookie, {String? referer}) => {
        'User-Agent': _ua,
        'Cookie': cookie,
        if (referer != null) 'Referer': referer,
      };

  // ---------- 网易云 ----------

  /// 我的歌单（含"我喜欢的音乐"，specialType==5）
  Future<List<FavCollection>> neteasePlaylists(String cookie) async {
    final nav = await _dio.get<dynamic>(
      'https://music.163.com/api/nuser/account/get',
      options: Options(headers: _h(cookie, referer: 'https://music.163.com/')),
    );
    final uid = ((nav.data as Map?)?['profile']?['userId'])?.toString() ??
        ((nav.data as Map?)?['account']?['id'])?.toString();
    if (uid == null || uid.isEmpty) throw Exception('未登录或 Cookie 已失效');

    final res = await _dio.post<dynamic>(
      'https://music.163.com/api/user/playlist',
      data: FormData.fromMap({'uid': uid, 'offset': '0', 'limit': '100'}),
      options: Options(headers: _h(cookie, referer: 'https://music.163.com/')),
    );
    final list = ((res.data as Map?)?['playlist'] as List?) ?? const [];
    return [
      for (final p in list.whereType<Map>())
        FavCollection(
          kind: 'netease_sheet',
          id: p['id'].toString(),
          title: (p['name'] ?? '未命名歌单').toString(),
          cover: p['coverImgUrl']?.toString(),
          count: (p['trackCount'] as num?)?.toInt(),
          isLiked: (p['specialType'] as num?)?.toInt() == 5,
        ),
    ];
  }

  // ---------- QQ音乐 ----------

  /// 从 cookie 取指定键
  static String? _cookieValue(String cookie, String key) {
    for (final part in cookie.split(RegExp(r';\s*'))) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      if (part.substring(0, i).trim() == key) return part.substring(i + 1).trim();
    }
    return null;
  }

  /// QQ 音乐 g_tk：5381 累加哈希（skey 存在时用 skey，否则 '0'）
  static int gTk(String skey) {
    var hash = 5381;
    for (final code in skey.codeUnits) {
      hash += (hash << 5) + code;
      hash &= 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }

  /// 我的歌单（含"我喜欢"）：musicu.fcg PlayListServer
  Future<List<FavCollection>> qqPlaylists(String cookie) async {
    final rawUin = _cookieValue(cookie, 'uin') ?? '';
    final uin = rawUin.startsWith('p_') || rawUin.startsWith('P_')
        ? rawUin.substring(rawUin.indexOf('_') + 1)
        : rawUin;
    final skey = _cookieValue(cookie, 'skey') ?? '0';
    if (uin.isEmpty) throw Exception('Cookie 缺少 uin，请在 QQ音乐 登录后重试');

    final payload = {
      'comm': {'ct': 11, 'g_tk': gTk(skey), 'uin': uin, 'format': 'json'},
      'req': {
        'module': 'music.musichallPlaylist.PlayListServer',
        'method': 'get_play_list',
        'param': {
          'folderType': 1,
          'start': 0,
          'size': 50,
          'loginUin': uin,
          'isGetCoverUrl': 1,
          'sin': 0,
        },
      },
    };
    final res = await _dio.get<dynamic>(
      'https://u.y.qq.com/cgi-bin/musicu.fcg',
      queryParameters: {'format': 'json', 'data': jsonEncode(payload)},
      options: Options(headers: _h(cookie, referer: 'https://y.qq.com/')),
    );
    final folders = ((((res.data as Map?)?['req'] as Map?)?['data']
                ?['v_list'] as List?) ??
            const [])
        .whereType<Map>();
    return [
      for (final f in folders)
        FavCollection(
          kind: 'qqmusic_sheet',
          id: (f['dissid'] ?? f['id'] ?? '').toString(),
          title: (f['dissname'] ?? '未命名歌单').toString(),
          cover: f['imgurl']?.toString(),
          count: (f['total_dissnum'] as num?)?.toInt() ??
              (f['song_count'] as num?)?.toInt(),
          isLiked: (f['dissname'] ?? '').toString().contains('我喜欢'),
        ),
    ];
  }

  /// 红心（我喜欢的歌曲）列表
  Future<List<FavCollection>> qqLikedFolder(String cookie) async =>
      qqPlaylists(cookie);

  // ---------- B站 ----------

  /// 我的信息（mid / 昵称 / 大会员）
  Future<Map<String, dynamic>> bilibiliNav(String cookie) async {
    final res = await _dio.get<dynamic>(
      'https://api.bilibili.com/x/web-interface/nav',
      options: Options(headers: _h(cookie, referer: 'https://www.bilibili.com/')),
    );
    final data = (res.data as Map?)?['data'] as Map?;
    if (data == null || data['isLogin'] != true) {
      throw Exception('未登录或 Cookie 已失效');
    }
    return Map<String, dynamic>.from(data);
  }

  /// 我创建/收藏的视频收藏夹
  Future<List<FavCollection>> bilibiliFolders(String cookie, int mid) async {
    final res = await _dio.get<dynamic>(
      'https://api.bilibili.com/x/v3/fav/folder/created/list-all',
      queryParameters: {'up_mid': mid},
      options: Options(headers: _h(cookie, referer: 'https://www.bilibili.com/')),
    );
    final list = ((res.data as Map?)?['list'] as List?) ?? const [];
    return [
      for (final f in list.whereType<Map>())
        FavCollection(
          kind: 'bilibili_fav',
          id: f['id'].toString(),
          title: (f['title'] ?? '未命名收藏夹').toString(),
          cover: f['cover']?.toString(),
          count: (f['media_count'] as num?)?.toInt(),
        ),
    ];
  }

  /// 收藏夹内容（视频条目，可进 MV 播放）
  Future<List<FavVideo>> bilibiliFolderContents(
      String cookie, String mediaId,
      {int page = 1}) async {
    final res = await _dio.get<dynamic>(
      'https://api.bilibili.com/x/v3/fav/folder/contents',
      queryParameters: {'media_id': mediaId, 'pn': page, 'ps': 20},
      options: Options(headers: _h(cookie, referer: 'https://www.bilibili.com/')),
    );
    final list = ((res.data as Map?)?['list'] as List?) ?? const [];
    return [
      for (final v in list.whereType<Map>())
        if (((v['bv_id'] ?? v['bvid']) ?? '').toString().isNotEmpty)
          FavVideo(
            bvid: (v['bv_id'] ?? v['bvid']).toString(),
            title: (v['title'] ?? '').toString(),
            cover: v['cover']?.toString(),
            uploader: (v['upper'] as Map?)?['name']?.toString(),
          ),
    ];
  }

  /// 我的收藏音频（B站音乐区收藏）
  Future<List<FavCollection>> bilibiliAudioCollections(String cookie) async {
    final res = await _dio.get<dynamic>(
      'https://api.bilibili.com/audio/collection/favlist',
      queryParameters: {'pn': 1, 'ps': 20},
      options: Options(
          headers: _h(cookie, referer: 'https://music.bilibili.com/')),
    );
    final list = (((res.data as Map?)?['data'] as Map?)?['list'] as List?) ??
        ((res.data as Map?)?['list'] as List?) ??
        const [];
    return [
      for (final c in list.whereType<Map>())
        FavCollection(
          kind: 'bilibili_audio_fav',
          id: (c['id'] ?? c['collection_id']).toString(),
          title: (c['title'] ?? '未命名音频收藏').toString(),
          cover: c['cover']?.toString(),
          count: (c['count'] as num?)?.toInt(),
        ),
    ];
  }
}

final accountServiceProvider = Provider<AccountService>((ref) {
  return AccountService(Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    validateStatus: (s) => s != null && s < 500,
  )));
});
