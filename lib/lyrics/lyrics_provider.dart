import '../models/lyrics.dart';
import '../models/song.dart';

/// An internet source of lyrics, used when the user has enabled fetching
/// lyrics from the internet.
abstract class LyricsProvider {
  const LyricsProvider();

  /// Stable key stored in settings; never change it for an existing provider.
  String get id;

  /// Shown in the settings and as "Lyrics from ...".
  String get displayName;

  /// Looks up [song]. Returns null when this source has no lyrics for it
  /// (an answer), and throws when it couldn't be asked (a failure) - callers
  /// treat the two differently. [translations] asks for a translated copy
  /// where the source offers one.
  Future<Lyrics?> fetch(Song song, {bool translations = false});
}

/// The Subsonic placeholders [Song.fromJson] fills in for missing tags - not
/// real names, so they must not be sent to a lyrics service or matched on.
bool isPlaceholderArtist(String artist) => artist.isEmpty || artist == 'Unknown artist';
bool isPlaceholderAlbum(String album) => album.isEmpty || album == 'Unknown album';

/// A title or name reduced to what identifies it: lower-case letters and
/// digits only, without anything in brackets ("(Remastered)", "[Live]").
String normalizeForMatch(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[\(\[（【][^\)\]）】]*[\)\]）】]'), '')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

/// Whether two song titles are the same song: equal once normalised, or one
/// contained in the other when it's long enough that that isn't a fluke
/// ("Go" must not match "Gone").
bool titlesMatch(String a, String b) {
  final na = normalizeForMatch(a);
  final nb = normalizeForMatch(b);
  if (na.isEmpty || nb.isEmpty) return false;
  if (na == nb) return true;
  final shorter = na.length <= nb.length ? na : nb;
  final longer = identical(shorter, na) ? nb : na;
  return shorter.length >= 5 && longer.contains(shorter);
}

/// Whether [songArtist] ("Bruno Mars, Lady Gaga", "A & B", "A feat. B") shares
/// at least one artist with [candidates].
bool artistsMatch(String songArtist, Iterable<String> candidates) {
  final wanted = songArtist
      .split(RegExp(r'\s*(?:,|&|;|/|\bfeat\.?|\bft\.?|\bfeaturing\b|\bx\b|\band\b)\s*', caseSensitive: false))
      .map(normalizeForMatch)
      .where((a) => a.isNotEmpty)
      .toSet();
  wanted.add(normalizeForMatch(songArtist));
  wanted.remove('');
  for (final candidate in candidates) {
    final name = normalizeForMatch(candidate);
    if (name.isEmpty) continue;
    if (wanted.contains(name)) return true;
    for (final w in wanted) {
      if (w.length >= 4 && (name.contains(w) || w.contains(name) && name.length >= 4)) return true;
    }
  }
  return false;
}
