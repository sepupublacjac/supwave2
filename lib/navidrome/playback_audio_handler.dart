import 'package:audio_service/audio_service.dart';

import '../models/song.dart';
import '../state/player_controller.dart';
import 'navidrome_repository.dart';

/// Bridges [PlayerController] - the app's single source of playback truth -
/// to Android's system media notification via `audio_service`. Notification
/// taps are forwarded into the controller; the controller's own state is
/// mirrored back out as [PlaybackState]/[MediaItem] updates.
///
/// Created once at app startup (before login), since `AudioService.init`
/// must run exactly once for the app's lifetime. [attach]/[detach] connect
/// and disconnect it from the actual [PlayerController], which only exists
/// once a session is logged in and is recreated on every login/logout.
class PlaybackAudioHandler extends BaseAudioHandler {
  PlayerController? _controller;
  NavidromeRepository? _repo;
  String? _lastSongId;

  void attach(PlayerController controller, NavidromeRepository repo) {
    if (identical(_controller, controller)) return;
    _controller?.removeListener(_syncFromController);
    _controller = controller;
    _repo = repo;
    controller.addListener(_syncFromController);
    _syncFromController();
  }

  void detach() {
    _controller?.removeListener(_syncFromController);
    _controller = null;
    _repo = null;
    _lastSongId = null;
    mediaItem.add(null);
    playbackState.add(
      playbackState.value.copyWith(processingState: AudioProcessingState.idle, playing: false),
    );
  }

  void _syncFromController() {
    final controller = _controller;
    if (controller == null) return;

    final song = controller.currentSong;
    if (song?.id != _lastSongId) {
      _lastSongId = song?.id;
      mediaItem.add(song == null ? null : _toMediaItem(song));
    }

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          controller.isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: song == null ? AudioProcessingState.idle : AudioProcessingState.ready,
        playing: controller.isPlaying,
        updatePosition: controller.position,
      ),
    );
  }

  MediaItem _toMediaItem(Song song) {
    final repo = _repo;
    return MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.duration,
      artUri: repo != null && song.coverArtId != null
          ? Uri.tryParse(repo.coverArtUrl(song.coverArtId!, size: 500))
          : null,
    );
  }

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> stop() async {
    await _controller?.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async => _controller?.next();

  @override
  Future<void> skipToPrevious() async => _controller?.previous();

  @override
  Future<void> seek(Duration position) async {
    final controller = _controller;
    final total = controller?.currentSong?.duration;
    if (controller == null || total == null || total.inMilliseconds == 0) return;
    await controller.seekTo(position.inMilliseconds / total.inMilliseconds);
  }
}
