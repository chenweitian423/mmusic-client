/// 数据模型:统一 zypt 聚合源与 MusicFree 插件两种返回结构。

String _s(dynamic v) => v == null ? '' : v.toString();

const zyptSources = ['wy', 'kw', 'tx', 'kg', 'mg'];

String zyptName(String code) =>
    const {
      'wy': '网易云',
      'kw': '酷我',
      'tx': 'QQ音乐',
      'kg': '酷狗',
      'mg': '咪咕',
    }[code] ??
    code;

class Song {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String artwork;

  /// 插件 hash 或 zypt 源代码(wy/kw/tx/kg/mg),用于 /proxy 请求
  final String source;

  /// 展示用平台名
  final String platform;
  final String interval;
  final List<String> qualities;
  final Map<String, dynamic> raw;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.artwork,
    required this.source,
    required this.platform,
    required this.interval,
    required this.qualities,
    required this.raw,
  });

  factory Song.fromJson(Map<String, dynamic> j) {
    final qualities = <String>[];
    final types = j['types'];
    if (types is List) {
      for (final t in types) {
        if (t is Map && t['type'] != null) qualities.add(_s(t['type']));
      }
    }
    String artwork = '';
    for (final k in ['artwork', 'img', 'picUrl', 'cover', 'pic_id']) {
      final v = _s(j[k]);
      if (v.startsWith('http')) {
        artwork = v;
        break;
      }
    }
    final id = _s(j['id']).isNotEmpty ? _s(j['id']) : _s(j['songmid']);
    final source =
        _s(j['_plugin_hash']).isNotEmpty ? _s(j['_plugin_hash']) : _s(j['source']);
    return Song(
      id: id,
      title: _s(j['title']).isNotEmpty ? _s(j['title']) : _s(j['name']),
      artist: _s(j['artist']).isNotEmpty ? _s(j['artist']) : _s(j['singer']),
      album: _s(j['album']).isNotEmpty ? _s(j['album']) : _s(j['albumName']),
      artwork: artwork,
      source: source,
      platform:
          _s(j['platform']).isNotEmpty ? _s(j['platform']) : zyptName(_s(j['source'])),
      interval: _s(j['interval']),
      qualities: qualities,
      raw: Map<String, dynamic>.from(j),
    );
  }

  /// 存到服务端"我喜欢"列表时,补齐 Web 播放器(GD 风格)需要的字段
  Map<String, dynamic> toFavJson() {
    final m = Map<String, dynamic>.from(raw);
    m['id'] = id;
    m['name'] = title;
    m['title'] = title;
    m['artist'] = artist;
    m['singer'] = artist;
    m['album'] = album;
    m['url_id'] = m['url_id'] ?? id;
    m['lyric_id'] = m['lyric_id'] ?? id;
    m['pic_id'] = m['pic_id'] ?? artwork;
    m['source'] = source;
    m['artwork'] = artwork;
    return m;
  }

  String get key => '$source|$id';

  bool get isPlugin => source.length > 20; // 插件 hash 很长,zypt 代码只有 2 位
}

class Sheet {
  final String id;
  final String title;
  final String artist;
  final String artwork;
  final String playCount;
  final String description;
  final String source; // 插件 hash 或 zypt 代码
  final String platform;
  final Map<String, dynamic> raw;

  Sheet({
    required this.id,
    required this.title,
    required this.artist,
    required this.artwork,
    required this.playCount,
    required this.description,
    required this.source,
    required this.platform,
    required this.raw,
  });

  factory Sheet.fromJson(Map<String, dynamic> j) {
    String artwork = '';
    for (final k in ['artwork', 'img', 'picUrl', 'cover']) {
      final v = _s(j[k]);
      if (v.startsWith('http')) {
        artwork = v;
        break;
      }
    }
    return Sheet(
      id: _s(j['id']),
      title: _s(j['title']).isNotEmpty ? _s(j['title']) : _s(j['name']),
      artist: _s(j['artist']),
      artwork: artwork,
      playCount: _s(j['playCount']),
      description: _s(j['description']),
      source:
          _s(j['_plugin_hash']).isNotEmpty ? _s(j['_plugin_hash']) : _s(j['source']),
      platform: _s(j['platform']),
      raw: Map<String, dynamic>.from(j),
    );
  }
}

class Board {
  final String id;
  final String name;
  final String bangid;

  Board({required this.id, required this.name, required this.bangid});

  factory Board.fromJson(Map<String, dynamic> j) => Board(
        id: _s(j['id']),
        name: _s(j['name']),
        bangid: _s(j['bangid']).isNotEmpty ? _s(j['bangid']) : _s(j['id']),
      );
}

class PluginInfo {
  final String platform;
  final String hash;
  final List<String> searchTypes;

  PluginInfo({required this.platform, required this.hash, required this.searchTypes});

  factory PluginInfo.fromJson(Map<String, dynamic> j) => PluginInfo(
        platform: _s(j['platform']),
        hash: _s(j['hash']),
        searchTypes: (j['supportedSearchType'] is List)
            ? (j['supportedSearchType'] as List).map(_s).toList()
            : const [],
      );
}

Duration? parseInterval(String s) {
  if (s.isEmpty) return null;
  final parts = s.split(':');
  try {
    if (parts.length == 2) {
      return Duration(minutes: int.parse(parts[0]), seconds: int.parse(parts[1]));
    }
    if (parts.length == 3) {
      return Duration(
          hours: int.parse(parts[0]),
          minutes: int.parse(parts[1]),
          seconds: int.parse(parts[2]));
    }
  } catch (_) {}
  return null;
}
