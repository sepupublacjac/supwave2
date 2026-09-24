import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/song.dart';
import '../navidrome/audio_engine.dart';
import '../navidrome/navidrome_repository.dart';
import 'app_logger.dart';
import 'library_controller.dart';
import 'offline_manager.dart';
import 'player_session_store.dart';

enum PlayerRepeatMode { off, all, one }

/// Drives the mini + main player UI, backed by an [AudioEngine] streaming
/// from Navidrome's `/rest/stream.view` (the real implementation wraps
/// just_audio; tests inject a fake so they don't touch its platform channel).
/// Prefers a downloaded local file over the network stream when [_offline]
/// has one for the current song.
///
/// Persists the queue/current track/position via [PlayerSessionStore] so a
/// killed-and-relaunched app (not just backgrounded) still shows the mini
/// player where the user left off - see [restoreSession].
class PlayerController extends ChangeNotifier with WidgetsBindingObserver {
  PlayerController(
    this._repo,
    this._library,
    this._offline, {
    AudioEngine? audioEngine,
    PlayerSessionStore? sessionStore,
  }) : _engine = audioEngine ?? JustAudioEngine(),
       _sessionStore = sessionStore ?? PlayerSessionStore() {
    _engine.playingStream.listen((playing) {
      _isPlaying = playing;
      notifyListeners();
      _persistSession();
    });
    _engine.positionStream.listen((position) {
      _position = position;
      notifyListeners();
    });
    _engine.completedStream.listen((_) => _onTrackFinished());
    WidgetsBinding.instance.addObserver(this);
  }

  final NavidromeRepository _repo;
  final LibraryController _library;
  final OfflineManager _offline;
  final AudioEngine _engine;
  final PlayerSessionStore _sessionStore;

  List<Song> _queue = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  bool _shuffle = false;
  PlayerRepeatMode _repeatMode = PlayerRepeatMode.off;
  Duration _position = Duration.zero;
  final Set<String> _likedOverrides = {};

  /// A permutation of `_queue`'s indices, only meaningful while [_shuffle]
  /// is true: [next]/[previous] walk this order instead of `_queue`'s own,
  /// so shuffling doesn't touch the queue's actual (displayed, reorderable)
  /// order. Regenerated - keeping the current track first, so turning
  /// shuffle on mid-playback doesn't jump away from what's already playing
  /// - whenever it's turned on or the queue's contents change while it's on.
  List<int> _shuffleOrder = [];

  void _regenerateShuffleOrder() {
    final indices = List.generate(_queue.length, (i) => i)..shuffle();
    if (_currentIndex >= 0) {
      indices.remove(_currentIndex);
      indices.insert(0, _currentIndex);
    }
    _shuffleOrder = indices;
  }

  Song? get currentSong => _currentIndex >= 0 && _currentIndex < _queue.length
      ? _queue[_currentIndex]
      : null;

  List<Song> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  bool get shuffle => _shuffle;
  PlayerRepeatMode get repeatMode => _repeatMode;
  Duration get position => _position;

  bool isLiked(Song song) {
    final baseline = _library.isLiked(song);
    return _likedOverrides.contains(song.id) ? !baseline : baseline;
  }

  double get progress {
    final total = currentSong?.duration.inMilliseconds ?? 0;
    if (total == 0) return 0;
    return (_position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  /// Fire-and-forget: called after every queue/track change and every
  /// play/pause transition, so the persisted session stays current without
  /// needing to await it inline everywhere.
  void _persistSession() {
    unawaited(
      _sessionStore.save(
        queue: _queue,
        currentIndex: _currentIndex,
        position: _position,
        shuffle: _shuffle,
        repeatModeName: _repeatMode.name,
      ),
    );
  }

  /// Restores whatever was playing/queued the last time this app process
  /// ran, if anything - loading the track (so the mini player shows real
  /// art/metadata) and seeking to the saved position, but always paused:
  /// resuming audio without a fresh user gesture would be a surprise (and
  /// can run into platform audio-focus restrictions on some Android
  /// versions), so the user has to tap play themselves.
  Future<void> restoreSession() async {
    final session = await _sessionStore.load();
    if (session == null) return;

    _queue = session.queue;
    _currentIndex = session.currentIndex;
    _position = session.position;
    _shuffle = session.shuffle;
    _repeatMode = PlayerRepeatMode.values.firstWhere(
      (mode) => mode.name == session.repeatModeName,
      orElse: () => PlayerRepeatMode.off,
    );
    notifyListeners();

    // Captured before _loadCurrent, not read back off `_position`: loading
    // a fresh source resets the engine's own position to zero, and the
    // positionStream listener below updates `_position` to match as soon as
    // it reports in - which can happen before the seek() call below runs,
    // clobbering the restored value right back to zero.
    final savedPosition = session.position;
    await _loadCurrent(autoplay: false);
    if (savedPosition > Duration.zero) {
      await _engine.seek(savedPosition);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Best-effort capture of the latest position right as the app leaves
    // the foreground - covers being swiped away/reclaimed shortly after,
    // which doesn't otherwise give the queue-mutation-triggered saves above
    // a chance to run.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _persistSession();
    }
  }

  void _onTrackFinished() {
    if (_repeatMode == PlayerRepeatMode.one) {
      _engine.seek(Duration.zero);
      _engine.play();
    } else {
      next();
    }
  }

  Future<void> _loadCurrent({bool autoplay = true}) async {
    final song = currentSong;
    if (song == null) return;
    try {
      final localPath = _offline.localPathFor(song.id);
      if (localPath != null) {
        await _engine.setFilePath(localPath);
      } else {
        await _engine.setUrl(_repo.streamUrl(song.id)).timeout(const Duration(seconds: 20));
      }
      if (autoplay) {
        await _engine.play();
      }
      final action = autoplay ? 'Playing' : 'Loaded';
      AppLogger.instance.log('$action "${song.title}"${localPath != null ? ' (offline)' : ''}');
    } catch (e) {
      AppLogger.instance.log('Failed to play "${song.title}": $e', level: LogLevel.error);
    }
  }

  Future<void> playQueue(List<Song> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) return;
    _queue = List.of(songs);
    _currentIndex = startIndex;
    _position = Duration.zero;
    if (_shuffle) _regenerateShuffleOrder();
    notifyListeners();
    await _loadCurrent();
    _persistSession();
  }

  void playSingle(Song song) => playQueue([song]);

  /// Appends [song] to the end of the queue without disrupting playback.
  /// Starts playing it if nothing is queued yet.
  Future<void> addToQueue(Song song) async {
    if (_queue.isEmpty) {
      await playQueue([song]);
      return;
    }
    _queue.add(song);
    if (_shuffle) _regenerateShuffleOrder();
    AppLogger.instance.log('Added "${song.title}" to queue');
    notifyListeners();
    _persistSession();
  }

  /// Inserts [song] right after the currently playing track, so it plays
  /// next without disturbing anything already later in the queue - unlike
  /// [addToQueue], which appends to the end. Starts playing it immediately
  /// if nothing is queued yet.
  ///
  /// If [song] is already somewhere else in the queue, it's *moved* to play
  /// next rather than duplicated - both because the queue sheet keys each
  /// row by song id (so two rows sharing one id is a real bug, not just
  /// visual noise), and because moving it is exactly the manual
  /// re-arranging this exists to avoid.
  Future<void> playNext(Song song) async {
    if (_queue.isEmpty) {
      await playQueue([song]);
      return;
    }
    final existingIndex = _queue.indexWhere((s) => s.id == song.id);
    if (existingIndex == _currentIndex) {
      // Already the current track - there's nothing to move.
      return;
    }
    if (existingIndex != -1) {
      _queue.removeAt(existingIndex);
      if (existingIndex < _currentIndex) _currentIndex -= 1;
    }
    _queue.insert(_currentIndex + 1, song);
    if (_shuffle) _regenerateShuffleOrder();
    AppLogger.instance.log('"${song.title}" will play next');
    notifyListeners();
    _persistSession();
  }

  Future<void> togglePlayPause() async {
    if (currentSong == null) return;
    if (_isPlaying) {
      await _engine.pause();
    } else {
      await _engine.play();
    }
  }

  /// Explicit play/pause/stop, as opposed to [togglePlayPause] - used by the
  /// Android media notification, whose transport buttons each map to one
  /// fixed action rather than a toggle.
  Future<void> play() async {
    if (currentSong == null) return;
    await _engine.play();
  }

  Future<void> pause() async {
    await _engine.pause();
  }

  Future<void> stop() async {
    await _engine.stop();
    _position = Duration.zero;
    notifyListeners();
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_shuffle) {
      final pos = _shuffleOrder.indexOf(_currentIndex);
      if (pos != -1 && pos < _shuffleOrder.length - 1) {
        _currentIndex = _shuffleOrder[pos + 1];
      } else if (_repeatMode == PlayerRepeatMode.all) {
        _regenerateShuffleOrder();
        _currentIndex = _shuffleOrder.first;
      } else {
        await _engine.stop();
        return;
      }
    } else if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
    } else if (_repeatMode == PlayerRepeatMode.all) {
      _currentIndex = 0;
    } else {
      await _engine.stop();
      return;
    }
    _position = Duration.zero;
    notifyListeners();
    await _loadCurrent();
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (_position.inSeconds > 3) {
      await _engine.seek(Duration.zero);
      return;
    }
    if (_shuffle) {
      final pos = _shuffleOrder.indexOf(_currentIndex);
      if (pos > 0) {
        _currentIndex = _shuffleOrder[pos - 1];
        _position = Duration.zero;
        notifyListeners();
        await _loadCurrent();
        return;
      }
      await _engine.seek(Duration.zero);
      return;
    }
    if (_currentIndex > 0) {
      _currentIndex--;
      _position = Duration.zero;
      notifyListeners();
      await _loadCurrent();
    } else {
      await _engine.seek(Duration.zero);
    }
  }

  Future<void> seekTo(double fraction) async {
    final total = currentSong?.duration ?? Duration.zero;
    final target = Duration(
      milliseconds: (total.inMilliseconds * fraction.clamp(0.0, 1.0)).round(),
    );
    await _engine.seek(target);
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    if (_shuffle) _regenerateShuffleOrder();
    notifyListeners();
  }

  void cycleRepeatMode() {
    _repeatMode = PlayerRepeatMode.values[(_repeatMode.index + 1) % PlayerRepeatMode.values.length];
    notifyListeners();
  }

  Future<void> toggleLike(Song song) async {
    if (_likedOverrides.contains(song.id)) {
      _likedOverrides.remove(song.id);
    } else {
      _likedOverrides.add(song.id);
    }
    final newState = isLiked(song);
    _library.applyStarred(song, newState);
    notifyListeners();
    try {
      await _repo.setStarred(song.id, newState);
      AppLogger.instance.log('${newState ? 'Liked' : 'Unliked'} "${song.title}"');
    } catch (e) {
      AppLogger.instance.log('Failed to update like for "${song.title}": $e', level: LogLevel.error);
    }
  }

  /// [oldIndex]/[newIndex] as reported by `ReorderableListView.onReorderItem`
  /// - i.e. [newIndex] is already adjusted for the list shrinking by one
  /// when the dragged item is removed from [oldIndex] (unlike the
  /// deprecated `onReorder`, which passes the raw pre-removal index).
  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    final song = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, song);

    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex -= 1;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex += 1;
    }
    if (_shuffle) _regenerateShuffleOrder();
    notifyListeners();
    _persistSession();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);

    if (_queue.isEmpty) {
      _currentIndex = -1;
      _position = Duration.zero;
      _engine.stop();
    } else if (index == _currentIndex) {
      _currentIndex = _currentIndex.clamp(0, _queue.length - 1);
      _position = Duration.zero;
      _loadCurrent();
    } else if (index < _currentIndex) {
      _currentIndex -= 1;
    }
    if (_shuffle) _regenerateShuffleOrder();
    notifyListeners();
    _persistSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine.dispose();
    super.dispose();
  }
}
