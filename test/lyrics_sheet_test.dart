import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart' show Text, ValueKey;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supwave_gen2/main.dart';
import 'package:supwave_gen2/models/lyrics.dart';
import 'package:supwave_gen2/models/song.dart';
import 'package:supwave_gen2/navidrome/playback_audio_handler.dart';
import 'package:supwave_gen2/state/auth_controller.dart';
import 'package:supwave_gen2/state/player_controller.dart';
import 'package:supwave_gen2/widgets/mini_player.dart';

import 'fakes/fake_audio_engine.dart';
import 'fakes/fake_navidrome_repository.dart';

/// The lyrics sheet on the full player screen. See `settle` in
/// widget_test.dart for why this isn't `pumpAndSettle`.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Lyrics _synced(List<(int, String)> lines) => Lyrics(
  synced: true,
  lines: [for (final (ms, text) in lines) LyricLine(text, start: Duration(milliseconds: ms))],
);

class _Harness {
  _Harness(this.repo, this.engine, this.controller, this.songs);

  final FakeNavidromeRepository repo;
  final FakeAudioEngine engine;
  final PlayerController controller;
  final List<Song> songs;
}

/// Starts the app, queues the dashboard's songs from the first one, and opens
/// the full player. [setUpRepo] runs before anything loads.
Future<_Harness> _openPlayer(WidgetTester tester, void Function(FakeNavidromeRepository repo) setUpRepo) async {
  final repo = FakeNavidromeRepository();
  setUpRepo(repo);
  final engine = FakeAudioEngine();

  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => AuthController.authenticated(
        serverUrl: 'https://fake.test',
        username: 'tester',
        password: 'password',
      ),
      child: AuthGate(
        audioHandler: PlaybackAudioHandler(),
        repositoryOverride: repo,
        audioEngineOverride: engine,
        offlineDirectoryOverride: Directory.systemTemp.createTempSync('supwave_lyrics_test'),
      ),
    ),
  );
  await _settle(tester);

  final controller = tester.element(find.byType(MiniPlayer)).read<PlayerController>();
  final songs = (await repo.getDashboard()).quickPicks;
  await controller.playQueue(songs);
  await _settle(tester);

  await tester.tap(find.byType(MiniPlayer));
  await _settle(tester);
  return _Harness(repo, engine, controller, songs);
}

Future<void> _openLyricsSheet(WidgetTester tester) async {
  // The toolbar sits below the fold of this test's 800x600 surface.
  await tester.ensureVisible(find.byIcon(M3EIcons.lyrics));
  await _settle(tester);
  await tester.tap(find.byIcon(M3EIcons.lyrics));
  await _settle(tester);
}

String? _currentLine(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('current-lyric-line'));
  return finder.evaluate().isEmpty ? null : tester.widget<Text>(finder).data;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('synced lyrics: the current line follows playback and a tap seeks to a line', (tester) async {
    final h = await _openPlayer(tester, (repo) {
      repo.lyricsBySongId['s1'] = _synced([(0, 'First line'), (10000, 'Second line'), (20000, 'Third line')]);
    });
    await _openLyricsSheet(tester);

    expect(find.text('First line'), findsOneWidget);
    expect(find.text('Second line'), findsOneWidget);
    expect(find.text('Third line'), findsOneWidget);
    expect(_currentLine(tester), 'First line');

    // Playback reaches the second line.
    await h.engine.seek(const Duration(seconds: 12));
    await _settle(tester);
    expect(_currentLine(tester), 'Second line');

    // Tapping a line jumps the song there.
    await tester.tap(find.text('Third line'));
    await _settle(tester);
    expect(h.controller.position, const Duration(seconds: 20));
    expect(_currentLine(tester), 'Third line');
  });

  testWidgets('before the first timed line nothing is highlighted yet', (tester) async {
    await _openPlayer(tester, (repo) {
      repo.lyricsBySongId['s1'] = _synced([(5000, 'Late start'), (9000, 'Next')]);
    });
    await _openLyricsSheet(tester);

    expect(find.text('Late start'), findsOneWidget);
    expect(_currentLine(tester), isNull);
  });

  testWidgets('lyrics without timing are shown as plain text with no highlight', (tester) async {
    await _openPlayer(tester, (repo) {
      repo.lyricsBySongId['s1'] = Lyrics.fromPlainText('Plain one\nPlain two');
    });
    await _openLyricsSheet(tester);

    expect(find.text('Plain one'), findsOneWidget);
    expect(find.text('Plain two'), findsOneWidget);
    expect(_currentLine(tester), isNull);
  });

  testWidgets('a song with no lyrics says so', (tester) async {
    await _openPlayer(tester, (_) {});
    await _openLyricsSheet(tester);

    expect(find.text('No lyrics for this song'), findsOneWidget);
  });

  testWidgets('a failed lookup offers a retry that loads the lyrics', (tester) async {
    final h = await _openPlayer(tester, (repo) => repo.lyricsError = Exception('offline'));
    await _openLyricsSheet(tester);

    expect(find.text('Could not load lyrics'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    h.repo.lyricsError = null;
    h.repo.lyricsBySongId['s1'] = Lyrics.fromPlainText('Back online');
    await tester.tap(find.text('Retry'));
    await _settle(tester);

    expect(find.text('Could not load lyrics'), findsNothing);
    expect(find.text('Back online'), findsOneWidget);
  });

  testWidgets('the sheet follows the track: skipping to the next song loads its lyrics', (tester) async {
    final h = await _openPlayer(tester, (repo) {
      repo.lyricsBySongId['s1'] = Lyrics.fromPlainText('Words of song one');
      repo.lyricsBySongId['s2'] = Lyrics.fromPlainText('Words of song two');
    });
    await _openLyricsSheet(tester);
    expect(find.text('Words of song one'), findsOneWidget);

    await h.controller.next();
    await _settle(tester);

    expect(find.text('Words of song one'), findsNothing);
    expect(find.text('Words of song two'), findsOneWidget);
  });

  testWidgets('reopening the sheet for the same song does not ask the server again', (tester) async {
    final h = await _openPlayer(tester, (repo) {
      repo.lyricsBySongId['s1'] = Lyrics.fromPlainText('Cached words');
    });
    await _openLyricsSheet(tester);
    expect(find.text('Cached words'), findsOneWidget);
    expect(h.repo.lyricsRequests, 1);

    // Close the sheet (tap outside it) and open it again.
    await tester.tapAt(const Offset(400, 20));
    await _settle(tester);
    expect(find.text('Cached words'), findsNothing);
    await _openLyricsSheet(tester);

    expect(find.text('Cached words'), findsOneWidget);
    expect(h.repo.lyricsRequests, 1);
  });
}
