// 内置源引擎测试：用**真实的 QuickJS** 跑一个自建插件（test/fixtures/fake_plugin.js）。
//
// 这不是"单元测试"，而是把 spike 在容器里验证过的那条链路
// （QuickJS ← harness.js ← 插件 ← axios 垫片 ← 依赖模块）在**客户端仓库里**再跑一遍，
// 并且把它变成**可回归的**：以后动 harness / 升级 quickjs_engine / 改契约解析，
// 这条测试会立刻告诉你哪一步坏了。
//
// 前置：需要一个 Linux 的原生桥接库（Android 出包那条路是 NDK 自动编的，与此无关）
//   bash tool/run_embedded_test.sh          ← 一键（同容器内 pub get + 编库 + 跑）
// 手工跑：
//   bash tool/build_native.sh /tmp/mmusic-qjs
//   LIBQUICKJSC_TEST_PATH=/tmp/mmusic-qjs/libquickjs_c_bridge_plugin.so \
//     flutter test test/embedded_engine_test.dart
//
// 没有原生库时**整组跳过并在输出里写明原因** —— 静默绿是最坏的结果，
// 所以这里用 `markTestSkipped` 把原因打到日志里，而不是假装通过。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmusic_client/core/embedded/embedded_plugin.dart';
import 'package:mmusic_client/core/embedded/plugin_assets.dart';
import 'package:mmusic_client/core/embedded/plugin_contract.dart';
import 'package:mmusic_client/core/embedded/plugin_runtime.dart';
import 'package:mmusic_client/core/embedded/runtime_pool.dart';

String _read(String path) => File(path).readAsStringSync();

EmbeddedPlugin _plugin(String hash, {String platform = '测试源'}) =>
    EmbeddedPlugin(
      hash: hash,
      platform: platform,
      version: '0.0.1',
      importedAt: 0,
    );

/// 原生库在不在 —— 决定这一组是"真跑"还是"明确跳过"。
bool _nativeLibAvailable() {
  final override = Platform.environment['LIBQUICKJSC_TEST_PATH'];
  if (override != null && override.isNotEmpty) {
    return File(override).existsSync();
  }
  final name = Platform.isWindows
      ? 'quickjs_c_bridge_plugin.dll'
      : Platform.isMacOS
          ? 'libquickjs_c_bridge_plugin.dylib'
          : 'libquickjs_c_bridge_plugin.so';
  for (final p in [
    'packages/quickjs_engine/native/build/$name',
    'native/build/$name',
    '/tmp/mmusic-qjs/$name',
  ]) {
    if (File(p).existsSync()) return true;
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ★ 与 spike 同一个坑：TestWidgetsFlutterBinding 会把 HttpOverrides.global
  //   换成 mock，**所有真实 HTTP 都返回 400 空 body**，插件拿到空 body 去
  //   JSON.parse 就抛 "Unexpected token in JSON"。看起来像插件坏了。
  //   本组测试不打真网络，但保留这一行以防将来加联网用例时踩回去。
  HttpOverrides.global = null;

  // harness 与依赖产物从磁盘读（测试里没有 asset bundle）。
  // 顺带把"asset 文件真的在仓库里"这件事也验了 —— 见 plugin_contract_test。
  PluginAssets.overrideReaderForTest((key) async => _read(key));

  final hasLib = _nativeLibAvailable();
  if (!hasLib) {
    test('内置源引擎测试（需要原生库）', () {
      markTestSkipped(
        '缺少 QuickJS 原生桥接库，整组跳过。跑法：bash tool/run_embedded_test.sh '
        '（或先 bash tool/build_native.sh /tmp/mmusic-qjs 再设 LIBQUICKJSC_TEST_PATH）',
      );
    });
    return;
  }

  final fakeCode = _read('test/fixtures/fake_plugin.js');
  final incompleteCode = _read('test/fixtures/incomplete_plugin.js');

  group('PluginRuntime —— 装载与元数据', () {
    test('装载自建插件并读出元数据', () async {
      final rt = await PluginRuntime.create(_plugin('p1'), fakeCode);
      try {
        expect(rt.meta.platform, '测试源');
        expect(rt.meta.version, '0.0.1');
        expect(rt.meta.supportedSearchType, ['music', 'sheet']);
        expect(rt.meta.methods, contains('search'));
        expect(rt.meta.methods, contains('getMediaSource'));
        expect(rt.meta.missingCritical, isEmpty);
        // 顶层 require 的两个真依赖都被记下来了（依赖清单是"问"出来的）
        expect(rt.meta.requiredModules, contains('he'));
        expect(rt.meta.requiredModules, contains('dayjs'));
      } finally {
        rt.dispose();
      }
    });

    test('★ 缺关键方法的 JS 会在装载时被拒（别把一个普通库当插件收下）', () async {
      await expectLater(
        PluginRuntime.create(_plugin('bad'), incompleteCode),
        throwsA(isA<PluginEngineException>()
            .having((e) => e.message, 'message', contains('getMediaSource'))),
      );
    });

    test('语法错误的源码会给出带原因的装载失败', () async {
      await expectLater(
        PluginRuntime.create(_plugin('syntax'), 'var x = ((( ;'),
        throwsA(isA<PluginEngineException>()),
      );
    });
  });

  group('PluginRuntime —— 调用与契约', () {
    late PluginRuntime rt;
    setUp(() async {
      rt = await PluginRuntime.create(_plugin('p2'), fakeCode);
    });
    tearDown(() => rt.dispose());

    test('search 返回 {isEnd,data}，解析后拿到 2 条真实结构', () async {
      final env = await rt.call('search', ['晴天', 1, 'music']);
      expect(env.ok, isTrue, reason: env.error);
      final parsed = parsePluginList(env.value);
      expect(parsed.items.length, 2);
      expect(parsed.isEnd, isFalse);
      // he 真的生效了（没 require 到会在插件顶层就抛错）
      expect(parsed.items.first['title'], '晴天 & 测试');
    });

    test('★ getMediaSource 只在收到官方音质词时才给真地址', () async {
      final ok = await rt.call('getMediaSource', [
        {'id': 'song-1', 'title': '晴天'},
        'high',
      ]);
      final url = urlFromMediaSource(ok.value)!;
      expect(url, contains('song-1.mp3'));
      expect(url, contains('level=high'));
      expect(looksPlayableUrl(url), isTrue);

      // 传客户端档位（错误用法）→ 插件拼出 level=undefined
      final bad = await rt.call('getMediaSource', [
        {'id': 'song-1'},
        '320k',
      ]);
      expect(urlFromMediaSource(bad.value), contains('level=undefined'));
    });

    test('★ 上游占位地址能被 looksPlayableUrl 认出来', () async {
      final env = await rt.call('getMediaSource', [
        {'id': 'song-2'},
        'high',
      ]);
      final url = urlFromMediaSource(env.value)!;
      expect(url.startsWith('https://'), isTrue);
      expect(looksPlayableUrl(url), isFalse, reason: '中文占位地址必须判为不可播');
    });

    test('getLyric / getTopLists / getTopListDetail / getMusicSheetInfo 都能通',
        () async {
      expect(
          lyricFromPlugin((await rt.call('getLyric', [
            {'title': 'X'}
          ]))
              .value),
          '[00:01.00]X');

      final tops = parsePluginList((await rt.call('getTopLists', [])).value);
      expect(tops.items.length, 2);
      expect(tops.items.first['title'], '热歌榜');

      final detail = parsePluginList(
          (await rt.call('getTopListDetail', [tops.items.first, 1])).value);
      expect(detail.items.first['id'], 'hot-1');

      final sheet = parsePluginList(
        (await rt.call('getMusicSheetInfo', [
          {'id': 'sheet-1'},
          1
        ]))
            .value,
        listKeys: const ['musicList', 'data'],
      );
      expect(sheet.items.length, 1);
    });

    test('★ 插件抛错时信封是 ok:false，不是把 Dart 侧炸掉', () async {
      final env = await rt.call('boom', []);
      expect(env.ok, isFalse);
      expect(env.method, 'boom');
      expect(env.error, contains('故意的错误'));
      expect(env.friendly, isNotEmpty);
    });

    test('调用不存在的方法给 no-such-method（而不是莫名的 JS 报错）', () async {
      final env = await rt.call('notExist', []);
      expect(env.ok, isFalse);
      expect(env.kind, 'no-such-method');
    });

    test('诊断快照里能看到依赖编译耗时与 HTTP 计数', () async {
      await rt.call('search', ['x', 1, 'music']);
      final diag = rt.diag();
      final m = jsonDecode(diag) as Map;
      expect(m['loaded'], isTrue);
      expect(m['requiredModules'], contains('he'));
      // 懒编译：require 过的模块在 compiled 里有记录（没 require 的不会编译）
      final compiled = (m['compiled'] as List).map((e) => e['name']).toList();
      expect(compiled, contains('he'));
    });
  });

  group('RuntimePool —— 复用、隔离与回收', () {
    test('同一个插件复用同一个运行时（loadCode 只调一次）', () async {
      final pool = RuntimePool(maxAlive: 2);
      var loads = 0;
      Future<String> load() async {
        loads++;
        return fakeCode;
      }

      try {
        final a =
            await pool.use(_plugin('p3'), load, (rt) async => rt.meta.platform);
        final b =
            await pool.use(_plugin('p3'), load, (rt) async => rt.meta.platform);
        expect(a, '测试源');
        expect(b, '测试源');
        expect(loads, 1, reason: '第二次应该命中池子里的运行时');
        expect(pool.isAlive('p3'), isTrue);
      } finally {
        pool.disposeAll();
      }
    });

    test('超过上限时淘汰最久未用的空闲运行时', () async {
      final pool = RuntimePool(maxAlive: 1);
      try {
        await pool.use(_plugin('a'), () async => fakeCode, (rt) async => 0);
        expect(pool.isAlive('a'), isTrue);
        await pool.use(_plugin('b'), () async => fakeCode, (rt) async => 0);
        expect(pool.isAlive('b'), isTrue);
        expect(pool.isAlive('a'), isFalse, reason: '上限 1，第二个进来要淘汰第一个');
      } finally {
        pool.disposeAll();
      }
    });

    test('★ 一个插件装载失败不影响另一个（失败隔离）', () async {
      final pool = RuntimePool(maxAlive: 2);
      try {
        await expectLater(
          pool.use(
              _plugin('broken'), () async => incompleteCode, (rt) async => 0),
          throwsA(isA<PluginEngineException>()),
        );
        final ok = await pool.use(_plugin('good'), () async => fakeCode,
            (rt) async => rt.meta.platform);
        expect(ok, '测试源');
      } finally {
        pool.disposeAll();
      }
    });

    test('evict 之后运行时被释放', () async {
      final pool = RuntimePool(maxAlive: 2);
      try {
        await pool.use(_plugin('x'), () async => fakeCode, (rt) async => 0);
        pool.evict('x');
        expect(pool.isAlive('x'), isFalse);
      } finally {
        pool.disposeAll();
      }
    });

    test('释放后的运行时再调用会明确报错（而不是静默返回空）', () async {
      final rt = await PluginRuntime.create(_plugin('p4'), fakeCode);
      rt.dispose();
      // 这里是**同步抛**的（fail fast，不排进队列）—— 所以用 expect 而不是 expectLater
      expect(
        () => rt.call('search', ['x', 1, 'music']),
        throwsA(isA<PluginEngineException>()
            .having((e) => e.message, 'message', contains('已释放'))),
      );
    });
  });

  group('xhr 桥 —— 真实 HTTP 走引擎注入的 XMLHttpRequest', () {
    // 这一条要打真网络，且打的是**本地起的一次性 HTTP 服务**（不出网、可复现）。
    // 它验证的是整条网络链路：插件 → axios 垫片 → 引擎 XHR → Dart 侧 http。
    late HttpServer server;
    late String base;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((req) {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'ok': true,
          'path': req.uri.path,
          'query': req.uri.query,
        }));
        req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('一次 axios 调用能拿到 JSON 并正确解析', () async {
      // 注意 `axios` 是插件通过 require 拿到的模块，不是宿主注入的全局名
      // （harness 只把 require 交给插件；写成全局的会报 "axios is not defined"）
      final rt = await PluginRuntime.create(_plugin('net'), '''
        var axios = require('axios');
        module.exports = {
          platform: '网络源',
          search: function () { return Promise.resolve({isEnd:true,data:[]}); },
          getMediaSource: function () { return Promise.resolve(''); },
          fetchIt: async function (url, params) {
            var resp = await axios({method: 'get', url: url, params: params});
            return resp.data;
          }
        };
      ''');
      try {
        final env = await rt.call('fetchIt', [
          '$base/probe',
          {'a': '1', 'b': '你好'},
        ]);
        expect(env.ok, isTrue, reason: env.error);
        final data = Map<String, dynamic>.from(env.value as Map);
        expect(data['ok'], isTrue);
        expect(data['path'], '/probe');
        expect(data['query'], contains('a=1'));
        // 中文参数要被正确编码（encodeURIComponent）
        expect(data['query'], contains('b=%E4%BD%A0%E5%A5%BD'));
      } finally {
        rt.dispose();
      }
    });
  });
}
