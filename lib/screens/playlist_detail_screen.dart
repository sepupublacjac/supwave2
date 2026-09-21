import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../navidrome/navidrome_repository.dart';
import '../state/player_controller.dart';
import '../state/playlists_controller.dart';
import '../widgets/album_art.dart';
import '../widgets/playlist_dialogs.dart';
import '../widgets/song_tile.dart';

class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlaylistsController>().loadPlaylistSongs(widget.playlistId);
    });
  }

  Future<void> _deletePlaylist(String playlistName) async {
    final confirmed = await showConfirmDeletePlaylistDialog(context, playlistName);
    if (!confirmed || !mounted) return;

    final deleted = await context.read<PlaylistsController>().deletePlaylist(widget.playlistId);
    if (!mounted) return;

    if (deleted) {
      // Shown before popping (rather than after) so it's queued on the
      // still-valid, still-mounted context here - it stays on screen once
      // we're back on the playlists list, since there's one ScaffoldMessenger
      // for the whole app.
      M3ESnackbar.show(context, message: 'Deleted "$playlistName"');
      Navigator.of(context).pop();
    } else {
      M3ESnackbar.show(context, message: 'Could not delete "$playlistName"');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlayerController>();
    final repo = context.read<NavidromeRepository>();
    final playlistsController = context.watch<PlaylistsController>();
    final playlist = playlistsController.byId(widget.playlistId);
    final colorScheme = M3ETheme.of(context).colorScheme;
    final typography = M3ETheme.of(context).typography;

    if (playlist == null) {
      return const Scaffold(body: Center(child: M3EProgressIndicator.circular()));
    }

    final songs = playlist.songs;
    final loadingSongs = playlistsController.isLoadingSongs(widget.playlistId);
    final coverUrl = playlist.coverArtId != null
        ? repo.coverArtUrl(playlist.coverArtId!, size: 600)
        : null;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
            backgroundColor: colorScheme.surface,
            actions: [
              M3EMenu(
                anchorBuilder: (context, open) => M3EIconButton(
                  icon: const Icon(M3EIcons.more_vert),
                  onPressed: open,
                ),
                children: [
                  M3EMenuEntry(
                    label: 'Delete playlist',
                    leading: const Icon(M3EIcons.delete_outline),
                    isDestructive: true,
                    onPressed: () => _deletePlaylist(playlist.name),
                  ),
                ],
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [colorScheme.surfaceContainerHighest, colorScheme.surface],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 56, 24, 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 120,
                          child: AlbumArt(coverUrl: coverUrl, seed: playlist.id, borderRadius: 16),
                        ),
                        const SizedBox(height: 12),
                        Text(playlist.name, style: typography.emphasized.headlineMedium),
                        const SizedBox(height: 4),
                        Text(
                          playlist.description.isNotEmpty
                              ? '${playlist.description} · ${playlist.songCount} songs'
                              : '${playlist.songCount} songs',
                          style: typography.baseline.bodyMedium.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  M3EButton.icon(
                    onPressed: songs.isEmpty ? null : () => controller.playQueue(songs),
                    icon: const Icon(M3EIcons.play_arrow),
                    label: const Text('Play'),
                  ),
                  const SizedBox(width: 12),
                  M3EButton.icon(
                    style: M3EButtonStyle.outlined,
                    onPressed: songs.isEmpty
                        ? null
                        : () {
                            final shuffled = List.of(songs)..shuffle();
                            controller.playQueue(shuffled);
                          },
                    icon: const Icon(M3EIcons.shuffle),
                    label: const Text('Shuffle'),
                  ),
                ],
              ),
            ),
          ),
          if (loadingSongs && songs.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: M3EProgressIndicator.circular()),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: SongTile(
                  songs: songs,
                  playlistId: playlist.id,
                  onSongTap: (index) => controller.playQueue(songs, startIndex: index),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
