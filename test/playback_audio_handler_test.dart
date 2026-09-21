import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supwave_gen2/navidrome/playback_audio_handler.dart';
import 'package:supwave_gen2/state/library_controller.dart';
import 'package:supwave_gen2/state/offline_manager.dart';
import 'package:supwave_gen2/state/player_controller.dart';

import 'fakes/fake_audio_engine.dart';
import 'fakes/fake_navidrome_repository.dart';

/// Covers [PlaybackAudioHandler] in isolation - pure Dart, no platform
/// channel involved, since only `AudioService.init` (never called here)
/// touches one, not merely constructing/using this class.
void main() {
  // PlayerController registers a WidgetsBindingObserver (for session
  // persistence) and reads/writes shared_preferences, both of which need a
  // binding/mocked platform channel - neither exists by default under plain
  // `test()` (only `testWidgets()` sets one up automatically).
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNavidromeRepository repo;
  late PlayerController controller;
  late PlaybackAudioHandler handler;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = FakeNavidromeRepository();
    controller = PlayerController(
      repo,
      LibraryController(repo),
      OfflineManager(repo),
      audioEngine: FakeAudioEngine(),
    );
    handler = PlaybackAudioHandler();
  });

  test('attach mirrors the current song and play state into mediaItem/playbackState', () async {
    handler.attach(controller, repo);
    expect(handler.mediaItem.value, isNull);
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);

    await controller.playQueue((await repo.getDashboard()).quickPicks, startIndex: 0);
    final song = controller.currentSong!;

    expect(handler.mediaItem.value?.id, song.id);
    expect(handler.mediaItem.value?.title, song.title);
    expect(handler.playbackState.value.playing, isTrue);
    expect(handler.playbackState.value.processingState, AudioProcessingState.ready);
    expect(handler.playbackState.value.controls.map((c) => c.action), [
      MediaAction.pause,
      MediaAction.skipToNext,
      MediaAction.stop,
    ]);
  });

  test('notification actions are forwarded to the controller', () async {
    handler.attach(controller, repo);
    final quickPicks = (await repo.getDashboard()).quickPicks;
    await controller.playQueue(quickPicks, startIndex: 0);
    final first = controller.currentSong;

    await handler.pause();
    expect(controller.isPlaying, isFalse);
    expect(handler.playbackState.value.playing, isFalse);
    expect(handler.playbackState.value.controls.map((c) => c.action), contains(MediaAction.play));

    await handler.play();
    expect(controller.isPlaying, isTrue);

    await handler.skipToNext();
    expect(controller.currentSong, isNot(equals(first)));

    await handler.stop();
    expect(controller.isPlaying, isFalse);
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
  });

  test('detach clears the notification state and stops mirroring the old controller', () async {
    handler.attach(controller, repo);
    await controller.playQueue((await repo.getDashboard()).quickPicks, startIndex: 0);

    handler.detach();
    expect(handler.mediaItem.value, isNull);
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle);

    // The old controller changing after detach must not resurrect state.
    await controller.togglePlayPause();
    expect(handler.mediaItem.value, isNull);
  });

  test('attaching a second controller stops mirroring the first', () async {
    final repo2 = FakeNavidromeRepository();
    final controller2 = PlayerController(
      repo2,
      LibraryController(repo2),
      OfflineManager(repo2),
      audioEngine: FakeAudioEngine(),
    );

    handler.attach(controller, repo);
    handler.attach(controller2, repo2);

    await controller.playQueue((await repo.getDashboard()).quickPicks, startIndex: 0);
    expect(handler.mediaItem.value, isNull);

    await controller2.playQueue((await repo2.getDashboard()).quickPicks, startIndex: 0);
    expect(handler.mediaItem.value?.id, controller2.currentSong?.id);
  });
}
