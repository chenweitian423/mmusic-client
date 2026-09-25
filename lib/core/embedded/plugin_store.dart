/// 插件仓库：落盘、索引、导入、启停、删除。
///
/// 分工明确 ——
///  * **源码**落在应用私有目录 `<appSupport>/plugins/<hash>.js`（不进 SharedPreferences，
///    也不进安装包：插件是**插件作者**的 jsjiami 混淆产物，不该随我们的仓库分发）；
///  * **元数据**（平台名/版本/来源/启用状态/依赖清单）进 SharedPreferences，
///    列表页因此不需要启动 JS 引擎就能渲染。
///
/// `hash` = 源码 SHA256，与服务端语义一致（AGENTS §8.2），同名不同内容不会互相顶替。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';
import 'embedded_plugin.dart';
import 'plugin_contract.dart';
import 'plugin_runtime.dart';

/// 导入失败时抛出，[message] 是给人看的，[detail] 给"详情"。
class PluginImportException implements Exception {
  final String message;
  final String? detail;
  const PluginImportException(this.message, {this.detail});
  @override
  String toString() => message;
}

class PluginStore {
  static const _indexKey = 'embeddedPluginIndex';

  /// 被用户删掉过的**随包内置**插件：记下来，免得下次启动又"复活"。
  static const _dismissedKey = 'embeddedPluginDismissedBuiltins';

  /// 随安装包分发的插件放这里（目录被 .gitignore 忽略 `*.js`，CI 构建出来是空的）。
  static const builtinDir = 'assets/plugins/';

  /// 测试用：把插件目录指到临时目录，避开 path_provider 的平台通道。
  @visibleForTesting
  static Directory? debugDirOverride;

  final ValueNotifier<List<EmbeddedPlugin>> plugins =
      ValueNotifier<List<EmbeddedPlugin>>(<EmbeddedPlugin>[]);

  /// 正在导入（供界面显示进度）。
  final ValueNotifier<bool> importing = ValueNotifier<bool>(false);

  SharedPreferences? _sp;
  Directory? _dir;
  final Map<String, String> _codeCache = {};
  final Set<String> _dismissed = <String>{};

  List<EmbeddedPlugin> get enabled =>
      plugins.value.where((p) => p.enabled).toList();

  EmbeddedPlugin? byHash(String hash) {
    for (final p in plugins.value) {
      if (p.hash == hash) return p;
    }
    return null;
  }

  /// 参与搜索的插件（可按类型过滤，如只支持搜歌单的）。
  List<EmbeddedPlugin> enabledFor([String? searchType]) {
    final list = enabled;
    if (searchType == null) return list;
    return [
      for (final p in list)
        if (p.supports(searchType)) p
    ];
  }

  Future<void> init() async {
    _sp = await SharedPreferences.getInstance();
    final dir = debugDirOverride ??
        Directory('${(await getApplicationSupportDirectory()).path}/plugins');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;

    for (final h in _sp?.getStringList(_dismissedKey) ?? const <String>[]) {
      _dismissed.add(h);
    }
    _loadIndex();
    await _syncBuiltins();
  }

  /// 测试用：跳过 path_provider 与 asset bundle，只把索引读起来。
  @visibleForTesting
  Future<void> initForTest(Directory dir) async {
    debugDirOverride = dir;
    _sp = await SharedPreferences.getInstance();
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    for (final h in _sp?.getStringList(_dismissedKey) ?? const <String>[]) {
      _dismissed.add(h);
    }
    _loadIndex();
  }

  /// 测试用：直接往索引里塞一条记录（绕过需要 JS 引擎的装载过程）。
  @visibleForTesting
  Future<void> putForTest(EmbeddedPlugin plugin, {String? code}) async {
    if (code != null) {
      final file = File('${(await _pluginsDir()).path}/${plugin.hash}.js');
      await file.writeAsString(code);
      _codeCache[plugin.hash] = code;
    }
    await _upsert(plugin);
  }

  // ---------- 读取 ----------

  /// 取插件源码。内存里留一份（30~300KB × 少数几个，换来运行时重建不再读盘）。
  Future<String> code(String hash) async {
    final cached = _codeCache[hash];
    if (cached != null) return cached;
    final file = File('${(await _pluginsDir()).path}/$hash.js');
    if (!await file.exists()) {
      throw PluginImportException('插件源码丢失（$hash）',
          detail: '文件不存在：${file.path}');
    }
    final text = await file.readAsString();
    _codeCache[hash] = text;
    return text;
  }

  // ---------- 导入 ----------

  /// 从 URL 导入。多行文本会被逐行当成 URL（[importFromUrls]）。
  Future<EmbeddedPlugin> importFromUrl(String url, {Dio? dio}) async {
    final u = url.trim();
    if (u.isEmpty) throw const PluginImportException('URL 为空');
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      throw PluginImportException('URL 必须以 http:// 或 https:// 开头', detail: u);
    }
    final client = dio ??
        Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 60),
          followRedirects: true,
          // 作者的分发站会返回 418；把 >=400 也收下来自己判断，
          // 才能给出"站点在拦你"这种能行动的话，而不是一句 DioException。
          validateStatus: (s) => s != null,
          headers: {
            // 有的站点只认浏览器 UA —— 带上不吃亏（实测作者站连 UA 也不认，
            // 但那是站点侧访问控制，不是我们这里的问题）。
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
          },
        ));
    final Response<String> r;
    try {
      r = await client.get<String>(
        u,
        options: Options(responseType: ResponseType.plain),
      );
    } on DioException catch (e) {
      throw PluginImportException('下载失败：${_short(e)}', detail: u);
    }
    final status = r.statusCode ?? 0;
    if (status >= 400) {
      throw PluginImportException(
        '站点拒绝下载（HTTP $status）',
        detail: '这种情况多半是分发站做了访问控制（例如只让公众号渠道拿），'
            '不是地址写错。可改用「粘贴代码」导入。\n$u',
      );
    }
    final body = r.data ?? '';
    _assertLooksLikePlugin(body, source: u);
    return importFromCode(body, origin: 'url', originDetail: u);
  }

  /// 从一段文本里按行导入多个 URL，返回逐条结果（供界面汇总）。
  Future<List<({String target, EmbeddedPlugin? plugin, String? error})>>
      importFromUrls(String text, {Dio? dio}) async {
    final urls = [
      for (final line in text.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    final out = <({String target, EmbeddedPlugin? plugin, String? error})>[];
    importing.value = true;
    try {
      for (final u in urls) {
        try {
          final p = await importFromUrl(u, dio: dio);
          out.add((target: u, plugin: p, error: null));
        } catch (e) {
          out.add((target: u, plugin: null, error: '$e'));
        }
      }
    } finally {
      importing.value = false;
    }
    return out;
  }

  /// 从源码导入（粘贴 / 本地文件读出来的文本 / URL 下载到的内容都走这里）。
  ///
  /// **导入时会真装载一次**：装不上就当场拒绝，而不是把一个坏插件留在列表里
  /// 等用户点了搜索才发现。装载用时也能顺便把平台名/版本/依赖清单落库。
  Future<EmbeddedPlugin> importFromCode(
    String code, {
    String origin = 'paste',
    String originDetail = '',
    bool replaceExisting = true,
  }) async {
    _assertLooksLikePlugin(code,
        source: originDetail.isEmpty ? origin : originDetail);
    final hash = sha256.convert(utf8.encode(code)).toString();
    final existing = byHash(hash);

    if (existing != null && !replaceExisting) return existing;

    // 先落盘再装载：装载要用到插件对象，而这个对象需要 hash 与元数据
    final file = File('${(await _pluginsDir()).path}/$hash.js');
    await file.writeAsString(code);
    _codeCache[hash] = code;

    final draft = EmbeddedPlugin(
      hash: hash,
      platform: existing?.platform ?? '',
      origin: origin,
      originDetail: originDetail,
      enabled: existing?.enabled ?? true,
      order: existing?.order ?? _nextOrder(),
      importedAt: DateTime.now().millisecondsSinceEpoch,
      byteSize: code.length,
    );

    PluginRuntime? rt;
    try {
      rt = await PluginRuntime.create(
        draft,
        code,
        platform: kPluginPlatform,
        appVersion: kAppVersion,
      );
      final meta = rt.meta;
      final plugin = draft.copyWith(
        platform: meta.platform,
        version: meta.version,
        author: meta.author,
        srcUrl: meta.srcUrl,
        supportedSearchType: meta.supportedSearchType,
        requiredModules: meta.requiredModules,
        origin: existing?.origin ?? origin,
        originDetail: originDetail,
        enabled: existing?.enabled ?? true,
        order: existing?.order,
      );
      await _upsert(plugin);
      return plugin;
    } catch (e) {
      // 装不上就不留残骸：文件删掉、运行时（由 create 内部）已释放
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      _codeCache.remove(hash);
      if (e is PluginEngineException) {
        throw PluginImportException(
          '这个插件装载失败：${e.message}',
          detail: e.detail,
        );
      }
      throw PluginImportException('这个插件装载失败：$e');
    } finally {
      rt?.dispose();
    }
  }

  /// 随包内置插件：装一次即"转正"为普通插件，之后可停用/删除。
  Future<void> _syncBuiltins() async {
    final assets = await _listBuiltinAssets();
    if (assets.isEmpty) return;
    for (final key in assets) {
      try {
        final code = await rootBundle.loadString(key);
        if (code.trim().isEmpty) continue;
        final hash = sha256.convert(utf8.encode(code)).toString();
        if (_dismissed.contains(hash)) continue;
        if (byHash(hash) != null) continue;
        await importFromCode(code, origin: 'builtin', originDetail: key);
      } catch (e) {
        // 内置插件装不上不该让 App 起不来 —— 记一条日志继续
        debugPrint('[pluginStore] 内置插件导入失败 $key: $e');
      }
    }
  }

  Future<List<String>> _listBuiltinAssets() async {
    // flutter test / 无 asset bundle 的环境下这里会抛，静默跳过即可
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return manifest
          .listAssets()
          .where((a) => a.startsWith(builtinDir) && a.endsWith('.js'))
          .toList()
        ..sort();
    } catch (_) {
      return const <String>[];
    }
  }

  // ---------- 启停 / 删除 ----------

  Future<void> setEnabled(String hash, bool value) async {
    final p = byHash(hash);
    if (p == null) return;
    await _upsert(p.copyWith(enabled: value));
  }

  Future<void> remove(String hash) async {
    final p = byHash(hash);
    if (p == null) return;
    if (p.origin == 'builtin') {
      // 内置插件删掉后不该在下次启动又冒出来
      _dismissed.add(hash);
      await _sp?.setStringList(_dismissedKey, _dismissed.toList());
    }
    final file = File('${(await _pluginsDir()).path}/$hash.js');
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
    _codeCache.remove(hash);
    plugins.value = [
      for (final e in plugins.value)
        if (e.hash != hash) e,
    ];
    await _saveIndex();
  }

  /// 重新装载一次，用于刷新元数据 / 验证插件是否还活着。
  Future<PluginMeta> reloadMeta(String hash) async {
    final p = byHash(hash);
    if (p == null) throw const PluginImportException('插件不存在');
    final code = await this.code(hash);
    PluginRuntime? rt;
    try {
      rt = await PluginRuntime.create(
        p,
        code,
        platform: kPluginPlatform,
        appVersion: kAppVersion,
      );
      final meta = rt.meta;
      await _upsert(p.copyWith(
        platform: meta.platform,
        version: meta.version,
        author: meta.author,
        srcUrl: meta.srcUrl,
        supportedSearchType: meta.supportedSearchType,
        requiredModules: meta.requiredModules,
        byteSize: code.length,
      ));
      return meta;
    } catch (e) {
      if (e is PluginEngineException) {
        throw PluginImportException(e.message, detail: e.detail);
      }
      rethrow;
    } finally {
      rt?.dispose();
    }
  }

  // ---------- 内部 ----------

  Future<void> _upsert(EmbeddedPlugin plugin) async {
    final list = List<EmbeddedPlugin>.of(plugins.value)
      ..removeWhere((e) => e.hash == plugin.hash)
      ..add(plugin);
    list.sort((a, b) {
      final c = a.order.compareTo(b.order);
      return c != 0 ? c : a.importedAt.compareTo(b.importedAt);
    });
    plugins.value = list;
    await _saveIndex();
  }

  int _nextOrder() {
    var max = 0;
    for (final p in plugins.value) {
      if (p.order > max) max = p.order;
    }
    return max + 1;
  }

  Future<Directory> _pluginsDir() async {
    final d = _dir;
    if (d != null) return d;
    final override = debugDirOverride;
    final dir = override ??
        Directory('${(await getApplicationSupportDirectory()).path}/plugins');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  void _loadIndex() {
    final text = _sp?.getString(_indexKey);
    if (text == null || text.isEmpty) {
      plugins.value = <EmbeddedPlugin>[];
      return;
    }
    try {
      final decoded = jsonDecode(text);
      plugins.value = decoded is List
          ? [
              for (final e in decoded)
                if (e is Map)
                  EmbeddedPlugin.fromJson(Map<String, dynamic>.from(e)),
            ].where((e) => e.hash.isNotEmpty).toList()
          : <EmbeddedPlugin>[];
    } catch (_) {
      plugins.value = <EmbeddedPlugin>[];
    }
  }

  Future<void> _saveIndex() async {
    await _sp?.setString(
      _indexKey,
      jsonEncode([for (final p in plugins.value) p.toJson()]),
    );
  }

  /// 导入前的粗校验交给 [pluginCodeIssue]（纯函数，可单测）。
  static void _assertLooksLikePlugin(String code, {required String source}) {
    final issue = pluginCodeIssue(code);
    if (issue != null) {
      throw PluginImportException(
        issue,
        detail:
            code.length > 200 ? '${code.substring(0, 200)}…\n$source' : source,
      );
    }
  }

  static String _short(Object e) {
    var s = e.toString();
    final nl = s.indexOf('\n');
    if (nl > 0) s = s.substring(0, nl);
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }
}

final pluginStore = PluginStore();
