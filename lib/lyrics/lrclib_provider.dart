import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/lyrics.dart';
import '../models/song.dart';
import 'lyrics_provider.dart';

/// Lyrics from lrclib.net, a free, open lyrics database with a documented API
/// (https://lrclib.net/docs). Prefers its time-synced lyrics.
class LrcLibProvider extends LyricsProvider {
  LrcLibProvider({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  static const providerId = 'lrclib';

  final http.Client _http;

  static const _host = 'lrclib.net';
  static const _timeout = Duration(seconds: 15);

  /// lrclib asks clients to identify themselves.
  static const _headers = {
    'User-Agent': 'Supwave2 (https://github.com/sepupublacjac/supwave2)',
    'Lrclib-Client': 'Supwave2 (https://github.com/sepupublacjac/supwave2)',
  };

  /// How far a result's length may differ from the song's and still be taken
  /// for the same recording.
  static const _durationSlack = 3;

  @override
  String get id => providerId;

  @override
  String get displayName => 'lrclib.net';

  @override
  Future<Lyrics?> fetch(Song song, {bool translations = false}) async {
    // Exact lookup first: it's one request and matches the recording.
    final exact = await _getJson('/api/get', {
      if (!isPlaceholderArtist(song.artist)) 'artist_name': song.artist,
      'track_name': song.title,
      if (!isPlaceholderAlbum(song.album)) 'album_name': song.album,
      if (song.duration > Duration.zero) 'duration': '${song.duration.inSeconds}',
    });
    if (exact is Map<String, dynamic>) return _toLyrics(exact);

    // Not found: search, and accept only a result that is clearly this song.
    final results = await _getJson('/api/search', {
      'track_name': song.title,
      if (!isPlaceholderArtist(song.artist)) 'artist_name': song.artist,
    });
    if (results is! List) return null;

    final candidates = results.whereType<Map<String, dynamic>>().where((r) {
      if (!titlesMatch(song.title, (r['trackName'] as String?) ?? '')) return false;
      if (song.duration == Duration.zero) return true;
      final length = (r['duration'] as num?)?.toDouble();
      return length != null && (length - song.duration.inSeconds).abs() <= _durationSlack;
    }).toList();
    if (candidates.isEmpty) return null;

    // Closest in length first, then prefer one with synced lyrics.
    double gap(Map<String, dynamic> r) =>
        (((r['duration'] as num?)?.toDouble() ?? 0) - song.duration.inSeconds).abs();
    bool hasSynced(Map<String, dynamic> r) => ((r['syncedLyrics'] as String?) ?? '').trim().isNotEmpty;
    candidates.sort((a, b) {
      if (hasSynced(a) != hasSynced(b)) return hasSynced(a) ? -1 : 1;
      return gap(a).compareTo(gap(b));
    });
    return _toLyrics(candidates.first);
  }

  Lyrics? _toLyrics(Map<String, dynamic> json) {
    if (json['instrumental'] == true) return null;

    final synced = ((json['syncedLyrics'] as String?) ?? '').trim();
    if (synced.isNotEmpty) {
      final lyrics = Lyrics.fromLrc(synced);
      if (!lyrics.isEmpty) return lyrics;
    }
    final plain = ((json['plainLyrics'] as String?) ?? '').trim();
    if (plain.isEmpty) return null;
    final lyrics = Lyrics.fromPlainText(plain);
    return lyrics.isEmpty ? null : lyrics;
  }

  /// Decoded JSON, or null for a 404 ("no such track" is an answer). Any other
  /// failure throws.
  Future<Object?> _getJson(String path, Map<String, String> query) async {
    final response = await _http.get(Uri.https(_host, path, query), headers: _headers).timeout(_timeout);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('lrclib.net returned HTTP ${response.statusCode}');
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }
}
