import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../state/playlists_controller.dart';

/// Bottom sheet listing every playlist so [song] can be added to one.
/// Shared by the player's "..." menu and the per-song context menu on
/// Playlist / Album / Artist screens.
void showAddToPlaylistSheet(BuildContext context, Song song) {
  M3EBottomSheet.show<void>(
    context,
    builder: (sheetContext) {
      return Consumer<PlaylistsController>(
        builder: (context, playlistsController, _) {
          final playlists = playlistsController.playlists;
          final colorScheme = M3ETheme.of(context).colorScheme;

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  M3ECardList(
                    variant: M3ECardVariant.filled,
                    itemCount: playlists.length,
                    onTap: (index) async {
                      final playlist = playlists[index];
                      final added = await playlistsController.addSongToPlaylist(playlist.id, song);
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      M3ESnackbar.show(
                        context,
                        message: added
                            ? 'Added "${song.title}" to ${playlist.name}'
                            : '"${song.title}" is already in ${playlist.name}',
                      );
                    },
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      final alreadyAdded = playlistsController.isSongInPlaylist(
                        playlist.id,
                        song,
                      );
                      return M3EListItem(
                        leading: const Icon(M3EIcons.queue_music),
                        headline: playlist.name,
                        supportingText: '${playlist.songCount} songs',
                        trailing: alreadyAdded
                            ? Icon(M3EIcons.check_circle, color: colorScheme.primary)
                            : null,
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
