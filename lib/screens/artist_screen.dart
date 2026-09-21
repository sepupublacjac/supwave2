import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/artist.dart';
import '../models/song.dart';
import '../navidrome/navidrome_repository.dart';
import '../state/player_controller.dart';
import '../widgets/album_art.dart';
import '../widgets/song_tile.dart';
import 'album_screen.dart';

class _ArtistPageData {
  const _ArtistPageData(this.artist, this.songs);

  final Artist artist;

  /// Every song across the artist's albums, fetched from the individual
  /// album details since Subsonic's `getArtist` only returns album
  /// metadata (no flat song list).
  final List<Song> songs;
}

class ArtistScreen extends StatefulWidget {
  const ArtistScreen({super.key, required this.artistId});

  final String artistId;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  late final Future<_ArtistPageData> _future = _load();

  Future<_ArtistPageData> _load() async {
    final repo = context.read<NavidromeRepository>();
    final artist = await repo.getArtistDetail(widget.artistId);
    final albumDetails = await Future.wait(artist.albums.map((a) => repo.getAlbumDetail(a.id)));
    final songs = albumDetails.expand((a) => a.songs).toList();
    return _ArtistPageData(artist, songs);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlayerController>();
    final repo = context.read<NavidromeRepository>();
    final colorScheme = M3ETheme.of(context).colorScheme;
    final typography = M3ETheme.of(context).typography;

    return Scaffold(
      body: FutureBuilder<_ArtistPageData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: M3EProgressIndicator.circular());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load artist: ${snapshot.error}'));
          }

          final artist = snapshot.data!.artist;
          final songs = snapshot.data!.songs;
          final coverUrl = artist.coverArtId != null
              ? repo.coverArtUrl(artist.coverArtId!, size: 300)
              : null;
          final albums = artist.albums;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 260,
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
                              width: 96,
                              height: 96,
                              child: AlbumArt(coverUrl: coverUrl, seed: artist.id, borderRadius: 999),
                            ),
                            const SizedBox(height: 12),
                            Text(artist.name, style: typography.emphasized.headlineMedium),
                            const SizedBox(height: 4),
                            Text(
                              '${albums.length} albums · ${songs.length} songs',
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
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text('Albums', style: typography.emphasized.titleLarge),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 190,
                  child: albums.isEmpty
                      ? Center(
                          child: Text(
                            'No albums found',
                            style: typography.baseline.bodyMedium.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: albums.length,
                          separatorBuilder: (context, index) => const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final album = albums[index];
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
                                      '${album.songCount} songs',
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
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('All songs', style: typography.emphasized.titleLarge),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: SongTile(
                    songs: songs,
                    showAlbum: true,
                    onSongTap: (index) => controller.playQueue(songs, startIndex: index),
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
