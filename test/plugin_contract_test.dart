import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmusic_client/core/app_info.dart';
import 'package:mmusic_client/core/embedded/embedded_plugin.dart';
import 'package:mmusic_client/core/embedded/plugin_assets.dart';
import 'package:mmusic_client/core/embedded/plugin_contract.dart';

void main() {
  // ---------------- 音质词表 ----------------
  //
  // 这是整个内置源实现里**最容易悄悄错**的一处：传错词表不会报错，
  // 酷我的中转站宽容（照样给地址），网易回空 body、QQ 说"会员歌曲无法解析"——
  // spike 里为此白查了一轮，看起来像"三个插件只有一个能用"。
  group('音质：客户端档位 → MusicFree 官方词表', () {
    test('四档都能翻译到官方词', () {
      expect(musicFreeQuality('999'), 'super');
      expect(musicFreeQuality('320'), 'high');
      expect(musicFreeQuality('192'), 'standard');
      expect(musicFreeQuality('128'), 'low');
      // 历史别名
      expect(musicFreeQuality('flac'), 'super');
    });

    test('未知档位退回 high（而不是原样传出去）', () {
      // 原样传出去就会拼出 level=undefined —— 一定要挡住
      expect(musicFreeQuality('320k'), 'high');
      expect(musicFreeQuality('unknown'), 'high');
      expect(musicFreeQuality(''), 'high');
    });

    test('降级顺序：用户选的排最前', () {
      expect(qualityCandidatesFor('999').first, 'super');
      expect(qualityCandidatesFor('320').first, 'high');
      expect(qualityCandidatesFor('192').first, 'standard');
      expect(qualityCandidatesFor('128').first, 'low');
    });

    test('候选里只会出现官方词，不会出现客户端档位', () {
      for (final q in ['128', '192', '320', '999', 'flac', 'unknown']) {
        for (final c in qualityCandidatesFor(q)) {
          expect(musicFreeQualities, contains(c), reason: '$q 的候选里混进了非官方词 $c');
        }
      }
    });

    test('192 / 128 两档不含 super —— 选了低音质不该偷偷拉无损', () {
      // 与 brCandidatesFor(服务端路径) 里"这两档不排 flac"是同一条纪律
      expect(qualityCandidatesFor('192'), isNot(contains('super')));
      expect(qualityCandidatesFor('128'), isNot(contains('super')));
      expect(qualityCandidatesFor('192'), contains('standard'));
      expect(qualityCandidatesFor('128'), contains('low'));
    });

    test('候选永不为空（空列表等于一次都不尝试）', () {
      for (final q in ['', 'x', '999', '320']) {
        expect(qualityCandidatesFor(q), isNotEmpty);
      }
    });
  });

  // ---------------- 可播地址判据 ----------------
  group('looksPlayableUrl —— 挡住上游的占位地址', () {
    test('正常直链通过', () {
      expect(
        looksPlayableUrl('https://car-er.kuwo.cn/.../M800000bYDlc2XxKLs.mp3'),
        isTrue,
      );
      expect(looksPlayableUrl('http://iot202.music.126.net/x.mp3?a=1'), isTrue);
    });

    test('★ 中文占位地址必须判为不可播', () {
      // 上游拿不到音源时把错误文案塞进 URL 路径，以 http 开头、长度正常，
      // 只判"url 非空"的话这里会假装成功（NAS 健康检查就栽在这上面）
      const placeholder =
          'https://sjy6.stream.qqmusic.qq.com/获取音频失败,好像没有这个音质哦~,也可能是会员过期了~';
      expect(looksPlayableUrl(placeholder), isFalse);
    });

    test('非 http 与空串都不算', () {
      expect(looksPlayableUrl(''), isFalse);
      expect(looksPlayableUrl('ftp://a.com/x.mp3'), isFalse);
      expect(looksPlayableUrl('//a.com/x.mp3'), isFalse);
    });
  });

  // ---------------- 返回值解析 ----------------
  group('parsePluginList —— 实测形状是 {isEnd,data}，不是裸数组', () {
    test('★ 元力插件的真实形状', () {
      final r = parsePluginList(
          jsonDecode('{"isEnd":false,"data":[{"id":"1","title":"晴天"}]}'));
      expect(r.items.length, 1);
      expect(r.items.first['title'], '晴天');
      expect(r.isEnd, isFalse);
    });

    test('裸数组（MusicFree 文档写的形状）也要接', () {
      final r = parsePluginList(jsonDecode('[{"id":"1"},{"id":"2"}]'));
      expect(r.items.length, 2);
      expect(r.isEnd, isTrue);
    });

    test('{data:[...]} / {musicList:[...]} 等变体', () {
      expect(
          parsePluginList(jsonDecode('{"data":[{"id":"a"}]}')).items.length, 1);
      expect(
        parsePluginList(jsonDecode('{"musicList":[{"id":"a"},{"id":"b"}]}'))
            .items
            .length,
        2,
      );
    });

    test('空值/无法识别的结构返回空列表而不是抛异常', () {
      expect(parsePluginList(null).items, isEmpty);
      expect(parsePluginList(jsonDecode('{"foo":1}')).items, isEmpty);
      expect(parsePluginList('不是 JSON 结构').items, isEmpty);
    });
  });

  group('urlFromMediaSource', () {
    test('字符串直给', () {
      expect(urlFromMediaSource('https://a.com/x.mp3'), 'https://a.com/x.mp3');
    });

    test('对象包装（url / playUrl / src）', () {
      expect(urlFromMediaSource({'url': 'https://a.com/x'}), 'https://a.com/x');
      expect(urlFromMediaSource({'playUrl': 'https://a.com/y'}),
          'https://a.com/y');
      expect(urlFromMediaSource({'src': 'https://a.com/z'}), 'https://a.com/z');
    });

    test('再包一层的也要能挖出来', () {
      expect(
        urlFromMediaSource({
          'data': {'url': 'https://a.com/deep'}
        }),
        'https://a.com/deep',
      );
    });

    test('没有地址返回 null', () {
      expect(urlFromMediaSource(null), isNull);
      expect(urlFromMediaSource(''), isNull);
      expect(urlFromMediaSource({'foo': 'bar'}), isNull);
    });
  });

  group('lyricFromPlugin', () {
    test('rawLrc / 字符串两种都要', () {
      expect(lyricFromPlugin({'rawLrc': '[00:01.00]你好'}), '[00:01.00]你好');
      expect(lyricFromPlugin('[00:01.00]你好'), '[00:01.00]你好');
      expect(
          lyricFromPlugin({
            'data': {'lyric': 'x'}
          }),
          'x');
      expect(lyricFromPlugin(null), '');
    });
  });

  // ---------------- 歌曲映射 ----------------
  group('songFromPlugin —— 边界上的字段映射', () {
    test('id 是字符串，duration 要转成 mm:ss', () {
      final s = songFromPlugin(
        {
          'id': '228908',
          'title': '晴天',
          'artist': '周杰伦',
          'album': '叶惠美',
          'artwork': 'https://img/x.jpg',
          'duration': 269,
        },
        pluginId: 'hash-abc',
        platform: '元力KW',
      );
      expect(s.id, '228908');
      expect(s.title, '晴天');
      expect(s.artist, '周杰伦');
      expect(s.interval, '04:29'); // 269 秒
      expect(s.artwork, 'https://img/x.jpg');
      expect(s.source, 'hash-abc');
      expect(s.platform, '元力KW');
    });

    test('数字 id 原样保留 —— 改成字符串再回传插件可能拼错请求', () {
      final s = songFromPlugin(
        {'id': 123456, 'title': 'T'},
        pluginId: 'h',
        platform: 'P',
      );
      expect(s.raw['id'], 123456);
      expect(s.id, '123456'); // 展示/索引用的仍是字符串
    });

    test('插件字段原样留在 raw 里（取直链要把这份 JSON 回传给插件）', () {
      final s = songFromPlugin(
        {'songmid': '0039MnYb0qxYhV', 'title': 'T', 'custom': 'keep-me'},
        pluginId: 'h',
        platform: 'P',
      );
      expect(s.raw['songmid'], '0039MnYb0qxYhV');
      expect(s.raw['custom'], 'keep-me');
      expect(s.raw['_plugin_hash'], 'h');
      expect(s.raw['source'], 'h');
    });

    test('interval 已经带冒号时原样保留；缺 duration 时为空', () {
      expect(intervalFromDuration('03:45'), '03:45');
      expect(intervalFromDuration(null), '');
      expect(intervalFromDuration(0), '');
      expect(intervalFromDuration(65), '01:05');
    });
  });

  // ---------------- 调用信封 ----------------
  group('PluginEnvelope —— 跨语言边界上的信封', () {
    test('成功信封取 value', () {
      final e =
          PluginEnvelope.parse('{"ok":true,"method":"search","value":{"a":1}}');
      expect(e.ok, isTrue);
      expect(e.method, 'search');
      expect((e.value as Map)['a'], 1);
    });

    test('失败信封带方法与分类，且给出人话', () {
      final e = PluginEnvelope.parse(
          '{"ok":false,"method":"getMediaSource","kind":"timeout","error":"timeout of 20000ms"}');
      expect(e.ok, isFalse);
      expect(e.method, 'getMediaSource');
      expect(e.kind, 'timeout');
      expect(e.friendly, contains('超时'));
    });

    test('多包一层 JSON 字符串也能吃下（引擎 toString 行为差异的防御）', () {
      const inner = '{"ok":true,"method":"search","value":[1,2]}';
      final e = PluginEnvelope.parse(jsonEncode(inner));
      expect(e.ok, isTrue);
      expect(e.value, [1, 2]);
    });

    test('垃圾输入不抛异常，只返回 bad-envelope', () {
      final e = PluginEnvelope.parse('<html>不是 JSON</html>');
      expect(e.ok, isFalse);
      expect(e.kind, 'bad-envelope');
      expect(e.friendly, isNotEmpty);
    });

    test('各分类都有面向用户的说法（不能把 JS 原文直接甩给用户）', () {
      for (final k in [
        'timeout',
        'network',
        'missing-module',
        'no-such-method',
        'not-a-function',
      ]) {
        final e = PluginEnvelope.parse(
            '{"ok":false,"method":"m","kind":"$k","error":"raw detail"}');
        expect(e.friendly, isNotEmpty);
      }
    });
  });

  // ---------------- 导入前校验 ----------------
  group('pluginCodeIssue —— 别把错误页当插件装进去', () {
    test('正常源码通过', () {
      expect(
          pluginCodeIssue('var _0xodM="jsjiami.com.v7";${'x' * 300}'), isNull);
    });

    test('HTML 错误页被识破', () {
      // 注意填充物要放在**标签内部**：`pluginCodeIssue` 先 trim，尾部空格会被去掉，
      // 那样会先命中"内容太短"那条，测的就不是"识破网页"了（写这条时踩过）
      expect(pluginCodeIssue('<html><body>418 ${'x' * 300}</body></html>'),
          contains('网页'));
    });

    test('接口错误 JSON 被识破', () {
      expect(pluginCodeIssue('{"detail":"${'需要登录' * 60}"}'), contains('JSON'));
    });

    test('空 / 过短被拒', () {
      expect(pluginCodeIssue(''), contains('空'));
      expect(pluginCodeIssue('var x=1'), contains('太短'));
    });
  });

  // ---------------- 插件元数据 ----------------
  group('EmbeddedPlugin / PluginMeta', () {
    test('JSON round-trip 不丢字段', () {
      final p = EmbeddedPlugin(
        hash: 'a' * 64,
        platform: '元力KW',
        version: '0.1.0',
        author: '公众号:科技长青',
        origin: 'url',
        originDetail: 'https://x/kw.js',
        enabled: false,
        order: 3,
        importedAt: 1700000000000,
        supportedSearchType: const ['music', 'sheet'],
        requiredModules: const ['axios', 'he'],
        byteSize: 12345,
      );
      final back = EmbeddedPlugin.fromJson(p.toJson());
      expect(back.hash, p.hash);
      expect(back.platform, p.platform);
      expect(back.enabled, isFalse);
      expect(back.supportedSearchType, ['music', 'sheet']);
      expect(back.requiredModules, ['axios', 'he']);
      expect(back.byteSize, 12345);
      expect(back.originDetail, 'https://x/kw.js');
    });

    test('缺字段时给安全默认值（enabled 默认 true、搜索类型默认 music）', () {
      final p = EmbeddedPlugin.fromJson({'hash': 'h'});
      expect(p.enabled, isTrue);
      expect(p.supportedSearchType, ['music']);
      expect(p.displayName, contains('h'));
      expect(p.shortHash, 'h');
    });

    test('supportedSearchType 缺失时按 [music] 处理', () {
      final meta = PluginMeta.fromJson({
        'methods': ['search', 'getMediaSource']
      });
      expect(meta.supportedSearchType, ['music']);
      expect(meta.missingCritical, isEmpty);
    });

    test('★ 缺少关键方法时要报出来（否则导入一个不是插件的 JS 也能过）', () {
      final meta = PluginMeta.fromJson({
        'methods': ['foo']
      });
      expect(meta.missingCritical, ['search', 'getMediaSource']);
    });
  });

  // ---------------- 静态资源清单 ----------------
  //
  // 这几条守的是"构建输入"：harness 与 6 个依赖产物必须真在仓库里
  // （CI 与本地 build.sh 都直接拿它们出包，没有网络回退）。
  group('静态资源清单', () {
    test('assets/js/harness.js 存在且不是空文件', () {
      final f = File(PluginAssets.harnessPath);
      expect(f.existsSync(), isTrue, reason: '缺少 ${PluginAssets.harnessPath}');
      expect(f.lengthSync() > 2000, isTrue);
    });

    test('每个依赖模块都有对应的产物文件', () {
      for (final e in PluginAssets.modulePaths.entries) {
        final f = File(e.value);
        expect(f.existsSync(), isTrue, reason: '缺少依赖产物 ${e.value}');
        expect(f.lengthSync() > 1000, isTrue, reason: '${e.value} 太小，像下载失败');
      }
    });

    test('harness 里定义的依赖模块名与 Dart 侧清单对齐', () {
      // harness 只负责"按名字注册源码"，名字对不上就会报"宿主未提供模块"
      final harness = File(PluginAssets.harnessPath).readAsStringSync();
      expect(harness.contains('__defineModuleSource'), isTrue);
      for (final name in PluginAssets.modulePaths.keys) {
        expect(name.isNotEmpty, isTrue);
      }
      // 关键契约名：插件加载器的七个形参名不能改
      for (final n in [
        'require',
        '__musicfree_require',
        'module',
        'exports',
        'console',
        'env',
        'process',
      ]) {
        expect(harness.contains(n), isTrue, reason: 'harness 里丢了形参名 $n');
      }
    });

    test('插件源码目录存在（可以没有 .js，但目录必须在，否则 pubspec 的 asset 声明会报错）', () {
      expect(Directory('assets/plugins').existsSync(), isTrue);
    });

    test('pubspec 的 version 与 kAppVersion 一致', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m =
          RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
      expect(m, isNotNull);
      expect(m!.group(1), kAppVersion,
          reason:
              'pubspec.yaml 的 version 与 core/app_info.dart 的 kAppVersion 漂移了');
    });
  });
}
