import 'dart:async';

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../navidrome/navidrome_repository.dart';
import '../state/player_controller.dart';
import '../widgets/album_art.dart';
import '../widgets/song_tile.dart';
import 'album_screen.dart';
import 'artist_screen.dart';

/// Searches the Navidrome library by song/album/artist name. Input is
/// debounced so a call to `search3.view` only fires once the user pauses
/// typing, instead of on every keystroke.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  String? _error;
  SearchResults? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _query = '';
        _results = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(trimmed));
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _query = query;
      _loading = true;
      _error = null;
    });
    try {
      final results = await context.read<NavidromeRepository>().search(query);
      // The query may have changed again while this was in flight; drop a
      // stale response instead of clobbering a newer one.
      if (!mounted || query != _query) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || query != _query) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final typography = M3ETheme.of(context).typography;
    final colorScheme = M3ETheme.of(context).colorScheme;
    final controller = context.read<PlayerController>();
    final repo = context.read<NavidromeRepository>();
    final results = _results;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Search', style: typography.emphasized.headlineSmall),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: M3ESearchBar(
                controller: _controller,
                hintText: 'Search songs, albums, artists',
                leading: const Icon(M3EIcons.search),
                trailing: _query.isEmpty
                    ? null
                    : [
                        M3EIconButton(
                          icon: const Icon(M3EIcons.close),
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                          },
                        ),
                      ],
                onChanged: _onChanged,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          if (_query.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'Search your library by song, album, or artist',
                    textAlign: TextAlign.center,
                    style: typography.baseline.bodyMedium.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            )
          else if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: M3EProgressIndicator.circular()),
              ),
            )
          else if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Search failed: $_error',
                  style: typography.baseline.bodyMedium.copyWith(color: colorScheme.error),
                ),
              ),
            )
          else if (results == null ||
              (results.songs.isEmpty && results.albums.isEmpty && results.artists.isEmpty))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No results for "$_query"',
                    style: typography.baseline.bodyMedium.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            )
          else ...[
            if (results.artists.isNotEmpty) ...[
              const _SectionHeader(title: 'Artists'),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: M3ECardList(
                    variant: M3ECardVariant.filled,
                    itemCount: results.artists.length,
                    onTap: (index) => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ArtistScreen(artistId: results.artists[index].id),
                      ),
                    ),
                    itemBuilder: (context, index) {
                      final artist = results.artists[index];
                      return M3EListItem(
                        leading: SizedBox(
                          width: 44,
                          height: 44,
                          child: AlbumArt(
                            coverUrl: artist.coverArtId != null
                                ? repo.coverArtUrl(artist.coverArtId!, size: 96)
                                : null,
                            seed: artist.id,
                            borderRadius: 999,
                          ),
                        ),
                        headline: artist.name,
                        supportingText: '${artist.albumCount} albums',
                      );
                    },
                  ),
                ),
              ),
            ],
            if (results.albums.isNotEmpty) ...[
              const _SectionHeader(title: 'Albums'),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 190,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: results.albums.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final album = results.albums[index];
                      return SizedBox(
                        width: 140,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => AlbumScreen(albumId: album.id)),
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
                ),
              ),
            ],
            if (results.songs.isNotEmpty) ...[
              const _SectionHeader(title: 'Songs'),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: SongTile(
                    songs: results.songs,
                    showAlbum: true,
                    onSongTap: (index) => controller.playQueue(results.songs, startIndex: index),
                  ),
                ),
              ),
            ],
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
        child: Text(title, style: M3ETheme.of(context).typography.emphasized.titleLarge),
      ),
    );
  }
}
