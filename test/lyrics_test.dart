import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supwave_gen2/models/lyrics.dart';
import 'package:supwave_gen2/models/song.dart';
import 'package:supwave_gen2/navidrome/navidrome_api_repository.dart';
import 'package:supwave_gen2/navidrome/subsonic_client.dart';
import 'package:supwave_gen2/state/lyrics_controller.dart';
import 'package:supwave_gen2/state/lyrics_settings.dart';

import 'fakes/fake_lyrics_provider.dart';
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

  group('Lyrics.fromLrc', () {
    List<int?> starts(Lyrics l) => l.lines.map((line) => line.start?.inMilliseconds).toList();

    test('reads time-tagged lines as synced lyrics', () {
      final lyrics = Lyrics.fromLrc('[00:01.50]hello\n[00:04.00]world');

      expect(lyrics.synced, isTrue);
      expect(lyrics.lines.map((l) => l.text), ['hello', 'world']);
      expect(starts(lyrics), [1500, 4000]);
    });

    test('understands 1, 2 and 3 digit fractions and none at all', () {
      final lyrics = Lyrics.fromLrc('[00:01.5]a\n[00:02.50]b\n[00:03.05]c\n[00:04.500]d\n[00:05]e\n[01:02.25]f');

      // ".5" and ".50" are half a second; ".05" is 50 ms.
      expect(starts(lyrics), [1500, 2500, 3050, 4500, 5000, 62250]);
    });

    test('a line with several time tags becomes one line per tag, in time order', () {
      final lyrics = Lyrics.fromLrc('[00:10.00][01:20.00]chorus\n[00:30.00]verse');

      expect(lyrics.lines.map((l) => l.text), ['chorus', 'verse', 'chorus']);
      expect(starts(lyrics), [10000, 30000, 80000]);
    });

    test('sorts lines that arrive out of order, keeping the file order for equal times', () {
      final lyrics = Lyrics.fromLrc('[00:20.00]late\n[00:05.00]first\n[00:05.00]second');

      expect(lyrics.lines.map((l) => l.text), ['first', 'second', 'late']);
    });

    test('ignores metadata tags and applies the [offset:] header like OpenSubsonic (positive = sooner)', () {
      final lyrics = Lyrics.fromLrc('[ar:Someone]\n[ti:Something]\n[by:me]\n[offset:+500]\n[00:02.00]line');

      expect(lyrics.lines.single.text, 'line');
      expect(starts(lyrics), [1500]);
    });

    test('strips enhanced per-word tags', () {
      final lyrics = Lyrics.fromLrc('[00:01.00]<00:01.00>Hel<00:01.40>lo <00:01.80>world');

      expect(lyrics.lines.single.text, 'Hello world');
    });

    test('keeps an empty timed line as a gap, and handles CRLF', () {
      final lyrics = Lyrics.fromLrc('[00:01.00]sing\r\n[00:30.00]\r\n[00:40.00]again\r\n');

      expect(lyrics.lines.map((l) => l.text), ['sing', '', 'again']);
    });

    test('text with no time tags falls back to plain lyrics', () {
      final lyrics = Lyrics.fromLrc('just words\nno timing');

      expect(lyrics.synced, isFalse);
      expect(lyrics.lines.map((l) => l.text), ['just words', 'no timing']);
    });

    group('translations', () {
      test('are attached to the line that starts at the same time', () {
        final lyrics = Lyrics.fromLrc(
          '[00:01.000]hello\n[00:05.000]goodbye',
          translationLrc: '[by:someone]\n[00:01.000]bonjour\n[00:05.000]au revoir',
        );

        expect(lyrics.lines.map((l) => l.translation), ['bonjour', 'au revoir']);
      });

      test('tolerate a small timing difference but not a large one', () {
        final lyrics = Lyrics.fromLrc(
          '[00:01.000]near\n[00:10.000]far',
          translationLrc: '[00:01.300]proche\n[00:11.500]loin',
        );

        expect(lyrics.lines[0].translation, 'proche'); // 300 ms away
        expect(lyrics.lines[1].translation, isNull); // 1.5 s away
      });

      test('are skipped for gap lines and when the translation is empty', () {
        final lyrics = Lyrics.fromLrc(
          '[00:01.000]sing\n[00:09.000]\n[00:12.000]more',
          translationLrc: '[00:01.000]chante\n[00:09.000]\n[00:12.000]',
        );

        expect(lyrics.lines.map((l) => l.translation), ['chante', null, null]);
      });

      test('are absent when none was asked for', () {
        final lyrics = Lyrics.fromLrc('[00:01.000]hello');

        expect(lyrics.lines.single.translation, isNull);
      });
    });

    test('withSource keeps everything else', () {
      final lyrics = Lyrics.fromLrc('[00:01.000]hello', language: 'eng').withSource('lrclib.net');

      expect(lyrics.source, 'lrclib.net');
      expect(lyrics.synced, isTrue);
      expect(lyrics.language, 'eng');
      expect(lyrics.lines.single.text, 'hello');
    });
  });

  group('LyricsController sources', () {
    late FakeNavidromeRepository repo;
    late LyricsSettings settings;

    Lyrics serverLyrics() => Lyrics.fromPlainText('from the server');
    Lyrics remote(String text) => Lyrics.fromPlainText(text);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      repo = FakeNavidromeRepository();
      settings = LyricsSettings();
    });

    LyricsController controllerWith(List<FakeLyricsProvider> providers) =>
        LyricsController(repo, settings: settings, providers: providers);

    test('with the internet off (the default) only the server is asked', () async {
      final netease = FakeLyricsProvider('netease', result: remote('remote'));
      repo.lyricsBySongId['s1'] = serverLyrics();

      final lyrics = await controllerWith([netease]).lyricsFor(_song);

      expect(lyrics!.lines.single.text, 'from the server');
      expect(lyrics.source, 'Your server');
      expect(netease.calls, 0);
    });

    test('with the internet off and nothing on the server there are no lyrics', () async {
      final netease = FakeLyricsProvider('netease', result: remote('remote'));

      expect(await controllerWith([netease]).lyricsFor(_song), isNull);
      expect(netease.calls, 0);
    });

    test('prefer local: the server wins and providers are not bothered', () async {
      await settings.setFetchFromInternet(true);
      final netease = FakeLyricsProvider('netease', result: remote('remote'));
      repo.lyricsBySongId['s1'] = serverLyrics();

      final lyrics = await controllerWith([netease]).lyricsFor(_song);

      expect(lyrics!.source, 'Your server');
      expect(netease.calls, 0);
    });

    test('prefer local: falls back to the providers when the server has nothing', () async {
      await settings.setFetchFromInternet(true);
      final netease = FakeLyricsProvider('netease', displayName: 'NetEase', result: remote('from netease'));
      final lrclib = FakeLyricsProvider('lrclib', displayName: 'lrclib.net', result: remote('from lrclib'));

      final lyrics = await controllerWith([netease, lrclib]).lyricsFor(_song);

      expect(lyrics!.lines.single.text, 'from netease');
      expect(lyrics.source, 'NetEase');
      expect(lrclib.calls, 0, reason: 'the first provider that answers wins');
    });

    test('providers are tried in the order they were enabled', () async {
      await settings.setFetchFromInternet(true);
      // Default order is netease, lrclib. Re-enabling netease puts it last.
      await settings.setProviderEnabled('netease', false);
      await settings.setProviderEnabled('netease', true);
      expect(settings.providerIds, ['lrclib', 'netease']);

      final netease = FakeLyricsProvider('netease', result: remote('from netease'));
      final lrclib = FakeLyricsProvider('lrclib', result: remote('from lrclib'));
      final lyrics = await controllerWith([netease, lrclib]).lyricsFor(_song);

      expect(lyrics!.lines.single.text, 'from lrclib');
      expect(netease.calls, 0);
    });

    test('a provider that is switched off is never asked', () async {
      await settings.setFetchFromInternet(true);
      await settings.setProviderEnabled('netease', false);
      final netease = FakeLyricsProvider('netease', result: remote('from netease'));
      final lrclib = FakeLyricsProvider('lrclib', result: remote('from lrclib'));

      await controllerWith([netease, lrclib]).lyricsFor(_song);

      expect(netease.calls, 0);
      expect(lrclib.calls, 1);
    });

    test('no providers enabled means the internet adds nothing', () async {
      await settings.setFetchFromInternet(true);
      await settings.setProviderEnabled('netease', false);
      await settings.setProviderEnabled('lrclib', false);
      final netease = FakeLyricsProvider('netease', result: remote('x'));

      expect(await controllerWith([netease]).lyricsFor(_song), isNull);
      expect(netease.calls, 0);
    });

    test('prefer remote: providers go first and the server is the fallback', () async {
      await settings.setFetchFromInternet(true);
      await settings.setPreferLocal(false);
      repo.lyricsBySongId['s1'] = serverLyrics();
      final lrclib = FakeLyricsProvider('lrclib', displayName: 'lrclib.net', result: remote('from lrclib'));

      final first = await controllerWith([lrclib]).lyricsFor(_song);
      expect(first!.source, 'lrclib.net');
      expect(repo.lyricsRequests, 0, reason: 'the server is not asked when a provider answers');

      lrclib.result = null;
      final other = Song(
        id: 'other',
        title: 'Other',
        artist: 'A',
        artistId: 'a',
        album: 'B',
        albumId: 'b',
        duration: const Duration(minutes: 3),
      );
      repo.lyricsBySongId['other'] = serverLyrics();
      final fallback = await controllerWith([lrclib]).lyricsFor(other);
      expect(fallback!.source, 'Your server');
    });

    test('nothing anywhere is a real "no lyrics"', () async {
      await settings.setFetchFromInternet(true);
      final netease = FakeLyricsProvider('netease');
      final lrclib = FakeLyricsProvider('lrclib');

      expect(await controllerWith([netease, lrclib]).lyricsFor(_song), isNull);
      expect(netease.calls + lrclib.calls, 2);
    });

    test('a failing provider does not hide lyrics found by the next one', () async {
      await settings.setFetchFromInternet(true);
      final netease = FakeLyricsProvider('netease', error: Exception('blocked'));
      final lrclib = FakeLyricsProvider('lrclib', result: remote('from lrclib'));

      final lyrics = await controllerWith([netease, lrclib]).lyricsFor(_song);

      expect(lyrics!.lines.single.text, 'from lrclib');
    });

    test('a failing source with nothing found elsewhere is a failure, not "no lyrics"', () async {
      await settings.setFetchFromInternet(true);
      final netease = FakeLyricsProvider('netease', error: Exception('blocked'));
      final lrclib = FakeLyricsProvider('lrclib'); // answers: none

      await expectLater(controllerWith([netease, lrclib]).lyricsFor(_song), throwsException);
    });

    test('a failing server does not hide lyrics found on the internet', () async {
      await settings.setFetchFromInternet(true);
      repo.lyricsError = Exception('server down');
      final lrclib = FakeLyricsProvider('lrclib', result: remote('from lrclib'));

      final lyrics = await controllerWith([lrclib]).lyricsFor(_song);

      expect(lyrics!.lines.single.text, 'from lrclib');
    });

    test('translations are only requested when enabled', () async {
      await settings.setFetchFromInternet(true);
      final netease = FakeLyricsProvider('netease', result: remote('x'));

      await controllerWith([netease]).lyricsFor(_song);
      expect(netease.translationFlags, [false]);

      await settings.setNeteaseTranslations(true);
      final controller = controllerWith([netease]);
      await controller.lyricsFor(_song);
      expect(netease.translationFlags.last, isTrue);
    });

    test('cached answers are dropped when a source setting changes, but not for the offset', () async {
      await settings.setFetchFromInternet(true);
      final lrclib = FakeLyricsProvider('lrclib', result: remote('from lrclib'));
      final controller = controllerWith([lrclib]);

      await controller.lyricsFor(_song);
      await controller.lyricsFor(_song);
      expect(lrclib.calls, 1);

      await settings.setOffsetMs(500); // display only: same lyrics
      await controller.lyricsFor(_song);
      expect(lrclib.calls, 1);

      await settings.setPreferLocal(false); // could change the answer
      await controller.lyricsFor(_song);
      expect(lrclib.calls, 2);
    });

    test('dispose stops it listening to settings', () async {
      final lrclib = FakeLyricsProvider('lrclib', result: remote('x'));
      await settings.setFetchFromInternet(true);
      final controller = controllerWith([lrclib]);
      await controller.lyricsFor(_song);

      controller.dispose();
      await settings.setPreferLocal(false); // would have cleared the cache

      await controller.lyricsFor(_song);
      expect(lrclib.calls, 1);
    });
  });
}
