import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../navidrome/navidrome_repository.dart';
import '../state/offline_manager.dart';
import '../state/player_controller.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/album_art.dart';
import '../widgets/offline_actions.dart';
import 'album_screen.dart';
import 'artist_screen.dart';

class MainPlayerScreen extends StatelessWidget {
  const MainPlayerScreen({super.key});

  /// Marks this route so [ShellVisibilityObserver] can hide the persistent
  /// mini player/nav bar while the full player is open - showing the mini
  /// player underneath the screen it expands from would be redundant.
  static const routeName = '/player';

  static Route<void> route() {
    return PageRouteBuilder(
      settings: const RouteSettings(name: routeName),
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) =>
          const MainPlayerScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colorScheme = theme.colorScheme;
    final typography = theme.typography;
    final controller = context.watch<PlayerController>();
    final offline = context.watch<OfflineManager>();
    final repo = context.read<NavidromeRepository>();
    final song = controller.currentSong;

    if (song == null) {
      return const Scaffold(body: Center(child: Text('Nothing playing')));
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          // Scrollable, and the artwork is sized by width rather than by
          // whatever vertical space is left: this screen's available height
          // can briefly shrink by a few pixels while the persistent app
          // shell (mini player/nav bar) is transitioning in or out around
          // it, and a fixed Expanded-based layout would hard-overflow
          // during that one frame instead of just scrolling.
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    M3EIconButton(
                      icon: const Icon(M3EIcons.keyboard_arrow_down),
                      onPressed: () => Navigator.of(context).pop(),
                      variant: M3EIconButtonVariant.filled,
                      size: M3EIconButtonSize.sm,
                      shape: M3EIconButtonShapeVariant.round,
                      width: M3EIconButtonWidth.defaultWidth,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: M3ECard(
                        variant: M3ECardVariant.filled,
                        child: Column(
                          children: [
                            Text(
                              'PLAYING FROM QUEUE',
                              style: typography.baseline.labelSmall.copyWith(
                                letterSpacing: 1.2,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              song.album,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: typography.emphasized.labelMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    M3EMenu(
                      anchorBuilder: (context, open) => M3EIconButton(
                        icon: const Icon(M3EIcons.more_vert),
                        onPressed: open,
                        variant: M3EIconButtonVariant.tonal,
                        size: M3EIconButtonSize.sm,
                        shape: M3EIconButtonShapeVariant.round,
                        width: M3EIconButtonWidth.defaultWidth,
                      ),
                      children: [
                        M3EMenuEntry(
                          label: 'Add to playlist',
                          leading: const Icon(M3EIcons.playlist_add),
                          onPressed: () =>
                              showAddToPlaylistSheet(context, song),
                        ),
                        M3EMenuToggleable(
                          label: offline.isDownloading(song.id)
                              ? 'Downloading…'
                              : 'Available offline',
                          leading: const Icon(M3EIcons.download_for_offline),
                          checked: offline.isDownloaded(song.id),
                          enabled: !offline.isDownloading(song.id),
                          onChanged: (value) => setOfflineWithFeedback(
                            context,
                            offline,
                            song,
                            value,
                          ),
                        ),
                        M3EMenuEntry(
                          label: 'View album',
                          leading: const Icon(M3EIcons.album),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  AlbumScreen(albumId: song.albumId),
                            ),
                          ),
                        ),
                        M3EMenuEntry(
                          label: 'View artist',
                          leading: const Icon(M3EIcons.person),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ArtistScreen(artistId: song.artistId),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Hero(
                    tag: 'player-art',
                    child: AlbumArt(
                      coverUrl: song.coverArtId != null
                          ? repo.coverArtUrl(song.coverArtId!, size: 600)
                          : null,
                      seed: song.albumId.isNotEmpty ? song.albumId : song.id,
                      borderRadius: 42,
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: typography.emphasized.headlineSmall,
                          ),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: typography.baseline.bodyLarge.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        M3EIconButton(
                          icon: const Icon(M3EIcons.download_for_offline),
                          selectedIcon: const Icon(M3EIcons.download_done),
                          isSelected: offline.isDownloaded(song.id),
                          onPressed: offline.isDownloading(song.id)
                              ? null
                              : () => setOfflineWithFeedback(
                                  context,
                                  offline,
                                  song,
                                  !offline.isDownloaded(song.id),
                                ),
                        ),
                        M3EIconButton(
                          icon: const Icon(M3EIcons.favorite_border),
                          selectedIcon: const Icon(M3EIcons.favorite),
                          isSelected: controller.isLiked(song),
                          onPressed: () => controller.toggleLike(song),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _ProgressBar(controller: controller),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    M3EIconButton(
                      icon: const Icon(M3EIcons.skip_previous),
                      size: M3EIconButtonSize.md,
                      variant: M3EIconButtonVariant.tonal,
                      shape: M3EIconButtonShapeVariant.round,
                      width: M3EIconButtonWidth.defaultWidth,
                      onPressed: controller.previous,
                    ),
                    M3EIconButton(
                      icon: Icon(
                        controller.isPlaying
                            ? M3EIcons.pause
                            : M3EIcons.play_arrow,
                      ),
                      size: M3EIconButtonSize.lg,
                      variant: M3EIconButtonVariant.filled,
                      shape: M3EIconButtonShapeVariant.round,
                      width: M3EIconButtonWidth.defaultWidth,
                      onPressed: controller.togglePlayPause,
                    ),
                    M3EIconButton(
                      icon: const Icon(M3EIcons.skip_next),
                      size: M3EIconButtonSize.md,
                      variant: M3EIconButtonVariant.tonal,
                      shape: M3EIconButtonShapeVariant.round,
                      width: M3EIconButtonWidth.defaultWidth,
                      onPressed: controller.next,
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Center(
                  child: M3EToolbar(
                    actions: [
                      M3EToolbarAction(
                        icon: M3EIcons.shuffle,
                        active: controller.shuffle,
                        tooltip: 'Shuffle',
                        onPressed: controller.toggleShuffle,
                      ),
                      M3EToolbarAction(
                        icon: controller.repeatMode == PlayerRepeatMode.one
                            ? M3EIcons.repeat_one
                            : M3EIcons.repeat,
                        active: controller.repeatMode != PlayerRepeatMode.off,
                        tooltip: 'Repeat',
                        onPressed: controller.cycleRepeatMode,
                      ),
                      M3EToolbarAction(
                        icon: M3EIcons.queue_music,
                        tooltip: 'Queue',
                        onPressed: () => _showQueueSheet(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 42),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showQueueSheet(BuildContext context) {
    M3EBottomSheet.show<void>(
      context,
      builder: (sheetContext) {
        return SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.6,
          child: const _QueueSheetList(),
        );
      },
    );
  }
}

/// The queue bottom sheet's list content, split out from [MainPlayerScreen]
/// so it can own a [ScrollController] and auto-scroll to whichever song is
/// currently playing as soon as it's shown - otherwise a long queue always
/// opens scrolled to the top, forcing the user to hunt for the current song
/// before they can even see what's coming up next.
class _QueueSheetList extends StatefulWidget {
  const _QueueSheetList();

  @override
  State<_QueueSheetList> createState() => _QueueSheetListState();
}

class _QueueSheetListState extends State<_QueueSheetList> {
  final _scrollController = ScrollController();
  bool _didScrollToCurrent = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentIfNeeded(PlayerController controller) {
    if (_didScrollToCurrent) return;
    final queue = controller.queue;
    final currentIndex = controller.currentIndex;
    if (queue.length <= 1 || currentIndex <= 0) return;
    _didScrollToCurrent = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      // Rows aren't a fixed height, so rather than guess one, jump to the
      // same fraction through the scroll range as the current index is
      // through the queue - close enough to bring it on screen without
      // needing per-row measurement.
      final target = (currentIndex / (queue.length - 1)) * maxExtent;
      _scrollController.jumpTo(target.clamp(0, maxExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerController>(
      builder: (context, controller, _) {
        _scrollToCurrentIfNeeded(controller);
        final queue = controller.queue;
        final colorScheme = M3ETheme.of(context).colorScheme;
        final repo = context.read<NavidromeRepository>();

        // Flutter's own ReorderableListView + Dismissible, not the
        // M3E dismissible/reorder list: M3E's drag-to-reorder arms via
        // a raw pointer long-press timer that never formally competes
        // in the gesture arena, so when this list was wrapped in our
        // own SingleChildScrollView (needed since M3EDismissibleColumn
        // has no scrollable variant), the ScrollView's own drag
        // recognizer would win the arena on any real movement and
        // drag the whole sheet/list along with the row instead of
        // reordering it. ReorderableListView owns its own Scrollable
        // and is built to coexist with descendant drag handles, so it
        // doesn't have this problem.
        return ReorderableListView.builder(
          scrollController: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: queue.length,
          // onReorderItem (not the deprecated onReorder) already
          // adjusts newIndex for the removed-item shift, matching
          // PlayerController.reorderQueue's expectations below.
          onReorderItem: controller.reorderQueue,
          itemBuilder: (context, index) {
                  final song = queue[index];
                  final isCurrent = index == controller.currentIndex;
                  return Dismissible(
                    // Keyed by song id alone: fine for the common case of no
                    // duplicate songs in the queue. If the same song is
                    // queued twice, swipe/reorder may attribute the action
                    // to the wrong occurrence - a reasonable trade-off here
                    // rather than introducing a separate queue-entry id.
                    key: ValueKey(song.id),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => controller.removeFromQueue(index),
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        M3EIcons.delete,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: M3ECard(
                        variant: M3ECardVariant.filled,
                        border: isCurrent
                            ? BorderSide(color: colorScheme.primary, width: 2)
                            : null,
                        padding: EdgeInsets.zero,
                        onPressed: () =>
                            controller.playQueue(queue, startIndex: index),
                        child: M3EListItem(
                          leading: SizedBox(
                            width: 44,
                            height: 44,
                            child: Stack(
                              children: [
                                AlbumArt(
                                  coverUrl: song.coverArtId != null
                                      ? repo.coverArtUrl(
                                          song.coverArtId!,
                                          size: 96,
                                        )
                                      : null,
                                  seed: song.albumId.isNotEmpty
                                      ? song.albumId
                                      : song.id,
                                  borderRadius: 8,
                                ),
                                if (isCurrent)
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: Colors.black.withValues(
                                          alpha: 0.45,
                                        ),
                                      ),
                                      child: Icon(
                                        M3EIcons.graphic_eq,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          headline: song.title,
                          supportingText: song.artist,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(song.durationLabel),
                              const SizedBox(width: 8),
                              ReorderableDragStartListener(
                                index: index,
                                child: Icon(
                                  M3EIcons.drag_handle,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
          );
        },
      );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final song = controller.currentSong!;
    final typography = M3ETheme.of(context).typography;
    return Column(
      children: [
        M3ESlider.wavy(
          value: controller.progress,
          trackThickness: 10,
          onChanged: controller.seekTo,
          onChangeEnd: controller.seekTo,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(controller.position),
                style: typography.baseline.bodySmall,
              ),
              Text(song.durationLabel, style: typography.baseline.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
