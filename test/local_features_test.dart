import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mmusic_client/core/local_playlists.dart';
import 'package:mmusic_client/core/models.dart';
import 'package:mmusic_client/core/search_history.dart';
import 'package:mmusic_client/core/audio_handler.dart';

Song _song(String id, String title) => Song.fromJson({
      'id': id,
      'title': title,
      'artist': 'A',
      'album': '',
      'artwork': '',
      'source': 'wy',
      'platform': '网易云',
      'interval': '03:00',
      'types': [],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('local playlist stores songs in most-recent-first order without duplicates',
      () async {
    final store = LocalPlaylistsStore();
    await store.init();

    final playlist = await store.create('收藏');
    final a = _song('1', 'A');
    final b = _song('2', 'B');

    await store.addSong(playlist.id, a);
    await store.addSong(playlist.id, b);
    await store.addSong(playlist.id, a);

    final loaded = store.byId(playlist.id)!;
    expect(loaded.songs.map((e) => e.key).toList(), [a.key, b.key]);
  });

  test('search history keeps newest terms first and deduplicated', () async {
    final store = SearchHistoryStore();
    await store.init();

    await store.add('hello');
    await store.add('world');
    await store.add('hello');

    expect(store.terms.value, ['hello', 'world']);
  });

  test('auto advance triggers when playback is near the end', () {
    expect(
      shouldAutoAdvanceFromPosition(
        position: const Duration(minutes: 3, seconds: 59, milliseconds: 400),
        duration: const Duration(minutes: 4),
        loading: false,
        completedHandled: false,
        mode: PlayMode.sequence,
        hasQueue: true,
      ),
      isTrue,
    );
  });
}
