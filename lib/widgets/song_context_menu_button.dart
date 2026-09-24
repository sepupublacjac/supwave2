import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../screens/album_screen.dart';
import '../screens/artist_screen.dart';
import '../state/offline_manager.dart';
import '../state/player_controller.dart';
import '../state/playlists_controller.dart';
import 'add_to_playlist_sheet.dart';
import 'offline_actions.dart';

/// The "..." context menu for a song row on Playlist / Album / Artist /
/// Search / Liked Songs screens: play next, add to queue, add to playlist,
/// (optionally) remove from the current playlist, available offline, view
/// artist, view album.
class SongContextMenuButton extends StatelessWidget {
  const SongContextMenuButton({
    super.key,
    required this.song,
    this.playlistId,
  });

  final Song song;

  /// When set, shows "Remove from playlist" for this playlist's id.
  final String? playlistId;

  @override
  Widget build(BuildContext context) {
    final playerController = context.read<PlayerController>();
    final offline = context.watch<OfflineManager>();

    return M3EMenu(
      anchorBuilder: (context, open) => M3EIconButton(
        icon: const Icon(M3EIcons.more_vert),
        onPressed: open,
      ),
      children: [
        M3EMenuEntry(
          label: 'Play next',
          leading: const Icon(M3EIcons.play_arrow),
          onPressed: () {
            playerController.playNext(song);
            M3ESnackbar.show(context, message: '"${song.title}" will play next');
          },
        ),
        M3EMenuEntry(
          label: 'Add to queue',
          leading: const Icon(M3EIcons.queue_music),
          onPressed: () {
            playerController.addToQueue(song);
            M3ESnackbar.show(context, message: 'Added "${song.title}" to queue');
          },
        ),
        M3EMenuEntry(
          label: 'Add to playlist',
          leading: const Icon(M3EIcons.playlist_add),
          onPressed: () => showAddToPlaylistSheet(context, song),
        ),
        if (playlistId != null)
          M3EMenuEntry(
            label: 'Remove from playlist',
            leading: const Icon(M3EIcons.playlist_remove),
            isDestructive: true,
            onPressed: () async {
              final playlistsController = context.read<PlaylistsController>();
              final removed = await playlistsController.removeSongFromPlaylist(playlistId!, song);
              if (removed && context.mounted) {
                M3ESnackbar.show(context, message: 'Removed "${song.title}" from playlist');
              }
            },
          ),
        M3EMenuToggleable(
          label: offline.isDownloading(song.id) ? 'Downloading…' : 'Available offline',
          leading: const Icon(M3EIcons.download_for_offline),
          checked: offline.isDownloaded(song.id),
          enabled: !offline.isDownloading(song.id),
          onChanged: (value) => setOfflineWithFeedback(context, offline, song, value),
        ),
        M3EMenuEntry(
          label: 'View artist',
          leading: const Icon(M3EIcons.person),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ArtistScreen(artistId: song.artistId)),
          ),
        ),
        M3EMenuEntry(
          label: 'View album',
          leading: const Icon(M3EIcons.album),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AlbumScreen(albumId: song.albumId)),
          ),
        ),
      ],
    );
  }
}
