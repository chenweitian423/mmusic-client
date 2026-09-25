import 'dart:convert';

import 'package:dio/dio.dart';

import 'models.dart';
import 'settings.dart';

class ApiException implements Exception {
  final String message;

  /// 更细的技术信息(尝试次数、各状态码计数),给界面上的"详情"用。
  final String? detail;

  ApiException(this.message, {this.detail});

  @override
  String toString() => message;
}

Map<String, dynamic> asMap(dynamic d) {
  if (d is Map<String, dynamic>) return d;
  if (d is Map) return Map<String, dynamic>.from(d);
  if (d is String && d.isNotEmpty) {
    try {
      final v = jsonDecode(d);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
  }
  return {};
}

List<Song> songsFromList(dynamic l) {
  final out = <Song>[];
  if (l is List) {
    for (final e in l) {
      if (e is Map) {
        final m = Map<String, dynamic>.from(e);
        final song = Song.fromJson(m);
        if (song.id.isNotEmpty && song.title.isNotEmpty) out.add(song);
      }
    }
  }
  return out;
}

/// 在未知结构的响应里递归找歌曲列表(收藏歌单等接口结构不完全确定,做防御式解析)
List<Song> deepFindSongs(dynamic d, [int depth = 0]) {
  if (depth > 5 || d == null) return [];
  if (d is List) {
    if (d.isNotEmpty && d.first is Map) {
      final first = Map<String, dynamic>.from(d.first as Map);
      if (first.containsKey('title') || first.containsKey('name')) {
        final songs = songsFromList(d);
        if (songs.isNotEmpty) return songs;
      }
    }
    return [];
  }
  if (d is Map) {
    for (final k in [
      'playlist',
      'list',
      'songs',
      'results',
      'data',
      'musics',
      'tracks'
    ]) {
      if (d.containsKey(k)) {
        final r = deepFindSongs(d[k], depth + 1);
        if (r.isNotEmpty) return r;
      }
    }
    for (final v in d.values) {
      final r = deepFindSongs(v, depth + 1);
      if (r.isNotEmpty) return r;
    }
  }
  return [];
}

String extractPlayableUrl(dynamic data, [int depth = 0]) {
  if (depth > 5 || data == null) return '';
  if (data is String) return data.startsWith('http') ? data : '';
  if (data is List) {
    for (final item in data) {
      final url = extractPlayableUrl(item, depth + 1);
      if (url.isNotEmpty) return url;
    }
    return '';
  }
  if (data is Map) {
    final m = Map<String, dynamic>.from(data);
    for (final key in ['url', 'playUrl', 'src', 'location']) {
      final url = extractPlayableUrl(m[key], depth + 1);
      if (url.isNotEmpty) return url;
    }
    for (final key in [
      'data',
      'result',
      'mediaSource',
      'source',
      'musicSource'
    ]) {
      final url = extractPlayableUrl(m[key], depth + 1);
      if (url.isNotEmpty) return url;
    }
  }
  return '';
}

Map<String, dynamic> mediaSourceBody(Song song, String quality) {
  final body = song.toFavJson();
  body['quality'] = _mediaSourceQuality(quality);
  return body;
}

List<Map<String, dynamic>> mediaSourceBodies(
  Song song,
  String quality, [
  String? source,
]) {
  final q = _mediaSourceQuality(quality);
  final body = song.toFavJson();
  if (source != null && source.isNotEmpty) {
    body['source'] = source;
    if (source.length > 20) body['_plugin_hash'] = source;
  }
  return [
    {'musicItem': body, 'quality': q},
    {...body, 'quality': q},
    {'musicItem': body},
  ];
}

List<String> proxyIdCandidates(Song song) {
  final ids = <String>[];
  for (final key in ['url_id', 'songmid', 'mid', 'songId', 'id']) {
    final value = song.raw[key]?.toString() ?? '';
    if (value.isNotEmpty && !ids.contains(value)) ids.add(value);
  }
  if (song.id.isNotEmpty && !ids.contains(song.id)) ids.add(song.id);
  return ids;
}

Map<String, dynamic> proxyUrlParams(
  Song song,
  String id, [
  String? br,
  String? source,
]) {
  final params = <String, dynamic>{};
  for (final entry in song.raw.entries) {
    final value = entry.value;
    if (value == null) continue;
    if (value is String || value is num || value is bool) {
      params[entry.key] = value.toString();
    }
  }
  params['types'] = 'url';
  params['source'] = source ?? song.source;
  params['id'] = id;
  if (br != null && br.isNotEmpty) params['br'] = br;
  return params;
}

List<String> sourceCandidatesForSong(Song song, List<PluginInfo> plugins) {
  final out = <String>[];
  void add(String s) {
    if (s.isNotEmpty && !out.contains(s)) out.add(s);
  }

  if (zyptSources.contains(song.source)) {
    for (final p in plugins) {
      if (pluginMatchesSource(p, song.source)) add(p.hash);
    }
    if (out.isNotEmpty) return out;
  }

  add(song.source);
  return out;
}

/// 插件平台名 → zypt 短码的匹配关键词表。
///
/// 背景：服务端不提供 hash ↔ 短码的映射接口，客户端只能拿插件的 `platform`
/// 字符串做模糊匹配（详见 AGENTS.md §3.2）。这层映射天生脆弱，换个插件名就可能失配。
///
/// 为什么中英文都要列：2026-07-26 探测时服务端上的插件叫「元力KW」「元力WY」，
/// 名字里带着英文短码，所以只匹配英文也能碰巧跑通。但插件是随时可增删的，
/// 而 MusicFree 生态里「网易云音乐」这种纯中文命名很常见；一旦换成那样的插件，
/// 匹配会失败并**静默**退回内置 zypt 源（见 sourceCandidatesForSong 的兜底逻辑），
/// 不报错但直链成功率下降。所以这张表宁可多列，不要删。
const Map<String, List<String>> sourceMatchKeywords = {
  'tx': ['QQ', 'TX', 'TENCENT', '腾讯'],
  'wy': ['WY', 'NETEASE', '网易'],
  'kw': ['KW', 'KUWO', '酷我'],
  'kg': ['KG', 'KUGOU', '酷狗'],
  'mg': ['MG', 'MIGU', '咪咕'],
};

bool pluginMatchesSource(PluginInfo plugin, String source) {
  final keywords = sourceMatchKeywords[source];
  if (keywords == null) return false;
  // 中文字符不受 toUpperCase 影响，所以中英文关键词可以放在同一张表里比。
  final p = plugin.platform.toUpperCase();
  return keywords.any((k) => p.contains(k));
}

String _mediaSourceQuality(String br) {
  switch (br) {
    case '320':
      return '320k';
    case '192':
      return '192k';
    case '128':
      return '128k';
    case '999':
    case 'flac':
      return 'flac';
    default:
      return br;
  }
}

/// 取播放直链时的探测记录。
///
/// 为什么需要它:[playUrl] 要把「音源 × 音质 × id 候选 × 两种路由」几十种组合
/// 全试一遍,每一步的失败原先都被 `catch (_) {}` 吞掉,最后只剩一句
/// 「无法获取播放地址」—— 用户看不懂,排查的人也无从下手。
/// 这个类把每一步的结果攒起来,最后翻成一句**可行动**的话。
///
/// 判据来自 AGENTS.md §8.8 那类真实故障:插件失效(中转站改了接口路径)时
/// 服务端一切正常、只是取不到直链,而这在旧实现下和「服务器挂了」长得一模一样。
class PlayUrlProbe {
  /// 发起的请求总数(含成功那次)。
  int attempts = 0;

  /// 401 / 403:服务端收到了请求但不给数据,基本等于登录过期。
  int unauthorized = 0;

  /// 404:音源名或接口路径不对。
  int notFound = 0;

  /// 其它 4xx。
  int badRequest = 0;

  /// 200 但响应里没有可用地址:服务端活着,只是这组参数给不出直链。
  int emptyBody = 0;

  /// 网络层异常(连不上 / 超时)。
  int networkErrors = 0;

  /// 非网络层的其它异常。
  int otherErrors = 0;

  /// 最近一次异常的描述。
  String lastError = '';

  /// 最近一次看到的状态码。
  int? lastStatus;

  void recordResponse(int? status) {
    attempts++;
    lastStatus = status;
    if (status == null) return;
    if (status == 401 || status == 403) {
      unauthorized++;
    } else if (status == 404) {
      notFound++;
    } else if (status >= 400) {
      badRequest++;
    }
  }

  /// 200 但取不到地址。
  void recordEmptyBody() => emptyBody++;

  void recordError(Object e) {
    attempts++;
    lastError = shortErrorText(e);
    if (_isNetworkError(e)) {
      networkErrors++;
    } else {
      otherErrors++;
    }
  }

  /// 面向用户的一句话原因(按"用户能做什么"排序,而不是按发生次数)。
  String describe(int sourceCount) {
    if (attempts == 0) {
      return '没有可用的音源';
    }
    if (unauthorized > 0) {
      return '登录已过期,请重新登录';
    }
    if (networkErrors == attempts) {
      return '连不上服务端($lastError)';
    }
    if (emptyBody > 0) {
      return '服务端正常,但 $sourceCount 个音源都没给出播放地址(多半是插件失效)';
    }
    if (notFound > 0) {
      return '服务端返回 404:音源名或接口路径不对';
    }
    if (badRequest > 0) {
      return '服务端拒绝了请求(HTTP $lastStatus)';
    }
    if (networkErrors > 0) {
      return '网络不稳定($lastError)';
    }
    if (otherErrors > 0) {
      return '请求出错($lastError)';
    }
    return '取不到播放地址';
  }

  /// 给「详情」用的技术摘要。
  String get summary {
    final parts = <String>[];
    if (unauthorized > 0) parts.add('401/403×$unauthorized');
    if (notFound > 0) parts.add('404×$notFound');
    if (badRequest > 0) parts.add('4xx×$badRequest');
    if (emptyBody > 0) parts.add('空应答×$emptyBody');
    if (networkErrors > 0) parts.add('网络异常×$networkErrors');
    if (otherErrors > 0) parts.add('其它异常×$otherErrors');
    final tail = parts.isEmpty ? '无响应记录' : parts.join(' / ');
    return '共尝试 $attempts 次:$tail';
  }

  static bool _isNetworkError(Object e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return true;
        default:
          return false;
      }
    }
    final s = e.toString().toLowerCase();
    return s.contains('socket') ||
        s.contains('timeout') ||
        s.contains('connection');
  }
}

/// 把异常压成一小段人话,塞进上面的文案里(+ 避免把整个 DioException 堆栈铺到界面上)。
String shortErrorText(Object e) {
  var s = e.toString();
  final nl = s.indexOf('\n');
  if (nl > 0) s = s.substring(0, nl);
  if (s.length > 80) s = '${s.substring(0, 77)}...';
  return s;
}

class Api {
  Dio _dio = Dio();
  List<PluginInfo>? _pluginCache;

  void configure() {
    _dio = Dio(BaseOptions(
      baseUrl: settings.serverUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 40),
      headers: {'Accept': 'application/json'},
      validateStatus: (s) => s != null && s < 500,
    ));
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      final c = settings.authCookie;
      if (c.isNotEmpty) o.headers['Cookie'] = c;
      h.next(o);
    }));
  }

  Map<String, String> get imageHeaders =>
      settings.authCookie.isEmpty ? {} : {'Cookie': settings.authCookie};

  String proxyImage(String url) =>
      '${settings.serverUrl}/proxy-image?url=${Uri.encodeComponent(url)}';

  // ---------- 连接 / 认证 ----------

  Future<bool> testServer(String url) async {
    try {
      final d = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (s) => s != null && s < 500,
      ));
      final r = await d.get('$url/api/auth-status');
      return r.statusCode == 200 && asMap(r.data).containsKey('authenticated');
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> authStatus() async {
    final r = await _dio.get('/api/auth-status');
    return asMap(r.data);
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final r = await _dio
        .post('/api/login', data: {'username': username, 'password': password});
    final data = asMap(r.data);
    if (data['success'] == true) {
      final setCookies = r.headers['set-cookie'] ?? [];
      for (final sc in setCookies) {
        if (sc.startsWith('auth=')) {
          await settings.setAuthCookie(sc.split(';').first);
        }
      }
      await settings.setUsername(username);
    }
    return data;
  }

  Future<void> logout() async {
    try {
      await _dio.post('/api/logout');
    } catch (_) {}
    await settings.clearAuth();
  }

  // ---------- 插件 / 音源 ----------

  Future<List<PluginInfo>> plugins() async {
    final r = await _dio.get('/plugins');
    final data = asMap(r.data);
    final out = <PluginInfo>[];
    if (data['plugins'] is List) {
      for (final e in data['plugins']) {
        if (e is Map) {
          out.add(PluginInfo.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    _pluginCache = out;
    return out;
  }

  // ---------- 搜索 ----------

  Future<List<Song>> search(
    String query, {
    int page = 1,
    String? source, // zypt 代码
    String? pluginHash, // 插件 hash
  }) async {
    final params = <String, dynamic>{
      'query': query,
      'page': page,
      'search_type': 'music',
    };
    if (source != null && source.isNotEmpty) params['source'] = source;
    if (pluginHash != null && pluginHash.isNotEmpty) {
      params['plugin_hash'] = pluginHash;
    }
    final r = await _dio.get('/search', queryParameters: params);
    if (r.statusCode != 200) throw ApiException('搜索失败(${r.statusCode})');
    return songsFromList(asMap(r.data)['results']);
  }

  Future<List<Sheet>> searchSheets(String query,
      {required String pluginHash, int page = 1}) async {
    final r = await _dio.get('/search', queryParameters: {
      'query': query,
      'page': page,
      'search_type': 'sheet',
      'plugin_hash': pluginHash,
    });
    final out = <Sheet>[];
    final list = asMap(r.data)['results'];
    if (list is List) {
      for (final e in list) {
        if (e is Map) {
          final s = Sheet.fromJson(Map<String, dynamic>.from(e));
          if (s.id.isNotEmpty && s.title.isNotEmpty) out.add(s);
        }
      }
    }
    return out;
  }

  // ---------- 播放地址 / 歌词 ----------

  List<String> _brCandidates() {
    switch (settings.quality) {
      case '999':
        return ['999', 'flac', '320', '192', '128'];
      case '128':
        return ['128', '192', '320', '999'];
      case '192':
        return ['192', '320', '128', '999'];
      default:
        return ['320', '192', '999', 'flac', '128'];
    }
  }

  Future<String> playUrl(Song song) async {
    final probe = PlayUrlProbe();
    final sources = await _sourceCandidates(song, probe);
    for (final source in sources) {
      for (final br in _brCandidates()) {
        final proxyUrl = await _playUrlViaProxy(song, source, br, probe);
        if (proxyUrl.isNotEmpty) return proxyUrl;

        final mediaSourceUrl =
            await _playUrlViaMediaSource(song, source, br, probe);
        if (mediaSourceUrl.isNotEmpty) return mediaSourceUrl;
      }
    }
    // 旧实现只抛一句"无法获取播放地址",用户和排查者都看不出区别;
    // 现在带上 probe 归类出来的原因 + 计数摘要(界面会展示,见 audio_handler)。
    throw ApiException(probe.describe(sources.length), detail: probe.summary);
  }

  Future<List<String>> _sourceCandidates(Song song, PlayUrlProbe probe) async {
    if (zyptSources.contains(song.source)) {
      try {
        final list = _pluginCache ?? await plugins();
        return sourceCandidatesForSong(song, list);
      } catch (e) {
        // 插件列表拿不到(常见于服务端连不上)也要记账,否则这里会静默退回短码,
        // 最终报错里就看不出"其实是服务端没响应"。
        probe.recordError(e);
      }
    }
    return [song.source];
  }

  Future<String> _playUrlViaMediaSource(
    Song song,
    String source,
    String br,
    PlayUrlProbe probe,
  ) async {
    for (final body in mediaSourceBodies(song, br, source)) {
      try {
        final r = await _dio.post('/media-source', data: body);
        probe.recordResponse(r.statusCode);
        if (r.statusCode == 200) {
          final url = extractPlayableUrl(r.data);
          if (url.isNotEmpty) return url;
          probe.recordEmptyBody();
        }
      } catch (e) {
        probe.recordError(e);
      }
    }
    return '';
  }

  Future<String> _playUrlViaProxy(
    Song song,
    String source,
    String br,
    PlayUrlProbe probe,
  ) async {
    for (final id in proxyIdCandidates(song)) {
      for (final params in [
        proxyUrlParams(song, id, null, source),
        proxyUrlParams(song, id, br, source),
      ]) {
        try {
          final r = await _dio.get('/proxy', queryParameters: params);
          probe.recordResponse(r.statusCode);
          if (r.statusCode == 200) {
            final url = extractPlayableUrl(r.data);
            if (url.isNotEmpty) return url;
            probe.recordEmptyBody();
          }
        } catch (e) {
          probe.recordError(e);
        }
      }
    }
    return '';
  }

  Future<String> lyric(Song song) async {
    try {
      final r = await _dio.get('/proxy', queryParameters: {
        'types': 'lyric',
        'source': song.source,
        'id': song.id,
      });
      if (r.statusCode == 200) {
        final m = asMap(r.data);
        final l = (m['lyric'] ?? m['rawLrc'] ?? '').toString();
        if (l.isNotEmpty) return l;
      }
    } catch (_) {}
    // 插件歌曲兜底:直接 POST /lyric
    if (song.isPlugin) {
      try {
        final r = await _dio.post('/lyric', data: song.raw);
        if (r.statusCode == 200) {
          final m = asMap(r.data);
          return (m['rawLrc'] ?? m['lyric'] ?? '').toString();
        }
      } catch (_) {}
    }
    return '';
  }

  // ---------- 排行榜 ----------

  Future<List<Board>> boards(String source) async {
    final r = await _dio
        .get('/api/leaderboard/boards', queryParameters: {'source': source});
    if (r.statusCode != 200) throw ApiException('获取榜单失败(${r.statusCode})');
    final out = <Board>[];
    final list = asMap(r.data)['boards'];
    if (list is List) {
      for (final e in list) {
        if (e is Map) out.add(Board.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return out;
  }

  Future<List<Song>> boardSongs(String source, String bangid,
      {int page = 1, int limit = 100}) async {
    final r = await _dio.get('/api/leaderboard/list', queryParameters: {
      'source': source,
      'bangid': bangid,
      'page': page,
      'limit': limit,
    });
    if (r.statusCode != 200) throw ApiException('获取榜单歌曲失败(${r.statusCode})');
    return songsFromList(asMap(r.data)['songs']);
  }

  // ---------- 歌单详情 ----------

  /// 插件歌单映射回 zypt 源代码(元力KW 的歌单其实是酷我歌单)
  String _detailSource(Sheet sheet) {
    if (zyptSources.contains(sheet.source)) return sheet.source;
    final p = sheet.platform.toUpperCase();
    for (final code in zyptSources) {
      if (p.contains(code.toUpperCase())) return code;
    }
    return sheet.source;
  }

  Future<List<Song>> sheetDetail(Sheet sheet,
      {int page = 1, int limit = 200}) async {
    final r = await _dio.get('/api/playlist/detail', queryParameters: {
      'playlist_id': sheet.id,
      'source': _detailSource(sheet),
      'page': page,
      'limit': limit,
    });
    if (r.statusCode != 200) throw ApiException('获取歌单失败(${r.statusCode})');
    final data = asMap(r.data);
    final pl = data['playlist'];
    if (pl is Map && pl['list'] is List) {
      return songsFromList(pl['list']);
    }
    return deepFindSongs(data);
  }

  // ---------- 我喜欢(服务端播放列表) ----------

  Map<String, dynamic>? _favOuter;

  Future<List<Song>> favorites() async {
    final r = await _dio.get('/api/playlist');
    final data = asMap(r.data);
    final outer = data['playlist'];
    if (outer is Map) {
      _favOuter = Map<String, dynamic>.from(outer);
      return songsFromList(_favOuter!['playlist']);
    }
    _favOuter = {'playlist': []};
    return [];
  }

  Future<void> saveFavorites(List<Song> songs) async {
    final outer = Map<String, dynamic>.from(_favOuter ?? {});
    outer['playlist'] = songs.map((s) => s.toFavJson()).toList();
    final r = await _dio.post('/api/playlist', data: outer);
    if (r.statusCode != 200 || asMap(r.data)['success'] == false) {
      throw ApiException('同步收藏失败');
    }
    _favOuter = outer;
  }

  // ---------- 收藏的歌单 ----------

  Future<List<Map<String, dynamic>>> collections() async {
    final r = await _dio.get('/api/playlist/collections');
    final list = asMap(r.data)['playlists'];
    final out = <Map<String, dynamic>>[];
    if (list is List) {
      for (final e in list) {
        if (e is Map) out.add(Map<String, dynamic>.from(e));
      }
    }
    return out;
  }

  Future<List<Song>> collectionDetail(String filename) async {
    final r = await _dio.get('/api/playlist/collection/$filename');
    if (r.statusCode != 200) throw ApiException('获取歌单失败(${r.statusCode})');
    return deepFindSongs(asMap(r.data));
  }
}

final api = Api();
