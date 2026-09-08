import 'package:flutter_test/flutter_test.dart';
import 'package:mmusic_client/core/api.dart';
import 'package:mmusic_client/core/audio_handler.dart';
import 'package:mmusic_client/core/models.dart';

PluginInfo _plugin(String platform, {String hash = 'test-hash'}) =>
    PluginInfo(platform: platform, hash: hash, searchTypes: const ['music']);

void main() {
  test('extractPlayableUrl accepts wrapped media-source responses', () {
    final url = extractPlayableUrl({
      'success': true,
      'data': {
        'url': 'https://example.com/song.flac',
        'quality': 'flac',
      },
    });

    expect(url, 'https://example.com/song.flac');
  });

  test('mediaSourceBody keeps original song fields and applies quality', () {
    final song = Song.fromJson({
      'id': '3403334518',
      'name': 'Test Song',
      'artist': 'Test Artist',
      'source': 'wy',
      'url_id': '3403334518',
      'types': [
        {'type': '320k', 'size': '1MB'},
      ],
    });

    final body = mediaSourceBody(song, '320k');

    expect(body['id'], '3403334518');
    expect(body['url_id'], '3403334518');
    expect(body['source'], 'wy');
    expect(body['quality'], '320k');
  });

  test('mediaSourceBodies tries wrapped body before direct body', () {
    final song = Song.fromJson({
      'id': '710523937',
      'name': 'Test Song',
      'artist': 'Test Artist',
      'source': 'tx',
      'songmid': '0039MnYb0qxYhV',
    });

    final bodies = mediaSourceBodies(song, '320');

    expect(bodies.first['musicItem']['songmid'], '0039MnYb0qxYhV');
    expect(bodies.first['quality'], '320k');
    expect(bodies[1]['songmid'], '0039MnYb0qxYhV');
  });

  test('mediaSourceBodies can override source with plugin hash', () {
    final song = Song.fromJson({
      'id': '710523937',
      'name': 'Test Song',
      'artist': 'Test Artist',
      'source': 'tx',
    });

    final bodies = mediaSourceBodies(song, '320', 'plugin-hash-value-that-is-long');

    expect(bodies.first['musicItem']['source'], 'plugin-hash-value-that-is-long');
    expect(bodies.first['musicItem']['_plugin_hash'],
        'plugin-hash-value-that-is-long');
  });

  test('sourceCandidatesForSong does not fall back to raw source when plugin matches', () {
    final song = Song.fromJson({
      'id': '7077187',
      'name': 'Test Song',
      'artist': 'Test Artist',
      'source': 'kw',
    });
    final plugins = [
      PluginInfo(
        platform: '元力KW',
        hash: 'b0f998e4eee24bd950e950c7739f9b2c6714f5413b0924841d0635e65d62b5ae',
        searchTypes: const ['music'],
      ),
    ];

    expect(sourceCandidatesForSong(song, plugins), [
      'b0f998e4eee24bd950e950c7739f9b2c6714f5413b0924841d0635e65d62b5ae',
    ]);
  });

  // 服务端不提供 hash ↔ 短码映射,只能靠插件名模糊匹配(AGENTS.md §3.2)。
  // 实测的「元力KW / 元力WY」自带英文短码,只匹配英文也能碰巧跑通;
  // 但换成纯中文命名的插件就会静默退回内置 zypt 源。下面两个用例把两种命名都钉住。
  test('pluginMatchesSource matches plugins named with the latin short code', () {
    expect(pluginMatchesSource(_plugin('元力KW'), 'kw'), isTrue);
    expect(pluginMatchesSource(_plugin('元力WY'), 'wy'), isTrue);
    expect(pluginMatchesSource(_plugin('元力KW'), 'wy'), isFalse);
  });

  test('pluginMatchesSource matches plugins named only in Chinese', () {
    expect(pluginMatchesSource(_plugin('网易云音乐'), 'wy'), isTrue);
    expect(pluginMatchesSource(_plugin('酷我音乐'), 'kw'), isTrue);
    expect(pluginMatchesSource(_plugin('酷狗音乐'), 'kg'), isTrue);
    expect(pluginMatchesSource(_plugin('咪咕音乐'), 'mg'), isTrue);
    expect(pluginMatchesSource(_plugin('QQ音乐'), 'tx'), isTrue);
    expect(pluginMatchesSource(_plugin('腾讯音乐'), 'tx'), isTrue);
  });

  test('pluginMatchesSource rejects unknown sources and plugin hashes', () {
    expect(pluginMatchesSource(_plugin('网易云音乐'), 'unknown'), isFalse);
    // 插件条目的 source 是 64 位 hash,不该被当成短码匹配上任何插件
    expect(
      pluginMatchesSource(_plugin('网易云音乐'),
          '4dc6735a06062d0910e07ee01ff327a7221c9d544f02ab8339dd343a158fe4a1'),
      isFalse,
    );
  });

  test('sourceCandidatesForSong picks up a Chinese-named plugin', () {
    final song = Song.fromJson({
      'id': '7077187',
      'name': 'Test Song',
      'artist': 'Test Artist',
      'source': 'wy',
    });

    expect(sourceCandidatesForSong(song, [_plugin('网易云音乐', hash: 'hash-wy')]),
        ['hash-wy']);

    // 没有任何插件匹配时,退回内置 zypt 短码(这是兜底,不是失败)
    expect(sourceCandidatesForSong(song, [_plugin('酷我音乐', hash: 'hash-kw')]),
        ['wy']);
  });

  test('shouldAutoAdvanceFromPosition triggers near the end', () {
    expect(
      shouldAutoAdvanceFromPosition(
        position: const Duration(seconds: 179, milliseconds: 500),
        duration: const Duration(minutes: 3),
        loading: false,
        completedHandled: false,
        mode: PlayMode.sequence,
        hasQueue: true,
      ),
      isTrue,
    );

    expect(
      shouldAutoAdvanceFromPosition(
        position: const Duration(seconds: 179, milliseconds: 500),
        duration: const Duration(minutes: 3),
        loading: true,
        completedHandled: false,
        mode: PlayMode.sequence,
        hasQueue: true,
      ),
      isFalse,
    );
  });

  test('shouldAutoAdvanceFromCompletion triggers for a real queue', () {
    expect(
      shouldAutoAdvanceFromCompletion(
        loading: false,
        completedHandled: false,
        mode: PlayMode.sequence,
        queueLength: 2,
      ),
      isTrue,
    );

    expect(
      shouldAutoAdvanceFromCompletion(
        loading: false,
        completedHandled: false,
        mode: PlayMode.one,
        queueLength: 2,
      ),
      isFalse,
    );

    expect(
      shouldAutoAdvanceFromCompletion(
        loading: false,
        completedHandled: true,
        mode: PlayMode.sequence,
        queueLength: 2,
      ),
      isFalse,
    );
  });

  test('proxyIdCandidates prefers url_id and songmid before parsed id', () {
    final song = Song.fromJson({
      'id': '710523937',
      'name': 'Test Song',
      'artist': 'Test Artist',
      'source': 'tx',
      'url_id': 'url-id',
      'songmid': '0039MnYb0qxYhV',
    });

    expect(proxyIdCandidates(song), ['url-id', '0039MnYb0qxYhV', '710523937']);
  });

  test('proxyUrlParams includes scalar raw fields and can omit br', () {
    final song = Song.fromJson({
      'id': '237016753',
      'name': '不再流浪',
      'artist': '周深',
      'source': '4dc6735a06062d0910e07ee01ff327a7221c9d544f02ab8339dd343a158fe4a1',
      'songmid': '001xwUwW32VflK',
      'albumName': '电影《罗小黑战记2》',
      'types': [
        {'type': '320k', 'size': '1MB'},
      ],
    });

    final params = proxyUrlParams(song, '237016753', null,
        '4dc6735a06062d0910e07ee01ff327a7221c9d544f02ab8339dd343a158fe4a1');

    expect(params['types'], 'url');
    expect(params['id'], '237016753');
    expect(params['source'],
        '4dc6735a06062d0910e07ee01ff327a7221c9d544f02ab8339dd343a158fe4a1');
    expect(params['songmid'], '001xwUwW32VflK');
    expect(params['albumName'], '电影《罗小黑战记2》');
    expect(params.containsKey('br'), isFalse);
  });
}
