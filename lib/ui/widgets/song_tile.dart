import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/globals.dart';
import '../../core/models.dart';
import '../../core/song_cache.dart';
import 'cover.dart';
import 'playlist_picker.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final List<Song> listContext;
  final int index;
  final bool showIndex;

  const SongTile({
    super.key,
    required this.song,
    required this.listContext,
    required this.index,
    this.showIndex = false,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Song?>(
      valueListenable: musicHandler.currentN,
      builder: (context, cur, _) {
        final isCurrent = cur?.key == song.key;
        final titleColor = isCurrent ? kRed : Colors.black87;
        return ListTile(
          contentPadding: const EdgeInsets.only(left: 16, right: 4),
          leading: showIndex
              ? SizedBox(
                  width: 34,
                  child: Center(
                    child: index < 3
                        ? Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: kRed,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 15,
                            ),
                          ),
                  ),
                )
              : Cover(song.artwork, size: 46),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              color: titleColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Row(
            children: [
              if (song.platform.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    border: Border.all(color: kRed.withOpacity(0.6), width: 0.8),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    song.platform,
                    style: const TextStyle(fontSize: 9, color: kRed),
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(
                  song.album.isEmpty ? song.artist : '${song.artist} 路 ${song.album}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
          trailing: _SongMenu(song: song),
          onTap: () => musicHandler.setQueueAndPlay(listContext, index),
        );
      },
    );
  }
}

class _SongMenu extends StatelessWidget {
  final Song song;
  const _SongMenu({required this.song});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: songCache.cachedKeys,
      builder: (context, _, __) {
        final cached = songCache.contains(song);
        return PopupMenuButton<String>(
          icon: Icon(
            Icons.more_vert_rounded,
            color: Colors.grey.shade400,
            size: 20,
          ),
          onSelected: (v) async {
            final messenger = ScaffoldMessenger.of(context);
            switch (v) {
              case 'next':
                await musicHandler.playNext(song);
                messenger.showSnackBar(const SnackBar(
                  content: Text('已添加为下一首播放'),
                  duration: Duration(seconds: 1),
                ));
                break;
              case 'cache':
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
                break;
              case 'removeCache':
                await songCache.remove(song);
                messenger.showSnackBar(const SnackBar(
                  content: Text('已删除本地缓存'),
                  duration: Duration(seconds: 1),
                ));
                break;
              case 'fav':
                final msg = await favorites.toggle(song);
                messenger.showSnackBar(SnackBar(
                  content: Text(msg),
                  duration: const Duration(seconds: 1),
                ));
                break;
              case 'playlist':
                await showAddToPlaylistSheet(context, song);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'next',
              child: Row(
                children: [
                  Icon(Icons.playlist_play_rounded,
                      size: 20, color: Colors.black54),
                  SizedBox(width: 10),
                  Text('下一首播放'),
                ],
              ),
            ),
            PopupMenuItem(
              value: cached ? 'removeCache' : 'cache',
              child: Row(
                children: [
                  Icon(
                    cached
                        ? Icons.download_done_rounded
                        : Icons.download_for_offline_outlined,
                    size: 20,
                    color: cached ? kRed : Colors.black54,
                  ),
                  const SizedBox(width: 10),
                  Text(cached ? '删除本地缓存' : '缓存到手机'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'playlist',
              child: Row(
                children: [
                  const Icon(Icons.library_music_rounded,
                      size: 20, color: Colors.black54),
                  const SizedBox(width: 10),
                  const Text('添加到歌单'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'fav',
              child: Row(
                children: [
                  Icon(
                    favorites.contains(song)
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 20,
                    color: favorites.contains(song) ? kRed : Colors.black54,
                  ),
                  const SizedBox(width: 10),
                  Text(favorites.contains(song) ? '取消喜欢' : '添加到我喜欢'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
