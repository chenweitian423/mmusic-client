import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api.dart';
import '../models.dart';
import '../music_source.dart';
import '../settings.dart';
import 'embedded_plugin.dart';
import 'plugin_contract.dart';
import 'plugin_runtime.dart';
import 'plugin_store.dart';
import 'runtime_pool.dart';

/// 内置源：完全不经过服务端，直接在 App 里跑 MusicFree 插件。
///
/// 它实现的是与 [Api] **同一套形状**的接口，所以上层 UI 只需要换一个入口
/// （`musicSource`），不必关心这一首歌是从 NAS 还是从本机插件拿到的。
///
/// 三处与服务端语义的对齐（很重要，否则两种模式的数据会串味）：
///  * `Song.source` = 插件源码 SHA256 —— 与服务端的插件 hash 同构；
///  * 音质档位走 [qualityCandidatesFor] 翻译成 MusicFree 官方词表；
///  * 「能不能播」一律用 [looksPlayableUrl] 判（挡住上游的占位地址）。
class EmbeddedSource implements MusicSource {
  static const _searchTimeout = Duration(seconds: 32);
  static const _mediaTimeout = Duration(seconds: 26);
  static const _metaTimeout = Duration(seconds: 26);

  /// 最近一次跨插件调用的告警（某个源失败但其它源成功了）。
  ///
  /// 为什么要有它：并行搜三个源时，一个源挂了不该让整次搜索失败 ——
  /// 但**也不能静默吞掉**（这个项目已经吃过一次"静默跳下一首"的亏）。
  final ValueNotifier<List<String>> lastIssues =
      ValueNotifier<List<String>>(const []);

  /// `getTopListDetail` 需要把 `getTopLists` 返回的**原始条目对象**原样回传，
  /// 而 [Board] 模型只带得走 id/name —— 所以这里存一份。
  final Map<String, Map<String, dynamic>> _topListCache = {};

  @override
  SourceKind get kind => SourceKind.embedded;

  @override
  String get label => '内置源';

  @override
  bool get needsServer => false;

  @override
  bool get supportsServerLibrary => false;

  List<EmbeddedPlugin> get installed => pluginStore.plugins.value;
  List<EmbeddedPlugin> get usable => pluginStore.enabled;

  @override
  Future<List<PluginInfo>> plugins() async => [
        for (final p in usable)
          PluginInfo(
            platform: p.platform,
            hash: p.hash,
            searchTypes: p.supportedSearchType,
          ),
      ];

  // ---------- 搜索 ----------

  /// 搜索。[pluginHash] 指定单个插件；不指定则**并行搜所有启用的插件**。
  ///
  /// 为什么默认搜全部：服务端的 `/search` 不带 source 时也是聚合搜索，
  /// 行为要对齐；而且用户装三个源就是想一次搜遍。
  @override
  Future<List<Song>> search(
    String query, {
    int page = 1,
    String? source,
    String? pluginHash,
  }) async {
    final targets = _targets(pluginHash);
    if (targets.isEmpty) throw ApiException(_noPluginHint);

    final out = <Song>[];
    final issues = <String>[];
    final results = await Future.wait([
      for (final p in targets)
        _searchOne(p, query, page)
            .then<({List<Song> songs, String? error})>(
                (v) => (songs: v, error: null))
            .catchError((Object e) => (songs: <Song>[], error: '$e')),
    ]);
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      out.addAll(r.songs);
      if (r.error != null) {
        issues.add('${targets[i].displayName}：${r.error}');
      }
    }
    lastIssues.value = issues;

    if (out.isEmpty && issues.isNotEmpty) {
      throw ApiException(
        '所有音源都没能搜到结果',
        detail: issues.join('\n'),
      );
    }
    return out;
  }

  Future<List<Song>> _searchOne(
    EmbeddedPlugin plugin,
    String query,
    int page,
  ) async {
    if (!plugin.supports('music')) {
      return const <Song>[];
    }
    final env = await _invoke(
      plugin,
      'search',
      [query.trim(), page, 'music'],
      timeout: _searchTimeout,
    );
    final parsed = parsePluginList(env.value);
    return [
      for (final m in parsed.items)
        songFromPlugin(m, pluginId: plugin.hash, platform: plugin.platform),
    ].where((s) => s.id.isNotEmpty && s.title.isNotEmpty).toList();
  }

  /// 搜歌单（只支持声明了 `sheet` 的插件）。
  @override
  Future<List<Sheet>> searchSheets(
    String query, {
    required String pluginHash,
    int page = 1,
  }) async {
    final plugin = pluginStore.byHash(pluginHash);
    if (plugin == null) throw ApiException('插件不存在（${_short(pluginHash)}）');
    final env = await _invoke(
      plugin,
      'search',
      [query.trim(), page, 'sheet'],
      timeout: _searchTimeout,
    );
    final parsed = parsePluginList(env.value);
    final out = <Sheet>[];
    for (final m in parsed.items) {
      final s = Sheet(
        id: _s(m['id']),
        title: _s(m['title']).isNotEmpty ? _s(m['title']) : _s(m['name']),
        artist: _s(m['artist']),
        artwork: _firstHttp([m['artwork'], m['img'], m['cover']]),
        playCount: _s(m['playCount']),
        description: _s(m['description']),
        source: plugin.hash,
        platform: plugin.platform,
        raw: {...m, '_plugin_hash': plugin.hash, 'platform': plugin.platform},
      );
      if (s.id.isNotEmpty && s.title.isNotEmpty) out.add(s);
    }
    return out;
  }

  // ---------- 播放地址 ----------

  /// 取可播直链。
  ///
  /// 音质按 [qualityCandidatesFor] 依次降级；每一步都用 [looksPlayableUrl] 判真伪
  /// —— 上游拿不到音源时会给一个**占位地址**（中文错误文案塞在 URL 路径里），
  /// 只判"url 非空"的话这儿会假装成功（NAS 上的健康检查就栽在这上面）。
  @override
  Future<String> playUrl(Song song) async {
    final plugin = _pluginForSong(song);
    final qualities = qualityCandidatesFor(settings.quality);
    final tried = <String>[];
    var placeholders = 0;

    for (final q in qualities) {
      final env = await _tryInvoke(
        plugin,
        'getMediaSource',
        [song.raw, q],
        timeout: _mediaTimeout,
      );
      if (env == null || !env.ok) {
        tried.add('$q:${env == null ? '调用失败' : env.friendly}');
        continue;
      }
      final url = urlFromMediaSource(env.value);
      if (url == null || url.isEmpty) {
        tried.add('$q:没有地址');
        continue;
      }
      if (!looksPlayableUrl(url)) {
        placeholders++;
        tried.add('$q:上游占位地址');
        continue;
      }
      return url;
    }

    final reason = placeholders > 0
        ? '上游没给真地址（${plugin.displayName} 的会员歌曲常见），共 $placeholders 次拿到占位地址'
        : '${plugin.displayName} 没给出播放地址';
    throw ApiException(
      reason,
      detail: '音质依次尝试：${qualities.join(' → ')}\n${tried.join('\n')}',
    );
  }

  // ---------- 歌词 ----------

  @override
  Future<String> lyric(Song song) async {
    final plugin = _pluginForSong(song);
    final env = await _tryInvoke(
      plugin,
      'getLyric',
      [song.raw],
      timeout: _metaTimeout,
    );
    if (env == null || !env.ok) return '';
    return lyricFromPlugin(env.value);
  }

  // ---------- 榜单 ----------

  /// 内置源里有没有覆盖某个 zypt 短码的插件。
  ///
  /// 榜单页用它决定"要不要为这个平台显示一个标签页" —— 没有对应插件时
  /// 摆一个点进去必然报错的标签页，比不摆更糟。
  bool hasSourceCode(String code) => _pluginForSourceCode(code) != null;

  /// 内置源下 [source] 是 zypt 短码（`wy`/`kw`/…），按插件平台名模糊匹配
  /// —— 与 `pluginMatchesSource` 同一套关键词表，避免两处逻辑漂移。
  @override
  Future<List<Board>> boards(String source) async {
    final plugin = _pluginForSourceCode(source);
    if (plugin == null) {
      throw ApiException('内置源里没有${zyptName(source)}的插件');
    }
    final env = await _invoke(
      plugin,
      'getTopLists',
      const [],
      timeout: _metaTimeout,
    );
    final parsed = parsePluginList(env.value);
    final out = <Board>[];
    for (final m in parsed.items) {
      final id = _s(m['id']);
      final name = _s(m['title']).isNotEmpty ? _s(m['title']) : _s(m['name']);
      if (id.isEmpty || name.isEmpty) continue;
      _topListCache['${plugin.hash}|$id'] = m;
      out.add(Board(id: id, name: name, bangid: id));
    }
    return out;
  }

  @override
  Future<List<Song>> boardSongs(
    String source,
    String bangid, {
    int page = 1,
    int limit = 100,
  }) async {
    final plugin = _pluginForSourceCode(source);
    if (plugin == null) {
      throw ApiException('内置源里没有${zyptName(source)}的插件');
    }
    var item = _topListCache['${plugin.hash}|$bangid'];
    if (item == null) {
      // 榜单条目没缓存（App 重启过 / 直接进的详情页）→ 重新拉一次榜单找回原始条目，
      // 因为 getTopListDetail 拿的就是那个对象（只给 id 插件不认）。
      final boards = await this.boards(source);
      if (!boards.any((b) => b.bangid == bangid)) {
        throw ApiException('榜单不存在：$bangid');
      }
      item = _topListCache['${plugin.hash}|$bangid'];
    }
    if (item == null) throw ApiException('榜单信息丢失（$bangid）');

    final env = await _invoke(
      plugin,
      'getTopListDetail',
      [item, page],
      timeout: _searchTimeout,
    );
    final parsed = parsePluginList(env.value);
    return [
      for (final m in parsed.items)
        songFromPlugin(m, pluginId: plugin.hash, platform: plugin.platform),
    ].where((s) => s.id.isNotEmpty && s.title.isNotEmpty).toList();
  }

  // ---------- 歌单详情 ----------

  @override
  Future<List<Song>> sheetDetail(Sheet sheet,
      {int page = 1, int limit = 200}) async {
    final plugin =
        pluginStore.byHash(sheet.source) ?? _pluginForSourceCode(sheet.source);
    if (plugin == null) throw ApiException('插件不存在（${_short(sheet.source)}）');
    final env = await _invoke(
      plugin,
      'getMusicSheetInfo',
      [sheet.raw, page],
      timeout: _searchTimeout,
    );
    final parsed = parsePluginList(env.value, listKeys: const [
      'musicList',
      'data',
      'songs',
      'items',
      'list',
    ]);
    return [
      for (final m in parsed.items)
        songFromPlugin(m, pluginId: plugin.hash, platform: plugin.platform),
    ].where((s) => s.id.isNotEmpty && s.title.isNotEmpty).toList();
  }

  // ---------- 插件自检（插件管理页用） ----------

  /// 对一个插件做一次端到端体检：装载 → 搜索 → 取直链。
  ///
  /// 返回逐项结果，**不抛异常** —— 这是诊断工具，失败本身就是要展示的信息。
  Future<List<EngineCheck>> selfTest(
    EmbeddedPlugin plugin, {
    String keyword = '晴天',
  }) async {
    final checks = <EngineCheck>[];
    final sw = Stopwatch()..start();
    PluginMeta meta;
    try {
      final code = await pluginStore.code(plugin.hash);
      final rt = await runtimePool.use<PluginRuntime>(
        plugin,
        () async => code,
        (rt) async => rt,
      );
      meta = rt.meta;
      checks.add(EngineCheck('装载插件', true, '${sw.elapsedMilliseconds} ms',
          '${meta.platform} v${meta.version}'));
    } catch (e) {
      checks.add(
          EngineCheck('装载插件', false, '${sw.elapsedMilliseconds} ms', '$e'));
      return checks;
    }

    sw.reset();
    List<Song> songs;
    try {
      songs = await _searchOne(plugin, keyword, 1);
      checks.add(EngineCheck(
        '搜索「$keyword」',
        songs.isNotEmpty,
        '${sw.elapsedMilliseconds} ms',
        '${songs.length} 条',
      ));
    } catch (e) {
      checks.add(EngineCheck(
          '搜索「$keyword」', false, '${sw.elapsedMilliseconds} ms', '$e'));
      return checks;
    }
    if (songs.isEmpty) return checks;

    sw.reset();
    var placeholder = 0;
    final triedQualities = <String>[];
    for (final q in qualityCandidatesFor(settings.quality)) {
      final env = await _tryInvoke(
        plugin,
        'getMediaSource',
        [songs.first.raw, q],
        timeout: _mediaTimeout,
      );
      final url = env == null || !env.ok ? null : urlFromMediaSource(env.value);
      if (url != null && looksPlayableUrl(url)) {
        final host = Uri.tryParse(url)?.host ?? '?';
        checks.add(EngineCheck(
          '取直链',
          true,
          '${sw.elapsedMilliseconds} ms',
          '音质 $q · $host',
        ));
        return checks;
      }
      if (url != null) placeholder++;
      triedQualities.add('$q:${url == null ? '无地址' : '占位地址'}');
    }
    checks.add(EngineCheck(
      '取直链',
      false,
      '${sw.elapsedMilliseconds} ms',
      placeholder > 0
          ? '上游只给占位地址（会员歌曲常见）；试过 ${triedQualities.join(' ')}'
          : '四档音质都没地址；试过 ${triedQualities.join(' ')}',
    ));
    return checks;
  }

  // ---------- 内部 ----------

  static const String _noPluginHint = '还没有可用的内置插件。到「我的 → 设置 → 插件管理」导入插件后再试。';

  List<EmbeddedPlugin> _targets(String? pluginHash) {
    if (pluginHash != null && pluginHash.isNotEmpty) {
      final p = pluginStore.byHash(pluginHash);
      if (p == null) throw ApiException('插件不存在（${_short(pluginHash)}）');
      if (!p.enabled) throw ApiException('插件「${p.displayName}」已停用');
      return [p];
    }
    return pluginStore.enabledFor('music');
  }

  /// 按 zypt 短码找插件（`wy` → 平台名里含「网易/WY/NETEASE」的那个）。
  EmbeddedPlugin? _pluginForSourceCode(String code) {
    if (pluginStore.byHash(code) != null) return pluginStore.byHash(code);
    for (final p in usable) {
      if (pluginMatchesSource(
        PluginInfo(
          platform: p.platform,
          hash: p.hash,
          searchTypes: p.supportedSearchType,
        ),
        code,
      )) {
        return p;
      }
    }
    return null;
  }

  /// 播放某首歌该用哪个插件：优先按 `Song.source` 精确命中；
  /// 命不中就退回"唯一启用的插件"（用户只装一个源时这是常态）。
  EmbeddedPlugin _pluginForSong(Song song) {
    final byHash = pluginStore.byHash(song.source);
    if (byHash != null) return byHash;
    final byCode = _pluginForSourceCode(song.source);
    if (byCode != null) return byCode;
    final list = usable;
    if (list.length == 1) return list.first;
    if (list.isEmpty) throw ApiException(_noPluginHint);
    throw ApiException('这首歌的音源插件已经不在列表里了（${_short(song.source)}）');
  }

  /// 统一的调用入口：串行池 + 超时 + 网络类失败重试一次 + 错误归档。
  ///
  /// 失败即抛 [ApiException]（搜索、榜单这些"必须成功"的路径用）。
  Future<PluginEnvelope> _invoke(
    EmbeddedPlugin plugin,
    String method,
    List<dynamic> args, {
    required Duration timeout,
    int attempts = 2,
  }) async {
    Object? lastError;
    for (var i = 1; i <= attempts; i++) {
      try {
        final env = await runtimePool.use(
          plugin,
          () => pluginStore.code(plugin.hash),
          (rt) => rt.call(method, args, timeout: timeout),
        );
        if (env.ok) {
          runtimePool.clearError(plugin.hash);
          return env;
        }
        lastError = ApiException(
          '${plugin.displayName} $method：${env.friendly}',
          detail: env.error,
        );
        // 只有"网络天气"值得重试；插件自己抛的错重试也是同一个结果
        if ((env.kind == 'timeout' || env.kind == 'network') && i < attempts) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          continue;
        }
        break;
      } on PluginEngineException catch (e) {
        runtimePool.recordError(plugin.hash, e, detail: e.detail);
        throw ApiException(e.message, detail: e.detail);
      } catch (e) {
        runtimePool.recordError(plugin.hash, e);
        throw ApiException('${plugin.displayName} $method：$e');
      }
    }
    final err = lastError is ApiException
        ? lastError
        : ApiException('${plugin.displayName} $method 调用失败');
    runtimePool.recordError(plugin.hash, err, detail: err.detail);
    throw err;
  }

  /// 与 [_invoke] 相同，但失败返回 null 而不是抛 —— 取直链要逐档降级，
  /// 一失败就抛会把"换一档再试"的机会也掐掉。
  Future<PluginEnvelope?> _tryInvoke(
    EmbeddedPlugin plugin,
    String method,
    List<dynamic> args, {
    required Duration timeout,
    int attempts = 2,
  }) async {
    try {
      return await _invoke(plugin, method, args,
          timeout: timeout, attempts: attempts);
    } on ApiException {
      return null;
    }
  }

  static String _s(dynamic v) => v == null ? '' : v.toString();

  static String _firstHttp(List<dynamic> candidates) {
    for (final c in candidates) {
      final s = _s(c);
      if (s.startsWith('http')) return s;
    }
    return '';
  }

  static String _short(String s) =>
      s.length > 10 ? '${s.substring(0, 10)}…' : s;
}

/// 自检里的一项结果。
class EngineCheck {
  final String name;
  final bool ok;
  final String cost;
  final String? note;

  const EngineCheck(this.name, this.ok, this.cost, this.note);

  @override
  String toString() =>
      '${ok ? '✅' : '❌'} $name  $cost${note == null ? '' : '  $note'}';
}

/// 全局唯一的插件运行时池在 [runtimePool]（见 runtime_pool.dart），
/// 这里只做一层导出，方便 UI 直接引用而不必 import 两个文件。
RuntimePool get pluginRuntimePool => runtimePool;
