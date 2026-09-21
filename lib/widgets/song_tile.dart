import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../navidrome/navidrome_repository.dart';
import '../state/player_controller.dart';
import 'album_art.dart';
import 'song_context_menu_button.dart';

/// A list of songs rendered as a filled [M3ECardList] (grouped rows with
/// dynamic corner rounding), replacing a plain [SliverList] of loose tiles.
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.songs,
    required this.onSongTap,
    this.showAlbum = false,
    this.playlistId,
  });

  final List<Song> songs;
  final ValueChanged<int> onSongTap;
  final bool showAlbum;

  /// When set, each row's context menu offers "Remove from playlist" for
  /// this playlist's id (used on the playlist detail screen).
  final String? playlistId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlayerController>();
    final repo = context.read<NavidromeRepository>();
    final colorScheme = M3ETheme.of(context).colorScheme;
    final typography = M3ETheme.of(context).typography;

    return M3ECardList(
      variant: M3ECardVariant.filled,
      itemCount: songs.length,
      onTap: onSongTap,
      itemBuilder: (context, index) {
        final song = songs[index];
        final isCurrent = controller.currentSong?.id == song.id;

        return M3EListItem(
          leading: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              children: [
                AlbumArt(
                  coverUrl: song.coverArtId != null
                      ? repo.coverArtUrl(song.coverArtId!, size: 96)
                      : null,
                  seed: song.albumId.isNotEmpty ? song.albumId : song.id,
                  borderRadius: 8,
                ),
                if (isCurrent)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.black.withValues(alpha: 0.45),
                      ),
                      child: Icon(M3EIcons.graphic_eq, color: Colors.white, size: 20),
                    ),
                  ),
              ],
            ),
          ),
          headline: song.title,
          supportingText: showAlbum
              ? '${song.artist} • ${song.album}'
              : song.artist,
          selected: isCurrent,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (controller.isLiked(song))
                Icon(M3EIcons.favorite, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(song.durationLabel, style: typography.baseline.bodySmall),
              SongContextMenuButton(song: song, playlistId: playlistId),
            ],
          ),
        );
      },
    );
  }
}
