/// 单个插件 = 一个独立的 JS 运行时。
///
/// 为什么必须一插件一运行时（而不是共用一个）：
///  * **失败隔离** —— 一个插件把 JS 上下文搞崩（死循环、内存爆掉、全局变量污染），
///    不该带走另外两个源；
///  * **可诊断** —— assert 报错时能明确是哪个插件；
///  * spike 的实测数据就是按插件分开记的，内存/耗时口径一致，便于对比。
///
/// 代价是内存：每个运行时约 5~11MB（实测），所以上层有 [RuntimePool] 做 LRU 回收。
library;

import 'dart:async';
import 'dart:convert';

import 'package:quickjs_engine/extensions/xhr.dart';
import 'package:quickjs_engine/quickjs_engine.dart';

import 'embedded_plugin.dart';
import 'plugin_assets.dart';
import 'plugin_contract.dart';

/// 引擎层面的失败（装载失败 / 调用抛错 / 超时）。
///
/// 与 [PluginEnvelope] 的分工：信封负责"插件正常跑完了但返回错误"，
/// 这里负责"插件根本没能跑起来"。两者对用户的含义完全不同
/// （前者是插件/上游的问题，后者是宿主或插件包本身的问题）。
class PluginEngineException implements Exception {
  final String message;

  /// 技术细节（依赖清单、HTTP 记录摘要），给"详情"用。
  final String? detail;

  const PluginEngineException(this.message, {this.detail});

  @override
  String toString() => message;
}

class PluginRuntime {
  PluginRuntime._(this.plugin, this.meta, this._js);

  final EmbeddedPlugin plugin;
  final PluginMeta meta;
  final JavascriptRuntime _js;

  bool _disposed = false;

  /// 被标记为"可能卡住了"（Dart 层超时过）。不再复用，等延迟回收。
  bool get poisoned => _poisoned;
  bool _poisoned = false;

  Timer? _reclaimTimer;

  /// 同一运行时的调用必须串行 —— JS 上下文只有一个，Promise 的推进靠引擎
  /// 的周期轮询（`executePendingJob`），并发调用会互相踩。
  Future<void> _lock = Future<void>.value();

  String? _diagCache;

  bool get disposed => _disposed;

  /// 装载一个插件。耗时主要在 JS 侧：混淆代码 `new Function` + 顶层 require。
  /// 实测 59~157ms（Linux 容器），真机略有差异。
  static Future<PluginRuntime> create(
    EmbeddedPlugin plugin,
    String code, {
    Map<String, String> envVariables = const {},
    String platform = 'android',
    String appVersion = '1.0.0',
  }) async {
    final bundle = await PluginAssets.load();
    final js = getJavascriptRuntime(xhr: false);
    try {
      // xhr:false 是**必须**的：默认的 enableFetch() 会用 rootBundle 去读一个
      // 写死的 `packages/flutter_js/assets/js/fetch.js`，而插件声明的资源键是
      // `packages/quickjs_engine/assets/js/...` —— 路径不匹配，默认路径必抛异常。
      // 我们只要 XMLHttpRequest，所以自己注入（`enableXhr` 未被包导出，
      // 得从 extensions/xhr.dart 进）。
      js.enableXhr();

      _evalOrThrow(js, bundle.harness, '装载 harness');
      _evalOrThrow(js, '__setPlatform(${jsonEncode(platform)})', '设置平台');
      _evalOrThrow(js, '__setAppVersion(${jsonEncode(appVersion)})', '设置版本');
      // 两层 encode：JS 侧的 __setEnvVars 收的是一个 JSON 字符串
      _evalOrThrow(
        js,
        '__setEnvVars(${jsonEncode(jsonEncode(envVariables))})',
        '注入用户变量',
      );

      // axios 是我们的垫片（走引擎注入的 XHR）；其余依赖**只登记源码**，
      // 谁 require 谁才编译（见 plugin_assets.dart 的说明）。
      _evalOrThrow(js, '__defineModule("axios", __axios)', '注册 axios 垫片');
      for (final e in bundle.modules.entries) {
        _evalOrThrow(
          js,
          '__defineModuleSource(${jsonEncode(e.key)}, ${jsonEncode(e.value)})',
          '登记依赖 ${e.key}',
        );
      }

      final metaRes =
          _evalOrThrow(js, '__loadPlugin(${jsonEncode(code)})', '加载插件');
      final metaMap = jsonDecode(metaRes.stringResult);
      if (metaMap is! Map) {
        throw const PluginEngineException('插件加载后没有返回元数据');
      }
      final meta = PluginMeta.fromJson(Map<String, dynamic>.from(metaMap));
      final missing = meta.missingCritical;
      if (missing.isNotEmpty) {
        throw PluginEngineException(
          '这不是一个可用的 MusicFree 插件：缺少 ${missing.join(' / ')} 方法',
          detail: '导出的方法：${meta.methods.join(', ')}',
        );
      }
      return PluginRuntime._(plugin, meta, js);
    } catch (e) {
      // 装载失败必须把上下文释放掉，否则每次重试都漏一个 JS 运行时
      try {
        js.dispose();
      } catch (_) {}
      rethrow;
    }
  }

  /// 调用一个插件方法，返回结构化信封（永不抛 JS 异常 —— 见 harness 的 `__callJsonSafe`）。
  ///
  /// [timeout] 必须**大于** harness 里 XHR 的 20s 默认超时：JS 侧先超时会走到
  /// axios 的 reject 分支，信封能带回一句有用的话；若 Dart 侧先超时，我们只能
  /// 说"超时了"，而且引擎里那个 Promise 还在轮询。
  Future<PluginEnvelope> call(
    String method,
    List<dynamic> args, {
    Duration timeout = const Duration(seconds: 32),
  }) {
    if (_disposed) {
      throw PluginEngineException('插件运行时已释放（${plugin.displayName}）');
    }
    return _serialize(() async {
      final expr = '__callJsonSafe(${jsonEncode(method)}, ${jsonEncode(args)})';
      final JsEvalResult raw;
      try {
        raw = _js.evaluate(expr);
      } catch (e) {
        throw PluginEngineException('调用 ${plugin.displayName}.$method 失败：$e');
      }
      if (raw.isError) {
        throw PluginEngineException(
          '调用 $method 时 JS 抛错：${raw.stringResult}',
          detail: diag(),
        );
      }

      JsEvalResult res;
      try {
        res = await _js.handlePromise(raw, timeout: timeout);
      } on TimeoutException {
        // 不可复用：引擎内部还在为这个 Promise 轮询，上下文状态不干净。
        // 延迟回收而不是立刻 dispose —— 需要给那个 Promise 一点时间自行落定，
        // 否则引擎的周期轮询会在已释放的上下文上继续跑。
        _poison();
        throw PluginEngineException(
          '插件调用超时（$method，${timeout.inSeconds}s）',
          detail: diag(),
        );
      } catch (e) {
        _poison();
        throw PluginEngineException(
          '插件调用失败（$method）：$e',
          detail: diag(),
        );
      }
      return PluginEnvelope.parse(_stringOf(res));
    });
  }

  /// 引擎自检（是否会用到，取决于排障场景；真机上用来确认能力与容器一致）。
  String probe() {
    if (_disposed) return '{}';
    try {
      return _js.evaluate('__engineProbe()').stringResult;
    } catch (e) {
      return '{"error":${jsonEncode('$e')}}';
    }
  }

  /// 诊断快照：依赖清单 / 已编译模块耗时 / 插件 console / HTTP 记录。
  ///
  /// 失败时把它塞进异常 detail —— 排查"插件坏了 vs 上游变了"第一眼就要看这个，
  /// 而不是去读那些被 jsjiami 塞进字符串表的字段名。
  String diag() {
    final cached = _diagCache;
    if (cached != null) return cached;
    if (_disposed) return '{}';
    try {
      final d = _js.evaluate('__diag()').stringResult;
      _diagCache = d;
      return d;
    } catch (e) {
      return '{"error":${jsonEncode('$e')}}';
    }
  }

  /// 人话版诊断摘要：把 diag 里最有用的两条抽出来。
  String diagSummary() {
    try {
      final m = jsonDecode(diag());
      if (m is! Map) return '';
      final parts = <String>[];
      final compiled = m['compiled'];
      if (compiled is List && compiled.isNotEmpty) {
        parts.add(
          '依赖编译：${compiled.map((e) => '${e['name']}=${e['ms']}ms').join(' ')}',
        );
      }
      final http = m['httpLog'];
      if (http is List && http.isNotEmpty) {
        var send = 0, done = 0;
        for (final e in http) {
          if (e is! Map) continue;
          if (e['phase'] == 'send') send++;
          if (e['phase'] == 'done') done++;
        }
        parts.add('HTTP：发出 $send 次 / 完成 $done 次');
        // 发出去了但一次没回来 —— 这是"上游限流"与"我们自己坏了"的分水岭
        if (send > 0 && done == 0) parts.add('请求发出但无响应（上游/网络问题）');
      }
      final console = m['consoleLog'];
      if (console is List && console.isNotEmpty) {
        parts.add('插件日志：${console.last}');
      }
      return parts.join('；');
    } catch (_) {
      return '';
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _reclaimTimer?.cancel();
    _reclaimTimer = null;
    try {
      _js.dispose();
    } catch (_) {}
  }

  /// 超时/异常之后不复用这个运行时，但也不立刻销毁（见 [call] 里的说明）。
  void _poison() {
    if (_poisoned) return;
    _poisoned = true;
    _diagCache = null;
    _reclaimTimer = Timer(const Duration(seconds: 90), dispose);
  }

  Future<T> _serialize<T>(Future<T> Function() fn) {
    final next = _lock.then((_) => fn(), onError: (_) => fn());
    // 锁本身不能因为一次失败就断掉（后续调用还得能进来）
    _lock = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  static String _stringOf(JsEvalResult res) {
    final s = res.stringResult;
    if (s.isNotEmpty && s != 'null') return s;
    final raw = res.rawResult;
    return raw is String ? raw : s;
  }

  static JsEvalResult _evalOrThrow(
    JavascriptRuntime js,
    String code,
    String what,
  ) {
    final r = js.evaluate(code);
    if (r.isError) {
      throw PluginEngineException('$what 失败：${r.stringResult}');
    }
    return r;
  }
}
