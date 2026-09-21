import 'dart:async';

import 'package:supwave_gen2/navidrome/audio_engine.dart';

/// Instant, in-memory [AudioEngine] for widget tests - no platform channel,
/// no real network, no delay.
class FakeAudioEngine implements AudioEngine {
  final _positionController = StreamController<Duration>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _completedController = StreamController<void>.broadcast();

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<void> get completedStream => _completedController.stream;

  @override
  Future<void> setUrl(String url) async {
    // Matches just_audio: loading a new source resets playback position to
    // zero and reports that back on positionStream - a real bug (restoring
    // a saved position raced against this and lost) went uncaught while
    // this fake stayed silent here instead of mirroring that.
    _positionController.add(Duration.zero);
  }

  @override
  Future<void> setFilePath(String path) async {
    _positionController.add(Duration.zero);
  }

  @override
  Future<void> play() async {
    _playingController.add(true);
  }

  @override
  Future<void> pause() async {
    _playingController.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    _positionController.add(position);
  }

  @override
  Future<void> stop() async {
    _playingController.add(false);
  }

  @override
  Future<void> dispose() async {
    await _positionController.close();
    await _playingController.close();
    await _completedController.close();
  }
}
