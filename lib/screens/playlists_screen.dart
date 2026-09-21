import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../navidrome/navidrome_repository.dart';
import '../state/library_controller.dart';
import '../state/playlists_controller.dart';
import '../widgets/album_art.dart';
import '../widgets/playlist_dialogs.dart';
import 'liked_songs_screen.dart';
import 'playlist_detail_screen.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlaylistsController>().loadPlaylists();
    });
  }

  Future<void> _createPlaylist() async {
    final name = await showCreatePlaylistDialog(context);
    if (name == null || !mounted) return;

    final playlistsController = context.read<PlaylistsController>();
    final playlist = await playlistsController.createPlaylist(name);
    if (!mounted) return;

    if (playlist != null) {
      M3ESnackbar.show(context, message: 'Created "$name"');
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlistId: playlist.id)),
      );
    } else {
      M3ESnackbar.show(context, message: 'Could not create "$name"');
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlistsController = context.watch<PlaylistsController>();
    final library = context.watch<LibraryController>();
    final playlists = playlistsController.playlists;
    final typography = M3ETheme.of(context).typography;
    final colorScheme = M3ETheme.of(context).colorScheme;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Playlists', style: typography.emphasized.headlineSmall),
                  ),
                  M3EIconButton(
                    icon: const Icon(M3EIcons.add),
                    variant: M3EIconButtonVariant.tonal,
                    onPressed: _createPlaylist,
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverToBoxAdapter(
              child: M3ECard(
                variant: M3ECardVariant.filled,
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: colorScheme.primaryContainer,
                          ),
                          child: Icon(M3EIcons.favorite, color: colorScheme.onPrimaryContainer),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Liked Songs', style: typography.emphasized.titleMedium),
                            const SizedBox(height: 4),
                            Text(
                              '${library.likedSongs.length} songs',
                              style: typography.baseline.bodySmall.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(M3EIcons.chevron_right, color: colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (playlistsController.loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: M3EProgressIndicator.circular()),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverToBoxAdapter(
                child: M3ECardList(
                  variant: M3ECardVariant.filled,
                  itemCount: playlists.length,
                  itemBuilder: (context, index) => _PlaylistRow(playlist: playlists[index]),
                  onTap: (index) => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlaylistDetailScreen(playlistId: playlists[index].id),
                    ),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final typography = M3ETheme.of(context).typography;
    final colorScheme = M3ETheme.of(context).colorScheme;
    final repo = context.read<NavidromeRepository>();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: AlbumArt(
              coverUrl: playlist.coverArtId != null
                  ? repo.coverArtUrl(playlist.coverArtId!, size: 150)
                  : null,
              seed: playlist.id,
              borderRadius: 10,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(playlist.name, style: typography.emphasized.titleMedium),
                const SizedBox(height: 4),
                if (playlist.description.isNotEmpty)
                  Text(
                    playlist.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typography.baseline.bodySmall,
                  ),
                const SizedBox(height: 4),
                Text(
                  '${playlist.songCount} songs',
                  style: typography.baseline.bodySmall.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(M3EIcons.chevron_right, color: colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
