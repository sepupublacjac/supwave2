import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supwave_gen2/state/library_controller.dart';
import 'package:supwave_gen2/state/offline_manager.dart';
import 'package:supwave_gen2/state/player_controller.dart';

import 'fakes/fake_audio_engine.dart';
import 'fakes/fake_navidrome_repository.dart';

/// Covers shuffle, repeat mode, and the "play next" feature.
///
/// Shuffle was a real bug: toggleShuffle() only flipped a cosmetic flag that
/// nothing else read - next()/previous() always walked the queue
/// sequentially regardless of it.
void main() {
  // PlayerController registers a WidgetsBindingObserver and touches
  // shared_preferences, neither of which exists by default under plain
  // `test()`.
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNavidromeRepository repo;
  late FakeAudioEngine engine;
  late PlayerController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = FakeNavidromeRepository();
    engine = FakeAudioEngine();
    controller = PlayerController(
      repo,
      LibraryController(repo),
      OfflineManager(repo),
      audioEngine: engine,
    );
  });

  group('shuffle', () {
    test('off: next() advances sequentially through the queue', () async {
      final songs = (await repo.getDashboard()).quickPicks;
      await controller.playQueue(songs, startIndex: 0);

      for (var i = 1; i < songs.length; i++) {
        await controller.next();
        expect(controller.currentSong?.id, songs[i].id);
      }
    });

    test(
      'on: next() visits every song exactly once, in an order that is '
      'actually shuffled (regression: toggleShuffle used to do nothing, so '
      'next() just kept walking the queue in order)',
      () async {
        final songs = (await repo.getDashboard()).quickPicks;
        await controller.playQueue(songs, startIndex: 0);
        controller.toggleShuffle();
        expect(controller.shuffle, isTrue);

        final visitedInOrder = [controller.currentSong!.id];
        for (var i = 1; i < songs.length; i++) {
          await controller.next();
          visitedInOrder.add(controller.currentSong!.id);
        }

        // Every song exactly once - no skips, no repeats.
        expect(visitedInOrder.toSet(), songs.map((s) => s.id).toSet());
        // With 6 songs, a real shuffle landing on the exact same order as
        // the original queue by chance is a ~1-in-720 fluke, not something
        // a passing test should routinely rely on getting right.
        expect(visitedInOrder, isNot(songs.map((s) => s.id).toList()));
      },
    );

    test('on: turning shuffle on mid-playback does not change the current track', () async {
      final songs = (await repo.getDashboard()).quickPicks;
      await controller.playQueue(songs, startIndex: 2);
      final before = controller.currentSong?.id;

      controller.toggleShuffle();

      expect(controller.currentSong?.id, before);
    });
  });

  group('repeat mode', () {
    test('off: playback stops after the last track finishes', () async {
      final songs = (await repo.getDashboard()).quickPicks;
      await controller.playQueue(songs, startIndex: songs.length - 1);
      await pumpEventQueue();
      expect(controller.repeatMode, PlayerRepeatMode.off);

      engine.simulateTrackCompleted();
      await pumpEventQueue();

      expect(controller.isPlaying, isFalse);
      expect(controller.currentIndex, songs.length - 1);
    });

    test('all: wraps back to the first track after the last one finishes', () async {
      final songs = (await repo.getDashboard()).quickPicks;
      await controller.playQueue(songs, startIndex: songs.length - 1);
      controller.cycleRepeatMode(); // off -> all
      expect(controller.repeatMode, PlayerRepeatMode.all);

      engine.simulateTrackCompleted();
      await pumpEventQueue();

      expect(controller.currentIndex, 0);
    });

    test('one: replays the same track instead of advancing', () async {
      final songs = (await repo.getDashboard()).quickPicks;
      await controller.playQueue(songs, startIndex: 1);
      controller.cycleRepeatMode(); // off -> all
      controller.cycleRepeatMode(); // all -> one
      expect(controller.repeatMode, PlayerRepeatMode.one);

      engine.simulateTrackCompleted();
      await pumpEventQueue();

      expect(controller.currentIndex, 1);
      expect(controller.isPlaying, isTrue);
    });
  });

  group('playNext', () {
    test('inserts the song right after the current track, not at the end', () async {
      final songs = (await repo.getDashboard()).quickPicks;
      await controller.playQueue(songs, startIndex: 0);

      final extra = (await repo.search('Song 8')).songs.first;
      await controller.playNext(extra);

      expect(controller.queue[1].id, extra.id);
      expect(controller.currentSong?.id, songs[0].id);
    });

    test('starts playing immediately if the queue was empty', () async {
      final song = (await repo.getDashboard()).quickPicks.first;
      await controller.playNext(song);
      expect(controller.currentSong?.id, song.id);
    });

    test(
      'moves (not duplicates) a song already later in the queue '
      '(regression: the queue sheet keys rows by song id, so two entries '
      'sharing one id is a real bug, not just a cosmetic duplicate)',
      () async {
        final songs = (await repo.getDashboard()).quickPicks;
        await controller.playQueue(songs, startIndex: 0);

        await controller.playNext(songs[3]);

        expect(controller.queue.length, songs.length);
        expect(controller.queue.map((s) => s.id).toSet().length, songs.length);
        expect(controller.queue[1].id, songs[3].id);
      },
    );

    test('is a no-op when asked to play the current track next', () async {
      final songs = (await repo.getDashboard()).quickPicks;
      await controller.playQueue(songs, startIndex: 0);

      await controller.playNext(songs[0]);

      expect(controller.queue.map((s) => s.id).toList(), songs.map((s) => s.id).toList());
      expect(controller.currentIndex, 0);
    });
  });
}
