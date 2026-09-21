import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/album.dart';
import '../models/song.dart';
import '../navidrome/navidrome_repository.dart';
import '../state/auth_controller.dart';
import '../state/library_controller.dart';
import '../state/player_controller.dart';
import '../widgets/album_art.dart';
import 'album_screen.dart';
import 'logs_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  void _showProfilePopup(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colorScheme = theme.colorScheme;
    final typography = theme.typography;
    final auth = context.read<AuthController>();
    final library = context.read<LibraryController>();

    M3EBottomSheet.show<void>(
      context,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Account card.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: AlbumArt(
                        seed: auth.username ?? 'user',
                        borderRadius: 999,
                        iconScale: 0.5,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            auth.username ?? '',
                            style: typography.emphasized.titleLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            auth.serverUrl ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: typography.baseline.bodyMedium.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Info rows.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: M3ECard(
                  variant: M3ECardVariant.outlined,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      const _ProfileStatRow(
                        icon: M3EIcons.info,
                        label: 'App version',
                        value: '1.0.0 (1)',
                      ),
                      const M3EDivider(),
                      _ProfileStatRow(
                        icon: M3EIcons.dns,
                        label: 'Server URL',
                        value: auth.serverUrl ?? '',
                      ),
                      const M3EDivider(),
                      _ProfileStatRow(
                        icon: M3EIcons.music_note,
                        label: 'Total songs',
                        value: '${library.totalSongCount}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                child: M3ECardList(
                  variant: M3ECardVariant.filled,
                  itemCount: 3,
                  onTap: (index) {
                    // M3EBottomSheet.show uses showGeneralDialog, which
                    // (unlike showModalBottomSheet) pushes onto the *root*
                    // navigator by default - so closing it here must target
                    // that same root navigator explicitly. AppShell's own
                    // nested navigator (the default `Navigator.of(context)`
                    // target, which hosts RootShell/Settings/Logs) must stay
                    // untouched, or popping it here would pop RootShell's
                    // own route off instead of the sheet.
                    Navigator.of(context, rootNavigator: true).pop();
                    if (index == 0) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    } else if (index == 1) {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LogsScreen()),
                      );
                    } else if (index == 2) {
                      context.read<AuthController>().logout();
                    }
                  },
                  itemBuilder: (context, index) {
                    const labels = ['Settings', 'Logs', 'Sign out'];
                    const icons = [
                      M3EIcons.settings,
                      M3EIcons.article,
                      M3EIcons.logout,
                    ];
                    return M3EListItem(
                      leading: Icon(icons[index]),
                      headline: labels[index],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlayerController>();
    final library = context.watch<LibraryController>();
    final typography = M3ETheme.of(context).typography;
    final colorScheme = M3ETheme.of(context).colorScheme;

    return SafeArea(
      child: M3ERefreshIndicator(
        onRefresh: library.refresh,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _greeting(),
                        style: typography.emphasized.headlineSmall,
                      ),
                    ),
                    M3EIconButton(
                      icon: const Icon(M3EIcons.person),
                      variant: M3EIconButtonVariant.tonal,
                      onPressed: () => _showProfilePopup(context),
                    ),
                  ],
                ),
              ),
            ),
            if (library.loading && library.quickPicks.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: M3EProgressIndicator.circular()),
                ),
              )
            else if (library.error != null && library.quickPicks.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(
                        'Could not load your library',
                        style: typography.baseline.bodyMedium.copyWith(
                          color: colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                      M3EButton(
                        onPressed: library.refresh,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 64,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final song = library.quickPicks[index];
                    return _QuickPickTile(
                      song: song,
                      // Each quick pick is an unrelated random suggestion, not
                      // part of a set the user meant to listen through - so
                      // picking one just plays that song, instead of queuing
                      // up the rest of the (unrelated) random batch behind it.
                      onTap: () => controller.playSingle(song),
                    );
                  }, childCount: library.quickPicks.length),
                ),
              ),
              const _SectionHeader(title: 'Recently added'),
              SliverToBoxAdapter(
                child: _AlbumRow(albums: library.newestAlbums),
              ),
              const _SectionHeader(title: 'Recently played'),
              SliverToBoxAdapter(
                child: _AlbumRow(albums: library.recentAlbums),
              ),
              const _SectionHeader(title: 'Jump back in'),
              SliverToBoxAdapter(
                child: _AlbumRow(albums: library.frequentAlbums),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _ProfileStatRow extends StatelessWidget {
  const _ProfileStatRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(label, style: theme.typography.baseline.bodyMedium),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.emphasized.labelLarge,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          title,
          style: M3ETheme.of(context).typography.emphasized.titleLarge,
        ),
      ),
    );
  }
}

class _QuickPickTile extends StatelessWidget {
  const _QuickPickTile({required this.song, required this.onTap});

  final Song song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<NavidromeRepository>();
    return M3ECard(
      variant: M3ECardVariant.filled,
      onPressed: onTap,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: AlbumArt(
              coverUrl: song.coverArtId != null
                  ? repo.coverArtUrl(song.coverArtId!, size: 150)
                  : null,
              seed: song.albumId.isNotEmpty ? song.albumId : song.id,
              borderRadius: 0,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              song.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: M3ETheme.of(context).typography.emphasized.labelLarge,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _AlbumRow extends StatelessWidget {
  const _AlbumRow({required this.albums});

  final List<Album> albums;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return const SizedBox(height: 190);
    }
    final repo = context.read<NavidromeRepository>();
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: albums.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final album = albums[index];
          final typography = M3ETheme.of(context).typography;
          return SizedBox(
            width: 140,
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AlbumScreen(albumId: album.id),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AlbumArt(
                    coverUrl: album.coverArtId != null
                        ? repo.coverArtUrl(album.coverArtId!, size: 300)
                        : null,
                    seed: album.id,
                    borderRadius: 16,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typography.emphasized.labelLarge,
                  ),
                  Text(
                    album.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typography.baseline.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
