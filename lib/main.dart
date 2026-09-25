import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/api.dart';
import 'core/audio_handler.dart';
import 'core/embedded/plugin_store.dart';
import 'core/globals.dart';
import 'core/local_playlists.dart';
import 'core/search_history.dart';
import 'core/settings.dart';
import 'core/song_cache.dart';
import 'core/sources.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await settings.init();
  await songCache.init();
  await localPlaylists.init();
  await searchHistory.init();
  api.configure();

  // 插件仓库要在启动闸门之前就绪：内置源模式下「有没有插件」直接决定
  // 用户看到的是主界面还是"去导入插件"的引导。
  // 首次启动若安装包里带了插件，这一步会把它们装载一次（约几百毫秒/个），
  // 之后就只是读索引，开销可以忽略。
  await pluginStore.init();
  syncSourceKind();

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  musicHandler = await AudioService.init(
    builder: () => MusicHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.sky.mmusic.audio',
      androidNotificationChannelName: 'M音乐 播放',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  runApp(const MMusicApp());
}
