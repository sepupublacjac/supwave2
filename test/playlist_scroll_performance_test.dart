import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    show Element, Size, debugOnRebuildDirtyWidget;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supwave_gen2/main.dart';
import 'package:supwave_gen2/models/playlist.dart';
import 'package:supwave_gen2/models/song.dart';
import 'package:supwave_gen2/navidrome/playback_audio_handler.dart';
import 'package:supwave_gen2/screens/playlist_detail_screen.dart';
import 'package:supwave_gen2/state/auth_controller.dart';
import 'package:supwave_gen2/state/player_controller.dart';
import 'package:supwave_gen2/widgets/album_art.dart';
import 'package:supwave_gen2/widgets/song_context_menu_button.dart';
import 'package:supwave_gen2/widgets/song_tile.dart';

import 'fakes/fake_audio_engine.dart';
import 'fakes/fake_navidrome_repository.dart';

/// Regression guard for playlist scroll jank on real phones. A long playlist
/// used to build every row up front (300 cover images + context menus) and
/// then rebuild all of them on every ~200ms playback position tick. These
/// tests pin both fixes: rows are built lazily, and position ticks no longer
/// rebuild the list.

const _songCount = 300;

final _bigPlaylistSongs = List.generate(
  _songCount,
  (i) => Song(
    id: 'big$i',
    title: 'Big song $i',
    artist: 'Artist',
    artistId: 'ar1',
    album: 'Album',
    albumId: 'al$i',
    duration: const Duration(minutes: 3),
  ),
);

class _BigPlaylistRepository extends FakeNavidromeRepository {
  @override
  Future<List<Playlist>> getPlaylists() async => [
    const Playlist(
      id: 'big',
      name: 'Big playlist',
      description: '',
      songCount: _songCount,
      duration: Duration(hours: 15),
    ),
  ];

  @override
  Future<List<Song>> getPlaylistSongs(String playlistId) async => _bigPlaylistSongs;
}

/// See `settle` in widget_test.dart for why this isn't `pumpAndSettle`.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens the big playlist's detail screen on a phone-sized surface.
Future<FakeAudioEngine> _openBigPlaylist(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

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
        repositoryOverride: _BigPlaylistRepository(),
        audioEngineOverride: engine,
        offlineDirectoryOverride: Directory.systemTemp.createTempSync('supwave_perf_test'),
      ),
    ),
  );
  await _settle(tester);

  await tester.tap(find.text('Playlists'));
  await _settle(tester);
  await tester.tap(find.text('Big playlist'));
  await _settle(tester);
  return engine;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a $_songCount-song playlist only builds the rows near the viewport', (
    WidgetTester tester,
  ) async {
    await _openBigPlaylist(tester);

    int built(Type type) => find
        .descendant(of: find.byType(PlaylistDetailScreen), matching: find.byType(type))
        .evaluate()
        .length;

    // A phone viewport shows roughly a dozen rows; allow generous headroom
    // for the sliver's cache extent. Eagerly building all rows would be 300.
    expect(built(SongContextMenuButton), greaterThan(0));
    expect(built(SongContextMenuButton), lessThan(60));
    expect(built(AlbumArt), lessThan(60));
  });

  testWidgets('playback position ticks do not rebuild the song list', (
    WidgetTester tester,
  ) async {
    final engine = await _openBigPlaylist(tester);

    await tester.tap(find.text('Play'));
    await _settle(tester);

    final rebuilds = <Type, int>{};
    debugOnRebuildDirtyWidget = (Element element, bool builtOnce) {
      final type = element.widget.runtimeType;
      if (type == SongTile || type == AlbumArt || type == SongContextMenuButton) {
        rebuilds[type] = (rebuilds[type] ?? 0) + 1;
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    // ~1 second of real playback: the engine reports every ~200ms.
    for (var i = 1; i <= 5; i++) {
      await engine.seek(Duration(seconds: i));
      await tester.pump(const Duration(milliseconds: 200));
    }
    debugOnRebuildDirtyWidget = null;

    expect(rebuilds, isEmpty, reason: 'position ticks rebuilt: $rebuilds');
  });

  testWidgets('position ticks still reach positionListenable, and only seeks notify', (
    WidgetTester tester,
  ) async {
    final engine = await _openBigPlaylist(tester);
    final controller = tester
        .element(find.byType(PlaylistDetailScreen))
        .read<PlayerController>();

    await tester.tap(find.text('Play'));
    await _settle(tester);

    var notifications = 0;
    controller.addListener(() => notifications++);

    // A plain engine tick updates the position without notifying listeners.
    await engine.seek(const Duration(seconds: 7));
    await tester.pump();
    expect(controller.positionListenable.value, const Duration(seconds: 7));
    expect(controller.position, const Duration(seconds: 7));
    expect(notifications, 0);

    // A user seek does notify, so the Android media notification resyncs.
    await controller.seekTo(0.5);
    await tester.pump();
    expect(controller.positionListenable.value, const Duration(seconds: 90));
    expect(notifications, greaterThan(0));
  });
}
