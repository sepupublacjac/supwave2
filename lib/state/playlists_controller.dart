import 'package:flutter/foundation.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../navidrome/navidrome_repository.dart';
import 'app_logger.dart';

/// Mirrors the user's real Navidrome playlists. The list endpoint only
/// returns metadata (name, counts), so each playlist's [Playlist.songs]
/// stays empty until [loadPlaylistSongs] is called for it.
class PlaylistsController extends ChangeNotifier {
  PlaylistsController(this._repo);

  final NavidromeRepository _repo;

  List<Playlist> _playlists = [];
  final Set<String> _loadingSongsFor = {};
  bool _loading = false;
  String? _error;

  List<Playlist> get playlists => List.unmodifiable(_playlists);
  bool get loading => _loading;
  String? get error => _error;

  Playlist? byId(String id) {
    for (final playlist in _playlists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  bool isLoadingSongs(String playlistId) => _loadingSongsFor.contains(playlistId);

  Future<void> loadPlaylists() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _playlists = await _repo.getPlaylists();
    } catch (e) {
      _error = '$e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Creates a new, empty playlist named [name] on the server and adds it
  /// to the local list. Returns the created playlist, or `null` if the
  /// server call failed.
  Future<Playlist?> createPlaylist(String name) async {
    try {
      final playlist = await _repo.createPlaylist(name);
      _playlists = [..._playlists, playlist];
      AppLogger.instance.log('Created playlist "$name"');
      notifyListeners();
      return playlist;
    } catch (e) {
      AppLogger.instance.log('Failed to create playlist "$name": $e', level: LogLevel.error);
      return null;
    }
  }

  /// Deletes the playlist matching [playlistId] on the server and removes
  /// it from the local list. Returns whether the call succeeded.
  Future<bool> deletePlaylist(String playlistId) async {
    final playlist = byId(playlistId);
    if (playlist == null) return false;

    try {
      await _repo.deletePlaylist(playlistId);
      _playlists = _playlists.where((p) => p.id != playlistId).toList();
      AppLogger.instance.log('Deleted playlist "${playlist.name}"');
      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.instance.log('Failed to delete playlist "${playlist.name}": $e', level: LogLevel.error);
      return false;
    }
  }

  Future<List<Song>> loadPlaylistSongs(String playlistId) async {
    final existing = byId(playlistId);
    if (existing != null && existing.songs.isNotEmpty) {
      return existing.songs;
    }

    _loadingSongsFor.add(playlistId);
    notifyListeners();
    try {
      final songs = await _repo.getPlaylistSongs(playlistId);
      final index = _playlists.indexWhere((p) => p.id == playlistId);
      if (index != -1) {
        _playlists[index] = _playlists[index].copyWith(songs: songs);
      }
      return songs;
    } finally {
      _loadingSongsFor.remove(playlistId);
      notifyListeners();
    }
  }

  bool isSongInPlaylist(String playlistId, Song song) {
    return byId(playlistId)?.songs.any((s) => s.id == song.id) ?? false;
  }

  /// Adds [song] to the playlist matching [playlistId]. Returns whether the
  /// call succeeded (no-op-but-true if it was already there, since the
  /// server call still succeeds).
  Future<bool> addSongToPlaylist(String playlistId, Song song) async {
    final playlist = byId(playlistId);
    if (playlist == null) return false;
    if (playlist.songs.any((s) => s.id == song.id)) return false;

    try {
      await _repo.addSongToPlaylist(playlistId, song);
      final index = _playlists.indexWhere((p) => p.id == playlistId);
      if (index != -1) {
        final updatedSongs = [..._playlists[index].songs, song];
        _playlists[index] = _playlists[index].copyWith(
          songs: updatedSongs,
          songCount: _playlists[index].songCount + 1,
        );
      }
      AppLogger.instance.log('Added "${song.title}" to ${playlist.name}');
      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.instance.log('Failed to add "${song.title}" to ${playlist.name}: $e', level: LogLevel.error);
      return false;
    }
  }

  Future<bool> removeSongFromPlaylist(String playlistId, Song song) async {
    final playlist = byId(playlistId);
    if (playlist == null) return false;

    try {
      await _repo.removeSongFromPlaylist(playlistId, song);
      final index = _playlists.indexWhere((p) => p.id == playlistId);
      if (index != -1) {
        final updatedSongs = _playlists[index].songs.where((s) => s.id != song.id).toList();
        _playlists[index] = _playlists[index].copyWith(
          songs: updatedSongs,
          songCount: _playlists[index].songCount - 1,
        );
      }
      AppLogger.instance.log('Removed "${song.title}" from ${playlist.name}');
      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'Failed to remove "${song.title}" from ${playlist.name}: $e',
        level: LogLevel.error,
      );
      return false;
    }
  }
}
