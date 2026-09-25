import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'audio_handler.dart';
import 'models.dart';
import 'settings.dart';
import 'sources.dart';

/// 全局播放器实例(在 main 中初始化)
late MusicHandler musicHandler;

/// 「我喜欢的音乐」。
///
/// 两套存储，按当前音源模式自动选：
///  * **服务端模式**：同步到 NAS 的 `/api/playlist`（能在网页端看到、多设备共享）；
///  * **内置源模式**：没有服务端可用，落本地（SharedPreferences）。
///    两份数据**各存各的**，切换模式不会互相覆盖 —— 把本地列表推给服务端
///    会污染用户在网页端那份，把服务端那份写进本地又会在离线时留下过期副本。
class FavoritesStore {
  final ValueNotifier<List<Song>> songs = ValueNotifier(<Song>[]);
  bool loaded = false;

  /// 上一份数据来自哪种模式。切模式后据此重新加载，避免展示脏数据。
  bool _loadedFromEmbedded = false;

  Future<void> load({bool force = false}) async {
    final wantEmbedded = isEmbeddedMode;
    if (loaded && !force && _loadedFromEmbedded == wantEmbedded) return;

    if (wantEmbedded) {
      songs.value = _readLocal();
      loaded = true;
      _loadedFromEmbedded = true;
      return;
    }
    try {
      songs.value = await api.favorites();
      loaded = true;
      _loadedFromEmbedded = false;
    } catch (_) {
      // 连不上服务端时保留旧值 —— 清空会让用户以为收藏丢了
    }
  }

  bool contains(Song s) => songs.value.any((e) => e.key == s.key);

  /// 返回提示文案，失败时返回一句明确的失败原因。
  Future<String> toggle(Song s) async {
    if (!loaded || _loadedFromEmbedded != isEmbeddedMode) {
      await load(force: true);
    }
    final list = List.of(songs.value);
    final was = contains(s);
    if (was) {
      list.removeWhere((e) => e.key == s.key);
    } else {
      list.insert(0, s);
    }

    if (isEmbeddedMode) {
      songs.value = list;
      await _writeLocal(list);
      return was ? '已取消喜欢' : '已添加到我喜欢的音乐';
    }

    try {
      await api.saveFavorites(list);
      songs.value = list;
      return was ? '已取消喜欢' : '已添加到我喜欢的音乐';
    } catch (e) {
      return '同步失败:$e';
    }
  }

  List<Song> _readLocal() {
    final raw = settings.localFavorites;
    if (raw.isEmpty) return <Song>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Song>[];
      return [
        for (final e in decoded)
          if (e is Map) Song.fromJson(Map<String, dynamic>.from(e)),
      ].where((s) => s.id.isNotEmpty).toList();
    } catch (_) {
      return <Song>[];
    }
  }

  Future<void> _writeLocal(List<Song> list) async {
    await settings.setLocalFavorites(
      jsonEncode([for (final s in list) s.toFavJson()]),
    );
  }
}

final favorites = FavoritesStore();
