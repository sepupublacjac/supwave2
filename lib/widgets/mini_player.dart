import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../navidrome/navidrome_repository.dart';
import '../screens/main_player_screen.dart';
import '../state/player_controller.dart';
import '../state/root_tab_controller.dart';
import 'album_art.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlayerController>();
    final repo = context.read<NavidromeRepository>();
    final song = controller.currentSong;
    final colorScheme = M3ETheme.of(context).colorScheme;

    if (song == null) return const SizedBox.shrink();

    // MiniPlayer is rendered by AppShell via M3EMaterialApp's `appBuilder`,
    // which sits above the Navigator - so `context` here has no Navigator
    // ancestor for `Navigator.of(context)` to find; go through the shared
    // key instead (see RootTabController.navigatorKey).
    final navigatorKey = context.read<RootTabController>().navigatorKey;

    return M3ECard(
      variant: M3ECardVariant.filled,
      onPressed: () => navigatorKey.currentState?.push(MainPlayerScreen.route()),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.zero,
      elevation: 0,
      clipBehavior: Clip.none,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            M3EProgressIndicator.linear(
              value: controller.progress,
              linearSize: M3EProgressIndicatorSize.s,
              strokeWidth: 2,
              color: colorScheme.primary,
              trackColor: colorScheme.surfaceContainerHighest,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Hero(
                    tag: 'player-art',
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: AlbumArt(
                        coverUrl: song.coverArtId != null
                            ? repo.coverArtUrl(song.coverArtId!, size: 96)
                            : null,
                        seed: song.albumId.isNotEmpty ? song.albumId : song.id,
                        borderRadius: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: M3ETheme.of(
                            context,
                          ).typography.emphasized.titleSmall,
                        ),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: M3ETheme.of(
                            context,
                          ).typography.baseline.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  M3EIconButton(
                    icon: Icon(
                      controller.isPlaying
                          ? M3EIcons.pause
                          : M3EIcons.play_arrow,
                    ),
                    variant: M3EIconButtonVariant.filled,
                    onPressed: controller.togglePlayPause,
                  ),
                  const SizedBox(width: 4),
                  M3EIconButton(
                    icon: const Icon(M3EIcons.skip_next),
                    variant: M3EIconButtonVariant.tonal,
                    onPressed: controller.next,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
