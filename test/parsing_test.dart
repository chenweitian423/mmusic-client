import 'package:flutter_test/flutter_test.dart';

import 'package:mmusic_client/core/api.dart';
import 'package:mmusic_client/core/models.dart';

/// 一条最小可用的歌曲 JSON(id + 标题齐全才不会被解析器丢掉)。
Map<String, dynamic> _songJson({String id = '1', String title = '歌'}) => {
      'id': id,
      'name': title,
      'source': 'wy',
    };

void main() {
  // 两套音源的字段名与取值都抄自真实探测样本,别改成"看起来更合理"的假数据:
  //   zypt 条目 → api-samples/08-search-wy.json
  //   插件条目 → api-samples/07-search-default.json
  group('Song.fromJson —— 两套音源字段归一', () {
    test('zypt 条目:platform 缺失时要靠短码反查出中文名', () {
      final s = Song.fromJson({
        'id': '509781655',
        'songmid': '509781655',
        'title': '想你就写信 (Live)',
        'name': '想你就写信 (Live)',
        'artist': '周杰伦、李硕、张鑫',
        'singer': '周杰伦、李硕、张鑫',
        'source': 'wy',
        'interval': '03:58',
        'artwork': 'http://p2.music.126.net/x.jpg',
        'img': 'http://p2.music.126.net/x.jpg',
        'types': [
          {'type': '128k', 'size': '3.6MB'},
          {'type': '192k', 'size': '5.5MB'},
          {'type': '320k', 'size': '9.1MB'},
          {'type': 'flac', 'size': '26.1MB'},
        ],
      });

      expect(s.title, '想你就写信 (Live)');
      expect(s.artist, '周杰伦、李硕、张鑫');
      expect(s.id, '509781655');
      // 真实样本里 zypt 条目的 platform 是 null,所以这一步实际走的是短码反查
      expect(s.platform, '网易云');
      expect(s.qualities, ['128k', '192k', '320k', 'flac']);
      expect(s.isPlugin, isFalse);
      expect(s.key, 'wy|509781655');
    });

    test('插件条目:source 取 _plugin_hash,platform 用它自报的名字', () {
      const hash =
          '4dc6735a06062d0910e07ee01ff327a7221c9d544f02ab8339dd343a158fe4a1';
      final s = Song.fromJson({
        'id': '237016753',
        'title': '不再流浪',
        'artist': '周深',
        'artwork': 'http://p1.music.126.net/y.jpg',
        'platform': '元力QQ',
        '_plugin': 'qq.js',
        '_plugin_hash': hash,
      });

      expect(s.source, hash);
      expect(s.platform, '元力QQ');
      // isPlugin 的判据就是"source 比 2 位短码长得多",这条规则一变全 App 都受影响
      expect(s.isPlugin, isTrue);
      expect(s.key, '$hash|237016753');
    });

    test('id 缺失时退回 songmid(酷狗/QQ 条目常见的形态)', () {
      final s =
          Song.fromJson({'name': '歌', 'source': 'kg', 'songmid': 'abc123'});
      expect(s.id, 'abc123');
      expect(s.key, 'kg|abc123');
    });

    test('只有 name/singer 没有 title/artist 时也能解析', () {
      final s = Song.fromJson({
        'name': '老歌',
        'singer': '某歌手',
        'source': 'kw',
        'albumName': '某专辑',
      });
      expect(s.title, '老歌');
      expect(s.artist, '某歌手');
      expect(s.album, '某专辑');
    });

    test('artwork 按 artwork→img→picUrl→cover→pic_id 取第一个 http 地址', () {
      expect(
          Song.fromJson({'artwork': 'http://a.jpg'}).artwork, 'http://a.jpg');
      expect(Song.fromJson({'img': 'http://i.jpg'}).artwork, 'http://i.jpg');
      expect(Song.fromJson({'picUrl': 'http://p.jpg'}).artwork, 'http://p.jpg');
      expect(Song.fromJson({'cover': 'http://c.jpg'}).artwork, 'http://c.jpg');
      // 靠前的候选不是 http 就跳过,继续往后找
      expect(
        Song.fromJson({'artwork': 'not-a-url', 'img': 'http://i.jpg'}).artwork,
        'http://i.jpg',
      );
      // 全是"非 http"(相对路径 / 纯数字 id)⇒ 留空,交给界面显示占位图
      expect(
        Song.fromJson({'pic_id': '1099511630', 'cover': '/rel/a.jpg'}).artwork,
        '',
      );
    });

    test('types 不是 [{type:...}] 形态时 qualities 为空且不抛异常', () {
      // ⚠️ 真实样本里同时带 types(List) 和 _types(Map: {flac:{size:...}})。
      //    代码读的是 types —— 这条用例把"读错字段会静默拿到空列表"钉住。
      expect(
        Song.fromJson({
          '_types': {
            '320k': {'size': '9.1MB'},
          },
        }).qualities,
        isEmpty,
      );
      expect(Song.fromJson({'types': 'oops'}).qualities, isEmpty);
      expect(
        Song.fromJson({
          'types': [
            {'size': '1MB'},
            'x',
            null,
          ],
        }).qualities,
        isEmpty,
      );
    });

    test('未知短码原样当作平台名(不炸也不猜)', () {
      expect(Song.fromJson({'source': 'zz'}).platform, 'zz');
    });
  });

  group('toFavJson —— 写回服务端"我喜欢"时补齐网页播放器字段', () {
    test('补齐 name/title/artist/singer/album 与缺失的 id', () {
      final m = Song.fromJson({
        'id': '1',
        'name': '歌',
        'artist': 'A',
        'albumName': '某专辑',
        'source': 'wy',
      }).toFavJson();

      expect(m['name'], '歌');
      expect(m['title'], '歌');
      expect(m['artist'], 'A');
      expect(m['singer'], 'A');
      expect(m['album'], '某专辑');
      // raw 里没有 url_id / lyric_id ⇒ 落到歌曲 id
      expect(m['url_id'], '1');
      expect(m['lyric_id'], '1');
      expect(m['source'], 'wy');
    });

    test('已有 url_id / lyric_id / pic_id 时不被覆盖', () {
      final m = Song.fromJson({
        'id': '1',
        'name': '歌',
        'source': 'wy',
        'url_id': 'real-url-id',
        'lyric_id': 'real-lyric-id',
        'pic_id': 'real-pic-id',
      }).toFavJson();

      expect(m['url_id'], 'real-url-id');
      expect(m['lyric_id'], 'real-lyric-id');
      expect(m['pic_id'], 'real-pic-id');
    });

    test('raw 里的其它字段原样带过去(网页端靠它们回显)', () {
      final m = Song.fromJson({
        'id': '1',
        'name': '歌',
        'source': 'wy',
        'otherSource': 'kg',
        'albumId': '999',
      }).toFavJson();

      expect(m['otherSource'], 'kg');
      expect(m['albumId'], '999');
    });
  });

  group('parseInterval', () {
    test('分:秒 与 时:分:秒 两种格式都认', () {
      expect(parseInterval('03:58'), const Duration(minutes: 3, seconds: 58));
      expect(
        parseInterval('1:02:03'),
        const Duration(hours: 1, minutes: 2, seconds: 3),
      );
    });

    test('空串 / 非法值返回 null(界面据此不显示时长)', () {
      expect(parseInterval(''), isNull);
      expect(parseInterval('abc'), isNull);
      expect(parseInterval('12'), isNull);
      expect(parseInterval('1:2:3:4'), isNull);
    });
  });

  group('Sheet / Board / PluginInfo', () {
    test('Sheet:title 退回 name,_plugin_hash 优先于 source', () {
      final sh = Sheet.fromJson({
        'id': 'p1',
        'name': '某歌单',
        'source': 'wy',
        '_plugin_hash': 'hash-from-plugin',
        'platform': '元力KW',
      });

      expect(sh.title, '某歌单');
      expect(sh.source, 'hash-from-plugin');
      expect(sh.platform, '元力KW');
    });

    test('Board:bangid 缺失时退回 id(注意调 list 接口要用 bangid)', () {
      expect(
        Board.fromJson({'id': 'wy__19723756', 'name': '飙升榜'}).bangid,
        'wy__19723756',
      );
      expect(
        Board.fromJson(
            {'id': 'wy__19723756', 'name': '飙升榜', 'bangid': '19723756'}).bangid,
        '19723756',
      );
    });

    test('PluginInfo:supportedSearchType 缺失或非列表时给空列表', () {
      expect(
        PluginInfo.fromJson({'platform': '元力KW', 'hash': 'h'}).searchTypes,
        isEmpty,
      );
      expect(
        PluginInfo.fromJson({
          'platform': '元力KW',
          'hash': 'h',
          'supportedSearchType': 'music',
        }).searchTypes,
        isEmpty,
      );
      expect(
        PluginInfo.fromJson({
          'platform': '元力KW',
          'hash': 'h',
          'supportedSearchType': ['music', 'sheet'],
        }).searchTypes,
        ['music', 'sheet'],
      );
    });
  });

  group('deepFindSongs —— 面对未知返回结构的防御式解析', () {
    test('顶层直接就是歌曲数组', () {
      expect(deepFindSongs([_songJson()]).length, 1);
    });

    test('歌单详情 playlist.list', () {
      expect(
          deepFindSongs({
            'playlist': {
              'list': [_songJson()]
            }
          }).length,
          1);
    });

    test('排行榜 songs / 包在 data.results 里都找得到', () {
      expect(
          deepFindSongs({
            'songs': [_songJson()]
          }).length,
          1);
      expect(
          deepFindSongs({
            'data': {
              'results': [_songJson()]
            }
          }).length,
          1);
    });

    test('元素不是对象时不下钻(别把数字数组当成歌)', () {
      expect(deepFindSongs([1, 2, 3]), isEmpty);
      expect(deepFindSongs(['a', 'b']), isEmpty);
    });

    test('找不到就返回空列表,绝不抛异常', () {
      expect(deepFindSongs(null), isEmpty);
      expect(deepFindSongs('str'), isEmpty);
      expect(deepFindSongs(42), isEmpty);
      expect(deepFindSongs({'foo': 'bar'}), isEmpty);
      expect(
          deepFindSongs({
            'playlist': {'info': {}}
          }),
          isEmpty);
      // 列表里第一条没有 title/name ⇒ 不认为是歌曲列表
      expect(
          deepFindSongs([
            {'x': 1}
          ]),
          isEmpty);
    });

    test('嵌套在深度上限内能找到', () {
      expect(
        deepFindSongs({
          'a': {
            'b': {
              'c': {
                'list': [_songJson()]
              },
            },
          },
        }).length,
        1,
      );
    });

    test('超过深度上限就停(防止畸形结构把递归拖爆)', () {
      dynamic nested = {
        'list': [_songJson()]
      };
      for (var i = 0; i < 7; i++) {
        nested = {'x': nested};
      }
      expect(deepFindSongs(nested), isEmpty);
    });
  });

  group('asMap / songsFromList', () {
    test('asMap 能吃 Map、JSON 字符串,吃不下的一律给空 Map', () {
      expect(asMap({'a': 1}), {'a': 1});
      expect(asMap('{"a":1}'), {'a': 1});
      expect(asMap('not json'), isEmpty);
      expect(asMap(null), isEmpty);
      expect(asMap(42), isEmpty);
      expect(asMap(''), isEmpty);
    });

    test('songsFromList 丢掉缺 id 或缺标题的条目', () {
      final songs = songsFromList([
        _songJson(id: '1', title: '有'),
        {'name': '没 id', 'source': 'wy'},
        {'id': '3', 'source': 'wy'},
        'not-a-map',
        null,
      ]);

      expect(songs.length, 1);
      expect(songs.first.id, '1');
    });
  });
}
