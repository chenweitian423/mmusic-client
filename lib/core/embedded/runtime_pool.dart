/// 插件运行时的池子：懒加载 + 失败隔离 + LRU 回收。
///
/// 三个必须解决的问题：
///  ① **首次调用要等装载**（60~160ms 起，含依赖编译）。做成懒加载，
///     用到哪个插件才装哪个 —— App 冷启动不为没打开的源付内存。
///  ② **内存**。每个运行时 5~11MB（实测），三个插件全常驻就是 30MB 级别。
///     所以只保留 [maxAlive] 个，超出时淘汰最久没用且**当前空闲**的那个。
///  ③ **失败隔离**。任何一次装载失败只影响那一个插件，错误原文留在池子里
///     供界面展示；其它插件照常。
library;

import 'dart:async';
import 'dart:collection';

import 'embedded_plugin.dart';
import 'plugin_runtime.dart';

/// 池子里一个运行时的状态（给插件管理页展示）。
class RuntimeStat {
  final String hash;
  final bool alive;
  final bool poisoned;
  final int activeCalls;
  final int idleMs;
  final String? lastError;

  const RuntimeStat({
    required this.hash,
    required this.alive,
    required this.poisoned,
    required this.activeCalls,
    required this.idleMs,
    this.lastError,
  });
}

class RuntimePool {
  RuntimePool({this.maxAlive = 2});

  /// 同时存活的运行时上限。默认 2：够覆盖"搜索完一首歌立刻取直链"这种相邻调用，
  /// 又不至于让 3 个源的 JS 上下文长期常驻。
  final int maxAlive;

  final LinkedHashMap<String, PluginRuntime> _alive = LinkedHashMap();
  final Map<String, int> _active = {};
  final Map<String, int> _lastUsedAt = {};
  final Map<String, String> _errors = {};

  /// 正在创建中的运行时：并发的同一个插件请求共享同一次装载，
  /// 否则首屏"发现页一次搜两个源"会各装一遍（内存与耗时都翻倍）。
  final Map<String, Future<PluginRuntime>> _creating = {};

  /// 取一个可用的运行时执行 [body]，用完归还。
  ///
  /// [loadCode] 只在真的需要新建运行时时才会被调用（装载失败时不缓存错误代码）。
  Future<T> use<T>(
    EmbeddedPlugin plugin,
    Future<String> Function() loadCode,
    Future<T> Function(PluginRuntime rt) body, {
    Map<String, String> env = const {},
  }) async {
    final rt = await _acquire(plugin, loadCode, env);
    _active[rt.plugin.hash] = (_active[rt.plugin.hash] ?? 0) + 1;
    _lastUsedAt[rt.plugin.hash] = DateTime.now().millisecondsSinceEpoch;
    try {
      return await body(rt);
    } finally {
      final n = (_active[rt.plugin.hash] ?? 1) - 1;
      _active[rt.plugin.hash] = n < 0 ? 0 : n;
      _lastUsedAt[rt.plugin.hash] = DateTime.now().millisecondsSinceEpoch;
    }
  }

  Future<PluginRuntime> _acquire(
    EmbeddedPlugin plugin,
    Future<String> Function() loadCode,
    Map<String, String> env,
  ) async {
    final hash = plugin.hash;

    final existing = _alive[hash];
    if (existing != null && existing.disposed) {
      _alive.remove(hash);
    } else if (existing != null && !existing.poisoned) {
      // 命中即刷新 LRU 位置：LinkedHashMap 的插入顺序就是淘汰顺序
      _alive.remove(hash);
      _alive[hash] = existing;
      return existing;
    } else if (existing != null) {
      // 卡过的上下文不复用（引擎内部的 Promise 轮询可能还挂在它上面）
      _alive.remove(hash);
    }

    final inflight = _creating[hash];
    if (inflight != null) return inflight;

    // ★ 这里**不能**写成 `f.whenComplete(() => _creating.remove(hash))`。
    //
    //   箭头函数会**把被删除的值返回出去**，而 `_creating` 里存的正是
    //   "`whenComplete` 之后那个新 future"本身 —— 于是 whenComplete 认为
    //   "回调返回了一个 Future，我要等它完成"，而那个 Future 正在等这次回调
    //   ⇒ **自己等自己，永久挂起**（表现：池里的第一个 use 永远不返回，
    //   事件循环还是活的、定时器照跳，只有这个 Future 不完成，极难定位）。
    //
    // ★ 也**不能**在 catch 里 `rethrow` 之后不管 completer：
    //   那样 `completer.future` 就成了"没人监听的失败 Future"，
    //   在测试里会被报成 unhandled error（生产里则是一句没人看得懂的日志）。
    //   统一让调用方 await 同一个 completer.future，错误只有一条出口。
    final completer = Completer<PluginRuntime>();
    _creating[hash] = completer.future;
    try {
      _evictIfNeeded();
      final code = await loadCode();
      final rt = await PluginRuntime.create(plugin, code, envVariables: env);
      _alive[hash] = rt;
      _errors.remove(hash);
      completer.complete(rt);
    } catch (e, st) {
      completer.completeError(e, st);
    } finally {
      _creating.remove(hash);
    }
    return completer.future;
  }

  /// 淘汰一个空闲的最久未用运行时（绝不淘汰正在调用的、也绝不淘汰刚建好的）。
  void _evictIfNeeded() {
    while (_alive.length >= maxAlive) {
      String? victim;
      for (final hash in _alive.keys) {
        if ((_active[hash] ?? 0) > 0) continue;
        victim = hash;
        break;
      }
      if (victim == null) return; // 全在忙，宁可超限也不打断调用
      final rt = _alive.remove(victim);
      rt?.dispose();
    }
  }

  /// 主动丢掉某个插件的运行时（插件被删/被重新导入/被停用时调用）。
  void evict(String hash) {
    _alive.remove(hash)?.dispose();
    _errors.remove(hash);
    _lastUsedAt.remove(hash);
  }

  void disposeAll() {
    for (final rt in _alive.values) {
      rt.dispose();
    }
    _alive.clear();
    _active.clear();
    _errors.clear();
  }

  /// 记录一次装载/调用失败，供界面展示（不抛出，调用方自己决定怎么报）。
  void recordError(String hash, Object error, {String? detail}) {
    _errors[hash] =
        detail == null || detail.isEmpty ? '$error' : '$error\n$detail';
  }

  String? lastError(String hash) => _errors[hash];

  void clearError(String hash) => _errors.remove(hash);

  bool isAlive(String hash) {
    final rt = _alive[hash];
    return rt != null && !rt.disposed && !rt.poisoned;
  }

  PluginRuntime? peek(String hash) {
    final rt = _alive[hash];
    return (rt == null || rt.disposed) ? null : rt;
  }

  List<RuntimeStat> stats() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final hashes = <String>{..._alive.keys, ..._errors.keys};
    return [
      for (final h in hashes)
        RuntimeStat(
          hash: h,
          alive: isAlive(h),
          poisoned: _alive[h]?.poisoned ?? false,
          activeCalls: _active[h] ?? 0,
          idleMs: _lastUsedAt[h] == null ? -1 : now - _lastUsedAt[h]!,
          lastError: _errors[h],
        ),
    ];
  }
}

/// 全局唯一的运行时池（插件管理页与内置源共用同一份运行时）。
final runtimePool = RuntimePool();
