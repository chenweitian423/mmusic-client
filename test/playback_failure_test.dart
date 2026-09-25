import 'package:flutter_test/flutter_test.dart';

import 'package:mmusic_client/core/api.dart';
import 'package:mmusic_client/core/audio_handler.dart';
import 'package:mmusic_client/core/models.dart';

void main() {
  group('PlayUrlProbe.describe —— 把"取不到地址"翻译成可行动的一句话', () {
    test('一次请求都没发出去时说没有可用音源', () {
      expect(PlayUrlProbe().describe(0), '没有可用的音源');
    });

    test('401/403 优先判为登录过期(用户能直接去重新登录)', () {
      final probe = PlayUrlProbe()
        ..recordResponse(401)
        ..recordResponse(403)
        ..recordResponse(404);
      final msg = probe.describe(2);
      expect(msg, contains('登录已过期'));
      expect(probe.summary, contains('401/403×2'));
    });

    test('全部请求都是网络异常才判为连不上服务端', () {
      final probe = PlayUrlProbe()
        ..recordError(Exception('SocketException: Connection refused'))
        ..recordError(Exception('TimeoutException after 0:00:12'));
      expect(probe.describe(1), contains('连不上服务端'));
      expect(probe.summary, contains('网络异常×2'));
    });

    test('只要有过非网络层应答,就不该说"连不上服务端"', () {
      final probe = PlayUrlProbe()
        ..recordError(Exception('SocketException'))
        ..recordResponse(200);
      final msg = probe.describe(1);
      expect(msg, isNot(contains('连不上服务端')));
      expect(msg, contains('网络不稳定'));
    });

    test('服务端活着但没给出地址时,提示指向插件失效(§8.8 那类故障)', () {
      final probe = PlayUrlProbe()
        ..recordResponse(200)
        ..recordEmptyBody()
        ..recordResponse(200)
        ..recordEmptyBody();
      final msg = probe.describe(3);
      expect(msg, contains('服务端正常'));
      expect(msg, contains('3 个音源'));
      expect(msg, contains('插件失效'));
      expect(probe.summary, contains('空应答×2'));
    });

    test('纯 404 时提示是音源名/路径不对', () {
      final probe = PlayUrlProbe()..recordResponse(404);
      expect(probe.describe(1), contains('404'));
    });

    test('其它 4xx 带上状态码', () {
      final probe = PlayUrlProbe()..recordResponse(400);
      expect(probe.describe(1), contains('400'));
    });

    test('summary 汇总各类计数与总尝试次数', () {
      final probe = PlayUrlProbe()
        ..recordResponse(404)
        ..recordEmptyBody()
        ..recordError(Exception('TimeoutException'));
      final s = probe.summary;
      // 注意 recordEmptyBody() 不额外计数:那次 200 已经由 recordResponse 计过,
      // 否则"200 但没地址"会被算成两次请求。
      expect(s, contains('共尝试 2 次'));
      expect(s, contains('404×1'));
      expect(s, contains('空应答×1'));
      expect(s, contains('网络异常×1'));
    });

    test('一条记录都没有时 summary 不会崩', () {
      expect(PlayUrlProbe().summary, contains('共尝试 0 次'));
    });
  });

  group('shouldSkipAfterFailure —— 失败后还要不要自动跳下一首', () {
    test('队列还长、失败次数不多时继续跳', () {
      expect(shouldSkipAfterFailure(failStreak: 1, queueLength: 10), isTrue);
      expect(shouldSkipAfterFailure(failStreak: 4, queueLength: 10), isTrue);
    });

    test('连挂 5 首就停(多半是服务端/网络的问题,再跳也是白跳)', () {
      expect(shouldSkipAfterFailure(failStreak: 5, queueLength: 50), isFalse);
    });

    test('失败次数追上队列长度就停(整队列都挂时别无限转)', () {
      expect(shouldSkipAfterFailure(failStreak: 3, queueLength: 3), isFalse);
      expect(shouldSkipAfterFailure(failStreak: 2, queueLength: 3), isTrue);
    });

    test('单曲队列不跳', () {
      expect(shouldSkipAfterFailure(failStreak: 1, queueLength: 1), isFalse);
    });
  });

  group('describeLoadFailure —— 异常翻译成人话', () {
    test('ApiException 直接用它的 message(已在 playUrl 里归过类)', () {
      expect(
        describeLoadFailure(ApiException('登录已过期,请重新登录', detail: '共尝试 3 次')),
        '登录已过期,请重新登录',
      );
    });

    test('本地缓存读不出来时提示删缓存重试', () {
      final msg = describeLoadFailure(
        Exception('FileSystemException: Cannot open file, path = /x/y.mp3'),
      );
      expect(msg, contains('缓存'));
    });

    test('其它异常退回短文本,不把整段堆栈铺到界面上', () {
      final msg = describeLoadFailure(Exception('boom\nline2\nline3'));
      expect(msg, 'Exception: boom');
    });
  });

  group('shortErrorText', () {
    test('多行只留第一行', () {
      expect(shortErrorText(Exception('a\nb')), 'Exception: a');
    });

    test('过长时截断', () {
      final s = shortErrorText(Exception('x' * 200));
      expect(s.length, lessThanOrEqualTo(80));
      expect(s, endsWith('...'));
    });
  });

  group('PlaybackFailure', () {
    test('按歌曲 key 与原因描述自己', () {
      final f = PlaybackFailure(
        song: _song('1', '晴天'),
        reason: '连不上服务端',
        detail: '共尝试 12 次',
        at: DateTime(2026, 9, 25),
      );
      expect(f.toString(), contains('晴天'));
      expect(f.toString(), contains('连不上服务端'));
      expect(f.detail, '共尝试 12 次');
    });
  });
}

/// 构造一个最小可用的 Song(与 local_features_test.dart 里的写法保持一致)。
Song _song(String id, String title) => Song.fromJson({
      'id': id,
      'title': title,
      'artist': 'A',
      'album': '',
      'artwork': '',
      'source': 'wy',
      'platform': '网易云',
      'interval': '03:00',
      'types': [],
    });
