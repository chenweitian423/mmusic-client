import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class LocalPlaylist {
  final String id;
  final String name;
  final List<Song> songs;
  final int createdAt;
  final int updatedAt;

  const LocalPlaylist({
    required this.id,
    required this.name,
    required this.songs,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LocalPlaylist.fromJson(Map<String, dynamic> json) {
    final rawSongs = json['songs'];
    return LocalPlaylist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名歌单',
      songs: rawSongs is List
          ? rawSongs
              .whereType<Map>()
              .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <Song>[],
      createdAt: int.tryParse(json['createdAt']?.toString() ?? '') ?? 0,
      updatedAt: int.tryParse(json['updatedAt']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'songs': songs.map((e) => e.toFavJson()).toList(),
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  LocalPlaylist copyWith({
    String? name,
    List<Song>? songs,
    int? updatedAt,
  }) {
    return LocalPlaylist(
      id: id,
      name: name ?? this.name,
      songs: songs ?? this.songs,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class LocalPlaylistsStore {
  static const _key = 'localPlaylists';

  SharedPreferences? _sp;
  final ValueNotifier<List<LocalPlaylist>> playlists =
      ValueNotifier(<LocalPlaylist>[]);

  Future<void> init() async {
    _sp = await SharedPreferences.getInstance();
    _loadFromPrefs();
  }

  Future<void> reload() async {
    _loadFromPrefs();
  }

  LocalPlaylist? byId(String id) {
    for (final playlist in playlists.value) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  Future<LocalPlaylist> create(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw Exception('歌单名称不能为空');
    final now = DateTime.now().millisecondsSinceEpoch;
    final playlist = LocalPlaylist(
      id: 'pl_$now',
      name: trimmed,
      songs: const <Song>[],
      createdAt: now,
      updatedAt: now,
    );
    playlists.value = [playlist, ...playlists.value];
    await _save();
    return playlist;
  }

  Future<String> addSong(String playlistId, Song song) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var found = false;
    var duplicate = false;
    final next = playlists.value.map((playlist) {
      if (playlist.id != playlistId) return playlist;
      found = true;
      duplicate = playlist.songs.any((e) => e.key == song.key);
      final songs = [
        song,
        ...playlist.songs.where((e) => e.key != song.key),
      ];
      return playlist.copyWith(songs: songs, updatedAt: now);
    }).toList();
    if (!found) throw Exception('歌单不存在');
    playlists.value = next;
    await _save();
    return duplicate ? '歌曲已在歌单中，已移到最前' : '已添加到歌单';
  }

  Future<void> removeSong(String playlistId, Song song) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    playlists.value = playlists.value.map((playlist) {
      if (playlist.id != playlistId) return playlist;
      return playlist.copyWith(
        songs: playlist.songs.where((e) => e.key != song.key).toList(),
        updatedAt: now,
      );
    }).toList();
    await _save();
  }

  Future<void> delete(String playlistId) async {
    playlists.value =
        playlists.value.where((playlist) => playlist.id != playlistId).toList();
    await _save();
  }

  void _loadFromPrefs() {
    final text = _sp?.getString(_key);
    if (text == null || text.isEmpty) {
      playlists.value = <LocalPlaylist>[];
      return;
    }
    try {
      final decoded = jsonDecode(text);
      playlists.value = decoded is List
          ? decoded
              .whereType<Map>()
              .map((e) => LocalPlaylist.fromJson(Map<String, dynamic>.from(e)))
              .where((e) => e.id.isNotEmpty)
              .toList()
          : <LocalPlaylist>[];
    } catch (_) {
      playlists.value = <LocalPlaylist>[];
    }
  }

  Future<void> _save() async {
    await _sp?.setString(
      _key,
      jsonEncode(playlists.value.map((e) => e.toJson()).toList()),
    );
  }
}

final localPlaylists = LocalPlaylistsStore();
