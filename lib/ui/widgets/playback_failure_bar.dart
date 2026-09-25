import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/audio_handler.dart';
import '../../core/globals.dart';

/// 播放失败的**常驻**提示条(取代原来 2 秒就消失的 SnackBar)。
///
/// 为什么必须常驻:失败大多发生在用户没盯着播放器的时候 —— 他在翻榜单、歌单,
/// 队列自动连播到一首取不到直链的歌。等他抬头看,提示早就没了,屏幕上只会看到
/// "明明点了播却没声音",然后他去怀疑整个音源。现在提示留在原地,并且带「重试」。
///
/// 点击文字可看详情(尝试次数 + 各状态码计数),那是排查插件失效类问题最直接的线索
/// (见 AGENTS.md §8.8)。
class PlaybackFailureBar extends StatelessWidget {
  /// 全屏播放页是深色背景,配色要反一下。
  final bool onDark;

  const PlaybackFailureBar({super.key, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackFailure?>(
      valueListenable: musicHandler.failureN,
      builder: (context, failure, _) {
        if (failure == null) return const SizedBox.shrink();
        final bg = onDark ? const Color(0xFF3C2A2C) : const Color(0xFFFDECEC);
        final fg = onDark ? const Color(0xFFFFD9D9) : const Color(0xFF8A1F1F);

        return Material(
          color: bg,
          child: InkWell(
            onTap: () => _showDetail(context, failure),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 2, 6),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, size: 18, color: fg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '「${failure.song.title}」播放失败',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
                        ),
                        Text(
                          failure.reason,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: fg.withValues(alpha: 0.85),
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
                          width: 56,
                          height: 32,
                          child: Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: kRed,
                              ),
                            ),
                          ),
                        );
                      }
                      return TextButton(
                        onPressed: musicHandler.retryFailure,
                        style: TextButton.styleFrom(
                          foregroundColor: kRed,
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('重试', style: TextStyle(fontSize: 13)),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: fg.withValues(alpha: 0.7),
                    ),
                    onPressed: musicHandler.dismissFailure,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDetail(BuildContext context, PlaybackFailure failure) {
    final source = failure.song.platform.isNotEmpty
        ? failure.song.platform
        : failure.song.source;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('播放失败'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${failure.song.title} - ${failure.song.artist}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(failure.reason),
            if ((failure.detail ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                failure.detail!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '音源:$source',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            Text(
              '失败时间:${_hms(failure.at)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              musicHandler.retryFailure();
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 只取时分秒 —— 排查"是不是刚好在某个时间点集中失败"时够用,不必上完整日期。
  static String _hms(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}
