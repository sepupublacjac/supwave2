import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../state/root_tab_controller.dart';
import 'dashboard_screen.dart';
import 'playlists_screen.dart';
import 'search_screen.dart';

/// The 3 root tabs (Dashboard/Search/Playlists). The bottom nav bar and mini
/// player that used to live here are now part of [AppShell], since they need
/// to stay visible on pushed screens (Playlist Detail, Artist, Album,
/// Settings, ...) too - not just here.
class RootShell extends StatelessWidget {
  const RootShell({super.key});

  static const _tabs = [DashboardScreen(), SearchScreen(), PlaylistsScreen()];

  @override
  Widget build(BuildContext context) {
    final index = context.watch<RootTabController>().index;
    return IndexedStack(index: index, children: _tabs);
  }
}
