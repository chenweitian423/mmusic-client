import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../core/audio_handler.dart';
import '../../core/globals.dart';
import '../../core/lrc.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../widgets/cover.dart';
import '../widgets/mini_player.dart';

/// 全屏播放页(封面盘 / 歌词 双页切换)
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final _pageCtrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Song?>(
      valueListenable: musicHandler.currentN,
      builder: (context, song, _) {
        if (song == null) {
          return const Scaffold(
              backgroundColor: Color(0xFF33333B),
              body: Center(
                  child: Text('没有正在播放的歌曲',
                      style: TextStyle(color: Colors.white54))));
        }
        return Scaffold(
          backgroundColor: const Color(0xFF33333B),
          body: Stack(
            fit: StackFit.expand,
            children: [
              // 模糊封面背景
              if (song.artwork.startsWith('http'))
                CachedNetworkImage(
                  imageUrl: song.artwork,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      Container(color: const Color(0xFF33333B)),
                ),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: Container(color: Colors.black.withOpacity(0.55)),
              ),
              SafeArea(
                child: Column(
                  children: [
                    // 顶栏
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down_rounded,
                              color: Colors.white, size: 32),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 12)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    // 主体:封面盘 / 歌词
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          _pageCtrl.animateToPage(
                            _page == 0 ? 1 : 0,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          );
                        },
                        child: PageView(
                          controller: _pageCtrl,
                          onPageChanged: (i) => setState(() => _page = i),
                          children: [
                            _DiscView(song: song),
                            _LyricView(song: song),
                          ],
                        ),
                      ),
                    ),
                    // 页面指示点
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < 2; i++)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i == _page
                                  ? Colors.white70
                                  : Colors.white24,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _ActionRow(song: song),
                    _ProgressBar(),
                    _ControlRow(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 旋转唱片
class _DiscView extends StatefulWidget {
  final Song song;
  const _DiscView({required this.song});

  @override
  State<_DiscView> createState() => _DiscViewState();
}

class _DiscViewState extends State<_DiscView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rot;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _rot = AnimationController(
        vsync: this, duration: const Duration(seconds: 24));
    _sub = musicHandler.player.playingStream.listen((playing) {
      if (!mounted) return;
      if (playing) {
        _rot.repeat();
      } else {
        _rot.stop();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _rot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.width * 0.68;
    return Center(
      child: RotationTransition(
        turns: _rot,
        child: Container(
          width: size + 36,
          height: size + 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withOpacity(0.65),
            border: Border.all(color: Colors.white10, width: 4),
          ),
          child: Center(
            child: ClipOval(
              child: SizedBox(
                width: size,
                height: size,
                child: Cover(widget.song.artwork, size: size, radius: 0),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 同步歌词
class _LyricView extends StatefulWidget {
  final Song song;
  const _LyricView({required this.song});

  @override
  State<_LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends State<_LyricView> {
  static const double _lineHeight = 42;
  final _scroll = ScrollController();
  List<LrcLine>? _lines;
  int _index = -1;
  StreamSubscription<Duration>? _sub;

  @override
  void initState() {
    super.initState();
    _loadLyric();
    _sub = musicHandler.player.positionStream.listen(_onPos);
  }

  @override
  void didUpdateWidget(covariant _LyricView old) {
    super.didUpdateWidget(old);
    if (old.song.key != widget.song.key) {
      _lines = null;
      _index = -1;
      _loadLyric();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadLyric() async {
    final song = widget.song;
    final raw = await api.lyric(song);
    if (!mounted || song.key != widget.song.key) return;
    setState(() => _lines = parseLrc(raw));
  }

  void _onPos(Duration pos) {
    final lines = _lines;
    if (lines == null || lines.isEmpty || !mounted) return;
    final i = lrcIndexFor(lines, pos);
    if (i != _index) {
      setState(() => _index = i);
      if (_scroll.hasClients && i >= 0) {
        _scroll.animateTo(
          (i * _lineHeight - 140)
              .clamp(0.0, _scroll.position.maxScrollExtent)
              .toDouble(),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    if (lines == null) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white38));
    }
    if (lines.isEmpty) {
      return const Center(
          child: Text('暂无歌词', style: TextStyle(color: Colors.white38)));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 150, horizontal: 32),
      itemExtent: _lineHeight,
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final active = i == _index;
        return Center(
          child: Text(
            lines[i].text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? Colors.white : Colors.white38,
              fontSize: active ? 17 : 14,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        );
      },
    );
  }
}

/// 喜欢 / 音质 / 队列
class _ActionRow extends StatelessWidget {
  final Song song;
  const _ActionRow({required this.song});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ValueListenableBuilder<List<Song>>(
            valueListenable: favorites.songs,
            builder: (context, _, __) {
              final liked = favorites.contains(song);
              return IconButton(
                icon: Icon(
                  liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: liked ? kRed : Colors.white70,
                  size: 26,
                ),
                onPressed: () async {
                  final msg = await favorites.toggle(song);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(msg),
                        duration: const Duration(seconds: 1)));
                  }
                },
              );
            },
          ),
          _QualityButton(),
          IconButton(
            icon: const Icon(Icons.queue_music_rounded,
                color: Colors.white70, size: 26),
            onPressed: () => showQueueSheet(context),
          ),
        ],
      ),
    );
  }
}

class _QualityButton extends StatefulWidget {
  @override
  State<_QualityButton> createState() => _QualityButtonState();
}

class _QualityButtonState extends State<_QualityButton> {
  static const _labels = {
    '128': '标准',
    '192': '较高',
    '320': '极高',
    '999': '无损',
  };

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () async {
        final v = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('播放音质(切歌后生效)',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                for (final e in _labels.entries)
                  ListTile(
                    title: Center(
                        child: Text('${e.value} ${e.key == "999" ? "FLAC" : "${e.key}k"}',
                            style: TextStyle(
                                fontSize: 14,
                                color: settings.quality == e.key
                                    ? kRed
                                    : Colors.black87))),
                    onTap: () => Navigator.pop(context, e.key),
                  ),
              ],
            ),
          ),
        );
        if (v != null) {
          await settings.setQuality(v);
          setState(() {});
        }
      },
      child: Text(
        '音质·${_labels[settings.quality] ?? '极高'}',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}

/// 进度条
class _ProgressBar extends StatefulWidget {
  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  double? _dragValue;

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: musicHandler.player.durationStream,
      builder: (context, durSnap) {
        final duration = durSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: musicHandler.player.positionStream,
          builder: (context, posSnap) {
            var position = posSnap.data ?? Duration.zero;
            if (position > duration) position = duration;
            final total = duration.inMilliseconds.toDouble();
            final value = _dragValue ??
                (total > 0
                    ? position.inMilliseconds
                        .toDouble()
                        .clamp(0.0, total)
                        .toDouble()
                    : 0.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(_fmt(position),
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5),
                        overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12),
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        min: 0,
                        max: total > 0 ? total : 1,
                        value: value,
                        onChanged: total > 0
                            ? (v) => setState(() => _dragValue = v)
                            : null,
                        onChangeEnd: (v) {
                          musicHandler
                              .seek(Duration(milliseconds: v.round()));
                          _dragValue = null;
                        },
                      ),
                    ),
                  ),
                  Text(_fmt(duration),
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// 控制按钮行
class _ControlRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ValueListenableBuilder<PlayMode>(
            valueListenable: musicHandler.modeN,
            builder: (context, mode, _) => IconButton(
              icon: Icon(playModeIcon(mode), color: Colors.white70, size: 26),
              onPressed: musicHandler.cycleMode,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.skip_previous_rounded,
                color: Colors.white, size: 40),
            onPressed: musicHandler.skipToPrevious,
          ),
          ValueListenableBuilder<bool>(
            valueListenable: musicHandler.loadingN,
            builder: (context, loading, _) {
              if (loading) {
                return const SizedBox(
                  width: 68,
                  height: 68,
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 3),
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
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      color: Colors.white,
                      size: 68,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () =>
                        playing ? musicHandler.pause() : musicHandler.play(),
                  );
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.skip_next_rounded,
                color: Colors.white, size: 40),
            onPressed: musicHandler.skipToNext,
          ),
          IconButton(
            icon: const Icon(Icons.playlist_play_rounded,
                color: Colors.white70, size: 28),
            onPressed: () => showQueueSheet(context),
          ),
        ],
      ),
    );
  }
}
