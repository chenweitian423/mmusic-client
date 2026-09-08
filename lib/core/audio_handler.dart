import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'api.dart';
import 'models.dart';
import 'song_cache.dart';

enum PlayMode { sequence, one, shuffle }

bool shouldAutoAdvanceFromPosition({
  required Duration position,
  required Duration? duration,
  required bool loading,
  required bool completedHandled,
  required PlayMode mode,
  required bool hasQueue,
}) {
  if (loading || completedHandled || !hasQueue) return false;
  if (mode == PlayMode.one || duration == null) return false;
  if (duration < const Duration(seconds: 5)) return false;
  final remaining = duration - position;
  return remaining <= const Duration(milliseconds: 700);
}

bool shouldAutoAdvanceFromCompletion({
  required bool loading,
  required bool completedHandled,
  required PlayMode mode,
  required int queueLength,
}) {
  if (loading || completedHandled) return false;
  if (mode == PlayMode.one) return false;
  return queueLength > 1;
}

class MusicHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer player = AudioPlayer();

  final ValueNotifier<List<Song>> queueSongs = ValueNotifier(<Song>[]);
  final ValueNotifier<int> indexN = ValueNotifier(-1);
  final ValueNotifier<Song?> currentN = ValueNotifier(null);
  final ValueNotifier<PlayMode> modeN = ValueNotifier(PlayMode.sequence);
  final ValueNotifier<bool> loadingN = ValueNotifier(false);
  final ValueNotifier<String> errorN = ValueNotifier('');

  final Random _rnd = Random();
  int _loadSeq = 0;
  int _failStreak = 0;
  bool _completedHandled = false;
  bool _autoAdvanceInFlight = false;

  MusicHandler() {
    player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) {
        // ignore stream noise
      },
    );

    player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed &&
          shouldAutoAdvanceFromCompletion(
            loading: loadingN.value,
            completedHandled: _completedHandled,
            mode: modeN.value,
            queueLength: queueSongs.value.length,
          )) {
        unawaited(_autoNext());
      }
    });

    player.positionStream.listen((position) {
      if (shouldAutoAdvanceFromPosition(
        position: position,
        duration: player.duration ?? mediaItem.value?.duration,
        loading: loadingN.value,
        completedHandled: _completedHandled,
        mode: modeN.value,
        hasQueue: queueSongs.value.length > 1,
      )) {
        unawaited(_autoNext());
      }
    });

    player.durationStream.listen((d) {
      final mi = mediaItem.value;
      if (d != null && mi != null && mi.duration != d) {
        mediaItem.add(mi.copyWith(duration: d));
      }
    });
  }

  Future<void> setQueueAndPlay(List<Song> songs, int start) async {
    if (songs.isEmpty) return;
    queueSongs.value = List.of(songs);
    _failStreak = 0;
    await _load(start.clamp(0, songs.length - 1).toInt());
  }

  Future<void> playNext(Song song) async {
    final list = List.of(queueSongs.value);
    if (list.isEmpty) {
      await setQueueAndPlay([song], 0);
      return;
    }
    final at = (indexN.value + 1).clamp(0, list.length).toInt();
    list.insert(at, song);
    queueSongs.value = list;
  }

  Future<void> jumpTo(int i) async {
    if (i < 0 || i >= queueSongs.value.length) return;
    _failStreak = 0;
    await _load(i);
  }

  void removeAt(int i) {
    final list = List.of(queueSongs.value);
    if (i < 0 || i >= list.length) return;
    final cur = indexN.value;
    list.removeAt(i);
    queueSongs.value = list;
    if (list.isEmpty) {
      stop();
      currentN.value = null;
      indexN.value = -1;
      return;
    }
    if (i == cur) {
      _load(i.clamp(0, list.length - 1).toInt());
    } else if (i < cur) {
      indexN.value = cur - 1;
    }
  }

  void cycleMode() {
    final next = PlayMode.values[
        (PlayMode.values.indexOf(modeN.value) + 1) % PlayMode.values.length];
    modeN.value = next;
    player.setLoopMode(next == PlayMode.one ? LoopMode.one : LoopMode.off);
  }

  Future<void> _load(int i, {bool autoplay = true}) async {
    final songs = queueSongs.value;
    if (songs.isEmpty) return;
    final seq = ++_loadSeq;
    _completedHandled = false;
    indexN.value = i;
    final song = songs[i];
    currentN.value = song;
    loadingN.value = true;
    errorN.value = '';
    mediaItem.add(MediaItem(
      id: song.key,
      title: song.title,
      artist: song.artist,
      album: song.album,
      artUri: song.artwork.isNotEmpty ? Uri.tryParse(song.artwork) : null,
      duration: parseInterval(song.interval),
    ));

    try {
      final cachedPath = await songCache.localPath(song);
      if (seq != _loadSeq) return;
      if (cachedPath != null) {
        await player.setFilePath(cachedPath);
      } else {
        final url = await api.playUrl(song);
        if (seq != _loadSeq) return;
        await player.setUrl(url);
      }
      if (seq != _loadSeq) return;
      _failStreak = 0;
      if (autoplay) unawaited(player.play());
    } catch (e) {
      if (seq != _loadSeq) return;
      _failStreak++;
      errorN.value = '「${song.title}」播放失败，已跳过';
      if (_failStreak < songs.length && _failStreak < 5) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (seq == _loadSeq) await _load(_nextIndex());
      }
    } finally {
      if (seq == _loadSeq) loadingN.value = false;
    }
  }

  int _nextIndex() {
    final len = queueSongs.value.length;
    if (len <= 1) return 0;
    if (modeN.value == PlayMode.shuffle) {
      int n;
      do {
        n = _rnd.nextInt(len);
      } while (n == indexN.value);
      return n;
    }
    return (indexN.value + 1) % len;
  }

  int _prevIndex() {
    final len = queueSongs.value.length;
    if (len <= 1) return 0;
    if (modeN.value == PlayMode.shuffle) return _nextIndex();
    return (indexN.value - 1 + len) % len;
  }

  Future<void> _autoNext() async {
    if (_autoAdvanceInFlight) return;
    if (!shouldAutoAdvanceFromCompletion(
      loading: loadingN.value,
      completedHandled: _completedHandled,
      mode: modeN.value,
      queueLength: queueSongs.value.length,
    )) {
      return;
    }

    _autoAdvanceInFlight = true;
    _completedHandled = true;
    try {
      _failStreak = 0;
      if (defaultTargetPlatform != TargetPlatform.iOS) {
        await player.stop();
      }
      if (queueSongs.value.length > 1) {
        await _load(_nextIndex());
      }
    } finally {
      _autoAdvanceInFlight = false;
    }
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    if (queueSongs.value.isEmpty) return;
    _failStreak = 0;
    await _load(_nextIndex());
  }

  @override
  Future<void> skipToPrevious() async {
    if (queueSongs.value.isEmpty) return;
    _failStreak = 0;
    await _load(_prevIndex());
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[player.processingState]!,
      playing: playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: indexN.value >= 0 ? indexN.value : null,
    ));
  }
}
