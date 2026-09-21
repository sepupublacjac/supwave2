import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supwave_gen2/state/library_controller.dart';
import 'package:supwave_gen2/state/offline_manager.dart';
import 'package:supwave_gen2/state/player_controller.dart';

import 'fakes/fake_audio_engine.dart';
import 'fakes/fake_navidrome_repository.dart';

/// Covers the fix for "the mini player disappears after closing the app":
/// PlayerController persists its queue/track/position (via
/// PlayerSessionStore) and restores it into a *new* controller instance -
/// standing in for the app process being killed and relaunched, since a
/// fresh `PlayerController` here is exactly what `main.dart` constructs on
/// a cold start.
void main() {
  // PlayerController registers a WidgetsBindingObserver and touches
  // shared_preferences, neither of which exists by default under plain
  // `test()`.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  PlayerController buildController(FakeNavidromeRepository repo) {
    return PlayerController(
      repo,
      LibraryController(repo),
      OfflineManager(repo),
      audioEngine: FakeAudioEngine(),
    );
  }

  test('restoreSession is a no-op when nothing was persisted', () async {
    final controller = buildController(FakeNavidromeRepository());
    await controller.restoreSession();
    expect(controller.currentSong, isNull);
    expect(controller.queue, isEmpty);
  });

  test(
    'a queue played by one controller instance is restored by the next, paused, '
    'at the same track and position',
    () async {
      final repo = FakeNavidromeRepository();
      final quickPicks = (await repo.getDashboard()).quickPicks;

      final first = buildController(repo);
      await first.playQueue(quickPicks, startIndex: 1);
      await first.seekTo(0.5);
      await first.pause();
      // Flush the fire-and-forget persistence write triggered by the above.
      await pumpEventQueue();

      final expectedPosition = first.position;
      expect(expectedPosition, greaterThan(Duration.zero));

      final second = buildController(repo);
      expect(second.currentSong, isNull);
      await second.restoreSession();

      expect(second.currentSong?.id, quickPicks[1].id);
      expect(second.queue.map((s) => s.id), quickPicks.map((s) => s.id));
      // Regression: restoring used to always land back at 0:00, since
      // _loadCurrent's own positionStream listener clobbered the restored
      // position with the freshly-loaded source's reset-to-zero event
      // before the seek() to the saved position had a chance to apply.
      expect(second.position, expectedPosition);
      // Restoring never auto-plays, even if it was still playing when saved,
      // since resuming audio without a fresh user gesture would be a
      // surprise.
      expect(second.isPlaying, isFalse);
    },
  );

  test('clearing the queue removes the persisted session too', () async {
    final repo = FakeNavidromeRepository();
    final quickPicks = (await repo.getDashboard()).quickPicks;

    final first = buildController(repo);
    await first.playQueue(quickPicks, startIndex: 0);
    await pumpEventQueue();
    while (first.queue.isNotEmpty) {
      first.removeFromQueue(0);
    }
    await pumpEventQueue();

    final second = buildController(repo);
    await second.restoreSession();
    expect(second.currentSong, isNull);
  });
}
