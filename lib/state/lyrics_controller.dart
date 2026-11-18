import 'dart:collection';

import '../models/lyrics.dart';
import '../models/song.dart';
import '../navidrome/navidrome_repository.dart';
import 'app_logger.dart';

/// Loads lyrics from the server and remembers them, so reopening the lyrics
/// view for the same song (or for one just played) doesn't hit the network
/// again.
///
/// Only successful lookups are kept - including "this song has no lyrics",
/// which is a real answer. A failed lookup is forgotten so the next attempt
/// (e.g. the retry button) asks the server again.
class LyricsController {
  LyricsController(this._repo, {this.maxCached = 40});

  final NavidromeRepository _repo;

  /// Songs whose lyrics are kept in memory; the least recently used go first.
  final int maxCached;

  final LinkedHashMap<String, Future<Lyrics?>> _cache = LinkedHashMap();

  Future<Lyrics?> lyricsFor(Song song) {
    final cached = _cache.remove(song.id);
    if (cached != null) {
      _cache[song.id] = cached; // re-insert: now the most recently used
      return cached;
    }

    final future = _repo.getLyrics(song);
    _cache[song.id] = future;
    while (_cache.length > maxCached) {
      _cache.remove(_cache.keys.first);
    }

    // Swallowing here only prevents an unhandled-error report for the cache's
    // copy; callers awaiting [future] still see the failure.
    future.catchError((Object e) {
      AppLogger.instance.log('Failed to load lyrics for "${song.title}": $e', level: LogLevel.error);
      if (identical(_cache[song.id], future)) _cache.remove(song.id);
      return null;
    });
    return future;
  }
}
