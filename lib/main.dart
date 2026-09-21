import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'navidrome/audio_engine.dart';
import 'navidrome/navidrome_api_repository.dart';
import 'navidrome/navidrome_repository.dart';
import 'navidrome/playback_audio_handler.dart';
import 'navidrome/subsonic_client.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'state/app_logger.dart';
import 'state/auth_controller.dart';
import 'state/library_controller.dart';
import 'state/offline_manager.dart';
import 'state/player_controller.dart';
import 'state/playlists_controller.dart';
import 'state/root_tab_controller.dart';
import 'state/shell_visibility.dart';

/// Default Material You seed (matches Android's own default dynamic palette).
const Color kSeedColor = Color(0xFF6750A4);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Must be created exactly once for the app's lifetime, before login even
  // happens - see PlaybackAudioHandler's doc comment for how it connects to
  // the (per-session) PlayerController.
  final audioHandler = await AudioService.init(
    builder: PlaybackAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.megamendung.supwave2.audio',
      androidNotificationChannelName: 'Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      // Defaults to the full-color launcher icon, but Android strips all
      // color from notification icons and renders only their alpha shape -
      // since the launcher icon is a mostly-solid filled disc, that made it
      // show up as a plain white blob. This is a dedicated line-art mark
      // (no filled background) that stays legible once Android flattens it.
      androidNotificationIcon: 'drawable/ic_stat_notification',
    ),
  );
  runApp(SupwaveApp(audioHandler: audioHandler));
}

class SupwaveApp extends StatelessWidget {
  const SupwaveApp({super.key, required this.audioHandler});

  final PlaybackAudioHandler audioHandler;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthController()..restoreSession(),
      child: AuthGate(audioHandler: audioHandler),
    );
  }
}

/// Decides which top-level flow to show - a startup splash, [LoginScreen],
/// or the authenticated app - and owns the `M3EMaterialApp` (and thus the
/// `Navigator`) for whichever one is current.
///
/// This has to be the widget that creates `M3EMaterialApp`, not a child of
/// it: `M3EMaterialApp`/`MaterialApp` builds its own `Navigator`, and any
/// route later pushed onto that `Navigator` is inserted into its `Overlay`
/// at the point where the `Navigator` itself lives in the tree - NOT as a
/// descendant of whatever screen called `Navigator.push`. So the session
/// [MultiProvider] below must wrap `M3EMaterialApp` (i.e. sit above its
/// `Navigator`), or pushed routes like `LikedSongsScreen` can't see it.
/// [repositoryOverride] / [audioEngineOverride] let tests substitute fakes
/// while exercising this exact widget instead of a hand-rolled parallel one.
class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
    required this.audioHandler,
    this.repositoryOverride,
    this.audioEngineOverride,
    this.offlineDirectoryOverride,
  });

  /// Bridges the session's [PlayerController] to the Android media
  /// notification once it exists (see [_PlaybackServiceBinding] below).
  /// Created once at app startup - tests pass a bare instance, since only
  /// `AudioService.init` (not merely constructing this class) touches a
  /// platform channel.
  final PlaybackAudioHandler audioHandler;

  final NavidromeRepository? repositoryOverride;
  final AudioEngine? audioEngineOverride;

  /// Test-only: skips path_provider's platform channel for [OfflineManager].
  final Directory? offlineDirectoryOverride;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    if (auth.isRestoring) {
      return M3EMaterialApp(
        title: 'Supwave',
        debugShowCheckedModeBanner: false,
        data: M3EThemeData.light(seedColor: kSeedColor),
        autoTheming: true,
        dynamicColoring: true,
        home: const Scaffold(body: Center(child: M3EProgressIndicator.circular())),
      );
    }

    if (!auth.isLoggedIn) {
      return M3EMaterialApp(
        title: 'Supwave',
        debugShowCheckedModeBanner: false,
        data: M3EThemeData.light(seedColor: kSeedColor),
        autoTheming: true,
        dynamicColoring: true,
        home: const LoginScreen(),
      );
    }

    return MultiProvider(
      key: ValueKey('${auth.serverUrl}#${auth.username}'),
      providers: [
        Provider<NavidromeRepository>(
          create: (_) =>
              repositoryOverride ??
              NavidromeApiRepository(
                SubsonicClient(
                  serverUrl: auth.serverUrl!,
                  username: auth.username!,
                  password: auth.password!,
                ),
              ),
        ),
        ChangeNotifierProvider<LibraryController>(
          create: (ctx) => LibraryController(ctx.read<NavidromeRepository>())..refresh(),
        ),
        ChangeNotifierProvider<PlaylistsController>(
          create: (ctx) => PlaylistsController(ctx.read<NavidromeRepository>())..loadPlaylists(),
        ),
        ChangeNotifierProvider<OfflineManager>(
          create: (ctx) => OfflineManager(ctx.read<NavidromeRepository>())
            ..init(directoryOverride: offlineDirectoryOverride),
        ),
        ChangeNotifierProvider<RootTabController>(create: (_) => RootTabController()),
        ChangeNotifierProvider<ShellVisibility>(create: (_) => ShellVisibility()),
        ChangeNotifierProvider<PlayerController>(
          create: (ctx) => PlayerController(
            ctx.read<NavidromeRepository>(),
            ctx.read<LibraryController>(),
            ctx.read<OfflineManager>(),
            audioEngine: audioEngineOverride,
          )..restoreSession(),
        ),
      ],
      // drawUnderSystemBars only matters for the authenticated app - the
      // splash/login flows are simple enough not to need edge-to-edge.
      //
      // AppShell (mini player + nav bar) is `home:` here and owns its own
      // nested Navigator - not wrapped on via `appBuilder`, which runs
      // *outside* the `M3ETheme` it's given and so can't pick up the app's
      // (dynamic-color) theme at all.
      child: _PlaybackServiceBinding(
        audioHandler: audioHandler,
        child: M3EMaterialApp(
          title: 'Supwave',
          debugShowCheckedModeBanner: false,
          data: M3EThemeData.light(seedColor: kSeedColor),
          autoTheming: true,
          dynamicColoring: true,
          drawUnderSystemBars: true,
          home: const AppShell(),
        ),
      ),
    );
  }
}

/// Connects [audioHandler] to this session's [PlayerController] for exactly
/// as long as this subtree is mounted - i.e. for exactly as long as the
/// session is logged in, since [AuthGate] recreates the whole session
/// subtree (via the `MultiProvider`'s `key`) on every login/logout.
class _PlaybackServiceBinding extends StatefulWidget {
  const _PlaybackServiceBinding({required this.audioHandler, required this.child});

  final PlaybackAudioHandler audioHandler;
  final Widget child;

  @override
  State<_PlaybackServiceBinding> createState() => _PlaybackServiceBindingState();
}

class _PlaybackServiceBindingState extends State<_PlaybackServiceBinding> {
  @override
  void initState() {
    super.initState();
    widget.audioHandler.attach(context.read<PlayerController>(), context.read<NavidromeRepository>());
    // Deferred to the first post-frame callback rather than fired directly
    // from initState: some devices/OEM Android builds don't reliably show
    // the system permission dialog if it's requested before the first
    // frame has actually rendered and the Activity has full focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_requestNotificationPermission());
    });
  }

  /// Android 13+ (API 33+) requires this to be granted at *runtime*, or the
  /// playback notification (play/pause/next/stop) never appears - silently,
  /// with no error - even though it's declared in the manifest and works
  /// fine on an emulator that already had it granted from earlier testing.
  /// Logs the outcome (check the Logs screen) since there's otherwise no
  /// visible feedback either way.
  Future<void> _requestNotificationPermission() async {
    if (!Platform.isAndroid) return;
    final current = await Permission.notification.status;
    AppLogger.instance.log('Notification permission status: $current');
    if (current.isGranted) return;

    final result = await Permission.notification.request();
    AppLogger.instance.log('Notification permission request result: $result');
    if (result.isPermanentlyDenied) {
      AppLogger.instance.log(
        'Notification permission is permanently denied - enable it manually in '
        'Android Settings > Apps > Supwave > Notifications.',
        level: LogLevel.warning,
      );
    }
  }

  @override
  void dispose() {
    widget.audioHandler.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
