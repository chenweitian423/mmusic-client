/// LRC 歌词解析。
/// 服务端两种时间戳格式都要支持:
///   [00:26.17]  分:秒
///   [2.25]      纯秒数(插件 rawLrc)
class LrcLine {
  final Duration time;
  final String text;
  LrcLine(this.time, this.text);
}

List<LrcLine> parseLrc(String raw) {
  final lines = <LrcLine>[];
  final reg = RegExp(r'\[([\d:.]+)\]');
  for (final line in raw.split('\n')) {
    final ms = reg.allMatches(line).toList();
    if (ms.isEmpty) continue;
    final text = line.substring(ms.last.end).trim();
    if (text.isEmpty) continue;
    for (final m in ms) {
      final t = _parseTime(m.group(1)!);
      if (t != null) lines.add(LrcLine(t, text));
    }
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}

Duration? _parseTime(String s) {
  try {
    final parts = s.split(':');
    if (parts.length == 1) {
      final sec = double.parse(parts[0]);
      return Duration(milliseconds: (sec * 1000).round());
    }
    if (parts.length == 2) {
      final min = int.parse(parts[0]);
      final sec = double.parse(parts[1]);
      return Duration(milliseconds: min * 60000 + (sec * 1000).round());
    }
    if (parts.length == 3) {
      final h = int.parse(parts[0]);
      final min = int.parse(parts[1]);
      final sec = double.parse(parts[2]);
      return Duration(
          milliseconds: h * 3600000 + min * 60000 + (sec * 1000).round());
    }
  } catch (_) {}
  return null;
}

/// 当前播放到第几行(二分查找)
int lrcIndexFor(List<LrcLine> lines, Duration pos) {
  if (lines.isEmpty) return -1;
  var lo = 0, hi = lines.length - 1, ans = -1;
  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    if (lines[mid].time <= pos) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}
