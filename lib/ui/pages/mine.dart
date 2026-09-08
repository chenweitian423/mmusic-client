import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../core/globals.dart';
import '../../core/local_playlists.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/song_cache.dart';
import 'settings.dart';
import 'song_list_page.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  List<Map<String, dynamic>>? _collections;

  @override
  void initState() {
    super.initState();
    _loadCollections();
    if (!favorites.loaded) favorites.load();
  }

  Future<void> _loadCollections() async {
    try {
      final c = await api.collections();
      if (mounted) setState(() => _collections = c);
    } catch (_) {
      if (mounted) setState(() => _collections = []);
    }
  }

  String _str(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsPage()));
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: kRed,
        onRefresh: () async {
          await favorites.load();
          await localPlaylists.reload();
          await _loadCollections();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // 用户卡片
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: kRed.withOpacity(0.12),
                    child: const Icon(Icons.person_rounded,
                        color: kRed, size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            settings.username.isEmpty
                                ? '未登录'
                                : settings.username,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(settings.serverUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 我喜欢的音乐
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ValueListenableBuilder<List<Song>>(
                valueListenable: favorites.songs,
                builder: (context, favs, _) {
                  return ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFFFF7A7A), kRed]),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.favorite_rounded,
                          color: Colors.white),
                    ),
                    title: const Text('我喜欢的音乐',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    subtitle: Text('${favs.length} 首',
                        style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: Colors.grey),
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SongListPage(
                          title: '我喜欢的音乐',
                          loader: () async {
                            await favorites.load();
                            return favorites.songs.value;
                          },
                        ),
                      ));
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ValueListenableBuilder<List<LocalPlaylist>>(
                valueListenable: localPlaylists.playlists,
                builder: (context, playlists, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                        child: Row(
                          children: [
                            const Text('我的歌单',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.add_rounded, color: kRed),
                              onPressed: () => _createLocalPlaylist(context),
                            ),
                          ],
                        ),
                      ),
                      if (playlists.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          child: Text('还没有创建歌单',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade500)),
                        )
                      else
                        for (final playlist in playlists)
                          ListTile(
                            dense: true,
                            leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: kRed.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.library_music_rounded,
                                  color: kRed),
                            ),
                            title: Text(
                              playlist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text('${playlist.songs.length} 首',
                                style: const TextStyle(fontSize: 12)),
                            trailing: PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert_rounded,
                                  color: Colors.grey.shade400, size: 20),
                              onSelected: (v) async {
                                if (v != 'delete') return;
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('删除歌单'),
                                    content:
                                        Text('确定删除“${playlist.name}”吗？歌曲文件不会被删除。'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('取消')),
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('删除',
                                              style: TextStyle(color: kRed))),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  await localPlaylists.delete(playlist.id);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('已删除歌单'),
                                          duration: Duration(seconds: 1)));
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(children: [
                                    Icon(Icons.delete_outline_rounded,
                                        size: 20, color: kRed),
                                    SizedBox(width: 10),
                                    Text('删除歌单'),
                                  ]),
                                ),
                              ],
                            ),
                            onTap: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => SongListPage(
                                  title: playlist.name,
                                  loader: () async =>
                                      localPlaylists.byId(playlist.id)?.songs ??
                                      <Song>[],
                                ),
                              ));
                            },
                          ),
                      const SizedBox(height: 6),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ValueListenableBuilder<List<Song>>(
                valueListenable: songCache.songs,
                builder: (context, cached, _) {
                  return ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: kRed.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.download_done_rounded,
                          color: kRed),
                    ),
                    title: const Text('本地缓存',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    subtitle: Text('${cached.length} 首',
                        style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: Colors.grey),
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SongListPage(
                          title: '本地缓存',
                          loader: () async {
                            await songCache.refresh();
                            return songCache.songs.value;
                          },
                        ),
                      ));
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            // 收藏的歌单
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Text('收藏的歌单',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  if (_collections == null)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                          child: CircularProgressIndicator(color: kRed)),
                    )
                  else if (_collections!.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Text('还没有收藏歌单(可在网页端收藏)',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500)),
                    )
                  else
                    for (final c in _collections!)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.queue_music_rounded,
                            color: kRed),
                        title: Text(
                          _str(c, ['name', 'title', 'filename']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: Colors.grey, size: 20),
                        onTap: () {
                          final filename = _str(c, ['filename', 'id', 'name']);
                          if (filename.isEmpty) return;
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => SongListPage(
                              title: _str(c, ['name', 'title', 'filename']),
                              loader: () => api.collectionDetail(filename),
                            ),
                          ));
                        },
                      ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createLocalPlaylist(BuildContext context) async {
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
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('创建')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.trim().isEmpty) return;
    try {
      await localPlaylists.create(name);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已创建歌单'), duration: Duration(seconds: 1)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()), duration: const Duration(seconds: 2)));
    }
  }
}
