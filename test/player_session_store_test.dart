import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supwave_gen2/models/song.dart';
import 'package:supwave_gen2/state/player_session_store.dart';

Song _song(String id) => Song(
  id: id,
  title: 'Title $id',
  artist: 'Artist',
  artistId: 'ar1',
  album: 'Album',
  albumId: 'al1',
  duration: const Duration(minutes: 3),
  coverArtId: 'cover-$id',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('load returns null when nothing has been saved', () async {
    expect(await PlayerSessionStore().load(), isNull);
  });

  test('save then load round-trips the queue, index, position, shuffle, and repeat mode', () async {
    final store = PlayerSessionStore();
    await store.save(
      queue: [_song('s1'), _song('s2')],
      currentIndex: 1,
      position: const Duration(seconds: 42),
      shuffle: true,
      repeatModeName: 'all',
    );

    final session = await store.load();
    expect(session, isNotNull);
    expect(session!.queue.map((s) => s.id), ['s1', 's2']);
    expect(session.currentIndex, 1);
    expect(session.position, const Duration(seconds: 42));
    expect(session.shuffle, isTrue);
    expect(session.repeatModeName, 'all');
  });

  test('saving an empty queue clears any existing session', () async {
    final store = PlayerSessionStore();
    await store.save(
      queue: [_song('s1')],
      currentIndex: 0,
      position: Duration.zero,
      shuffle: false,
      repeatModeName: 'off',
    );
    expect(await store.load(), isNotNull);

    await store.save(
      queue: const [],
      currentIndex: -1,
      position: Duration.zero,
      shuffle: false,
      repeatModeName: 'off',
    );
    expect(await store.load(), isNull);
  });

  test('clear removes a saved session', () async {
    final store = PlayerSessionStore();
    await store.save(
      queue: [_song('s1')],
      currentIndex: 0,
      position: Duration.zero,
      shuffle: false,
      repeatModeName: 'off',
    );
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('an out-of-range currentIndex is clamped into bounds on load', () async {
    // save() itself refuses to persist an out-of-range index (it clears
    // instead), so this exercises load()'s own defensive clamp directly -
    // guarding against a hand-edited/corrupted or future-format entry,
    // rather than anything reachable through save() today.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'player_session_v1',
      jsonEncode({
        'queue': [_song('s1').toJson(), _song('s2').toJson()],
        'currentIndex': 5,
        'positionMs': 0,
        'shuffle': false,
        'repeatMode': 'off',
      }),
    );

    final session = await PlayerSessionStore().load();
    expect(session!.currentIndex, 1);
  });
}
