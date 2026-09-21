import 'package:flutter/foundation.dart';

import '../models/album.dart';
import '../models/song.dart';
import '../navidrome/navidrome_repository.dart';
import 'app_logger.dart';

/// Holds the dashboard's curated lists and the user's liked (starred) songs.
class LibraryController extends ChangeNotifier {
  LibraryController(this._repo);

  final NavidromeRepository _repo;

  List<Song> _quickPicks = [];
  List<Album> _recentAlbums = [];
  List<Album> _frequentAlbums = [];
  List<Album> _newestAlbums = [];
  List<Song> _likedSongs = [];
  int _totalSongCount = 0;
  bool _loading = true;
  String? _error;

  List<Song> get quickPicks => List.unmodifiable(_quickPicks);
  List<Album> get recentAlbums => List.unmodifiable(_recentAlbums);
  List<Album> get frequentAlbums => List.unmodifiable(_frequentAlbums);
  List<Album> get newestAlbums => List.unmodifiable(_newestAlbums);
  List<Song> get likedSongs => List.unmodifiable(_likedSongs);
  int get totalSongCount => _totalSongCount;
  bool get loading => _loading;
  String? get error => _error;

  bool isLiked(Song song) => _likedSongs.any((s) => s.id == song.id);

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      // Kicked off together (each call starts immediately); awaited in
      // sequence just to read the results back without a dynamic cast.
      final dashboardFuture = _repo.getDashboard();
      final likedFuture = _repo.getLikedSongs();
      final countFuture = _repo.getTotalSongCount();

      final dashboard = await dashboardFuture;
      _quickPicks = dashboard.quickPicks;
      _recentAlbums = dashboard.recentAlbums;
      _frequentAlbums = dashboard.frequentAlbums;
      _newestAlbums = dashboard.newestAlbums;
      _likedSongs = await likedFuture;
      _totalSongCount = await countFuture;
    } catch (e) {
      _error = '$e';
      AppLogger.instance.log('Failed to load library: $e', level: LogLevel.error);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Optimistically updates the local "liked songs" list so the UI reacts
  /// instantly; [PlayerController.toggleLike] is what actually calls the
  /// server.
  void applyStarred(Song song, bool starred) {
    if (starred) {
      if (!isLiked(song)) _likedSongs = [..._likedSongs, song];
    } else {
      _likedSongs = _likedSongs.where((s) => s.id != song.id).toList();
    }
    notifyListeners();
  }
}
