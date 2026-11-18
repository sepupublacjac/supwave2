import 'dart:async';

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/lyrics.dart';
import '../models/song.dart';
import '../state/lyrics_controller.dart';
import '../state/lyrics_settings.dart';
import '../state/player_controller.dart';

/// Opens the lyrics of whatever is playing in a bottom sheet. The sheet
/// follows the current track: if the song changes while it's open, it loads
/// the new song's lyrics.
void showLyricsSheet(BuildContext context) {
  M3EBottomSheet.show<void>(
    context,
    // By default a sheet opens at most half the screen tall and has to be
    // pulled up; lyrics are for reading, so open at full content height.
    initialValue: M3EBottomSheetValue.expanded,
    builder: (sheetContext) {
      return SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.75,
        child: const LyricsView(),
      );
    },
  );
}

/// The currently playing song's lyrics: a loading state, the lyrics (synced
/// ones highlight the current line and follow playback), or a message when
/// there are none or they couldn't be loaded.
class LyricsView extends StatelessWidget {
  const LyricsView({super.key});

  @override
  Widget build(BuildContext context) {
    final song = context.select<PlayerController, Song?>((c) => c.currentSong);
    final theme = M3ETheme.of(context);

    if (song == null) {
      return Center(
        child: Text(
          'Nothing playing',
          style: theme.typography.baseline.bodyMedium.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.emphasized.titleLarge,
              ),
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.baseline.bodyMedium.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        // Keyed by song so a track change rebuilds with a fresh lookup and a
        // fresh scroll position instead of reusing the last song's state.
        Expanded(child: _SongLyrics(key: ValueKey(song.id), song: song)),
      ],
    );
  }
}

class _SongLyrics extends StatefulWidget {
  const _SongLyrics({super.key, required this.song});

  final Song song;

  @override
  State<_SongLyrics> createState() => _SongLyricsState();
}

class _SongLyricsState extends State<_SongLyrics> {
  late Future<Lyrics?> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // A block body, not `=>`: setState asserts its callback doesn't return a
  // Future, and an arrow function would return the one being assigned.
  void _load() {
    _future = context.read<LyricsController>().lyricsFor(widget.song);
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);

    Widget message(String text, {Widget? action}) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.typography.baseline.bodyMedium.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (action != null) ...[const SizedBox(height: 16), action],
          ],
        ),
      ),
    );

    return FutureBuilder<Lyrics?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: M3EProgressIndicator.circular());
        }
        if (snapshot.hasError) {
          return message(
            'Could not load lyrics',
            action: M3EButton(
              style: M3EButtonStyle.outlined,
              onPressed: () => setState(_load),
              child: const Text('Retry'),
            ),
          );
        }
        final lyrics = snapshot.data;
        if (lyrics == null) return message('No lyrics for this song');

        final view = lyrics.synced ? _SyncedLyrics(lyrics: lyrics) : _PlainLyrics(lyrics: lyrics);
        final source = lyrics.source;
        if (source == null && !lyrics.synced) return view;
        return Column(
          children: [
            Expanded(child: view),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: source == null
                        ? const SizedBox.shrink()
                        : Text(
                            'Lyrics from $source',
                            style: theme.typography.baseline.bodySmall.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                  // Offset only matters when lines carry timestamps.
                  if (lyrics.synced) const _OffsetControl(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Lyrics without timing: just the text, scrollable.
class _PlainLyrics extends StatelessWidget {
  const _PlainLyrics({required this.lyrics});

  final Lyrics lyrics;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lyrics.lines)
            line.text.isEmpty
                ? const SizedBox(height: 20) // stanza break
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(line.text, style: theme.typography.baseline.bodyLarge),
                  ),
        ],
      ),
    );
  }
}

/// Timed lyrics: the line being sung is highlighted and kept in view as the
/// song plays, and tapping a line jumps the song to it.
///
/// Listens to [PlayerController.positionListenable] directly and only calls
/// setState when the *line* changes, not on every ~200ms position tick.
class _SyncedLyrics extends StatefulWidget {
  const _SyncedLyrics({required this.lyrics});

  final Lyrics lyrics;

  @override
  State<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends State<_SyncedLyrics> {
  /// How long auto-follow stays off after the user scrolls by hand, so it
  /// doesn't yank the view away while they're reading ahead.
  static const _followResumeDelay = Duration(seconds: 4);

  late final PlayerController _player = context.read<PlayerController>();
  late final LyricsSettings _settings = context.read<LyricsSettings>();
  late final List<GlobalKey> _lineKeys = List.generate(widget.lyrics.lines.length, (_) => GlobalKey());

  int _current = -1;
  bool _follow = true;
  Timer? _resumeFollow;

  @override
  void initState() {
    super.initState();
    _current = _lineAt(_player.position);
    _player.positionListenable.addListener(_onPosition);
    _settings.addListener(_onPosition); // the offset can change under us
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent(animate: false));
  }

  @override
  void dispose() {
    _player.positionListenable.removeListener(_onPosition);
    _settings.removeListener(_onPosition);
    _resumeFollow?.cancel();
    super.dispose();
  }

  /// The line being sung at [position], after the user's lyric offset: with a
  /// positive offset every line starts that much later, so the audio has to
  /// be that much further along to reach it.
  int _lineAt(Duration position) => widget.lyrics.indexAt(position - _settings.offset);

  void _onPosition() {
    final index = _lineAt(_player.positionListenable.value);
    if (index == _current) return;
    setState(() => _current = index);
    if (_follow) _scrollToCurrent();
  }

  void _scrollToCurrent({bool animate = true}) {
    if (!mounted || _current < 0) return;
    final lineContext = _lineKeys[_current].currentContext;
    if (lineContext == null) return;
    Scrollable.ensureVisible(
      lineContext,
      alignment: 0.35,
      duration: animate ? const Duration(milliseconds: 350) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  void _pauseFollowing() {
    _follow = false;
    _resumeFollow?.cancel();
    _resumeFollow = Timer(_followResumeDelay, () {
      if (!mounted) return;
      _follow = true;
      _scrollToCurrent();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colorScheme = theme.colorScheme;
    final lines = widget.lyrics.lines;

    return LayoutBuilder(
      builder: (context, constraints) {
        return NotificationListener<ScrollStartNotification>(
          // dragDetails is only set for a finger on the screen, not for our
          // own animated scrolling.
          onNotification: (notification) {
            if (notification.dragDetails != null) _pauseFollowing();
            return false;
          },
          child: SingleChildScrollView(
            // Room above and below so the first and last lines can still be
            // brought up to the highlighted position.
            padding: EdgeInsets.fromLTRB(24, constraints.maxHeight * 0.3, 24, constraints.maxHeight * 0.6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < lines.length; i++)
                  GestureDetector(
                    key: _lineKeys[i],
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _player.seekToPosition(lines[i].start! + _settings.offset),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 250),
                            style: i == _current
                                ? theme.typography.emphasized.headlineSmall.copyWith(color: colorScheme.primary)
                                : theme.typography.baseline.titleLarge.copyWith(
                                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                                  ),
                            child: Text(
                              // An empty timed line is a pause/instrumental gap.
                              lines[i].text.isEmpty ? '♪' : lines[i].text,
                              key: i == _current ? const ValueKey('current-lyric-line') : null,
                            ),
                          ),
                          if (lines[i].translation case final translation?)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                translation,
                                style: theme.typography.baseline.bodyLarge.copyWith(
                                  color: colorScheme.onSurfaceVariant.withValues(alpha: i == _current ? 1 : 0.55),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Nudges the global lyric offset without leaving the player: − / + step it,
/// tapping the value resets it to 0. Positive shows lyrics later.
class _OffsetControl extends StatelessWidget {
  const _OffsetControl();

  static const _step = 100;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final settings = context.watch<LyricsSettings>();
    final offset = settings.offsetMs;
    final label = '${offset > 0 ? '+' : ''}$offset ms';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        M3EIconButton(
          tooltip: 'Lyrics earlier',
          icon: const Icon(M3EIcons.remove),
          onPressed: () => settings.setOffsetMs(settings.offsetMs - _step),
        ),
        GestureDetector(
          key: const ValueKey('lyric-offset-value'),
          behavior: HitTestBehavior.opaque,
          onTap: offset == 0 ? null : () => settings.setOffsetMs(0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 64),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.typography.baseline.labelLarge.copyWith(
                color: offset == 0 ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.primary,
              ),
            ),
          ),
        ),
        M3EIconButton(
          tooltip: 'Lyrics later',
          icon: const Icon(M3EIcons.add),
          onPressed: () => settings.setOffsetMs(settings.offsetMs + _step),
        ),
      ],
    );
  }
}
