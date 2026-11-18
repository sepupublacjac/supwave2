import 'dart:collection';

import '../lyrics/lyrics_provider.dart';
import '../models/lyrics.dart';
import '../models/song.dart';
import '../navidrome/navidrome_repository.dart';
import 'app_logger.dart';
import 'lyrics_settings.dart';

/// Finds lyrics for a song - on the user's server and, if they've enabled it,
/// on internet providers - and remembers the answers, so reopening the lyrics
/// view for the same song (or for one just played) doesn't ask again.
///
/// Only successful lookups are kept - including "this song has no lyrics",
/// which is a real answer. A failed lookup is forgotten so the next attempt
/// (e.g. the retry button) asks again. Changing a setting that decides where
/// lyrics come from forgets everything, since the answers may now differ.
class LyricsController {
  LyricsController(
    this._repo, {
    LyricsSettings? settings,
    Iterable<LyricsProvider> providers = const [],
    this.maxCached = 40,
  }) : _settings = settings ?? LyricsSettings(),
       _providers = {for (final p in providers) p.id: p} {
    _signature = _settings.sourceSignature;
    _settings.addListener(_onSettingsChanged);
  }

  final NavidromeRepository _repo;
  final LyricsSettings _settings;
  final Map<String, LyricsProvider> _providers;

  /// Songs whose lyrics are kept in memory; the least recently used go first.
  final int maxCached;

  final LinkedHashMap<String, Future<Lyrics?>> _cache = LinkedHashMap();
  late String _signature;

  void dispose() => _settings.removeListener(_onSettingsChanged);

  void _onSettingsChanged() {
    final signature = _settings.sourceSignature;
    if (signature == _signature) return; // e.g. only the offset changed
    _signature = signature;
    _cache.clear();
  }

  Future<Lyrics?> lyricsFor(Song song) {
    final cached = _cache.remove(song.id);
    if (cached != null) {
      _cache[song.id] = cached; // re-insert: now the most recently used
      return cached;
    }

    final future = _lookup(song);
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

  Future<Lyrics?> _lookup(Song song) {
    Future<Lyrics?> fromServer() async => (await _repo.getLyrics(song))?.withSource('Your server');
    Future<Lyrics?> fromInternet() => _firstAnswer([
      for (final id in _settings.providerIds)
        if (_providers[id] case final provider?)
          () async => (await provider.fetch(song, translations: _settings.neteaseTranslations))?.withSource(
            provider.displayName,
          ),
    ]);

    if (!_settings.fetchFromInternet) return fromServer();
    return _firstAnswer(_settings.preferLocal ? [fromServer, fromInternet] : [fromInternet, fromServer]);
  }

  /// Tries each source in order and returns the first lyrics found.
  ///
  /// Null only if *every* source answered "none". If some failed and nothing
  /// was found, the failure is rethrown, so the UI offers a retry instead of
  /// claiming the song has no lyrics when a source simply couldn't be asked.
  Future<Lyrics?> _firstAnswer(List<Future<Lyrics?> Function()> sources) async {
    Object? failure;
    StackTrace? failureTrace;
    for (final source in sources) {
      try {
        final lyrics = await source();
        if (lyrics != null) return lyrics;
      } catch (e, trace) {
        failure ??= e;
        failureTrace ??= trace;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureTrace!);
    return null;
  }
}
