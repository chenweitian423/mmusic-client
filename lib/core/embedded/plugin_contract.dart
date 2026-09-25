/// MusicFree 插件的**真实契约**（与官方文档不一致的地方一律以实测为准）。
///
/// 这个文件刻意做成**纯函数集合**：不碰引擎、不碰网络、不碰 Flutter，
/// 于是插件契约的每一条都能用单测钉住。这些判据全部来自
/// `mmusic-embedded-spike/README.md` 的实测记录，每条都踩过坑：
///
///  * `search()` 返回 `{isEnd, data:[…]}` 而**不是裸数组**（按文档写会直接崩）；
///  * 音质参数必须用官方词表 `low/standard/high/super`（传 `'320k'` 会拼出
///    `level=undefined`，酷我的中转站宽容所以照样给地址，把错误掩盖了）；
///  * 上游拿不到音源时会返回**占位地址**（中文错误文案塞在 URL 路径里），
///    判定"能不能播"必须要求**地址全 ASCII**。
library;

import 'dart:convert';

import '../models.dart';

/// 导入前的粗校验：把"下回来一个 HTML 错误页 / 接口错误 JSON"这种事挡在装载之前。
///
/// 为什么不直接丢给引擎试：引擎报的是 `SyntaxError: unexpected token '<'`，
/// 用户看到只会以为插件坏了，而真实原因是下载被拦或地址写错。
/// 返回 null 表示"看着像插件源码"，否则返回一句给人看的原因。
String? pluginCodeIssue(String code) {
  final t = code.trim();
  if (t.isEmpty) return '内容为空';
  if (t.length < 200) return '内容太短（${t.length} 字节），不像插件源码';
  if (t.startsWith('<')) return '拿到的是网页而不是插件（多半被登录页/错误页替换了）';
  if (t.startsWith('{') || t.startsWith('[')) {
    // 插件源码是 JS 程序，不可能以 JSON 结构开场；多半是接口的错误响应
    return '拿到的是 JSON 而不是插件源码（可能是接口的错误响应）';
  }
  return null;
}

/// MusicFree 的**官方音质词表**（三个元力插件的 `qualityLevels` 键就是这四个）。
const List<String> musicFreeQualities = ['low', 'standard', 'high', 'super'];

/// 把客户端音质档位（128/192/320/999）翻译成 MusicFree 官方词表。
///
/// 为什么不直接传客户端的档位：三个插件的 `qualityLevels` 映射表键就是这四个词，
/// 传别的值会得到 `undefined`，拼出的 URL 里带 `level=undefined`。
/// 酷我的中转站宽容（照样给地址），网易直接回空 body —— 症状看着像"插件坏了"。
String musicFreeQuality(String clientQuality) {
  switch (clientQuality) {
    case '999':
    case 'flac':
      return 'super';
    case '320':
      return 'high';
    case '192':
      return 'standard';
    case '128':
      return 'low';
    default:
      return 'high';
  }
}

/// 取直链时的音质降级顺序（MusicFree 词表），用户选的档位排最前。
///
/// 为什么 192 / 128 两档里**没有 `super`**：与 `brCandidatesFor`（服务端路径）
/// 里"这两档不排 flac"是同一条纪律 —— 用户明确选了低音质，不该为了取到直链
/// 偷偷拉起几十 MB 的无损流。这是**有意的取舍**，不是漏写。
List<String> qualityCandidatesFor(String clientQuality) {
  switch (clientQuality) {
    case '999':
    case 'flac':
      return const ['super', 'high', 'standard', 'low'];
    case '192':
      return const ['standard', 'high', 'low'];
    case '128':
      return const ['low', 'standard', 'high'];
    default:
      return const ['high', 'super', 'standard', 'low'];
  }
}

/// 真·可播地址判断：`http(s)` 且**全 ASCII**。
///
/// 上游拿不到音源时回的是**占位地址**，把中文错误文案塞进 URL 路径，例如
/// `https://sjy6.stream.qqmusic.qq.com/获取音频失败,好像没有这个音质哦~,也可能是会员过期了~`
/// —— 以 http 开头、长度正常，"看着拿到了"，其实一放就废。
/// NAS 上那份健康检查就是被它骗了整整一周（只判"url 非空"）。
bool looksPlayableUrl(String url) {
  if (url.isEmpty) return false;
  if (!url.startsWith('http://') && !url.startsWith('https://')) return false;
  return !url.contains(RegExp(r'[^\x20-\x7E]'));
}

/// `search()` / `getTopListDetail()` 的返回信封。
class PluginListResult {
  /// 歌曲原始 JSON（**不做字段裁剪** —— 插件取直链时要拿它原样回传）。
  final List<Map<String, dynamic>> items;
  final bool isEnd;

  const PluginListResult(this.items, this.isEnd);
}

/// 解析插件的列表返回值。
///
/// 实测三种形状都要接：
///   · `{isEnd: bool, data: [...]}` ← 三个元力插件都是这个（**文档里没有**）
///   · `[...]`                     ← MusicFree 文档写的裸数组
///   · `{data: [...]}` / `{items: [...]}` / `{musicList: [...]}` ← 其它插件常见变体
PluginListResult parsePluginList(dynamic decoded,
    {List<String> listKeys = const [
      'data',
      'items',
      'list',
      'musicList',
      'songs',
      'results',
    ]}) {
  if (decoded == null) return const PluginListResult([], true);
  if (decoded is List) {
    return PluginListResult(_maps(decoded), true);
  }
  if (decoded is Map) {
    final m = Map<String, dynamic>.from(decoded);
    for (final k in listKeys) {
      final v = m[k];
      if (v is List) {
        return PluginListResult(
          _maps(v),
          m['isEnd'] == null ? true : m['isEnd'] == true,
        );
      }
    }
  }
  return const PluginListResult([], true);
}

List<Map<String, dynamic>> _maps(List raw) {
  final out = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is Map) out.add(Map<String, dynamic>.from(e));
  }
  return out;
}

/// 从 `getMediaSource()` 的返回值里取 URL。
///
/// 插件可能回字符串，也可能回 `{url}` / `{playUrl}` / `{src}` 对象。
/// **不做** `startsWith('http')` 之外的校验 —— 占位地址也满足 http，
/// 是否可播交给 [looksPlayableUrl] 判，两件事别混在一个函数里。
String? urlFromMediaSource(dynamic decoded) {
  if (decoded == null) return null;
  if (decoded is String) {
    final s = decoded.trim();
    return s.isEmpty ? null : s;
  }
  if (decoded is Map) {
    final m = Map<String, dynamic>.from(decoded);
    for (final k in ['url', 'playUrl', 'src', 'location']) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    // 有些插件把结果再包一层
    for (final k in ['data', 'result']) {
      final inner = urlFromMediaSource(m[k]);
      if (inner != null) return inner;
    }
  }
  return null;
}

/// 从 `getLyric()` 的返回值里取 LRC 文本。
String lyricFromPlugin(dynamic decoded) {
  if (decoded == null) return '';
  if (decoded is String) return decoded;
  if (decoded is Map) {
    final m = Map<String, dynamic>.from(decoded);
    for (final k in ['rawLrc', 'lyric', 'lrc', 'rawLrcTxt']) {
      final v = m[k];
      if (v is String && v.isNotEmpty) return v;
    }
    for (final k in ['data', 'result']) {
      final inner = lyricFromPlugin(m[k]);
      if (inner.isNotEmpty) return inner;
    }
  }
  return '';
}

/// 插件歌曲 JSON → [Song]。
///
/// 两个坑：
///  ① **id 系字段是字符串**（不是数字），酷我/QQ 给的是 songmid 风格串，网易是数字 id
///     —— 统一按字符串取，别做 int 转换；
///  ② 插件给的是 `duration`（秒，数字），而客户端模型用的是 `interval`（`mm:ss` 文本）。
///     `Song.fromJson` 认不出 `duration` 这个键，所以这里自己拼 Song。
///
/// [pluginId] 写进 `Song.source`（服务端那套用插件 hash，这里用本地插件 hash，
/// 语义对齐）；[platform] 是插件自己声明的平台名，用于列表里那个小标签。
Song songFromPlugin(
  Map<String, dynamic> song, {
  required String pluginId,
  required String platform,
}) {
  final raw = Map<String, dynamic>.from(song);
  final id = _str(raw['id']).isNotEmpty
      ? _str(raw['id'])
      : (_str(raw['songmid']).isNotEmpty
          ? _str(raw['songmid'])
          : _str(raw['mid']));

  String artwork = '';
  for (final k in ['artwork', 'img', 'picUrl', 'cover', 'albumArt']) {
    final v = _str(raw[k]);
    if (v.startsWith('http')) {
      artwork = v;
      break;
    }
  }

  final qualities = <String>[];
  final types = raw['types'];
  if (types is List) {
    for (final t in types) {
      if (t is Map && t['type'] != null) qualities.add(_str(t['type']));
    }
  }

  // 插件自己的字段原样留在 raw 里：getMediaSource(song) 要把这份 JSON 原样回传，
  // 裁字段等于把插件认得的字段丢掉（酷我/QQ 都依赖 songmid 之类）。
  //
  // ⚠️ **绝不覆盖已有的 `id`**：插件给的可能是数字（网易），改成字符串后
  //    再回传给 getMediaSource，某些插件会拼出不一样的请求（`id="123"` 之类）。
  //    只在本来就没有 id 时补一个。
  final existingId = raw['id'];
  if (existingId == null || _str(existingId).isEmpty) {
    if (id.isNotEmpty) raw['id'] = id;
  }
  raw['platform'] =
      _str(raw['platform']).isNotEmpty ? _str(raw['platform']) : platform;
  raw['_plugin_hash'] = pluginId;
  raw['source'] = pluginId;

  return Song(
    id: id,
    title:
        _str(raw['title']).isNotEmpty ? _str(raw['title']) : _str(raw['name']),
    artist: _str(raw['artist']).isNotEmpty
        ? _str(raw['artist'])
        : _str(raw['singer']),
    album: _str(raw['album']).isNotEmpty
        ? _str(raw['album'])
        : _str(raw['albumName']),
    artwork: artwork,
    source: pluginId,
    platform: _str(raw['platform']),
    interval: intervalFromDuration(raw['duration'] ?? raw['interval']),
    qualities: qualities,
    raw: raw,
  );
}

/// 秒数 → `mm:ss`。已经形如 `03:45` 的字符串原样保留（有些插件直接给 interval）。
String intervalFromDuration(dynamic v) {
  if (v == null) return '';
  if (v is String) {
    if (v.contains(':')) return v;
    final sec = int.tryParse(v);
    return sec == null ? '' : _mmss(sec);
  }
  if (v is num) {
    final sec = v.round();
    return sec <= 0 ? '' : _mmss(sec);
  }
  return '';
}

String _mmss(int totalSeconds) {
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String _str(dynamic v) => v == null ? '' : v.toString();

/// 跨语言边界上的信封解析（对应 harness 的 `__callJsonSafe`）。
class PluginEnvelope {
  final bool ok;
  final dynamic value;
  final String method;
  final String kind;
  final String error;

  const PluginEnvelope({
    required this.ok,
    this.value,
    required this.method,
    this.kind = '',
    this.error = '',
  });

  /// 解析失败时**不抛异常**，而是返回一个 `ok:false` 的信封 ——
  /// 调用方永远是同一套处理逻辑，不用同时接异常和错误码两条路。
  static PluginEnvelope parse(String raw) {
    final text = _unwrap(raw);
    if (text != null) {
      try {
        final v = jsonDecode(text);
        if (v is Map) {
          final m = Map<String, dynamic>.from(v);
          if (m['ok'] == true) {
            return PluginEnvelope(
                ok: true, value: m['value'], method: _str(m['method']));
          }
          return PluginEnvelope(
            ok: false,
            method: _str(m['method']),
            kind: _str(m['kind']),
            error: _str(m['error']),
          );
        }
      } catch (_) {}
    }
    return PluginEnvelope(
      ok: false,
      method: '',
      kind: 'bad-envelope',
      error: raw.length > 200 ? '${raw.substring(0, 200)}…' : raw,
    );
  }

  /// 剥掉可能多出来的一层 JSON 字符串引号。
  ///
  /// 为什么需要：引擎把 Promise 的结果带回来时走的是 `"$res"`（Dart 的 toString），
  /// 我们返回的本来就是字符串，正常情况下 `toString` 是恒等的；但若哪天引擎改成
  /// 先 `JSON.stringify` 再回传，拿到的就是 `"{\"ok\":true,...}"`。
  /// 多这一层剥壳，两种行为都能吃下 —— 这是**边界上的防御**，不是臆测的兼容。
  static String? _unwrap(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    for (var i = 0; i < 2; i++) {
      if (!s.startsWith('"')) return s;
      try {
        final once = jsonDecode(s);
        if (once is String && once.isNotEmpty) {
          s = once.trim();
          continue;
        }
        return s;
      } catch (_) {
        return s;
      }
    }
    return s;
  }

  /// 面向用户的一句话原因。
  String get friendly {
    switch (kind) {
      case 'timeout':
        return '插件调用超时（上游没响应）';
      case 'network':
        return '插件请求上游失败（网络或上游异常）';
      case 'missing-module':
        return '插件依赖的模块没提供齐：$error';
      case 'no-such-method':
        return '这个插件不支持该功能：$error';
      case 'not-a-function':
        return '插件内部报错（$error）';
      default:
        return error.isEmpty ? '插件调用失败' : error;
    }
  }
}
