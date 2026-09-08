import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/api.dart';
import 'core/audio_handler.dart';
import 'core/globals.dart';
import 'core/local_playlists.dart';
import 'core/search_history.dart';
import 'core/settings.dart';
import 'core/song_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await settings.init();
  await songCache.init();
  await localPlaylists.init();
  await searchHistory.init();
  api.configure();
  final session = await AudioSession.instance;
  await session.configure(AudioSessionConfiguration.music());
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
