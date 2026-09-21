import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../state/root_tab_controller.dart';
import '../state/shell_visibility.dart';
import '../widgets/mini_player.dart';
import 'main_player_screen.dart';
import 'root_shell.dart';

/// The persistent shell for the logged-in app: the mini player and bottom
/// nav bar, kept visible whether the current screen is [RootShell] itself or
/// a pushed screen like Playlist Detail, Artist, Album, or Settings.
///
/// This owns its own `Navigator` (all of RootShell's tabs and every screen
/// pushed on top of them live inside it) rather than wrapping the app's
/// M3EMaterialApp-level Navigator via `appBuilder`: `appBuilder` runs
/// *outside* the `M3ETheme` it wraps, so a chrome built there can't see the
/// app's dynamic-color theme at all - which is why the mini player/nav bar
/// stopped following the color scheme when they briefly lived there.
/// Nesting the Navigator here instead keeps this chrome a normal descendant
/// of `M3ETheme`, like everything else.
///
/// Tapping a nav destination always pops back to [RootShell] first (in case
/// a screen is pushed on top of it) and then selects that tab.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final ShellVisibilityObserver _shellVisibilityObserver;

  @override
  void initState() {
    super.initState();
    _shellVisibilityObserver = ShellVisibilityObserver(
      context.read<ShellVisibility>(),
      hideForRouteName: MainPlayerScreen.routeName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabController = context.watch<RootTabController>();
    final shellHidden = context.watch<ShellVisibility>().hidden;

    return Scaffold(
      body: Navigator(
        key: tabController.navigatorKey,
        observers: [_shellVisibilityObserver],
        onGenerateRoute: (settings) =>
            MaterialPageRoute(settings: settings, builder: (_) => const RootShell()),
      ),
      bottomNavigationBar: shellHidden
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MiniPlayer(),
                M3ENavigationBar(
                  selectedIndex: tabController.index,
                  onDestinationSelected: (value) {
                    tabController.navigatorKey.currentState?.popUntil((route) => route.isFirst);
                    tabController.setIndex(value);
                  },
                  destinations: const [
                    M3ENavigationBarDestination(
                      icon: Icon(M3EIcons.home),
                      label: 'Dashboard',
                    ),
                    M3ENavigationBarDestination(
                      icon: Icon(M3EIcons.search),
                      label: 'Search',
                    ),
                    M3ENavigationBarDestination(
                      icon: Icon(M3EIcons.queue_music),
                      label: 'Playlists',
                    ),
                  ],
                  autoLayout: false,
                  layout: M3ENavBarLayout.compact,
                  alignment: M3ENavBarAlignment.center,
                  wideDestinationWidth: 128,
                  labelBehavior: M3ENavBarLabelBehavior.alwaysShow,
                  iconBehavior: M3ENavBarIconBehavior.alwaysShow,
                  size: M3ENavBarSize.medium,
                  shapeFamily: M3ENavBarShapeFamily.square,
                  density: M3ENavBarDensity.regular,
                  indicatorStyle: M3ENavBarIndicatorStyle.pill,
                  safeArea: true,
                ),
              ],
            ),
    );
  }
}
