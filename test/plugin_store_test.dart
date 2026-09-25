import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmusic_client/core/embedded/embedded_plugin.dart';
import 'package:mmusic_client/core/embedded/plugin_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用一个独立的临时目录建一套"干净"的仓库。
///
/// 为什么不直接测全局 `pluginStore`：它会在 SharedPreferences 里留下状态，
/// 测试之间互相污染（顺序一变就红），而且 path_provider 在测试里没有平台通道。
Future<PluginStore> _freshStore(Directory dir) async {
  final store = PluginStore();
  await store.initForTest(dir);
  return store;
}

EmbeddedPlugin _plugin(
  String hash, {
  String platform = '元力KW',
  bool enabled = true,
  String origin = 'url',
  int order = 1,
}) =>
    EmbeddedPlugin(
      hash: hash,
      platform: platform,
      version: '0.1.0',
      enabled: enabled,
      origin: origin,
      order: order,
      importedAt: 1700000000000,
      supportedSearchType: const ['music'],
      byteSize: 1024,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('mmusic-plugins-');
  });

  tearDown(() {
    PluginStore.debugDirOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('插件代码落盘后可读回，且索引能跨实例恢复', () async {
    final store = await _freshStore(dir);
    const code = 'var _0xodM="jsjiami.com.v7"; var platform="元力KW";';
    await store.putForTest(_plugin('h1'), code: code);

    expect(store.plugins.value.length, 1);
    expect(await store.code('h1'), code);

    // 新实例（模拟重启）从 SharedPreferences 里恢复索引
    final reopened = await _freshStore(dir);
    expect(reopened.plugins.value.length, 1);
    expect(reopened.plugins.value.first.hash, 'h1');
    expect(reopened.plugins.value.first.origin, 'url');
    // 代码不需要再走引擎就能读回来
    expect(await reopened.code('h1'), code);
  });

  test('enable / disable 会落库，重启后仍然生效', () async {
    final store = await _freshStore(dir);
    await store.putForTest(_plugin('h1'), code: 'x' * 300);
    await store.putForTest(_plugin('h2', platform: '元力WY', order: 2),
        code: 'y' * 300);

    await store.setEnabled('h1', false);
    expect(store.enabled.length, 1);
    expect(store.enabled.first.hash, 'h2');

    final reopened = await _freshStore(dir);
    expect(reopened.byHash('h1')!.enabled, isFalse);
    expect(reopened.enabledFor('music').map((p) => p.hash), ['h2']);
  });

  test('enabledFor 按插件声明的可搜索类型过滤', () async {
    final store = await _freshStore(dir);
    await store.putForTest(
      _plugin('h1').copyWith(supportedSearchType: const ['music']),
      code: 'x' * 300,
    );
    await store.putForTest(
      _plugin('h2', order: 2).copyWith(supportedSearchType: const ['sheet']),
      code: 'y' * 300,
    );

    expect(store.enabledFor('music').map((p) => p.hash), ['h1']);
    expect(store.enabledFor('sheet').map((p) => p.hash), ['h2']);
    expect(store.enabledFor().length, 2);
  });

  test('删除会同时清掉索引项与磁盘文件', () async {
    final store = await _freshStore(dir);
    await store.putForTest(_plugin('h1'), code: 'x' * 300);
    final file = File('${dir.path}/h1.js');
    expect(file.existsSync(), isTrue);

    await store.remove('h1');
    expect(store.plugins.value, isEmpty);
    expect(file.existsSync(), isFalse);

    // 内存里那份也清掉，避免删了还能读出来
    expect(() => store.code('h1'), throwsA(isA<PluginImportException>()));
  });

  test('★ 删掉内置插件后，重启不会再"复活"', () async {
    final store = await _freshStore(dir);
    await store.putForTest(_plugin('builtin1', origin: 'builtin'),
        code: 'x' * 300);
    await store.remove('builtin1');

    final reopened = await _freshStore(dir);
    expect(reopened.plugins.value, isEmpty);
    // 标记落在 SharedPreferences 里（内置插件是随包分发的，不记下来就会反复导入）
    final sp = await SharedPreferences.getInstance();
    expect(sp.getStringList('embeddedPluginDismissedBuiltins'),
        contains('builtin1'));
  });

  test('删除普通（URL 导入）插件不写 dismissed 标记', () async {
    final store = await _freshStore(dir);
    await store.putForTest(_plugin('h1'), code: 'x' * 300);
    await store.remove('h1');
    final sp = await SharedPreferences.getInstance();
    expect(sp.getStringList('embeddedPluginDismissedBuiltins') ?? [], isEmpty);
  });

  test('索引条目按 order 排序，导入顺序不影响展示顺序', () async {
    final store = await _freshStore(dir);
    await store.putForTest(_plugin('c', order: 3), code: 'a' * 300);
    await store.putForTest(_plugin('a', order: 1), code: 'b' * 300);
    await store.putForTest(_plugin('b', order: 2), code: 'c' * 300);
    expect(store.plugins.value.map((p) => p.hash), ['a', 'b', 'c']);
  });

  test('索引损坏时降级为空列表，不抛异常（启动不能被一条脏数据卡死）', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('embeddedPluginIndex', '这不是 JSON');
    final store = await _freshStore(dir);
    expect(store.plugins.value, isEmpty);
  });

  test('code() 找不到文件时给出可行动的异常', () async {
    final store = await _freshStore(dir);
    await store.putForTest(_plugin('h1')); // 不写文件
    await expectLater(
      store.code('h1'),
      throwsA(isA<PluginImportException>()
          .having((e) => e.message, 'message', contains('源码丢失'))),
    );
  });

  test('索引 JSON 里不含插件源码（源码只落文件）', () async {
    final store = await _freshStore(dir);
    await store.putForTest(_plugin('h1'), code: 'SECRET_PLUGIN_BODY' * 40);
    final sp = await SharedPreferences.getInstance();
    final idx = sp.getString('embeddedPluginIndex') ?? '';
    expect(idx.contains('SECRET_PLUGIN_BODY'), isFalse);
    expect(jsonDecode(idx), isA<List>());
  });

  test('导入前的粗校验：HTML / JSON / 空内容都拒掉', () async {
    final store = await _freshStore(dir);
    await expectLater(
      store.importFromCode('<html>418</html>${' ' * 300}'),
      throwsA(isA<PluginImportException>()),
    );
    await expectLater(
      store.importFromCode('{"detail":"需要登录"}${' ' * 300}'),
      throwsA(isA<PluginImportException>()),
    );
    await expectLater(
      store.importFromCode(''),
      throwsA(isA<PluginImportException>()),
    );
    // 校验失败不该留下任何残骸
    expect(store.plugins.value, isEmpty);
  });

  test('URL 为空 / 协议不对时立刻拒绝', () async {
    final store = await _freshStore(dir);
    await expectLater(
        store.importFromUrl('  '), throwsA(isA<PluginImportException>()));
    await expectLater(store.importFromUrl('ftp://x/a.js'),
        throwsA(isA<PluginImportException>()));
    await expectLater(
      store.importFromUrl('file:///tmp/a.js'),
      throwsA(isA<PluginImportException>()),
    );
  });
}
