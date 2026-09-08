import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';
import 'settings.dart';

String cacheFileBaseName(String key) {
  var hash = 0xcbf29ce484222325;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

String audioExtensionFor(String url, String? contentType) {
  final type = (contentType ?? '').toLowerCase();
  if (type.contains('flac')) return '.flac';
  if (type.contains('mpeg') || type.contains('mp3')) return '.mp3';
  if (type.contains('aac')) return '.aac';
  if (type.contains('mp4') || type.contains('m4a')) return '.m4a';
  if (type.contains('ogg')) return '.ogg';
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  for (final ext in ['.flac', '.mp3', '.aac', '.m4a', '.ogg']) {
    if (path.endsWith(ext)) return ext;
  }
  return '.mp3';
}

class SongCacheStore {
  final ValueNotifier<Set<String>> cachedKeys = ValueNotifier(<String>{});
  final ValueNotifier<List<Song>> songs = ValueNotifier(<Song>[]);
  Directory? _dir;
  SharedPreferences? _sp;

  static const _indexKey = 'songCacheIndex';

  Future<void> init() async {
    _sp = await SharedPreferences.getInstance();
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/song_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    await refresh();
  }

  bool contains(Song song) =>
      cachedKeys.value.contains(cacheFileBaseName(song.key));

  Future<String?> localPath(Song song) async {
    final file = await _findFile(song);
    return file == null ? null : file.path;
  }

  Future<void> refresh() async {
    final dir = await _cacheDir();
    final keys = <String>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final dot = name.lastIndexOf('.');
      if (dot > 0) {
        final base = name.substring(0, dot);
        keys.add(base);
      }
    }
    cachedKeys.value = keys;
    final cachedSongs = _loadSongs()
        .where((song) => keys.contains(cacheFileBaseName(song.key)))
        .toList();
    songs.value = cachedSongs;
    await _saveSongs(cachedSongs);
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.endsWith('.tmp')) await entity.delete();
    }
  }

  Future<String> cache(Song song) async {
    final existing = await _findFile(song);
    if (existing != null) {
      cachedKeys.value = {
        ...cachedKeys.value,
        cacheFileBaseName(song.key),
      };
      await _upsertSong(song);
      return existing.path;
    }

    final url = await api.playUrl(song);
    final dio = Dio(BaseOptions(
      followRedirects: true,
      responseType: ResponseType.stream,
      headers:
          settings.authCookie.isEmpty ? null : {'Cookie': settings.authCookie},
      validateStatus: (s) => s != null && s < 500,
    ));
    final response = await dio.get<ResponseBody>(url);
    if (response.statusCode == null || response.statusCode! >= 400) {
      throw ApiException('缓存失败:${response.statusCode}');
    }

    final contentType = response.headers.value(Headers.contentTypeHeader);
    final base = cacheFileBaseName(song.key);
    final ext = audioExtensionFor(url, contentType);
    final file = File('${(await _cacheDir()).path}/$base$ext');
    final tempFile = File('${file.path}.tmp');
    final sink = tempFile.openWrite();
    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
      }
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await tempFile.exists()) await tempFile.delete();
      rethrow;
    }
    if (await file.exists()) await file.delete();
    await tempFile.rename(file.path);
    await refresh();
    await _upsertSong(song);
    return file.path;
  }

  Future<void> remove(Song song) async {
    final file = await _findFile(song);
    if (file != null) await file.delete();
    await _removeSong(song);
    await refresh();
  }

  Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    await init();
    return _dir!;
  }

  Future<File?> _findFile(Song song) async {
    final dir = await _cacheDir();
    final base = cacheFileBaseName(song.key);
    await for (final entity in dir.list()) {
      if (entity is File && entity.uri.pathSegments.last.startsWith('$base.')) {
        return entity;
      }
    }
    return null;
  }

  List<Song> _loadSongs() {
    final raw = _sp?.getString(_indexKey) ?? '[]';
    try {
      final list = jsonDecode(raw);
      if (list is! List) return <Song>[];
      return [
        for (final item in list)
          if (item is Map) Song.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return <Song>[];
    }
  }

  Future<void> _saveSongs(List<Song> value) async {
    await _sp?.setString(
        _indexKey, jsonEncode(value.map((song) => song.toFavJson()).toList()));
  }

  Future<void> _upsertSong(Song song) async {
    final list = List<Song>.of(songs.value)
      ..removeWhere((item) => item.key == song.key)
      ..insert(0, song);
    songs.value = list;
    await _saveSongs(list);
  }

  Future<void> _removeSong(Song song) async {
    final list = List<Song>.of(songs.value)
      ..removeWhere((item) => item.key == song.key);
    songs.value = list;
    await _saveSongs(list);
  }
}

final songCache = SongCacheStore();
