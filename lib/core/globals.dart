import 'package:flutter/foundation.dart';

import 'api.dart';
import 'audio_handler.dart';
import 'models.dart';

/// 全局播放器实例(在 main 中初始化)
late MusicHandler musicHandler;

/// "我喜欢的音乐"(同步到服务端 /api/playlist)
class FavoritesStore {
  final ValueNotifier<List<Song>> songs = ValueNotifier(<Song>[]);
  bool loaded = false;

  Future<void> load() async {
    try {
      songs.value = await api.favorites();
      loaded = true;
    } catch (_) {}
  }

  bool contains(Song s) => songs.value.any((e) => e.key == s.key);

  /// 返回提示文案,失败返回 null 让调用方展示错误
  Future<String> toggle(Song s) async {
    if (!loaded) await load();
    final list = List.of(songs.value);
    final was = contains(s);
    if (was) {
      list.removeWhere((e) => e.key == s.key);
    } else {
      list.insert(0, s);
    }
    try {
      await api.saveFavorites(list);
      songs.value = list;
      return was ? '已取消喜欢' : '已添加到我喜欢的音乐';
    } catch (e) {
      return '同步失败:$e';
    }
  }
}

final favorites = FavoritesStore();
