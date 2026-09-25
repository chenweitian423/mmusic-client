/// 插件运行所需的静态资源：harness.js + 6 个依赖产物。
///
/// 三件事在这里收口：
///  ① **只读一次盘**。6 个模块共约 780KB，每个插件都要用；原来（spike 版）是
///     每个运行时各读一遍，纯属浪费。
///  ② 读盘方式可替换（[reader]）—— `flutter test` 里没有 asset bundle，
///     测试换成读磁盘，正式运行时才走 rootBundle。
///  ③ 依赖产物**懒编译**：这里只把源码交给 JS 侧的 `__defineModuleSource`，
///     真正 `new Function(...)` 发生在插件第一次 `require` 它的时候。
///     cheerio 一个 343KB，而只有网易会 require 它（见 harness 的注释）。
library;

import 'package:flutter/services.dart' show rootBundle;

/// 资源键 → 文本。默认走 Flutter 的 asset bundle；测试里可替换成读本地文件。
typedef AssetTextReader = Future<String> Function(String key);

/// 一次装载好的 harness + 全部依赖源码。
class HarnessBundle {
  final String harness;

  /// 模块名（插件 `require()` 时用的字符串）→ UMD/CJS 源码。
  final Map<String, String> modules;

  const HarnessBundle({required this.harness, required this.modules});

  int get totalBytes =>
      harness.length + modules.values.fold<int>(0, (a, b) => a + b.length);
}

class PluginAssets {
  static const String harnessPath = 'assets/js/harness.js';

  /// 模块名 → 资源路径。
  ///
  /// 这份清单不是猜的，是 `__scanRequires` 把三个插件各扫一遍得到的**并集**
  /// （见 `mmusic-embedded-spike/README.md` §3.2）。产物由 `tool/fetch_gen.sh`
  /// 生成，版本全部钉死 —— 换版本就等于换一份依赖，得重新验证契约。
  static const Map<String, String> modulePaths = {
    'he': 'assets/gen/he.js',
    'dayjs': 'assets/gen/dayjs.js',
    'qs': 'assets/gen/qs.js',
    'crypto-js': 'assets/gen/crypto-js.js',
    'big-integer': 'assets/gen/big-integer.js',
    'cheerio': 'assets/gen/cheerio.js',
  };

  static AssetTextReader reader = _rootBundleReader;

  static Future<String> _rootBundleReader(String key) =>
      rootBundle.loadString(key);

  static HarnessBundle? _cache;

  /// 取（并缓存）harness 与依赖源码。
  static Future<HarnessBundle> load({bool refresh = false}) async {
    final cached = _cache;
    if (cached != null && !refresh) return cached;

    final harness = await reader(harnessPath);
    final modules = <String, String>{};
    for (final e in modulePaths.entries) {
      modules[e.key] = await reader(e.value);
    }
    final bundle = HarnessBundle(harness: harness, modules: modules);
    _cache = bundle;
    return bundle;
  }

  /// 测试用：换掉读取器并清掉缓存。
  static void overrideReaderForTest(AssetTextReader r) {
    reader = r;
    _cache = null;
  }

  /// 测试用：恢复默认并清缓存。
  static void reset() {
    reader = _rootBundleReader;
    _cache = null;
  }
}
