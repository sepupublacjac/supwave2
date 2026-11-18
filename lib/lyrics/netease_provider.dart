import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/lyrics.dart';
import '../models/song.dart';
import 'lyrics_provider.dart';

/// Lyrics from NetEase Cloud Music, including its translated lyrics.
///
/// Uses NetEase's public web endpoints, which are undocumented and unofficial:
/// they can change or start refusing requests without notice, in which case
/// lookups fail and the app falls through to the next source.
class NeteaseProvider extends LyricsProvider {
  NeteaseProvider({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  static const providerId = 'netease';

  final http.Client _http;

  static const _host = 'music.163.com';
  static const _timeout = Duration(seconds: 15);
  static const _headers = {'User-Agent': 'Supwave2 (https://github.com/sepupublacjac/supwave2)'};

  /// How far a result's length may differ from the song's and still be taken
  /// for the same recording (loosely - it's matched on title and artist too).
  static const _durationSlack = Duration(seconds: 5);

  /// Tighter bound used when the artist can't be matched (e.g. romanised vs
  /// native names): then only an almost identical length is trusted.
  static const _strictDurationSlack = Duration(seconds: 2);

  @override
  String get id => providerId;

  @override
  String get displayName => 'NetEase';

  @override
  Future<Lyrics?> fetch(Song song, {bool translations = false}) async {
    final trackId = await _findTrack(song);
    if (trackId == null) return null;

    final body = await _getJson('/api/song/lyric', {
      'id': '$trackId',
      'lv': '1',
      if (translations) 'tv': '-1',
    });
    if (body['nolyric'] == true || body['uncollected'] == true) return null;

    final lrc = ((body['lrc'] as Map<String, dynamic>?)?['lyric'] as String?) ?? '';
    if (lrc.trim().isEmpty) return null;

    final translation = translations
        ? ((body['tlyric'] as Map<String, dynamic>?)?['lyric'] as String?)
        : null;
    final lyrics = Lyrics.fromLrc(
      lrc,
      translationLrc: (translation ?? '').trim().isEmpty ? null : translation,
    );
    return lyrics.isEmpty ? null : lyrics;
  }

  /// The id of the search result that is this song, or null if none clearly is.
  Future<int?> _findTrack(Song song) async {
    final query = isPlaceholderArtist(song.artist) ? song.title : '${song.artist} ${song.title}';
    final body = await _getJson('/api/search/get', {'s': query, 'type': '1', 'limit': '10'});

    final songs = ((body['result'] as Map<String, dynamic>?)?['songs'] as List?) ?? const [];
    final wantedLength = song.duration;

    Duration? gap(Map<String, dynamic> s) {
      final ms = (s['duration'] as num?)?.toInt();
      if (ms == null || wantedLength == Duration.zero) return null;
      return (Duration(milliseconds: ms) - wantedLength).abs();
    }

    ({int id, Duration gap})? best;
    void consider(Map<String, dynamic> s, Duration slack, {required bool needArtist}) {
      if (!titlesMatch(song.title, (s['name'] as String?) ?? '')) return;
      if (needArtist) {
        final artists = [
          for (final a in (s['artists'] as List?) ?? const [])
            if (a is Map<String, dynamic>) (a['name'] as String?) ?? '',
        ];
        if (!isPlaceholderArtist(song.artist) && !artistsMatch(song.artist, artists)) return;
      }
      final g = gap(s);
      // Unknown lengths can't be compared, so title + artist have to do.
      if (g != null && g > slack) return;
      final id = (s['id'] as num?)?.toInt();
      if (id == null) return;
      final distance = g ?? Duration.zero;
      if (best == null || distance < best!.gap) best = (id: id, gap: distance);
    }

    final candidates = songs.whereType<Map<String, dynamic>>().toList();
    for (final s in candidates) {
      consider(s, _durationSlack, needArtist: true);
    }
    if (best == null) {
      for (final s in candidates) {
        consider(s, _strictDurationSlack, needArtist: false);
      }
    }
    return best?.id;
  }

  Future<Map<String, dynamic>> _getJson(String path, Map<String, String> query) async {
    final response = await _http.get(Uri.https(_host, path, query), headers: _headers).timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('NetEase returned HTTP ${response.statusCode}');
    }
    // Decode as UTF-8 ourselves: the response doesn't always declare a
    // charset, and lyrics are often Chinese.
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map<String, dynamic>) throw Exception('NetEase sent an unexpected response');
    final code = json['code'];
    if (code != null && code != 200) throw Exception('NetEase returned code $code');
    return json;
  }
}
