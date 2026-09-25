import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'api.dart';
import 'models.dart';
import 'song_cache.dart';
import 'sources.dart';

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

/// 一次播放失败的完整描述。
@immutable
class PlaybackFailure {
  /// 失败的歌曲。重试时按 [Song.key] 在当前队列里重新定位,所以不必存下标
  /// (存了下标,一旦用户删歌/换队列就会指错)。
  final Song song;

  /// 面向用户的一句话原因。
  final String reason;

  /// 技术摘要(尝试次数、各状态码计数),给「详情」弹窗看。
  final String? detail;

  final DateTime at;

  const PlaybackFailure({
    required this.song,
    required this.reason,
    this.detail,
    required this.at,
  });

  @override
  String toString() => 'PlaybackFailure(${song.title}: $reason)';
}

/// 失败后是否还该自动跳下一首。
///
/// 两个上限:不超过队列长度(整个队列都挂时别无限转),也不超过 5 首 ——
/// 连挂 5 首基本说明是服务端/网络的问题,再跳也是白跳。
bool shouldSkipAfterFailure({
  required int failStreak,
  required int queueLength,
}) =>
    failStreak < queueLength && failStreak < 5;

/// 把加载失败的异常翻译成一句能看懂的话。
///
/// [ApiException] 的 message 已经在 `Api.playUrl` 里归过类(登录过期 / 连不上服务端 /
/// 音源没给地址…),直接用;其余按来源粗分,兜底退回异常原文的短形式。
String describeLoadFailure(Object error) {
  if (error is ApiException) return error.message;
  if (error is PlayerInterruptedException) return '播放被中断';
  if (error is PlayerException) {
    return '音频地址无法播放(${error.message})';
  }
  final s = error.toString();
  if (s.contains('FileSystemException')) {
    return '本地缓存读取失败,删掉这首的缓存再试';
  }
  return shortErrorText(error);
}

class MusicHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer player = AudioPlayer();

  final ValueNotifier<List<Song>> queueSongs = ValueNotifier(<Song>[]);
  final ValueNotifier<int> indexN = ValueNotifier(-1);
  final ValueNotifier<Song?> currentN = ValueNotifier(null);
  final ValueNotifier<PlayMode> modeN = ValueNotifier(PlayMode.sequence);
  final ValueNotifier<bool> loadingN = ValueNotifier(false);

  /// 当前尚未处理的播放失败 —— 界面上的常驻提示条与「重试」按钮都读它。
  ///
  /// 只在三种情况下被清空:用户点了「关闭」、用户重试成功、或这首歌已经不在队列里。
  /// **不会因为"跳到下一首了"就自动消失** —— 那样就等于又变回静默跳过。
  final ValueNotifier<PlaybackFailure?> failureN = ValueNotifier(null);

  final Random _rnd = Random();
  int _loadSeq = 0;
  int _failStreak = 0;
  bool _completedHandled = false;
  bool _autoAdvanceInFlight = false;

  /// 播放器里当前是否真的装载了音源。失败后为 false —— 此时按播放键应当是"重试",
  /// 否则按下去毫无反应,看着像卡死。
  bool _hasLoadedSource = false;

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
    // 换了一整队歌,上一首的失败提示已经无关了。
    failureN.value = null;
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

  /// 加载并(可选)播放第 [i] 首。
  ///
  /// [skipOnFailure] 决定这首加载失败后要不要自动跳下一首:
  /// - `true` —— 队列自动连播、以及用户按了「上一首 / 下一首」时用。用户/播放流程
  ///   的意图是"继续放下去",别让一首坏歌把整个播放中断掉。
  /// - `false`(默认) —— 用户在列表里点播、或按了「重试」时用。这时用户明确要的是
  ///   **这一首**,失败了就该停下来说清楚,而不是偷偷换成别的歌
  ///   (那正是这次改造要干掉的"静默跳下一首")。
  Future<void> _load(
    int i, {
    bool autoplay = true,
    bool skipOnFailure = false,
  }) async {
    final songs = queueSongs.value;
    if (songs.isEmpty) return;
    final seq = ++_loadSeq;
    _completedHandled = false;
    indexN.value = i;
    final song = songs[i];
    currentN.value = song;
    loadingN.value = true;
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
        // 走当前音源：服务端模式是 NAS 的 /proxy|/media-source，
        // 内置源模式是本地 JS 插件直接算出上游直链（少一跳，首播更快）。
        final url = await musicSource.playUrl(song);
        if (seq != _loadSeq) return;
        await player.setUrl(url);
      }
      if (seq != _loadSeq) return;
      _hasLoadedSource = true;
      _failStreak = 0;
      // 之前报的是同一首 → 说明这次重试成功了,收回提示。
      // 报的是别的歌则保留,用户仍可以回去重试它。
      final failed = failureN.value;
      if (failed != null && failed.song.key == song.key) {
        failureN.value = null;
      }
      if (autoplay) unawaited(player.play());
    } catch (e) {
      if (seq != _loadSeq) return;
      _hasLoadedSource = false;
      _failStreak++;
      _reportFailure(song, e);
      if (skipOnFailure &&
          shouldSkipAfterFailure(
            failStreak: _failStreak,
            queueLength: songs.length,
          )) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (seq == _loadSeq) {
          await _load(_nextIndex(), skipOnFailure: true);
        }
      }
    } finally {
      if (seq == _loadSeq) loadingN.value = false;
    }
  }

  /// 记录一次失败,并把它变成界面上可操作的状态(而不是一句会自己消失的提示)。
  void _reportFailure(Song song, Object error) {
    failureN.value = PlaybackFailure(
      song: song,
      reason: describeLoadFailure(error),
      detail: error is ApiException ? error.detail : null,
      at: DateTime.now(),
    );
  }

  /// 重试上一次失败的歌曲。
  ///
  /// 返回是否真的发起了重试(歌曲已不在队列里则返回 false,调用方可以自己决定怎么办)。
  /// 成功后由 [_load] 收回提示;再失败会用新的原因覆盖提示。
  Future<bool> retryFailure() async {
    final failed = failureN.value;
    if (failed == null) return false;
    final i = queueSongs.value.indexWhere((s) => s.key == failed.song.key);
    if (i < 0) {
      // 队列里已经没有这首歌了(被删掉 / 换过队列),提示作废。
      failureN.value = null;
      return false;
    }
    _failStreak = 0;
    // skipOnFailure 保持 false:用户明确要求修好这一首,失败就停下来说清楚。
    await _load(i);
    return true;
  }

  /// 用户手动关掉失败提示。
  void dismissFailure() => failureN.value = null;

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
        await _load(_nextIndex(), skipOnFailure: true);
      }
    } finally {
      _autoAdvanceInFlight = false;
    }
  }

  @override
  Future<void> play() async {
    // 上一次加载失败了(播放器里没有音源),此时"播放"键的真实意图是"重试"。
    // 不做这层转发的话,按下去毫无反应,看着像卡死。
    if (!_hasLoadedSource && failureN.value != null) {
      if (await retryFailure()) return;
    }
    await player.play();
  }

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
    // 用户按的是"换一首",所以这首坏了就继续往后找(与旧行为一致)。
    await _load(_nextIndex(), skipOnFailure: true);
  }

  @override
  Future<void> skipToPrevious() async {
    if (queueSongs.value.isEmpty) return;
    _failStreak = 0;
    await _load(_prevIndex(), skipOnFailure: true);
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
