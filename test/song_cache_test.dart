import 'package:flutter_test/flutter_test.dart';
import 'package:mmusic_client/core/song_cache.dart';

void main() {
  test('cacheFileBaseName is stable and filesystem-safe', () {
    final first = cacheFileBaseName('source/hash|song:123');
    final second = cacheFileBaseName('source/hash|song:123');

    expect(first, second);
    expect(first, matches(RegExp(r'^[a-f0-9]{16}$')));
  });

  test('audioExtensionFor prefers known content type before url path', () {
    expect(audioExtensionFor('https://example.com/play?id=1', 'audio/flac'),
        '.flac');
    expect(audioExtensionFor('https://example.com/song.mp3?token=abc', null),
        '.mp3');
    expect(audioExtensionFor('https://example.com/play?id=1', null), '.mp3');
  });
}
