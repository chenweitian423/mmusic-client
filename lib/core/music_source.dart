/// 数据源抽象：同一套 UI 既能跑 NAS 服务端，也能跑 App 内置的 MusicFree 插件。
///
/// 为什么值得多这一层：`api.dart` 原本是全 App 的数据入口，内置源一上来就要
/// 把「搜索 / 直链 / 歌词 / 榜单 / 歌单」五条链路都接一遍。直接把 UI 里的
/// `api.xxx` 换成 `if (内置源) ... else ...` 会散落二十处判断，且每加一个源就多一轮。
/// 抽成一个接口之后，UI 只认 `musicSource`。
///
/// 注意分工：这里**只做形状转换**，任何解析/容错逻辑都留在各自的实现里
/// （服务端的坑在 api.dart，内置源的坑在 embedded/ 下）。
library;

import 'api.dart';
import 'models.dart';
import 'settings.dart';

enum SourceKind { server, embedded }

/// 一个音源必须能回答的问题。方法签名刻意与 [Api] 保持一致 ——
/// 服务端实现就是一层直通（见 [ServerSource]），不引入第二套语义。
abstract class MusicSource {
  SourceKind get kind;

  /// 界面上显示的名字。
  String get label;

  /// 是否必须配置并登录 NAS 服务端（决定启动闸门走不走登录页）。
  bool get needsServer;

  /// 服务端专属能力：收藏的歌单、服务端播放队列（跨设备同步）。
  /// 内置源下这些不可用，界面据此隐藏入口而不是给一个点了报错的按钮。
  bool get supportsServerLibrary;

  Future<List<PluginInfo>> plugins();

  Future<List<Song>> search(
    String query, {
    int page,
    String? source,
    String? pluginHash,
  });

  Future<List<Sheet>> searchSheets(
    String query, {
    required String pluginHash,
    int page,
  });

  Future<String> playUrl(Song song);

  Future<String> lyric(Song song);

  Future<List<Board>> boards(String source);

  Future<List<Song>> boardSongs(
    String source,
    String bangid, {
    int page,
    int limit,
  });

  Future<List<Song>> sheetDetail(Sheet sheet, {int page, int limit});
}

/// NAS 服务端音源：全部直通现有的 [Api]。
///
/// 这层包装**不做任何逻辑**（不重试、不改参数）——`api.dart` 里那套探测与降级
/// 是被 65 个单测和线上实践钉过的，挪到别处只会让两边慢慢漂移。
class ServerSource implements MusicSource {
  @override
  SourceKind get kind => SourceKind.server;

  @override
  String get label => '服务端';

  @override
  bool get needsServer => true;

  @override
  bool get supportsServerLibrary => true;

  @override
  Future<List<PluginInfo>> plugins() => api.plugins();

  @override
  Future<List<Song>> search(
    String query, {
    int page = 1,
    String? source,
    String? pluginHash,
  }) =>
      api.search(query, page: page, source: source, pluginHash: pluginHash);

  @override
  Future<List<Sheet>> searchSheets(
    String query, {
    required String pluginHash,
    int page = 1,
  }) =>
      api.searchSheets(query, pluginHash: pluginHash, page: page);

  @override
  Future<String> playUrl(Song song) => api.playUrl(song);

  @override
  Future<String> lyric(Song song) => api.lyric(song);

  @override
  Future<List<Board>> boards(String source) => api.boards(source);

  @override
  Future<List<Song>> boardSongs(
    String source,
    String bangid, {
    int page = 1,
    int limit = 100,
  }) =>
      api.boardSongs(source, bangid, page: page, limit: limit);

  @override
  Future<List<Song>> sheetDetail(Sheet sheet,
          {int page = 1, int limit = 200}) =>
      api.sheetDetail(sheet, page: page, limit: limit);
}

/// 当前生效的音源模式（来自 [settings].sourceMode）。
SourceKind sourceKindFromSettings() =>
    settings.sourceMode == 'embedded' ? SourceKind.embedded : SourceKind.server;
