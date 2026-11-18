import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supwave_gen2/lyrics/lrclib_provider.dart';
import 'package:supwave_gen2/lyrics/lyrics_provider.dart';
import 'package:supwave_gen2/lyrics/netease_provider.dart';
import 'package:supwave_gen2/models/song.dart';

Song song({
  String title = 'Can\'t Hold Us',
  String artist = 'Macklemore & Ryan Lewis',
  String album = 'The Heist',
  int seconds = 258,
}) => Song(
  id: 's1',
  title: title,
  artist: artist,
  artistId: 'ar1',
  album: album,
  albumId: 'al1',
  duration: Duration(seconds: seconds),
);

http.Response jsonResponse(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  // Deliberately no charset, like the real services sometimes.
  headers: {'content-type': 'application/json'},
);

void main() {
  group('title and artist matching', () {
    test('normalizeForMatch keeps letters and digits of any script, drops the rest', () {
      expect(normalizeForMatch("Can't Hold Us!"), 'canthold' 'us');
      expect(normalizeForMatch('Song (Remastered 2011) [Live]'), 'song');
      expect(normalizeForMatch('我很受伤，宝贝'), '我很受伤宝贝');
      expect(normalizeForMatch('  --  '), '');
    });

    test('titlesMatch ignores case, punctuation and bracketed extras', () {
      expect(titlesMatch("Can't Hold Us", "CAN'T HOLD US (feat. Ray Dalton)"), isTrue);
      expect(titlesMatch('Diamond Heart', 'Diamond Heart - Remix'), isTrue);
    });

    test('titlesMatch does not mistake short or different titles', () {
      expect(titlesMatch('Go', 'Gone'), isFalse);
      expect(titlesMatch('Stay', 'Stay Away'), isFalse);
      expect(titlesMatch('Yellow', 'Red'), isFalse);
      expect(titlesMatch('', 'Anything'), isFalse);
    });

    test('artistsMatch finds a shared artist in lists and credits', () {
      expect(artistsMatch('Macklemore & Ryan Lewis', ['Macklemore']), isTrue);
      expect(artistsMatch('Bruno Mars, Lady Gaga', ['Lady Gaga']), isTrue);
      expect(artistsMatch('Alan Walker feat. Sophia Somajo', ['Alan Walker']), isTrue);
      expect(artistsMatch('Macklemore', ['Macklemore & Ryan Lewis']), isTrue);
    });

    test('artistsMatch rejects unrelated artists', () {
      expect(artistsMatch('Macklemore', ['Taylor Swift', 'Drake']), isFalse);
      expect(artistsMatch('Macklemore', const []), isFalse);
    });

    test('placeholders from missing tags are recognised', () {
      expect(isPlaceholderArtist('Unknown artist'), isTrue);
      expect(isPlaceholderArtist(''), isTrue);
      expect(isPlaceholderArtist('Real Band'), isFalse);
      expect(isPlaceholderAlbum('Unknown album'), isTrue);
      expect(isPlaceholderAlbum('Real Album'), isFalse);
    });
  });

  group('LrcLibProvider', () {
    const synced = '[00:02.25] Ay, ay, ay\n[00:04.69] Good to see you';

    /// A provider over a fake server; every request is recorded in [requests].
    LrcLibProvider providerFor(List<http.Request> requests, http.Response Function(http.Request request) respond) {
      return LrcLibProvider(
        httpClient: MockClient((request) async {
          requests.add(request);
          return respond(request);
        }),
      );
    }

    test('asks /api/get with the song, identifies itself, and parses synced lyrics', () async {
      final requests = <http.Request>[];
      final provider = providerFor(
        requests,
        (_) => jsonResponse({'instrumental': false, 'syncedLyrics': synced, 'plainLyrics': 'Ay, ay, ay'}),
      );

      final lyrics = await provider.fetch(song());

      final request = requests.single;
      expect(request.url.host, 'lrclib.net');
      expect(request.url.path, '/api/get');
      expect(request.url.queryParameters, {
        'artist_name': 'Macklemore & Ryan Lewis',
        'track_name': "Can't Hold Us",
        'album_name': 'The Heist',
        'duration': '258',
      });
      expect(request.headers['User-Agent'], contains('Supwave2'));
      expect(request.headers['Lrclib-Client'], contains('Supwave2'));

      expect(lyrics!.synced, isTrue);
      expect(lyrics.lines.map((l) => l.text), ['Ay, ay, ay', 'Good to see you']);
      expect(lyrics.lines.first.start, const Duration(milliseconds: 2250));
    });

    test('does not send placeholder artist/album names or a zero duration', () async {
      final requests = <http.Request>[];
      final provider = providerFor(requests, (_) => jsonResponse({'plainLyrics': 'words'}));

      await provider.fetch(song(artist: 'Unknown artist', album: 'Unknown album', seconds: 0));

      expect(requests.single.url.queryParameters, {'track_name': "Can't Hold Us"});
    });

    test('uses plain lyrics when there are no synced ones', () async {
      final provider = providerFor([], (_) => jsonResponse({'syncedLyrics': null, 'plainLyrics': 'one\ntwo'}));

      final lyrics = await provider.fetch(song());

      expect(lyrics!.synced, isFalse);
      expect(lyrics.lines.map((l) => l.text), ['one', 'two']);
    });

    test('an instrumental track has no lyrics', () async {
      final provider = providerFor([], (_) => jsonResponse({'instrumental': true, 'plainLyrics': null}));

      expect(await provider.fetch(song()), isNull);
    });

    test('a hit with empty lyrics has no lyrics', () async {
      final provider = providerFor([], (_) => jsonResponse({'syncedLyrics': '  ', 'plainLyrics': ''}));

      expect(await provider.fetch(song()), isNull);
    });

    group('when /api/get does not know the track', () {
      Map<String, dynamic> hit(String name, num duration, {String? synced, String? plain}) => {
        'trackName': name,
        'duration': duration,
        'instrumental': false,
        'syncedLyrics': synced,
        'plainLyrics': plain,
      };

      http.Response notFoundThen(List<Object> searchResults, http.Request request) => request.url.path == '/api/get'
          ? jsonResponse({'name': 'TrackNotFound', 'statusCode': 404}, 404)
          : jsonResponse(searchResults);

      test('searches and takes the result with the right title and length', () async {
        final requests = <http.Request>[];
        final provider = providerFor(
          requests,
          (r) => notFoundThen([
            hit("Can't Hold Us", 300, plain: 'wrong length'),
            hit('Something Else', 258, plain: 'wrong title'),
            hit("Can't Hold Us", 259, plain: 'the one'),
          ], r),
        );

        final lyrics = await provider.fetch(song());

        expect(requests.map((r) => r.url.path), ['/api/get', '/api/search']);
        expect(requests.last.url.queryParameters['track_name'], "Can't Hold Us");
        expect(lyrics!.lines.single.text, 'the one');
      });

      test('prefers a synced result over a closer plain one', () async {
        final provider = providerFor(
          [],
          (r) => notFoundThen([
            hit("Can't Hold Us", 258, plain: 'plain, exact length'),
            hit("Can't Hold Us", 260, synced: '[00:01.00]synced, 2s off'),
          ], r),
        );

        final lyrics = await provider.fetch(song());

        expect(lyrics!.synced, isTrue);
        expect(lyrics.lines.single.text, 'synced, 2s off');
      });

      test('among equally good results takes the one closest in length', () async {
        final provider = providerFor(
          [],
          (r) => notFoundThen([
            hit("Can't Hold Us", 256, synced: '[00:01.00]two seconds off'),
            hit("Can't Hold Us", 259, synced: '[00:01.00]one second off'),
            hit("Can't Hold Us", 255.5, synced: '[00:01.00]two and a half off'),
          ], r),
        );

        final lyrics = await provider.fetch(song());

        expect(lyrics!.lines.single.text, 'one second off');
      });

      test('gives up when nothing in the search is clearly the same song', () async {
        final provider = providerFor(
          [],
          (r) => notFoundThen([hit('Other Song', 258, plain: 'x'), hit("Can't Hold Us", 400, plain: 'y')], r),
        );

        expect(await provider.fetch(song()), isNull);
      });

      test('accepts any length when the song has none', () async {
        final provider = providerFor([], (r) => notFoundThen([hit("Can't Hold Us", 123, plain: 'ok')], r));

        final lyrics = await provider.fetch(song(seconds: 0));

        expect(lyrics!.lines.single.text, 'ok');
      });

      test('a 404 on the search too means no lyrics', () async {
        final provider = providerFor([], (_) => jsonResponse({'statusCode': 404}, 404));

        expect(await provider.fetch(song()), isNull);
      });
    });

    test('a server error is a failure, not "no lyrics"', () async {
      final provider = providerFor([], (_) => http.Response('oops', 500));

      await expectLater(provider.fetch(song()), throwsException);
    });

    test('a network failure is a failure', () async {
      final provider = LrcLibProvider(httpClient: MockClient((_) async => throw http.ClientException('offline')));

      await expectLater(provider.fetch(song()), throwsA(isA<http.ClientException>()));
    });
  });

  group('NeteaseProvider', () {
    const lrc = '[00:01.000]Hey, hey, hey\n[00:04.150]Good to see you';
    const tlyric = '[by:someone]\n[00:01.000]嘿，嘿，嘿\n[00:04.150]很高兴见到你';

    Map<String, dynamic> searchHit(int id, String name, List<String> artists, int ms) => {
      'id': id,
      'name': name,
      'duration': ms,
      'artists': [
        for (final a in artists) {'name': a},
      ],
    };

    Map<String, dynamic> searchResponse(List<Map<String, dynamic>> songs) => {
      'code': 200,
      'result': {'songs': songs},
    };

    NeteaseProvider providerFor(
      List<http.Request> requests, {
      List<Map<String, dynamic>>? songs,
      Map<String, dynamic>? lyric,
      http.Response Function(http.Request request)? override,
    }) {
      return NeteaseProvider(
        httpClient: MockClient((request) async {
          requests.add(request);
          if (override != null) return override(request);
          if (request.url.path == '/api/search/get') {
            return jsonResponse(
              searchResponse(
                songs ??
                    [
                      searchHit(26244634, "Can't Hold Us", ['Macklemore', 'Macklemore & Ryan Lewis'], 258342),
                    ],
              ),
            );
          }
          return jsonResponse(
            lyric ??
                {
                  'code': 200,
                  'lrc': {'lyric': lrc},
                  'tlyric': {'lyric': tlyric},
                },
          );
        }),
      );
    }

    test('searches for artist and title, then fetches the lyric of the matching track', () async {
      final requests = <http.Request>[];
      final provider = providerFor(requests);

      final lyrics = await provider.fetch(song());

      expect(requests.map((r) => r.url.path), ['/api/search/get', '/api/song/lyric']);
      expect(requests.first.url.host, 'music.163.com');
      expect(requests.first.url.queryParameters['s'], "Macklemore & Ryan Lewis Can't Hold Us");
      expect(requests.first.url.queryParameters['type'], '1');
      expect(requests.last.url.queryParameters['id'], '26244634');
      expect(requests.first.headers['User-Agent'], contains('Supwave2'));

      expect(lyrics!.synced, isTrue);
      expect(lyrics.lines.map((l) => l.text), ['Hey, hey, hey', 'Good to see you']);
      expect(lyrics.lines.first.start, const Duration(seconds: 1));
    });

    test('does not ask for or attach translations unless requested', () async {
      final requests = <http.Request>[];
      final provider = providerFor(requests);

      final lyrics = await provider.fetch(song());

      expect(requests.last.url.queryParameters.containsKey('tv'), isFalse);
      expect(lyrics!.lines.every((l) => l.translation == null), isTrue);
    });

    test('with translations requested, asks for them and attaches them per line', () async {
      final requests = <http.Request>[];
      final provider = providerFor(requests);

      final lyrics = await provider.fetch(song(), translations: true);

      expect(requests.last.url.queryParameters['tv'], '-1');
      expect(lyrics!.lines.map((l) => l.translation), ['嘿，嘿，嘿', '很高兴见到你']);
    });

    test('picks the right song out of the search results', () async {
      final requests = <http.Request>[];
      final provider = providerFor(
        requests,
        songs: [
          searchHit(1, "Can't Hold Us", ['Someone Else'], 258000), // right title+length, wrong artist
          searchHit(2, "Can't Hold Us", ['Macklemore'], 200000), // right artist, wrong length
          searchHit(3, 'Another Song', ['Macklemore'], 258000), // wrong title
          searchHit(4, "Can't Hold Us", ['Macklemore'], 259500), // the one
        ],
      );

      await provider.fetch(song());

      expect(requests.last.url.queryParameters['id'], '4');
    });

    test('takes the closest length when several results match', () async {
      final requests = <http.Request>[];
      final provider = providerFor(
        requests,
        songs: [
          searchHit(1, "Can't Hold Us", ['Macklemore'], 261000),
          searchHit(2, "Can't Hold Us", ['Macklemore'], 258200),
        ],
      );

      await provider.fetch(song());

      expect(requests.last.url.queryParameters['id'], '2');
    });

    test('trusts a different artist spelling only with an almost identical length', () async {
      final close = <http.Request>[];
      await providerFor(close, songs: [searchHit(9, "Can't Hold Us", ['麦克莫', 'Mai Ke'], 258800)]).fetch(song());
      expect(close.last.url.path, '/api/song/lyric', reason: '0.8 s apart: accepted');

      final far = <http.Request>[];
      final lyrics = await providerFor(
        far,
        songs: [searchHit(9, "Can't Hold Us", ['麦克莫', 'Mai Ke'], 262000)],
      ).fetch(song());
      expect(lyrics, isNull, reason: '4 s apart with an unmatched artist: rejected');
      expect(far.map((r) => r.url.path), ['/api/search/get']);
    });

    test('searches by title alone when the artist is unknown', () async {
      final requests = <http.Request>[];
      await providerFor(requests).fetch(song(artist: 'Unknown artist'));

      expect(requests.first.url.queryParameters['s'], "Can't Hold Us");
    });

    test('no matching result means no lyrics, and the lyric is never requested', () async {
      final requests = <http.Request>[];
      final provider = providerFor(requests, songs: [searchHit(1, 'Unrelated', ['Nobody'], 100000)]);

      expect(await provider.fetch(song()), isNull);
      expect(requests.length, 1);
    });

    test('an empty search result means no lyrics', () async {
      final provider = providerFor(
        [],
        override: (_) => jsonResponse({'code': 200, 'result': <String, dynamic>{}}),
      );

      expect(await provider.fetch(song()), isNull);
    });

    test('a track flagged as having no lyrics, or an empty lyric, has no lyrics', () async {
      expect(
        await providerFor([], lyric: {'code': 200, 'nolyric': true}).fetch(song()),
        isNull,
      );
      expect(
        await providerFor([], lyric: {'code': 200, 'uncollected': true}).fetch(song()),
        isNull,
      );
      expect(
        await providerFor([], lyric: {
          'code': 200,
          'lrc': {'lyric': '  '},
        }).fetch(song()),
        isNull,
      );
    });

    test('decodes UTF-8 even though the response declares no charset', () async {
      final provider = providerFor(
        [],
        lyric: {
          'code': 200,
          'lrc': {'lyric': '[00:01.000]我很受伤，宝贝'},
        },
      );

      final lyrics = await provider.fetch(song());

      expect(lyrics!.lines.single.text, '我很受伤，宝贝');
    });

    test('an HTTP error is a failure', () async {
      final provider = providerFor([], override: (_) => http.Response('blocked', 403));

      await expectLater(provider.fetch(song()), throwsException);
    });

    test('an error code in the body is a failure', () async {
      final provider = providerFor([], override: (_) => jsonResponse({'code': -460, 'message': 'Cheating'}));

      await expectLater(provider.fetch(song()), throwsException);
    });

    test('a network failure is a failure', () async {
      final provider = NeteaseProvider(httpClient: MockClient((_) async => throw http.ClientException('offline')));

      await expectLater(provider.fetch(song()), throwsA(isA<http.ClientException>()));
    });
  });
}
