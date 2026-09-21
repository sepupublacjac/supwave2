import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../state/library_controller.dart';
import '../state/player_controller.dart';
import '../widgets/song_tile.dart';

/// Navidrome's starred tracks (`getStarred2`), presented like a playlist.
/// There's no real playlist behind it, so there's no "remove from playlist"
/// action here - use the like/heart toggle instead.
class LikedSongsScreen extends StatelessWidget {
  const LikedSongsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final controller = context.read<PlayerController>();
    final colorScheme = M3ETheme.of(context).colorScheme;
    final typography = M3ETheme.of(context).typography;
    final songs = library.likedSongs;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          M3EAppBar.sliver(
            titleText: 'Liked Songs',
            variant: M3EAppBarVariant.small,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  M3EButton.icon(
                    onPressed: songs.isEmpty
                        ? null
                        : () => controller.playQueue(songs),
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
          if (songs.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'Songs you like will show up here',
                    style: typography.baseline.bodyMedium.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: SongTile(
                  songs: songs,
                  showAlbum: true,
                  onSongTap: (index) =>
                      controller.playQueue(songs, startIndex: index),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
