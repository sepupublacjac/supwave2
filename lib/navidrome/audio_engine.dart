import 'package:just_audio/just_audio.dart';

/// Thin seam between [PlayerController] and the real audio engine, so tests
/// can swap in an instant fake instead of touching just_audio's platform
/// channel (which hangs, rather than failing fast, when there's no native
/// implementation registered - as is the case under `flutter test`).
abstract class AudioEngine {
  Stream<Duration> get positionStream;
  Stream<bool> get playingStream;

  /// Fires once whenever the current track finishes playing.
  Stream<void> get completedStream;

  Future<void> setUrl(String url);
  Future<void> setFilePath(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> dispose();
}

class JustAudioEngine implements AudioEngine {
  final AudioPlayer _player = AudioPlayer();

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<bool> get playingStream => _player.playerStateStream.map((s) => s.playing);

  @override
  Stream<void> get completedStream => _player.playerStateStream
      .where((s) => s.processingState == ProcessingState.completed)
      .map((_) {});

  @override
  Future<void> setUrl(String url) => _player.setUrl(url);

  @override
  Future<void> setFilePath(String path) => _player.setFilePath(path);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
