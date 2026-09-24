import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart'
    show Hero, ReorderableListView, Scrollable, Widget;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supwave_gen2/main.dart';
import 'package:supwave_gen2/navidrome/playback_audio_handler.dart';
import 'package:supwave_gen2/state/app_logger.dart';
import 'package:supwave_gen2/state/auth_controller.dart';

import 'fakes/fake_audio_engine.dart';
import 'fakes/fake_navidrome_repository.dart';

/// Mounts the real [AuthGate] - the exact widget `main.dart` uses - already
/// authenticated, with a fake repository/audio engine substituted in via its
/// override hooks. Exercising the production widget (instead of a hand-rolled
/// parallel tree) is what caught the provider-scoping regression below: an
/// earlier version of this helper nested things differently than `main.dart`
/// actually did, so it couldn't have caught that bug.
Widget buildAuthenticatedApp(FakeNavidromeRepository repo) {
  return ChangeNotifierProvider(
    create: (_) => AuthController.authenticated(
      serverUrl: 'https://fake.test',
      username: 'tester',
      password: 'password',
    ),
    child: AuthGate(
      // A bare instance is fine here: only `AudioService.init` (never called
      // under `flutter test`) touches a platform channel, not this class.
      audioHandler: PlaybackAudioHandler(),
      repositoryOverride: repo,
      audioEngineOverride: FakeAudioEngine(),
      // Avoids path_provider's platform channel (unavailable under
      // `flutter test`) - a real temp dir works fine for OfflineManager's
      // plain dart:io file operations.
      offlineDirectoryOverride: Directory.systemTemp.createTempSync('supwave_offline_test'),
    ),
  );
}

/// Stands in for `tester.pumpAndSettle()`, which hangs forever once the
/// dashboard (kept permanently mounted by `RootShell`'s `IndexedStack`) is
/// showing: its `M3ERefreshIndicator` always builds a contained
/// `M3ELoadingIndicator`, whose rotation animation runs via an unconditional
/// `AnimationController.repeat()` (see m3e_expressive_loading_indicator.dart)
/// unless the host manually drives it - so it never "settles" app-wide.
/// Pumping a fixed number of frames instead advances real animations/timers
/// without waiting for that perpetual one to stop.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    // AuthController.restoreSession/login/logout touch shared_preferences;
    // this keeps them fast and hermetic instead of hitting a real platform
    // channel that doesn't exist under `flutter test`.
    SharedPreferences.setMockInitialValues({});
    // AppLogger.instance is a process-wide singleton (all tests in this
    // file share one isolate), so without resetting it, entries logged by
    // one test leak into the next.
    AppLogger.instance.resetForTest();
  });

  testWidgets('Login screen renders the server/username/password fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthController()..restoreSession(),
        child: AuthGate(audioHandler: PlaybackAudioHandler()),
      ),
    );
    await settle(tester);

    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('App boots to the dashboard with a bottom nav bar', (WidgetTester tester) async {
    await tester.pumpWidget(buildAuthenticatedApp(FakeNavidromeRepository()));
    await settle(tester);

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.byType(M3ENavigationBar), findsOneWidget);
  });

  testWidgets('Playing a song from the dashboard shows the mini player, '
      'and opening it shows the full player', (WidgetTester tester) async {
    await tester.pumpWidget(buildAuthenticatedApp(FakeNavidromeRepository()));
    await settle(tester);

    // Tap the first quick-pick tile to start playback.
    await tester.tap(find.byType(M3ECard).first);
    await settle(tester);

    final miniPlayerProgress = find.byType(M3EProgressIndicator);
    expect(miniPlayerProgress, findsWidgets);

    // Open the full player from the mini player (target its Hero by tag,
    // since M3E widgets may use their own Heroes internally for morphs).
    final miniPlayerArt = find.byWidgetPredicate(
      (widget) => widget is Hero && widget.tag == 'player-art',
    );
    expect(miniPlayerArt, findsOneWidget);
    await tester.tap(miniPlayerArt);
    await settle(tester);

    expect(find.byType(M3ESlider), findsOneWidget);
    expect(find.byType(M3EToolbar), findsOneWidget);

    // Open the queue sheet from the toolbar's queue action.
    // The full player is scrollable now (its content can be taller than the
    // viewport, e.g. this test's wide/short default surface), so make sure
    // the toolbar is actually on screen before tapping its queue action.
    await tester.ensureVisible(find.byIcon(M3EIcons.queue_music));
    await settle(tester);
    await tester.tap(find.byIcon(M3EIcons.queue_music));
    await settle(tester);

    expect(find.byType(ReorderableListView), findsOneWidget);
    final initialCount = tester.widgetList<M3EListItem>(find.byType(M3EListItem)).length;
    expect(initialCount, greaterThan(0));

    // Swiping a row away should remove it from the queue (Flutter's own
    // Dismissible, wrapping each M3EListItem row).
    await tester.drag(find.byType(M3EListItem).first, const Offset(-500, 0));
    await settle(tester);

    final remainingCount = tester.widgetList<M3EListItem>(find.byType(M3EListItem)).length;
    expect(remainingCount, initialCount - 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dragging a queue row by its handle actually reorders it '
      '(regression: dragging used to move the whole sheet instead)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildAuthenticatedApp(FakeNavidromeRepository()));
    await settle(tester);

    // A single quick pick only plays that one song (no queue); play a whole
    // playlist instead to get a multi-song queue to reorder.
    await tester.tap(find.text('Playlists'));
    await settle(tester);
    await tester.tap(find.text('Chill Vibes'));
    await settle(tester);
    await tester.tap(find.widgetWithText(M3EButton, 'Play'));
    await settle(tester);
    // The mini player is part of the persistent app shell now, so it's still
    // reachable from the playlist detail screen without popping back first.
    final miniPlayerArt = find.byWidgetPredicate(
      (widget) => widget is Hero && widget.tag == 'player-art',
    );
    await tester.tap(miniPlayerArt);
    await settle(tester);

    // The full player is scrollable now (its content can be taller than the
    // viewport, e.g. this test's wide/short default surface), so make sure
    // the toolbar is actually on screen before tapping its queue action.
    await tester.ensureVisible(find.byIcon(M3EIcons.queue_music));
    await settle(tester);
    await tester.tap(find.byIcon(M3EIcons.queue_music));
    await settle(tester);

    List<String> titlesInOrder() => tester
        .widgetList<M3EListItem>(find.byType(M3EListItem))
        .map((item) => item.headline)
        .toList();

    final before = titlesInOrder();
    expect(before.length, greaterThan(2));

    // Drag the first row's handle down past the third row to move it there.
    final handle = find.byIcon(M3EIcons.drag_handle).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, 160));
    await settle(tester);
    await gesture.up();
    await settle(tester);

    final after = titlesInOrder();
    expect(after, isNot(equals(before)));
    // The dragged song is still in the list, just not still in first place.
    expect(after, contains(before.first));
    expect(after.first, isNot(equals(before.first)));
    // The bottom sheet itself must not have been dismissed by the drag.
    expect(find.byType(ReorderableListView), findsOneWidget);
  });

  testWidgets('Removing the last item in the queue does not throw (regression)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildAuthenticatedApp(FakeNavidromeRepository()));
    await settle(tester);

    // Queue up more than one song so there's a real "last" row - a single
    // quick pick only plays that one song, so play a whole playlist instead.
    await tester.tap(find.text('Playlists'));
    await settle(tester);
    await tester.tap(find.text('Chill Vibes'));
    await settle(tester);
    await tester.tap(find.widgetWithText(M3EButton, 'Play'));
    await settle(tester);
    // The mini player is part of the persistent app shell now, so it's still
    // reachable from the playlist detail screen without popping back first.
    final miniPlayerArt = find.byWidgetPredicate(
      (widget) => widget is Hero && widget.tag == 'player-art',
    );
    await tester.tap(miniPlayerArt);
    await settle(tester);

    // The full player is scrollable now (its content can be taller than the
    // viewport, e.g. this test's wide/short default surface), so make sure
    // the toolbar is actually on screen before tapping its queue action.
    await tester.ensureVisible(find.byIcon(M3EIcons.queue_music));
    await settle(tester);
    await tester.tap(find.byIcon(M3EIcons.queue_music));
    await settle(tester);

    final initialCount = tester.widgetList<M3EListItem>(find.byType(M3EListItem)).length;
    expect(initialCount, greaterThan(1));

    // Scroll the sheet so the last row is actually on screen before
    // dragging it - ReorderableListView is lazy, so an offscreen row isn't
    // even built yet.
    await tester.dragUntilVisible(
      find.byType(M3EListItem).last,
      find.byType(Scrollable).last,
      const Offset(0, -100),
    );
    await settle(tester);

    await tester.drag(find.byType(M3EListItem).last, const Offset(-800, 0));
    await settle(tester);

    // Regression coverage for the old M3EDismissibleColumn-based queue list,
    // which threw a RangeError from its own internal bookkeeping when the
    // dismissed row was the last one. The queue list is now Flutter's own
    // Dismissible/ReorderableListView, which doesn't have that bug, but this
    // is still a reasonable general safety net.
    expect(tester.takeException(), isNull);

    final remainingCount = tester.widgetList<M3EListItem>(find.byType(M3EListItem)).length;
    expect(remainingCount, initialCount - 1);
  });

  testWidgets(
    'Mini player and nav bar stay visible on pushed screens '
    '(regression: they used to disappear outside RootShell)',
    (tester) async {
      await tester.pumpWidget(buildAuthenticatedApp(FakeNavidromeRepository()));
      await settle(tester);

      await tester.tap(find.byType(M3ECard).first);
      await settle(tester);
      expect(find.byType(M3ENavigationBar), findsOneWidget);

      // Navigate into a pushed screen (not one of RootShell's own tabs).
      await tester.tap(find.text('Playlists'));
      await settle(tester);
      await tester.tap(find.text('Chill Vibes'));
      await settle(tester);

      expect(find.byWidgetPredicate((w) => w is Hero && w.tag == 'player-art'), findsOneWidget);
      expect(find.byType(M3ENavigationBar), findsOneWidget);

      // The full player, on the other hand, replaces the mini player/nav bar
      // entirely rather than showing them redundantly underneath it.
      await tester.tap(find.byWidgetPredicate((w) => w is Hero && w.tag == 'player-art'));
      await settle(tester);
      expect(find.byType(M3ESlider), findsOneWidget);
      expect(find.byType(M3ENavigationBar), findsNothing);

      await tester.tap(find.byIcon(M3EIcons.keyboard_arrow_down));
      await settle(tester);
      expect(find.byType(M3ENavigationBar), findsOneWidget);
    },
  );

  testWidgets('Navigating to a playlist shows its songs', (WidgetTester tester) async {
    await tester.pumpWidget(buildAuthenticatedApp(FakeNavidromeRepository()));
    await settle(tester);

    await tester.tap(find.text('Playlists'));
    await settle(tester);

    expect(find.byType(M3ECardList), findsOneWidget);

    await tester.tap(find.text('Chill Vibes'));
    await settle(tester);

    expect(find.widgetWithText(M3EButton, 'Play'), findsOneWidget);
    expect(find.byType(M3EListItem), findsWidgets);
    expect(find.text('Song 1'), findsOneWidget);
  });

  testWidgets('Creating and deleting a playlist works end to end', (WidgetTester tester) async {
    await tester.pumpWidget(buildAuthenticatedApp(FakeNavidromeRepository()));
    await settle(tester);

    await tester.tap(find.text('Playlists'));
    await settle(tester);

    expect(find.text('New Playlist'), findsNothing);

    // Create it.
    await tester.tap(find.byIcon(M3EIcons.add));
    await settle(tester);

    await tester.enterText(find.byType(M3ETextField), 'New Playlist');
    await settle(tester);
    await tester.tap(find.widgetWithText(M3EButton, 'Create'));
    await settle(tester);

    // Creating opens the new (empty) playlist straight away.
    expect(find.widgetWithText(M3EButton, 'Play'), findsOneWidget);
    expect(find.text('New Playlist'), findsWidgets);

    await tester.pageBack();
    await settle(tester);

    expect(find.text('New Playlist'), findsOneWidget);

    // Delete it via the detail screen's "..." menu, with confirmation - not
    // from the list itself.
    await tester.tap(find.text('New Playlist'));
    await settle(tester);
    await tester.tap(find.byIcon(M3EIcons.more_vert));
    await settle(tester);
    await tester.tap(find.text('Delete playlist'));
    await settle(tester);
    expect(find.text('Delete playlist?'), findsOneWidget);
    await tester.tap(find.widgetWithText(M3EButton, 'Delete'));
    await settle(tester);

    // Deleting pops back to the list automatically.
    expect(find.text('New Playlist'), findsNothing);
  });

  testWidgets('Search tab debounces input and shows matching songs', (WidgetTester tester) async {
    await tester.pumpWidget(buildAuthenticatedApp(FakeNavidromeRepository()));
    await settle(tester);

    await tester.tap(find.text('Search'));
    await settle(tester);

    expect(find.text('Search your library by song, album, or artist'), findsOneWidget);

    await tester.enterText(find.byType(M3ESearchBar), 'Song 1');
    // Right after typing, the debounce timer hasn't fired yet, so no
    // request has gone out and no results are shown.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('No results for "Song 1"'), findsNothing);

    // Once the debounce delay elapses, the search actually runs.
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);

    expect(find.text('Songs'), findsOneWidget);
    expect(find.widgetWithText(M3EListItem, 'Song 1'), findsOneWidget);
  });

  testWidgets('Player menu: add to playlist, view album, and view artist all work', (
    WidgetTester tester,
  ) async {
    final repo = FakeNavidromeRepository();
    await tester.pumpWidget(buildAuthenticatedApp(repo));
    await settle(tester);

    // Play the first quick pick and open the full player.
    await tester.tap(find.byType(M3ECard).first);
    await settle(tester);
    final miniPlayerArt = find.byWidgetPredicate(
      (widget) => widget is Hero && widget.tag == 'player-art',
    );
    await tester.tap(miniPlayerArt);
    await settle(tester);

    // Add to playlist: open the menu, pick a playlist, expect a confirmation.
    await tester.tap(find.byIcon(M3EIcons.more_vert));
    await settle(tester);
    await tester.tap(find.text('Add to playlist'));
    await settle(tester);

    expect(find.byType(M3ECardList), findsWidgets);
    // warnIfMissed off: M3ECardList wraps rows in extra gesture layers, so
    // the tap still reaches the row underneath even if the exact hit-tested
    // render object differs from the M3EListItem finder's own box.
    await tester.tap(find.byType(M3EListItem).first, warnIfMissed: false);
    await settle(tester);

    expect(find.textContaining('Added'), findsWidgets);

    // View album: opens the album screen for the current song.
    await tester.tap(find.byIcon(M3EIcons.more_vert));
    await settle(tester);
    await tester.tap(find.text('View album'));
    await settle(tester);

    expect(find.text('Album A'), findsOneWidget);

    await tester.pageBack();
    await settle(tester);

    // View artist: opens the artist screen for the current song.
    await tester.tap(find.byIcon(M3EIcons.more_vert));
    await settle(tester);
    await tester.tap(find.text('View artist'));
    await settle(tester);

    expect(find.text('Artist A'), findsOneWidget);
  });

  testWidgets('Profile popup shows account info and opens Logs and Settings', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildAuthenticatedApp(FakeNavidromeRepository()));
    await settle(tester);

    await tester.tap(find.byIcon(M3EIcons.person));
    await settle(tester);

    expect(find.text('App version'), findsOneWidget);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Total songs'), findsOneWidget);
    expect(find.text('Logs'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);

    // Open Logs - should show at least the startup log entry.
    await tester.tap(find.text('Logs'));
    await settle(tester);
    expect(find.text('App started'), findsOneWidget);

    await tester.pageBack();
    await settle(tester);

    // Reopen the popup and jump to Settings.
    await tester.tap(find.byIcon(M3EIcons.person));
    await settle(tester);
    await tester.tap(find.text('Settings'));
    await settle(tester);

    expect(find.text('Username'), findsOneWidget);

    // Storage section: real (empty) offline-download state, not a fake stat.
    expect(find.text('Downloaded songs'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Clear downloads'), findsOneWidget);
  });

  testWidgets('Liked Songs screen opens from the playlists tab without provider errors', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildAuthenticatedApp(FakeNavidromeRepository()));
    await settle(tester);

    await tester.tap(find.text('Playlists'));
    await settle(tester);

    await tester.tap(find.text('Liked Songs'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Liked Songs'), findsOneWidget);
    // The fake repo seeds one starred song ("Song 2").
    expect(find.text('Song 2'), findsOneWidget);
  });

  testWidgets('Song context menu on a playlist: add to queue and remove from playlist work', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildAuthenticatedApp(FakeNavidromeRepository()));
    await settle(tester);

    await tester.tap(find.text('Playlists'));
    await settle(tester);
    await tester.tap(find.text('Chill Vibes'));
    await settle(tester);

    final initialSongCount = tester.widgetList<M3EListItem>(find.byType(M3EListItem)).length;
    expect(initialSongCount, greaterThan(0));

    // Open the context menu for the first song row and check the full,
    // ordered set of actions. Index 0 is now the playlist detail screen's
    // own "..." (delete playlist) menu in the app bar, so the first song
    // row's is index 1.
    await tester.tap(find.byIcon(M3EIcons.more_vert).at(1), warnIfMissed: false);
    await settle(tester);

    expect(find.text('Play next'), findsOneWidget);
    expect(find.text('Add to queue'), findsOneWidget);
    expect(find.text('Add to playlist'), findsOneWidget);
    expect(find.text('Remove from playlist'), findsOneWidget);
    expect(find.text('Available offline'), findsOneWidget);
    expect(find.text('View artist'), findsOneWidget);
    expect(find.text('View album'), findsOneWidget);

    // Add to queue starts playback since nothing was playing yet, and
    // confirms with a snackbar.
    await tester.tap(find.text('Add to queue'));
    await settle(tester);
    expect(find.textContaining('Added "'), findsOneWidget);
    expect(find.textContaining('" to queue'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    expect(find.byType(M3EProgressIndicator), findsWidgets);

    // Re-enter the playlist and remove a song - the row count should drop
    // by one.
    await tester.tap(find.text('Chill Vibes'));
    await settle(tester);

    final currentSongCount = tester.widgetList<M3EListItem>(find.byType(M3EListItem)).length;
    await tester.tap(find.byIcon(M3EIcons.more_vert).at(1), warnIfMissed: false);
    await settle(tester);
    await tester.tap(find.text('Remove from playlist'));
    await settle(tester);

    final remainingCount = tester.widgetList<M3EListItem>(find.byType(M3EListItem)).length;
    expect(remainingCount, currentSongCount - 1);
  });

  testWidgets(
    '"Play next" on a song context menu inserts it right after the current '
    'track in the queue',
    (WidgetTester tester) async {
      await tester.pumpWidget(buildAuthenticatedApp(FakeNavidromeRepository()));
      await settle(tester);

      await tester.tap(find.text('Playlists'));
      await settle(tester);
      await tester.tap(find.text('Chill Vibes'));
      await settle(tester);
      // Chill Vibes is [Song 1, Song 2, Song 5]; playing it starts at Song 1.
      await tester.tap(find.widgetWithText(M3EButton, 'Play'));
      await settle(tester);

      // "Play next" the last song row (Song 5) from its context menu -
      // ensureVisible first, since the playlist header pushes it below the
      // fold on this test's viewport.
      final lastRowMenu = find.byIcon(M3EIcons.more_vert).last;
      await tester.ensureVisible(lastRowMenu);
      await settle(tester);
      await tester.tap(lastRowMenu, warnIfMissed: false);
      await settle(tester);
      await tester.tap(find.text('Play next'));
      await settle(tester);
      expect(find.textContaining('will play next'), findsOneWidget);

      // The playlist detail screen is a pushed route; pop back to reach the
      // mini player and open the full player's queue sheet.
      await tester.pageBack();
      await settle(tester);
      final miniPlayerArt = find.byWidgetPredicate(
        (widget) => widget is Hero && widget.tag == 'player-art',
      );
      await tester.tap(miniPlayerArt);
      await settle(tester);
      // The full player screen scrolls (its content can exceed the viewport
      // height), so the queue button may start out below the fold.
      final queueButton = find.byIcon(M3EIcons.queue_music);
      await tester.ensureVisible(queueButton);
      await settle(tester);
      await tester.tap(queueButton);
      await settle(tester);

      final titles = tester
          .widgetList<M3EListItem>(find.byType(M3EListItem))
          .map((item) => item.headline)
          .toList();
      // Song 5 moved from the end to right after the still-playing Song 1.
      expect(titles, ['Song 1', 'Song 5', 'Song 2']);
    },
  );
}
