import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/audio_handler.dart';
import '../../core/globals.dart';
import '../../core/models.dart';
import '../../core/song_cache.dart';
import '../pages/player.dart';
import 'cover.dart';
import 'playlist_picker.dart';

IconData playModeIcon(PlayMode mode) {
  switch (mode) {
    case PlayMode.sequence:
      return Icons.repeat_rounded;
    case PlayMode.one:
      return Icons.repeat_one_rounded;
    case PlayMode.shuffle:
      return Icons.shuffle_rounded;
  }
}

String playModeName(PlayMode mode) {
  switch (mode) {
    case PlayMode.sequence:
      return '列表循环';
    case PlayMode.one:
      return '单曲循环';
    case PlayMode.shuffle:
      return '随机播放';
  }
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Song?>(
      valueListenable: musicHandler.currentN,
      builder: (context, song, _) {
        if (song == null) return const SizedBox.shrink();
        return Material(
          color: Colors.white,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(PageRouteBuilder(
                fullscreenDialog: true,
                pageBuilder: (_, a, __) => const PlayerPage(),
                transitionsBuilder: (_, a, __, child) => SlideTransition(
                  position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                      .animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
                  child: child,
                ),
              ));
            },
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Cover(song.artwork, size: 40, radius: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: musicHandler.loadingN,
                    builder: (context, loading, _) {
                      if (loading) {
                        return const SizedBox(
                          width: 40,
                          height: 40,
                          child: Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: kRed,
                            ),
                          ),
                        );
                      }
                      return StreamBuilder<bool>(
                        stream: musicHandler.player.playingStream,
                        builder: (context, snap) {
                          final playing = snap.data ?? false;
                          return IconButton(
                            icon: Icon(
                              playing
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                              size: 32,
                              color: Colors.black87,
                            ),
                            onPressed: () =>
                                playing ? musicHandler.pause() : musicHandler.play(),
                          );
                        },
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.queue_music_rounded,
                        size: 26, color: Colors.black54),
                    onPressed: () => showQueueSheet(context),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> _toggleQueueCache(
    BuildContext context, Song song, bool cached) async {
  final messenger = ScaffoldMessenger.of(context);
  if (cached) {
    await songCache.remove(song);
    messenger.showSnackBar(const SnackBar(
      content: Text('已删除本地缓存'),
      duration: Duration(seconds: 1),
    ));
    return;
  }

  messenger.showSnackBar(const SnackBar(
    content: Text('正在缓存到手机...'),
    duration: Duration(seconds: 1),
  ));
  try {
    await songCache.cache(song);
    messenger.showSnackBar(const SnackBar(
      content: Text('已缓存到手机'),
      duration: Duration(seconds: 1),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text('缓存失败:$e'),
      duration: const Duration(seconds: 2),
    ));
  }
}

void showQueueSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.55,
          child: ValueListenableBuilder<List<Song>>(
            valueListenable: musicHandler.queueSongs,
            builder: (context, list, _) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                    child: Row(
                      children: [
                        Text(
                          '当前播放 (${list.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        ValueListenableBuilder<PlayMode>(
                          valueListenable: musicHandler.modeN,
                          builder: (context, mode, _) => TextButton.icon(
                            onPressed: musicHandler.cycleMode,
                            icon: Icon(
                              playModeIcon(mode),
                              size: 18,
                              color: Colors.black54,
                            ),
                            label: Text(
                              playModeName(mode),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: musicHandler.indexN,
                      builder: (context, cur, _) {
                        return ValueListenableBuilder<Set<String>>(
                          valueListenable: songCache.cachedKeys,
                          builder: (context, _, __) {
                            return ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (context, i) {
                                final s = list[i];
                                final isCur = i == cur;
                                final cached = songCache.contains(s);
                                return ListTile(
                                  dense: true,
                                  leading: isCur
                                      ? const Icon(Icons.volume_up_rounded,
                                          color: kRed, size: 18)
                                      : Text(
                                          '${i + 1}',
                                          style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 13,
                                          ),
                                        ),
                                  title: Text(
                                    '${s.title} - ${s.artist}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isCur ? kRed : Colors.black87,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip:
                                            cached ? '删除本地缓存' : '缓存到手机',
                                        icon: Icon(
                                          cached
                                              ? Icons.download_done_rounded
                                              : Icons.download_for_offline_outlined,
                                          size: 20,
                                          color: cached
                                              ? kRed
                                              : Colors.grey.shade500,
                                        ),
                                        onPressed: () =>
                                            _toggleQueueCache(context, s, cached),
                                      ),
                                      IconButton(
                                        tooltip: '添加到歌单',
                                        icon: const Icon(
                                          Icons.library_music_rounded,
                                          size: 20,
                                          color: Colors.grey,
                                        ),
                                        onPressed: () =>
                                            showAddToPlaylistSheet(context, s),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                          color: Colors.grey.shade400,
                                        ),
                                        onPressed: () => musicHandler.removeAt(i),
                                      ),
                                    ],
                                  ),
                                  onTap: () => musicHandler.jumpTo(i),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}
