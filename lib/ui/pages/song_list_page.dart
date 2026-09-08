import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/globals.dart';
import '../../core/models.dart';
import '../widgets/cover.dart';
import '../widgets/song_tile.dart';

/// 通用歌曲列表页:榜单歌曲 / 歌单详情 / 收藏歌单 / 我喜欢的音乐
class SongListPage extends StatefulWidget {
  final String title;
  final String? coverUrl;
  final String? subtitle;
  final bool showIndex;
  final Future<List<Song>> Function() loader;

  const SongListPage({
    super.key,
    required this.title,
    required this.loader,
    this.coverUrl,
    this.subtitle,
    this.showIndex = false,
  });

  @override
  State<SongListPage> createState() => _SongListPageState();
}

class _SongListPageState extends State<SongListPage> {
  List<Song>? _songs;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _songs = null;
      _error = '';
    });
    try {
      final songs = await widget.loader();
      if (!mounted) return;
      setState(() => _songs = songs);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _songs = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final songs = _songs;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: songs == null
          ? const Center(child: CircularProgressIndicator(color: kRed))
          : Column(
              children: [
                if (widget.coverUrl != null || widget.subtitle != null)
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        if (widget.coverUrl != null)
                          Cover(widget.coverUrl!, size: 72, radius: 8),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              if (widget.subtitle != null) ...[
                                const SizedBox(height: 4),
                                Text(widget.subtitle!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(
                  color: Colors.white,
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: songs.isEmpty
                            ? null
                            : () => musicHandler.setQueueAndPlay(songs, 0),
                        icon: const Icon(Icons.play_circle_filled,
                            color: kRed, size: 28),
                        label: Text('播放全部 (${songs.length})',
                            style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _load,
                        icon: Icon(Icons.refresh_rounded,
                            color: Colors.grey.shade500, size: 20),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _error.isNotEmpty
                      ? _ErrorRetry(error: _error, onRetry: _load)
                      : songs.isEmpty
                          ? Center(
                              child: Text('暂无歌曲',
                                  style:
                                      TextStyle(color: Colors.grey.shade500)))
                          : Container(
                              color: Colors.white,
                              child: ListView.builder(
                                itemCount: songs.length,
                                itemBuilder: (context, i) => SongTile(
                                  song: songs[i],
                                  listContext: songs,
                                  index: i,
                                  showIndex: widget.showIndex,
                                ),
                              ),
                            ),
                ),
              ],
            ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
