import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';

/// Cover art tile. Renders the real image from Navidrome's `getCoverArt`
/// when [coverUrl] is given; otherwise (or while it's loading / on error)
/// falls back to a gradient deterministically derived from [seed] (e.g. a
/// song/album/artist/playlist id) so placeholders stay stable and distinct.
class AlbumArt extends StatelessWidget {
  const AlbumArt({
    super.key,
    this.coverUrl,
    this.seed,
    this.size,
    this.borderRadius = 12,
    this.iconScale = 0.4,
  }) : assert(coverUrl != null || seed != null, 'Provide coverUrl and/or seed');

  final String? coverUrl;
  final String? seed;
  final double? size;
  final double borderRadius;
  final double iconScale;

  /// Drops the Subsonic auth params (`u`/`t`/`s`/`v`/`c`) from [url], which
  /// change on every app launch, keeping only what actually identifies the
  /// image (server, endpoint, cover id, size) - a stable key that still
  /// matches across restarts, unlike the raw authenticated URL.
  String _stableCacheKey(String url) {
    final uri = Uri.parse(url);
    const authParams = {'u', 't', 's', 'v', 'c'};
    final stableParams = Map<String, String>.fromEntries(
      uri.queryParameters.entries.where((e) => !authParams.contains(e.key)),
    );
    return uri.replace(queryParameters: stableParams).toString();
  }

  List<Color> _fallbackColors() {
    final hash = (seed ?? coverUrl ?? '').hashCode;
    final hue = (hash % 360).abs().toDouble();
    return [
      HSLColor.fromAHSL(1, hue, 0.5, 0.42).toColor(),
      HSLColor.fromAHSL(1, (hue + 45) % 360, 0.55, 0.62).toColor(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = size ?? constraints.maxWidth;
          final fallback = _FallbackTile(
            colors: _fallbackColors(),
            borderRadius: borderRadius,
            iconSize: side * iconScale,
          );

          if (coverUrl == null) return fallback;

          return ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            // Disk + memory cached: repeat views of the same cover (e.g.
            // scrolling a list back into view, or the same album shown on
            // the dashboard and its detail page) don't re-hit the server.
            //
            // cacheKey strips the session's auth token/salt from the URL,
            // since SubsonicClient generates a fresh one on every app
            // launch: without this, the same cover would get a new URL
            // (and thus a fresh, unmatched cache entry) every cold start,
            // even though the underlying image on disk hasn't changed.
            child: CachedNetworkImage(
              imageUrl: coverUrl!,
              cacheKey: _stableCacheKey(coverUrl!),
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (context, url) => fallback,
              errorWidget: (context, url, error) => fallback,
            ),
          );
        },
      ),
    );
  }
}

class _FallbackTile extends StatelessWidget {
  const _FallbackTile({required this.colors, required this.borderRadius, required this.iconSize});

  final List<Color> colors;
  final double borderRadius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: Colors.white.withValues(alpha: 0.85),
        size: iconSize,
      ),
    );
  }
}
