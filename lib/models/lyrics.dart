import 'dart:math' as math;

/// One line of a song's lyrics.
class LyricLine {
  const LyricLine(this.text, {this.start});

  final String text;

  /// When this line starts, from the beginning of the track, with the
  /// lyrics' timing offset already applied. Null for unsynced lyrics.
  final Duration? start;
}

/// A song's lyrics, either timed per line (synced) or plain text.
class Lyrics {
  const Lyrics({required this.lines, required this.synced, this.language});

  /// One OpenSubsonic `structuredLyrics` entry (from `getLyricsBySongId`).
  ///
  /// Line `start` times are milliseconds from the start of the track. The
  /// entry's `offset` (also ms) is applied to every line, and per the
  /// OpenSubsonic spec a *positive* offset makes lyrics appear *sooner*, so
  /// the effective start is `start - offset` (never before zero).
  factory Lyrics.fromStructured(Map<String, dynamic> json) {
    final offset = (json['offset'] as num?)?.toInt() ?? 0;
    final rawLines = json['line'];

    final parsed = <({String text, int? startMs})>[
      if (rawLines is List)
        for (final raw in rawLines)
          if (raw is Map<String, dynamic>)
            (
              text: (raw['value'] as String?) ?? '',
              startMs: (raw['start'] as num?)?.toInt(),
            ),
    ];

    // Only trust "synced" if every line actually carries a start time;
    // otherwise highlighting would jump around, so show it as plain text.
    final synced = json['synced'] == true && parsed.isNotEmpty && parsed.every((l) => l.startMs != null);

    return Lyrics(
      synced: synced,
      language: json['lang'] as String?,
      lines: [
        for (final line in parsed)
          LyricLine(
            line.text,
            start: synced ? Duration(milliseconds: math.max(0, line.startMs! - offset)) : null,
          ),
      ],
    );
  }

  /// Plain text from the legacy `getLyrics` endpoint. Blank lines (stanza
  /// breaks) are kept, but leading/trailing ones are dropped.
  factory Lyrics.fromPlainText(String text) {
    final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n').map((l) => l.trimRight()).toList();
    while (lines.isNotEmpty && lines.first.isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return Lyrics(synced: false, lines: [for (final l in lines) LyricLine(l)]);
  }

  /// The most useful of several lyrics for the same song: synced beats
  /// unsynced, and empty ones are ignored. Null if none has any text.
  static Lyrics? pickBest(Iterable<Lyrics> candidates) {
    final usable = candidates.where((l) => !l.isEmpty).toList();
    if (usable.isEmpty) return null;
    return usable.firstWhere((l) => l.synced, orElse: () => usable.first);
  }

  final List<LyricLine> lines;
  final bool synced;

  /// Language code as reported by the server (often ISO 639, or `und`/`xxx`
  /// when unknown). Null if not reported.
  final String? language;

  bool get isEmpty => lines.every((l) => l.text.trim().isEmpty);

  /// Index of the line being sung at [position]: the last line whose start is
  /// at or before it, or -1 before the first line (or if not [synced]).
  int indexAt(Duration position) {
    if (!synced) return -1;
    var low = 0;
    var high = lines.length - 1;
    var result = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (lines[mid].start! <= position) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }
}
