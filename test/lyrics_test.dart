import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supwave_gen2/models/lyrics.dart';
import 'package:supwave_gen2/models/song.dart';
import 'package:supwave_gen2/navidrome/navidrome_api_repository.dart';
import 'package:supwave_gen2/navidrome/subsonic_client.dart';
import 'package:supwave_gen2/state/lyrics_controller.dart';

import 'fakes/fake_navidrome_repository.dart';

const _song = Song(
  id: 's1',
  title: 'Test Song',
  artist: 'Test Artist',
  artistId: 'ar1',
  album: 'Test Album',
  albumId: 'al1',
  duration: Duration(minutes: 3),
);

Duration ms(int v) => Duration(milliseconds: v);

Map<String, dynamic> _synced(List<(int, String)> lines, {int? offset, String lang = 'eng'}) => {
  'lang': lang,
  'synced': true,
  'offset': ?offset,
  'line': [
    for (final (start, text) in lines) {'start': start, 'value': text},
  ],
};

Map<String, dynamic> _unsynced(List<String> lines) => {
  'lang': 'eng',
  'synced': false,
  'line': [
    for (final text in lines) {'value': text},
  ],
};

void main() {
  group('Lyrics.fromStructured', () {
    test('reads synced lines with their start times', () {
      final lyrics = Lyrics.fromStructured(_synced([(1000, 'one'), (4500, 'two')]));

      expect(lyrics.synced, isTrue);
      expect(lyrics.language, 'eng');
      expect(lyrics.lines.map((l) => l.text), ['one', 'two']);
      expect(lyrics.lines.map((l) => l.start), [ms(1000), ms(4500)]);
    });

    test('a positive offset makes lines appear sooner (OpenSubsonic spec)', () {
      final lyrics = Lyrics.fromStructured(_synced([(2000, 'a'), (5000, 'b')], offset: 100));

      expect(lyrics.lines.map((l) => l.start), [ms(1900), ms(4900)]);
    });

    test('a negative offset makes lines appear later', () {
      final lyrics = Lyrics.fromStructured(_synced([(2000, 'a')], offset: -250));

      expect(lyrics.lines.single.start, ms(2250));
    });

    test('an offset never pushes a line before the start of the track', () {
      final lyrics = Lyrics.fromStructured(_synced([(50, 'a')], offset: 400));

      expect(lyrics.lines.single.start, Duration.zero);
    });

    test('unsynced lyrics have no start times', () {
      final lyrics = Lyrics.fromStructured(_unsynced(['one', 'two']));

      expect(lyrics.synced, isFalse);
      expect(lyrics.lines.every((l) => l.start == null), isTrue);
    });

    test('lyrics claiming to be synced but missing a start are treated as plain text', () {
      final lyrics = Lyrics.fromStructured({
        'synced': true,
        'line': [
          {'start': 1000, 'value': 'timed'},
          {'value': 'untimed'},
        ],
      });

      expect(lyrics.synced, isFalse);
      expect(lyrics.lines.map((l) => l.text), ['timed', 'untimed']);
      expect(lyrics.lines.every((l) => l.start == null), isTrue);
    });
  });

  group('Lyrics.indexAt', () {
    final lyrics = Lyrics.fromStructured(_synced([(1000, 'a'), (4000, 'b'), (9000, 'c')]));

    test('is -1 before the first line', () {
      expect(lyrics.indexAt(Duration.zero), -1);
      expect(lyrics.indexAt(ms(999)), -1);
    });

    test('moves to a line exactly when it starts', () {
      expect(lyrics.indexAt(ms(1000)), 0);
      expect(lyrics.indexAt(ms(3999)), 0);
      expect(lyrics.indexAt(ms(4000)), 1);
      expect(lyrics.indexAt(ms(8999)), 1);
      expect(lyrics.indexAt(ms(9000)), 2);
    });

    test('stays on the last line after it', () {
      expect(lyrics.indexAt(const Duration(minutes: 10)), 2);
    });

    test('is always -1 for unsynced lyrics', () {
      expect(Lyrics.fromStructured(_unsynced(['a', 'b'])).indexAt(const Duration(seconds: 30)), -1);
    });
  });

  group('Lyrics.fromPlainText', () {
    test('keeps stanza breaks but drops leading and trailing blank lines', () {
      final lyrics = Lyrics.fromPlainText('\n\nline one\r\nline two\r\n\r\nline three  \n\n');

      expect(lyrics.synced, isFalse);
      expect(lyrics.lines.map((l) => l.text), ['line one', 'line two', '', 'line three']);
    });

    test('whitespace-only text is empty', () {
      expect(Lyrics.fromPlainText('  \n \n').isEmpty, isTrue);
    });
  });

  group('Lyrics.pickBest', () {
    test('prefers synced lyrics over unsynced ones, whatever the order', () {
      final plain = Lyrics.fromStructured(_unsynced(['plain']));
      final timed = Lyrics.fromStructured(_synced([(0, 'timed')]));

      expect(Lyrics.pickBest([plain, timed]), same(timed));
      expect(Lyrics.pickBest([timed, plain]), same(timed));
    });

    test('ignores empty lyrics, and is null when nothing has text', () {
      final empty = Lyrics.fromStructured(_unsynced(['', '  ']));
      final plain = Lyrics.fromStructured(_unsynced(['hello']));

      expect(Lyrics.pickBest([empty, plain]), same(plain));
      expect(Lyrics.pickBest([empty]), isNull);
      expect(Lyrics.pickBest(const []), isNull);
    });
  });

  group('NavidromeApiRepository.getLyrics', () {
    http.Response ok(Map<String, dynamic> body) => http.Response(
      jsonEncode({
        'subsonic-response': {'status': 'ok', 'version': '1.16.1', ...body},
      }),
      200,
    );

    http.Response failed(int code, String message) => http.Response(
      jsonEncode({
        'subsonic-response': {
          'status': 'failed',
          'version': '1.16.1',
          'error': {'code': code, 'message': message},
        },
      }),
      200,
    );

    /// Repository over a fake server; [paths] records every endpoint hit.
    NavidromeApiRepository repoFor(
      List<String> paths,
      http.Response Function(String path, Map<String, String> query) respond,
    ) {
      final client = MockClient((request) async {
        final path = request.url.path.split('/').last;
        paths.add(path);
        return respond(path, request.url.queryParameters);
      });
      return NavidromeApiRepository(
        SubsonicClient(
          serverUrl: 'https://music.test',
          username: 'u',
          password: 'p',
          httpClient: client,
        ),
      );
    }

    test('asks getLyricsBySongId for the song and returns the synced lyrics', () async {
      final paths = <String>[];
      Map<String, String>? query;
      final repo = repoFor(paths, (path, q) {
        query = q;
        return ok({
          'lyricsList': {
            'structuredLyrics': [
              _unsynced(['plain']),
              _synced([(1000, 'first'), (2000, 'second')]),
            ],
          },
        });
      });

      final lyrics = await repo.getLyrics(_song);

      expect(paths, ['getLyricsBySongId.view']);
      expect(query!['id'], 's1');
      expect(lyrics!.synced, isTrue);
      expect(lyrics.lines.map((l) => l.text), ['first', 'second']);
    });

    test('an empty lyricsList means no lyrics, without trying the legacy endpoint', () async {
      final paths = <String>[];
      final repo = repoFor(paths, (_, _) => ok({'lyricsList': <String, dynamic>{}}));

      expect(await repo.getLyrics(_song), isNull);
      expect(paths, ['getLyricsBySongId.view']);
    });

    test('error 70 (data not found) means no lyrics', () async {
      final paths = <String>[];
      final repo = repoFor(paths, (_, _) => failed(70, 'Lyrics not found'));

      expect(await repo.getLyrics(_song), isNull);
      expect(paths, ['getLyricsBySongId.view']);
    });

    test('falls back to the legacy getLyrics on a server without OpenSubsonic lyrics', () async {
      final paths = <String>[];
      Map<String, String>? legacyQuery;
      final repo = repoFor(paths, (path, q) {
        if (path == 'getLyricsBySongId.view') return failed(0, 'Not implemented');
        legacyQuery = q;
        return ok({
          'lyrics': {'artist': 'Test Artist', 'title': 'Test Song', 'value': 'old\nschool'},
        });
      });

      final lyrics = await repo.getLyrics(_song);

      expect(paths, ['getLyricsBySongId.view', 'getLyrics.view']);
      expect(legacyQuery!['artist'], 'Test Artist');
      expect(legacyQuery!['title'], 'Test Song');
      expect(lyrics!.synced, isFalse);
      expect(lyrics.lines.map((l) => l.text), ['old', 'school']);
    });

    test('also falls back when the endpoint answers HTTP 404', () async {
      final paths = <String>[];
      final repo = repoFor(paths, (path, _) {
        if (path == 'getLyricsBySongId.view') return http.Response('not found', 404);
        return ok({
          'lyrics': {'value': 'legacy text'},
        });
      });

      expect((await repo.getLyrics(_song))!.lines.single.text, 'legacy text');
      expect(paths, ['getLyricsBySongId.view', 'getLyrics.view']);
    });

    test('the legacy endpoint finding nothing means no lyrics', () async {
      final repo = repoFor(<String>[], (path, _) {
        if (path == 'getLyricsBySongId.view') return failed(0, 'Not implemented');
        return ok({
          'lyrics': <String, dynamic>{},
        });
      });

      expect(await repo.getLyrics(_song), isNull);
    });

    test('a network failure is reported, not mistaken for "no lyrics" or retried as legacy', () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path.split('/').last);
        throw http.ClientException('offline');
      });
      final repo = NavidromeApiRepository(
        SubsonicClient(
          serverUrl: 'https://music.test',
          username: 'u',
          password: 'p',
          httpClient: client,
        ),
      );

      await expectLater(repo.getLyrics(_song), throwsA(isA<SubsonicException>()));
      expect(paths, ['getLyricsBySongId.view']);
    });
  });

  group('LyricsController', () {
    late FakeNavidromeRepository repo;

    setUp(() => repo = FakeNavidromeRepository());

    Lyrics hello() => Lyrics.fromPlainText('hello');

    test('asks the server once per song and reuses the answer', () async {
      repo.lyricsBySongId['s1'] = hello();
      final controller = LyricsController(repo);

      final first = await controller.lyricsFor(_song);
      final second = await controller.lyricsFor(_song);

      expect(second, same(first));
      expect(repo.lyricsRequests, 1);
    });

    test('remembers that a song has no lyrics', () async {
      final controller = LyricsController(repo);

      expect(await controller.lyricsFor(_song), isNull);
      expect(await controller.lyricsFor(_song), isNull);
      expect(repo.lyricsRequests, 1);
    });

    test('forgets a failed lookup so a retry asks the server again', () async {
      final controller = LyricsController(repo);
      repo.lyricsError = Exception('offline');

      await expectLater(controller.lyricsFor(_song), throwsException);
      // Let the controller's own error handler run before retrying.
      await Future<void>.delayed(Duration.zero);

      repo.lyricsError = null;
      repo.lyricsBySongId['s1'] = hello();
      final retried = await controller.lyricsFor(_song);

      expect(retried, isNotNull);
      expect(repo.lyricsRequests, 2);
    });

    test('keeps only the most recently used songs', () async {
      final controller = LyricsController(repo, maxCached: 2);
      Song song(String id) => Song(
        id: id,
        title: id,
        artist: 'A',
        artistId: 'a',
        album: 'B',
        albumId: 'b',
        duration: const Duration(minutes: 3),
      );

      await controller.lyricsFor(song('a'));
      await controller.lyricsFor(song('b'));
      await controller.lyricsFor(song('a')); // a is now newer than b
      await controller.lyricsFor(song('c')); // evicts b
      expect(repo.lyricsRequests, 3);

      await controller.lyricsFor(song('a')); // still cached
      expect(repo.lyricsRequests, 3);
      await controller.lyricsFor(song('b')); // was evicted
      expect(repo.lyricsRequests, 4);
    });
  });
}
