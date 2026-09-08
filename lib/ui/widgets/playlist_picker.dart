import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/local_playlists.dart';
import '../../core/models.dart';

Future<void> showAddToPlaylistSheet(BuildContext pageContext, Song song) async {
  await showModalBottomSheet<void>(
    context: pageContext,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: ValueListenableBuilder<List<LocalPlaylist>>(
          valueListenable: localPlaylists.playlists,
          builder: (context, playlists, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
                  child: Row(
                    children: [
                      const Text(
                        '添加到歌单',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          final playlist =
                              await _createPlaylistDialog(sheetContext);
                          if (playlist == null) return;
                          final msg =
                              await localPlaylists.addSong(playlist.id, song);
                          if (!sheetContext.mounted) return;
                          Navigator.pop(sheetContext);
                          ScaffoldMessenger.of(pageContext).showSnackBar(
                            SnackBar(
                              content: Text(msg),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('新建'),
                      ),
                    ],
                  ),
                ),
                if (playlists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                    child: Text(
                      '还没有歌单，点右上角新建一个',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: playlists.length,
                      itemBuilder: (context, i) {
                        final playlist = playlists[i];
                        return ListTile(
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: kRed.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.library_music_rounded,
                              color: kRed,
                            ),
                          ),
                          title: Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15),
                          ),
                          subtitle: Text(
                            '${playlist.songs.length} 首',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onTap: () async {
                            final msg =
                                await localPlaylists.addSong(playlist.id, song);
                            if (!sheetContext.mounted) return;
                            Navigator.pop(sheetContext);
                            ScaffoldMessenger.of(pageContext).showSnackBar(
                              SnackBar(
                                content: Text(msg),
                                duration: const Duration(seconds: 1),
                              ),
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
      );
    },
  );
}

Future<LocalPlaylist?> _createPlaylistDialog(BuildContext context) async {
  final ctrl = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('新建歌单'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(hintText: '输入歌单名称'),
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, ctrl.text),
          child: const Text('创建'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  if (name == null || name.trim().isEmpty) return null;
  return localPlaylists.create(name);
}
