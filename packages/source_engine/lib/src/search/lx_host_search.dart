/// 洛雪宿主侧搜索器（Host-side search）。
///
/// ## 背景
/// 洛雪自定义源协议规定：**源只负责 `musicUrl` / `pic` / `lyric`，搜索是宿主的职责**。
/// 因此标准洛雪源在 xso 里「搜不到歌」并不是源残缺，而是缺宿主侧搜索。
/// 本模块把 lx-music-desktop 的官方搜索实现移植进 JS 沙箱，补齐这块能力。
///
/// ## 移植来源（lyswhut/lx-music-desktop @master）
/// - `src/renderer/utils/musicSdk/kg/musicSearch.js` → [kgSearch]（明文 GET，无签名）
/// - `src/renderer/utils/musicSdk/kw/musicSearch.js` → [kwSearch]（明文 GET，无签名）
/// - `src/renderer/utils/musicSdk/tx/musicSearch.js` → [txSearch]
/// - `src/renderer/utils/musicSdk/wy/musicSearch.js` → [wySearch]
/// - `src/renderer/utils/musicSdk/mg/musicSearch.js` → [mgSearch]
/// - `src/renderer/utils/musicSdk/tx/utils/crypto.js` → zzcSign（QQ音乐签名）
/// - `src/renderer/utils/musicSdk/wy/utils/crypto.js` → eapi（网易 EAPI 加密）
/// - `src/renderer/utils/index.js`        → formatPlayTime / sizeFormate / decodeName
/// - `src/renderer/utils/musicSdk/utils.js` → formatSingerName
/// - `src/renderer/request.js`            → httpFetch（改为走 `__jsHost.request` 宿主桥）
///
/// ## 签名/加密的处理
/// 洛雪原实现依赖 `node:crypto`，沙箱内没有，一律改用宿主注入的 CryptoJS：
/// - QQ音乐 tx：SHA1 + 位重排/XOR + Base64 → `zzc…`
/// - 网易 wy：MD5 + AES-128-ECB → EAPI `params`
/// - 咪咕 mg：纯 MD5，无其它依赖
///
/// ## 网络
/// 沙箱内不发起真实网络：与 MusicFree / Lx 适配器同一条通道，
/// 经 `__jsHost.request` 交由 Dart 侧执行（便于统一超时、UA、Cookie、证书处理）。
///
/// ## 产出的 musicInfo 结构
/// 与洛雪源 `action='musicUrl'` 的期望**逐字段对齐**：
/// - 酷狗：`hash`(FileHash) / `songmid`(Audioid) / `albumAudioId`(MixSongID) / `albumId` / `types`
/// - 酷我：`songmid`(MUSICRID 去掉前缀) / `albumId` / `types`
/// 实测验证：宿主搜索产出的 `hash` 与源取链实际请求的 id 一致（如 B3A52A7A…）。
library;

/// 宿主搜索 bundle：注入沙箱后暴露
/// `__lxHostSearchRun(platform, keyword, page, limit)` 与配套的
/// `__lxHostSearchStart/Take` 异步取结果桥。
class LxHostSearchBundle {
  static const String js = r'''
(function(){
  // ================= 工具（等价 src/renderer/utils/index.js）=================
  var ENTITY = { amp:'&', lt:'<', gt:'>', quot:'"', apos:"'", nbsp:' ' };
  function decodeName(s){
    if (s == null) return s;
    return String(s)
      .replace(/&(amp|lt|gt|quot|apos|nbsp);/g, function(_, e){ return ENTITY[e]; })
      .replace(/&#(\d+);/g, function(_, n){ return String.fromCharCode(Number(n)); })
      .replace(/&#x([0-9a-f]+);/gi, function(_, n){ return String.fromCharCode(parseInt(n,16)); });
  }
  function pad2(n){ n = String(n); return n.length < 2 ? '0' + n : n; }
  function formatPlayTime(sec){
    if (!sec) return '00:00';
    var s = Math.round(sec), m = Math.floor(s/60);
    return pad2(m) + ':' + pad2(s % 60);
  }
  function sizeFormate(size){
    if (!size) return '0B';
    var units = ['B','KB','MB','GB'], i = 0, n = Number(size);
    while (n >= 1024 && i < units.length - 1) { n /= 1024; i++; }
    return (i === 0 ? String(n) : n.toFixed(2)) + units[i];
  }
  // 等价 src/renderer/utils/musicSdk/utils.js
  function formatSingerName(singers, nameKey, join){
    nameKey = nameKey || 'name'; join = join || '\u3001';
    if (Object.prototype.toString.call(singers) === '[object Array]'){
      var out = [];
      for (var i = 0; i < singers.length; i++){
        var nm = singers[i] && singers[i][nameKey];
        if (nm) out.push(nm);
      }
      return decodeName(out.join(join));
    }
    return decodeName(String(singers == null ? '' : singers));
  }
  // ================= 网络：等价 src/renderer/request.js 的 httpFetch =================
  // 差异：不直接发请求，改走宿主桥 __jsHost.request（Dart 侧用 dio 执行）
  function urlEncode(obj){
    var parts = [];
    for (var k in obj) {
      if (!Object.prototype.hasOwnProperty.call(obj, k)) continue;
      parts.push(encodeURIComponent(k) + '=' + encodeURIComponent(String(obj[k])));
    }
    return parts.join('&');
  }
  function httpFetch(url, options){
    options = options || {};
    var headers = {};
    for (var k in (options.headers || {})) headers[k] = options.headers[k];
    var body = options.body;
    if (body != null && typeof body !== 'string') {
      // 对象 body：与洛雪一致按 JSON 发送
      body = JSON.stringify(body);
      headers['Content-Type'] = 'application/json';
    }
    // form：application/x-www-form-urlencoded（网易 EAPI 用）
    if (options.form != null) {
      body = typeof options.form === 'string' ? options.form : urlEncode(options.form);
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    return __jsHost.request({
      url: url,
      method: options.method || 'GET',
      headers: headers,
      body: body == null ? null : body
    }).then(function(resp){
      var text = resp && resp.data;
      if (text == null) text = '';
      return { statusCode: (resp && resp.status) || 0, headers: (resp && resp.headers) || {}, body: text };
    });
  }
  function parseBody(text){
    try { return JSON.parse(text); } catch (_) {}
    // 酷我偶发单引号 JSON：等价 kw/util.js 的 objStr2JSON（此处用无 lookbehind 的等价写法，
    // 保证老版 QuickJS 也能跑）
    try {
      var fixed = String(text)
        .replace(/([{,]\s*)'([^']*)'(\s*:)/g, '$1"$2"$3')
        .replace(/:\s*'([^']*)'/g, ': "$1"');
      return JSON.parse(fixed);
    } catch (e) {
      throw new Error('返回非 JSON: ' + String(text).slice(0, 120));
    }
  }
  // 宿主桥可能已代为 JSON 解析（返回对象），也可能给文本 —— 两者都收
  function asJson(v){
    if (v == null) throw new Error('空响应');
    if (typeof v === 'object') return v;
    return parseBody(v);
  }
  function fail(msg){ var e = new Error(msg); throw e; }

  // ================= 加密工具（宿主已注入 CryptoJS）=================
  // 沙箱无 node:crypto，SHA1/MD5/AES 一律走 CryptoJS（app/lib/runtime 注入）
  function cryptoReady(){
    return typeof CryptoJS !== 'undefined' && CryptoJS && CryptoJS.SHA1;
  }
  function md5Hex(s){ return CryptoJS.MD5(String(s)).toString(); }
  function sha1Hex(s){ return CryptoJS.SHA1(String(s)).toString(); }
  function b64FromBytes(bytes){
    var words = [];
    for (var i = 0; i < bytes.length; i += 4) {
      words.push((((bytes[i] || 0) << 24) | ((bytes[i+1] || 0) << 16) | ((bytes[i+2] || 0) << 8) | (bytes[i+3] || 0)) | 0);
    }
    return CryptoJS.enc.Base64.stringify(CryptoJS.lib.WordArray.create(words, bytes.length));
  }

  // ================= 酷狗：移植 kg/musicSearch.js =================
  function kgFilterData(raw){
    var types = [], _types = {};
    if (raw.FileSize !== 0)     { var s1 = sizeFormate(raw.FileSize);    types.push({type:'128k',      size:s1, hash:raw.FileHash});    _types['128k']      = {size:s1, hash:raw.FileHash}; }
    if (raw.HQFileSize !== 0)   { var s2 = sizeFormate(raw.HQFileSize);  types.push({type:'320k',      size:s2, hash:raw.HQFileHash}); _types['320k']      = {size:s2, hash:raw.HQFileHash}; }
    if (raw.SQFileSize !== 0)   { var s3 = sizeFormate(raw.SQFileSize);  types.push({type:'flac',      size:s3, hash:raw.SQFileHash}); _types.flac         = {size:s3, hash:raw.SQFileHash}; }
    if (raw.ResFileSize !== 0)  { var s4 = sizeFormate(raw.ResFileSize); types.push({type:'flac24bit', size:s4, hash:raw.ResFileHash});_types.flac24bit    = {size:s4, hash:raw.ResFileHash}; }
    return {
      singer: decodeName(formatSingerName(raw.Singers, 'name')),
      name: decodeName(String(raw.OriSongName || '') + (raw.Suffix ? ' ' + raw.Suffix : '')),
      albumName: decodeName(raw.AlbumName),
      albumId: raw.AlbumID,
      songmid: raw.Audioid,
      albumAudioId: raw.MixSongID,
      source: 'kg',
      interval: formatPlayTime(raw.Duration),
      _interval: raw.Duration,
      img: raw.web_albumpic_short || null, lrc: null, otherSource: null,
      hash: raw.FileHash,
      types: types, _types: _types, typeUrl: {}
    };
  }
  function kgHandleResult(rawData){
    var ids = {}, list = [];
    for (var i = 0; i < rawData.length; i++){
      var item = rawData[i];
      var key = item.Audioid + item.FileHash;
      if (!ids[key]) { ids[key] = 1; list.push(kgFilterData(item)); }
      var grp = item.Grp || [];
      for (var j = 0; j < grp.length; j++){
        if (ids[key]) continue;
        ids[key] = 1;
        list.push(kgFilterData(grp[j]));
      }
    }
    return list;
  }
  function kgSearch(keyword, page, limit){
    page = page || 1; limit = limit || 30;
    var url = 'http://songsearch.kugou.com/song_search_v2?platform=AndroidFilter&iscorrection=1'
      + '&keyword=' + encodeURIComponent(keyword)
      + '&hifiquality=0&pagesize=' + limit + '&PrivilegeFilter=0&page=' + page;
    return httpFetch(url).then(function(resp){
      var body = parseBody(resp.body);
      if (!body || body.error_code !== 0) fail('酷狗搜索失败 error_code=' + (body && body.error_code));
      var list = kgHandleResult(body.data.lists);
      var total = body.data.total;
      return { list: list, total: total, allPage: Math.ceil(total / limit), source: 'kg', isEnd: list.length < limit };
    });
  }

  // ================= 酷我：移植 kw/musicSearch.js =================
  var KW_MINFO = /level:(\w+),bitrate:(\d+),format:(\w+),size:([\w.]+)/;
  function kwHandleResult(rawData){
    var result = [];
    if (!rawData) return result;
    for (var i = 0; i < rawData.length; i++){
      var info = rawData[i];
      var songId = String(info.MUSICRID).replace('MUSIC_', '');
      if (!info.N_MINFO) return null;
      var types = [], _types = {};
      var arr = String(info.N_MINFO).split(';');
      for (var k = 0; k < arr.length; k++){
        var m = arr[k].match(KW_MINFO);
        if (!m) continue;
        var up = String(m[4]).toUpperCase();
        if (m[2] === '4000')      { types.push({type:'flac24bit', size:m[4]}); _types.flac24bit = {size:up}; }
        else if (m[2] === '2000') { types.push({type:'flac',      size:m[4]}); _types.flac      = {size:up}; }
        else if (m[2] === '320')  { types.push({type:'320k',      size:m[4]}); _types['320k']   = {size:up}; }
        else if (m[2] === '128')  { types.push({type:'128k',      size:m[4]}); _types['128k']   = {size:up}; }
      }
      types.reverse();
      var iv = parseInt(info.DURATION);
      result.push({
        name: decodeName(info.SONGNAME),
        // 等价 kw/util.js 的 formatSinger：& → 、
        singer: decodeName(String(info.ARTIST || '').replace(/&/g, '\u3001')),
        source: 'kw',
        songmid: songId,
        albumId: decodeName(info.ALBUMID || ''),
        interval: isNaN(iv) ? 0 : formatPlayTime(iv),
        albumName: info.ALBUM ? decodeName(info.ALBUM) : '',
        lrc: null, img: info.web_albumpic_short ? ('http://img1.kuwo.cn/' + info.web_albumpic_short) : null, otherSource: null,
        types: types, _types: _types, typeUrl: {}
      });
    }
    return result;
  }
  function kwSearch(keyword, page, limit){
    page = page || 1; limit = limit || 30;
    var url = 'http://search.kuwo.cn/r.s?client=kt&all=' + encodeURIComponent(keyword)
      + '&pn=' + (page - 1) + '&rn=' + limit
      + '&uid=794762570&ver=kwplayer_ar_9.2.2.1&vipver=1&show_copyright_off=1&newver=1'
      + '&ft=music&cluster=0&strategy=2012&encoding=utf8&rformat=json&vermerge=1&mobi=1&issubtitle=1';
    return httpFetch(url).then(function(resp){
      var body = parseBody(resp.body);
      if (!body || (body.TOTAL !== '0' && body.SHOW === '0')) fail('酷我搜索失败');
      var list = kwHandleResult(body.abslist);
      if (list == null) fail('酷我结果解析失败');
      var total = parseInt(body.TOTAL) || list.length;
      return { list: list, total: total, allPage: Math.ceil(total / limit), source: 'kw', isEnd: list.length < limit };
    });
  }

  // ================= QQ音乐：移植 tx/musicSearch.js（签名 zzcSign 来自 tx/utils/crypto.js）=================
  // zzcSign：SHA1(text) → 按固定下标摘取两段 → 前 20 字节与常量表 XOR → base64（去掉 \/+ =）
  var ZZC_P1 = [23, 14, 6, 36, 16, 40, 7, 19];
  var ZZC_P2 = [16, 1, 32, 12, 19, 27, 8, 5];
  var ZZC_SCRAMBLE = [89, 39, 179, 150, 218, 82, 58, 252, 177, 52, 186, 123, 120, 64, 242, 133, 143, 161, 121, 179];
  function zzcSign(text){
    var hash = sha1Hex(String(text)); // 40 位十六进制
    function pick(idx){
      var out = '';
      for (var i = 0; i < idx.length; i++) out += hash.charAt(idx[i]);
      return out;
    }
    var bytes = [];
    for (var i = 0; i < ZZC_SCRAMBLE.length; i++) {
      bytes.push((ZZC_SCRAMBLE[i] ^ parseInt(hash.slice(i * 2, i * 2 + 2), 16)) & 0xff);
    }
    var b64 = b64FromBytes(bytes).replace(/[\\/+=]/g, '');
    return ('zzc' + pick(ZZC_P1) + b64 + pick(ZZC_P2)).toLowerCase();
  }
  // PC 客户端版 searchid：32 位大写十六进制 + 5 位补零随机数（服务端只需唯一会话 ID）
  function txSearchId(){
    var guid = '';
    for (var i = 0; i < 32; i++) guid += Math.floor(Math.random() * 16).toString(16);
    var pad = String(Math.floor(Math.random() * 100000));
    while (pad.length < 5) pad = '0' + pad;
    return guid.toUpperCase() + pad;
  }
  function txHandleResult(rawList){
    if (!rawList || Object.prototype.toString.call(rawList) !== '[object Array]') return [];
    var list = [];
    for (var i = 0; i < rawList.length; i++) {
      var item = rawList[i];
      var file = item.file || {};
      if (!file.media_mid) continue;
      var types = [], _types = {};
      if (file.size_128mp3 != 0) { var s1 = sizeFormate(file.size_128mp3); types.push({type:'128k', size:s1}); _types['128k'] = {size:s1}; }
      if (file.size_320mp3 !== 0) { var s2 = sizeFormate(file.size_320mp3); types.push({type:'320k', size:s2}); _types['320k'] = {size:s2}; }
      if (file.size_flac !== 0) { var s3 = sizeFormate(file.size_flac); types.push({type:'flac', size:s3}); _types.flac = {size:s3}; }
      if (file.size_hires !== 0) { var s4 = sizeFormate(file.size_hires); types.push({type:'flac24bit', size:s4}); _types.flac24bit = {size:s4}; }
      var albumId = '', albumName = '';
      if (item.album) { albumName = item.album.name; albumId = item.album.mid; }
      list.push({
        singer: formatSingerName(item.singer, 'name'),
        name: item.title,
        albumName: albumName,
        albumId: albumId,
        source: 'tx',
        interval: item.interval ? formatPlayTime(item.interval) : null,
        songId: item.id,
        albumMid: item.album && item.album.mid ? item.album.mid : '',
        strMediaMid: file.media_mid,
        songmid: item.mid,
        img: (albumId === '' || albumId === '空')
          ? (item.singer && item.singer.length ? 'https://y.gtimg.cn/music/photo_new/T001R500x500M000' + item.singer[0].mid + '.jpg' : '')
          : 'https://y.gtimg.cn/music/photo_new/T002R500x500M000' + albumId + '.jpg',
        types: types, _types: _types, typeUrl: {}
      });
    }
    return list;
  }
  function txSearch(keyword, page, limit){
    page = page || 1; limit = limit || 50;
    if (!cryptoReady()) fail('缺少 CryptoJS（QQ音乐签名需要 SHA1）');
    var data = {
      comm: {
        _channelid: '0', _os_version: '6.2.9200-2', ct: '19', cv: '2151',
        guid: '1F70E520B2EAA7D25E11760783C53CA9', patch: '118',
        psrf_access_token_expiresAt: 0, psrf_qqaccess_token: '',
        psrf_qqopenid: '', psrf_qqunionid: '', tmeAppID: 'qqmusic',
        tmeLoginType: 0, uin: '0', wid: '7223299733393904640'
      },
      'music.search.SearchCgiService': {
        module: 'music.search.SearchCgiService',
        method: 'DoSearchForQQMusicDesktop',
        param: {
          grp: 1, num_per_page: limit, page_num: page, query: keyword,
          remoteplace: 'txt.newclient.top', search_type: 0, searchid: txSearchId()
        }
      }
    };
    return httpFetch('https://u.y.qq.com/cgi-bin/musics.fcg?sign=' + zzcSign(JSON.stringify(data)), {
      method: 'post',
      headers: { 'User-Agent': 'QQMusic 14090508(android 12)' },
      body: data
    }).then(function(resp){
      var body = asJson(resp.body);
      // 服务端偶返回空壳，重试一次即可（可这里是单次调用，故只做校验）
      var req = (body && body['music.search.SearchCgiService']) || (body && body.req);
      if (!req || body.code != 0 || req.code != 0) fail('QQ音乐搜索失败 code=' + (body && body.code) + '/' + (req && req.code));
      var list = txHandleResult(req.data && req.data.body && req.data.body.song ? req.data.body.song.list : []);
      var meta = (req.data && req.data.meta) || {};
      var total = meta.sum || 0;
      return { list: list, total: total, allPage: Math.ceil(total / limit), source: 'tx', isEnd: list.length < limit };
    });
  }

  // ================= 网易云：移植 wy/musicSearch.js（EAPI 加密来自 wy/utils/crypto.js）=================
  var WY_EAPI_KEY = 'e82ckenh8dichen8';
  // eapi：MD5(`nobody${url}use${text}md5forencrypt`) → `${url}-36cd479b6b5-${text}-36cd479b6b5-${digest}`
  //      → AES-128-ECB(eapiKey) → hex 大写
  function wyEapiParams(url, object){
    var text = typeof object === 'object' ? JSON.stringify(object) : String(object);
    var digest = md5Hex('nobody' + url + 'use' + text + 'md5forencrypt');
    var data = url + '-36cd479b6b5-' + text + '-36cd479b6b5-' + digest;
    var key = CryptoJS.enc.Utf8.parse(WY_EAPI_KEY);
    var enc = CryptoJS.AES.encrypt(data, key, {
      mode: CryptoJS.mode.ECB, padding: CryptoJS.pad.Pkcs7, iv: CryptoJS.lib.WordArray.create()
    });
    return CryptoJS.enc.Hex.stringify(enc.ciphertext).toUpperCase();
  }
  function wyHandleResult(rawList){
    if (!rawList) return [];
    var list = [];
    for (var i = 0; i < rawList.length; i++) {
      // v3 结构：外层 {simpleSongData:{...}} / 新版在 baseInfo.simpleSongData
      var raw = rawList[i];
      raw = raw.baseInfo && raw.baseInfo.simpleSongData ? raw.baseInfo.simpleSongData
          : (raw.simpleSongData || raw.resources || raw);
      if (!raw || !raw.name) continue;
      var types = [], _types = {};
      var priv = raw.privilege || {};
      var size;
      if (priv.maxBrLevel === 'hires') {
        size = raw.hr ? sizeFormate(raw.hr.size) : null;
        types.push({type:'flac24bit', size:size}); _types.flac24bit = {size:size};
      }
      // 原实现故意不加 break（高码率含低码率）
      switch (priv.maxbr) {
        case 999000: size = raw.sq ? sizeFormate(raw.sq.size) : null; types.push({type:'flac', size:size}); _types.flac = {size:size};
        case 320000: size = raw.h ? sizeFormate(raw.h.size) : null;  types.push({type:'320k', size:size}); _types['320k'] = {size:size};
        case 192000:
        case 128000: size = raw.l ? sizeFormate(raw.l.size) : null;  types.push({type:'128k', size:size}); _types['128k'] = {size:size};
      }
      types.reverse();
      var singers = [];
      if (raw.ar) for (var j = 0; j < raw.ar.length; j++) singers.push(raw.ar[j].name);
      list.push({
        singer: decodeName(singers.join('\u3001')),
        name: raw.name,
        albumName: raw.al ? raw.al.name : '',
        albumId: raw.al ? raw.al.id : '',
        source: 'wy',
        interval: formatPlayTime((raw.dt || 0) / 1000),
        songmid: raw.id,
        img: raw.al ? raw.al.picUrl : '',
        lrc: null,
        types: types, _types: _types, typeUrl: {}
      });
    }
    return list;
  }
  function wySearch(keyword, page, limit){
    page = page || 1; limit = limit || 30;
    if (!cryptoReady()) fail('缺少 CryptoJS（网易 EAPI 需要 MD5/AES）');
    var api = '/api/search/song/list/page';
    var params = wyEapiParams(api, {
      keyword: keyword,
      needCorrect: '1',
      channel: 'typing',
      offset: limit * (page - 1),
      scene: 'normal',
      total: page == 1,
      limit: limit
    });
    var headers = {
      'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.90 Safari/537.36',
      origin: 'https://music.163.com',
      referer: 'https://music.163.com/'
    };
    // Android 9+ 默认禁明文 HTTP，优先 https；失败退 http
    function attempt(base){
      return httpFetch(base + '/eapi/batch', { method: 'post', headers: headers, form: { params: params } });
    }
    return attempt('https://interface.music.163.com')
      .catch(function(e){ return attempt('http://interface.music.163.com'); })
      .then(function(resp){
        var result = asJson(resp.body);
        if (!result || result.code !== 200) fail('网易搜索失败 code=' + (result && result.code));
        var list = wyHandleResult((result.data && result.data.resources) || []);
        if (!list.length) fail('网易搜索无结果');
        var total = (result.data && result.data.totalCount) || 0;
        return { list: list, total: total, allPage: Math.ceil(total / limit), source: 'wy', isEnd: list.length < limit };
      });
  }

  // ================= 咪咕：移植 mg/musicSearch.js（签名为 MD5，无外部依赖）=================
  function mgSearch(keyword, page, limit){
    page = page || 1; limit = limit || 20;
    if (!cryptoReady()) fail('缺少 CryptoJS（咪咕签名需要 MD5）');
    var deviceId = '963B7AA0D21511ED807EE5846EC87D20';
    var time = String(Date.now());
    // createSignature(time, str)：MD5(str + '6cdc72a4…' + 'yyapp2' + 'd1614878…' + deviceId + time)
    var sign = md5Hex(keyword + '6cdc72a439cef99a3418d2a78aa28c73yyapp2d16148780a1dcc7408e06336b98cfd50' + deviceId + time);
    var url = 'https://jadeite.migu.cn/music_search/v3/search/searchAll'
      + '?isCorrect=0&isCopyright=1'
      + '&searchSwitch=' + encodeURIComponent('{"song":1,"album":0,"singer":0,"tagSong":1,"mvSong":0,"bestShow":1,"songlist":0,"lyricSong":0}')
      + '&pageSize=' + limit + '&text=' + encodeURIComponent(keyword)
      + '&pageNo=' + page + '&sort=0&sid=USS';
    return httpFetch(url, {
      headers: {
        uiVersion: 'A_music_3.6.1',
        deviceId: deviceId,
        timestamp: time,
        sign: sign,
        channel: '0146921',
        'User-Agent': 'Mozilla/5.0 (Linux; U; Android 11.0.0; zh-cn; MI 11 Build/OPR1.170623.032) AppleWebKit/534.30 (KHTML, like Gecko) Version/4.0 Mobile Safari/534.30'
      }
    }).then(function(resp){
      var result = asJson(resp.body);
      if (!result || result.code !== '000000') fail('咪咕搜索失败 code=' + (result && result.code));
      var songData = result.songResultData || { resultList: [], totalCount: 0 };
      var list = mgFilterData(songData.resultList);
      var total = parseInt(songData.totalCount) || 0;
      return { list: list, total: total, allPage: Math.ceil(total / limit), source: 'mg', isEnd: list.length < limit };
    });
  }
  function mgFilterData(rawData){
    var list = [], seen = {};
    if (!rawData) return list;
    for (var i = 0; i < rawData.length; i++) {
      var grp = rawData[i] || [];
      for (var j = 0; j < grp.length; j++) {
        var d = grp[j];
        if (!d.songId || !d.copyrightId || seen[d.copyrightId]) continue;
        seen[d.copyrightId] = 1;
        var types = [], _types = {};
        var af = d.audioFormats || [];
        for (var k = 0; k < af.length; k++) {
          var size = sizeFormate(af[k].asize != null ? af[k].asize : af[k].isize);
          switch (af[k].formatType) {
            case 'PQ':   types.push({type:'128k', size:size});      _types['128k'] = {size:size}; break;
            case 'HQ':   types.push({type:'320k', size:size});      _types['320k'] = {size:size}; break;
            case 'SQ':   types.push({type:'flac', size:size});      _types.flac = {size:size}; break;
            case 'ZQ24': types.push({type:'flac24bit', size:size}); _types.flac24bit = {size:size}; break;
          }
        }
        var img = d.img3 || d.img2 || d.img1 || null;
        if (img && !/https?:/.test(d.img3)) img = 'http://d.musicapp.migu.cn' + img;
        list.push({
          singer: formatSingerName(d.singerList),
          name: d.name,
          albumName: d.album,
          albumId: d.albumId,
          songmid: d.songId,
          copyrightId: d.copyrightId,
          source: 'mg',
          interval: formatPlayTime(d.duration),
          img: img,
          lrc: null, lrcUrl: d.lrcUrl, mrcUrl: d.mrcurl, trcUrl: d.trcUrl,
          types: types, _types: _types, typeUrl: {}
        });
      }
    }
    return list;
  }

  // ================= 注册 =================
  globalThis.__lxHostSearch = { kg: kgSearch, kw: kwSearch, tx: txSearch, wy: wySearch, mg: mgSearch };
  globalThis.__lxHostSearchRun = function(platform, keyword, page, limit){
    var fn = globalThis.__lxHostSearch[platform];
    if (!fn) return Promise.reject(new Error('宿主搜索未支持的平台: ' + platform));
    return fn(keyword, page, limit);
  };
  // 异步取结果桥（与 __lxSearchStart/Take 同构，供 Dart 侧轮询）
  globalThis.__lxHostSearchState = { result: '__pending__' };
  globalThis.__lxHostSearchStart = function(platform, keyword, page, limit){
    globalThis.__lxHostSearchState.result = '__pending__';
    Promise.resolve()
      .then(function(){ return globalThis.__lxHostSearchRun(platform, keyword, page, limit); })
      .then(function(r){ globalThis.__lxHostSearchState.result = JSON.stringify(r === undefined ? null : r); })
      .catch(function(e){ globalThis.__lxHostSearchState.result = JSON.stringify({ __error: (e && e.message) || String(e) }); });
    return 1;
  };
  globalThis.__lxHostSearchTake = function(){ return globalThis.__lxHostSearchState.result; };
  // 该平台是否有宿主搜索实现
  globalThis.__lxHostSearchHas = function(platform){
    return !!globalThis.__lxHostSearch[platform];
  };

  // ================= 专辑搜索（5 平台）=================
  function wyAlbumSearch(keyword, page, limit){
    page = page || 1; limit = limit || 30;
    var url = 'https://music.163.com/api/search/album?os=pc&s=' + encodeURIComponent(keyword)
      + '&limit=' + limit + '&offset=' + (limit * (page - 1));
    return httpFetch(url, {headers: {Referer: 'https://music.163.com/', 'User-Agent': 'Mozilla/5.0'}}).then(function(resp){
      var body = asJson(resp.body);
      if (!body || body.code !== 200) fail('网易专辑搜索失败');
      var albums = (body.result && body.result.albums) || [];
      var list = [];
      for (var i = 0; i < albums.length; i++){
        var a = albums[i];
        list.push({
          albumId: a.id, albumName: a.name,
          singer: a.artist ? a.artist.name : '',
          img: a.picUrl || '', source: 'wy',
          songCount: a.size || 0, publishTime: a.publishTime || 0
        });
      }
      var total = (body.result && body.result.albumCount) || list.length;
      return { list: list, total: total, source: 'wy', isEnd: list.length < limit };
    });
  }
  function kgAlbumSearch(keyword, page, limit){
    page = page || 1; limit = limit || 30;
    var url = 'http://mobilecdn.kugou.com/api/v3/search/album?keyword=' + encodeURIComponent(keyword)
      + '&page=' + page + '&pagesize=' + limit;
    return httpFetch(url).then(function(resp){
      var body = asJson(resp.body);
      if (!body || body.status !== 1) fail('酷狗专辑搜索失败');
      var info = (body.data && body.data.info) || [];
      var list = [];
      for (var i = 0; i < info.length; i++){
        var a = info[i];
        list.push({
          albumId: a.albumid, albumName: decodeName(a.albumname),
          singer: decodeName(a.singername || ''),
          img: a.img || '', source: 'kg',
          songCount: a.songcount || 0, publishTime: a.publishtime || 0
        });
      }
      var total = (body.data && body.data.total) || list.length;
      return { list: list, total: total, source: 'kg', isEnd: list.length < limit };
    });
  }
  function txAlbumSearch(keyword, page, limit){
    page = page || 1; limit = limit || 30;
    var payload = {
      comm: {ct: '19', cv: '2151'},
      req_1: {module: 'music.search.AlbumSearch', method: 'DoSearch',
        param: {search_query: keyword, page_num: page, page_size: limit}}
    };
    return httpFetch('https://u.y.qq.com/cgi-bin/musicu.fcg', {
      method: 'POST', headers: {'Content-Type': 'application/json', Referer: 'https://y.qq.com/'},
      body: JSON.stringify(payload)
    }).then(function(resp){
      var body = asJson(resp.body);
      var albums = (body && body.req_1 && body.req_1.data && body.req_1.data.body && body.req_1.data.body.album_list) || [];
      var list = [];
      for (var i = 0; i < albums.length; i++){
        var a = albums[i];
        list.push({
          albumId: a.album_mid, albumName: a.album_name,
          singer: formatSingerName(a.singers, 'name'),
          img: a.album_pic || '', source: 'tx',
          songCount: a.song_count || 0, publishTime: a.pub_time || 0
        });
      }
      var total = (body && body.req_1 && body.req_1.data && body.req_1.data.body && body.req_1.data.body.album_total) || list.length;
      return { list: list, total: total, source: 'tx', isEnd: list.length < limit };
    });
  }
  function kwAlbumSearch(keyword, page, limit){
    page = page || 1; limit = limit || 30;
    var url = 'http://search.kuwo.cn/r.s?client=kt&all=' + encodeURIComponent(keyword)
      + '&pn=' + (page - 1) + '&rn=' + limit
      + '&uid=794762570&ver=kwplayer_ar_9.2.2.1&vipver=1&show_copyright_off=1&newver=1'
      + '&ft=album&cluster=0&strategy=2012&encoding=utf8&rformat=json&vermerge=1&mobi=1';
    return httpFetch(url).then(function(resp){
      var body = parseBody(resp.body);
      if (!body) fail('酷我专辑搜索失败');
      var rawList = body.abslist || [];
      var list = [];
      for (var i = 0; i < rawList.length; i++){
        var a = rawList[i];
        list.push({
          albumId: a.ALBUMID, albumName: decodeName(a.ALBUM || ''),
          singer: decodeName(String(a.ARTIST || '').replace(/&/g, '\u3001')),
          img: a.web_albumpic_short ? ('http://img1.kuwo.cn/' + a.web_albumpic_short) : '',
          source: 'kw', songCount: parseInt(a.SONGNUM) || 0, publishTime: a.PUBLISHDATE || ''
        });
      }
      var total = parseInt(body.TOTAL) || list.length;
      return { list: list, total: total, source: 'kw', isEnd: list.length < limit };
    });
  }
  function mgAlbumSearch(keyword, page, limit){
    page = page || 1; limit = limit || 20;
    if (!cryptoReady()) fail('缺少 CryptoJS（咪咕签名需要 MD5）');
    var deviceId = '963B7AA0D21511ED807EE5846EC87D20';
    var time = String(Date.now());
    var sign = md5Hex(keyword + '6cdc72a439cef99a3418d2a78aa28c73yyapp2d16148780a1dcc7408e06336b98cfd50' + deviceId + time);
    var url = 'https://jadeite.migu.cn/music_search/v3/search/searchAll'
      + '?isCorrect=0&isCopyright=1'
      + '&searchSwitch=' + encodeURIComponent('{"song":0,"album":1,"singer":0,"tagSong":0,"mvSong":0,"bestShow":0,"songlist":0,"lyricSong":0}')
      + '&pageSize=' + limit + '&text=' + encodeURIComponent(keyword)
      + '&pageNo=' + page + '&sort=0&sid=USS';
    return httpFetch(url, {
      headers: {uiVersion: 'A_music_3.6.1', deviceId: deviceId, timestamp: time, sign: sign, channel: '0146921'}
    }).then(function(resp){
      var result = asJson(resp.body);
      if (!result || result.code !== '000000') fail('咪咕专辑搜索失败');
      var albumData = result.albumResultData || {resultList: [], totalCount: 0};
      var rawList = albumData.resultList || [];
      var list = [];
      for (var i = 0; i < rawList.length; i++){
        var a = rawList[i];
        list.push({
          albumId: a.albumId, albumName: a.albumName,
          singer: formatSingerName(a.singerList, 'name'),
          img: a.img || '', source: 'mg',
          songCount: a.songCount || 0, publishTime: a.publishDate || ''
        });
      }
      var total = parseInt(albumData.totalCount) || list.length;
      return { list: list, total: total, source: 'mg', isEnd: list.length < limit };
    });
  }

  // ================= 专辑曲目获取（5 平台）=================
  function wyAlbumTracks(albumId){
    var url = 'https://music.163.com/api/album/' + albumId;
    return httpFetch(url, {headers: {Referer: 'https://music.163.com/', 'User-Agent': 'Mozilla/5.0'}}).then(function(resp){
      var body = asJson(resp.body);
      if (!body || body.code !== 200) fail('网易专辑曲目失败');
      var songs = body.songs || [];
      var list = [];
      for (var i = 0; i < songs.length; i++){
        var s = songs[i];
        var singers = [];
        if (s.ar) for (var j = 0; j < s.ar.length; j++) singers.push(s.ar[j].name);
        list.push({
          name: s.name, singer: singers.join('\u3001'),
          albumName: s.al ? s.al.name : '', albumId: albumId,
          songmid: s.id, source: 'wy',
          img: s.al ? s.al.picUrl : '', interval: formatPlayTime((s.dt || 0) / 1000),
          types: [], _types: {}, typeUrl: {}
        });
      }
      return { list: list, total: list.length, source: 'wy', isEnd: true };
    });
  }
  function kgAlbumTracks(albumId){
    var url = 'http://mobilecdn.kugou.com/api/v3/album/song?albumid=' + albumId + '&page=1&pagesize=-1';
    return httpFetch(url).then(function(resp){
      var body = asJson(resp.body);
      if (!body || body.status !== 1) fail('酷狗专辑曲目失败');
      var info = (body.data && body.data.info) || [];
      var list = [];
      for (var i = 0; i < info.length; i++){
        var s = info[i];
        list.push({
          name: decodeName(s.songname), singer: decodeName(s.singername || ''),
          albumName: decodeName(s.albumname || ''), albumId: albumId,
          songmid: s.audioid, hash: s.hash, source: 'kg',
          img: s.img || '', interval: formatPlayTime(s.duration || 0),
          types: [], _types: {}, typeUrl: {}
        });
      }
      return { list: list, total: list.length, source: 'kg', isEnd: true };
    });
  }
  function txAlbumTracks(albumMid){
    var payload = {
      comm: {ct: '19', cv: '2151'},
      req_1: {module: 'music.musichallAlbum.AlbumSongList', method: 'GetAlbumSongList',
        param: {album_mid: albumMid, begin: 0, num: 200}}
    };
    return httpFetch('https://u.y.qq.com/cgi-bin/musicu.fcg', {
      method: 'POST', headers: {'Content-Type': 'application/json', Referer: 'https://y.qq.com/'},
      body: JSON.stringify(payload)
    }).then(function(resp){
      var body = asJson(resp.body);
      var songs = (body && body.req_1 && body.req_1.data && body.req_1.data.songList) || [];
      var list = [];
      for (var i = 0; i < songs.length; i++){
        var s = songs[i];
        list.push({
          name: s.song_name, singer: formatSingerName(s.singer, 'name'),
          albumName: s.album_name || '', albumId: albumMid,
          songmid: s.song_mid, source: 'tx',
          img: '', interval: s.interval ? formatPlayTime(s.interval) : null,
          types: [], _types: {}, typeUrl: {}
        });
      }
      return { list: list, total: list.length, source: 'tx', isEnd: true };
    });
  }
  function kwAlbumTracks(albumId){
    var url = 'http://api.kuwo.cn/api/www/album/albumInfo?albumId=' + albumId + '&pn=1&rn=200';
    return httpFetch(url, {headers: {Referer: 'https://www.kuwo.cn/', 'User-Agent': 'Mozilla/5.0'}}).then(function(resp){
      var body = asJson(resp.body);
      if (!body || body.code !== 200) fail('酷我专辑曲目失败');
      var songs = (body.data && body.data.musicList) || [];
      var list = [];
      for (var i = 0; i < songs.length; i++){
        var s = songs[i];
        list.push({
          name: decodeName(s.name), singer: decodeName(s.artist || ''),
          albumName: decodeName(s.album || ''), albumId: albumId,
          songmid: String(s.rid || '').replace('MUSIC_', ''), source: 'kw',
          img: s.albumpic || '', interval: formatPlayTime(s.duration || 0),
          types: [], _types: {}, typeUrl: {}
        });
      }
      return { list: list, total: list.length, source: 'kw', isEnd: true };
    });
  }
  function mgAlbumTracks(albumId){
    var url = 'https://c.musicapp.migu.cn/MIGUM2.0/v1.0/content/queryAlbumSong?albumId=' + albumId + '&pageNo=1&pageSize=200';
    return httpFetch(url).then(function(resp){
      var body = asJson(resp.body);
      if (!body || body.code !== '000000') fail('咪咕专辑曲目失败');
      var songs = (body.data && body.data.songList) || [];
      var list = [];
      for (var i = 0; i < songs.length; i++){
        var s = songs[i];
        list.push({
          name: s.songName, singer: formatSingerName(s.singerList, 'name'),
          albumName: '', albumId: albumId,
          songmid: s.songId, copyrightId: s.copyrightId, source: 'mg',
          img: '', interval: formatPlayTime((s.duration || 0) / 1000),
          types: [], _types: {}, typeUrl: {}
        });
      }
      return { list: list, total: list.length, source: 'mg', isEnd: true };
    });
  }

  // ================= 注册专辑桥 =================
  globalThis.__lxAlbumSearch = { kg: kgAlbumSearch, kw: kwAlbumSearch, tx: txAlbumSearch, wy: wyAlbumSearch, mg: mgAlbumSearch };
  globalThis.__lxAlbumTracks = { kg: kgAlbumTracks, kw: kwAlbumTracks, tx: txAlbumTracks, wy: wyAlbumTracks, mg: mgAlbumTracks };
  globalThis.__lxAlbumSearchState = { result: '__pending__' };
  globalThis.__lxAlbumSearchStart = function(platform, keyword, page, limit){
    globalThis.__lxAlbumSearchState.result = '__pending__';
    var fn = globalThis.__lxAlbumSearch[platform];
    if (!fn) { globalThis.__lxAlbumSearchState.result = JSON.stringify({__error: '专辑搜索不支持平台: ' + platform}); return 1; }
    Promise.resolve()
      .then(function(){ return fn(keyword, page, limit); })
      .then(function(r){ globalThis.__lxAlbumSearchState.result = JSON.stringify(r === undefined ? null : r); })
      .catch(function(e){ globalThis.__lxAlbumSearchState.result = JSON.stringify({__error: (e && e.message) || String(e)}); });
    return 1;
  };
  globalThis.__lxAlbumSearchTake = function(){ return globalThis.__lxAlbumSearchState.result; };
  globalThis.__lxAlbumTracksState = { result: '__pending__' };
  globalThis.__lxAlbumTracksStart = function(platform, albumId){
    globalThis.__lxAlbumTracksState.result = '__pending__';
    var fn = globalThis.__lxAlbumTracks[platform];
    if (!fn) { globalThis.__lxAlbumTracksState.result = JSON.stringify({__error: '专辑曲目不支持平台: ' + platform}); return 1; }
    Promise.resolve()
      .then(function(){ return fn(albumId); })
      .then(function(r){ globalThis.__lxAlbumTracksState.result = JSON.stringify(r === undefined ? null : r); })
      .catch(function(e){ globalThis.__lxAlbumTracksState.result = JSON.stringify({__error: (e && e.message) || String(e)}); });
    return 1;
  };
  globalThis.__lxAlbumTracksTake = function(){ return globalThis.__lxAlbumTracksState.result; };
  1
})();
''';
}
