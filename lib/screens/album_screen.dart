import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/album.dart';
import '../navidrome/navidrome_repository.dart';
import '../state/player_controller.dart';
import '../widgets/album_art.dart';
import '../widgets/song_tile.dart';
import 'artist_screen.dart';

class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key, required this.albumId});

  final String albumId;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  late final Future<Album> _future = context.read<NavidromeRepository>().getAlbumDetail(
    widget.albumId,
  );

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlayerController>();
    final repo = context.read<NavidromeRepository>();
    final colorScheme = M3ETheme.of(context).colorScheme;
    final typography = M3ETheme.of(context).typography;

    return Scaffold(
      body: FutureBuilder<Album>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: M3EProgressIndicator.circular());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load album: ${snapshot.error}'));
          }

          final album = snapshot.data!;
          final coverUrl = album.coverArtId != null
              ? repo.coverArtUrl(album.coverArtId!, size: 600)
              : null;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 300,
                backgroundColor: colorScheme.surface,
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
                              width: 140,
                              child: AlbumArt(
                                coverUrl: coverUrl,
                                seed: album.id,
                                borderRadius: 16,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(album.name, style: typography.emphasized.headlineMedium),
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ArtistScreen(artistId: album.artistId),
                                ),
                              ),
                              child: Text(
                                '${album.artist} · ${album.songCount} songs',
                                style: typography.baseline.bodyMedium.copyWith(
                                  color: colorScheme.primary,
                                ),
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
                        onPressed: () => controller.playQueue(album.songs),
                        icon: const Icon(M3EIcons.play_arrow),
                        label: const Text('Play'),
                      ),
                      const SizedBox(width: 12),
                      M3EButton.icon(
                        style: M3EButtonStyle.outlined,
                        onPressed: () {
                          final shuffled = List.of(album.songs)..shuffle();
                          controller.playQueue(shuffled);
                        },
                        icon: const Icon(M3EIcons.shuffle),
                        label: const Text('Shuffle'),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: SongTile(
                    songs: album.songs,
                    onSongTap: (index) => controller.playQueue(album.songs, startIndex: index),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}
