import 'dart:math' as math;

/// One line of a song's lyrics.
class LyricLine {
  const LyricLine(this.text, {this.start, this.translation});

  final String text;

  /// This line translated, when the source provides one (NetEase does).
  final String? translation;

  /// When this line starts, from the beginning of the track, with the
  /// lyrics' timing offset already applied. Null for unsynced lyrics.
  final Duration? start;
}

/// A song's lyrics, either timed per line (synced) or plain text.
class Lyrics {
  const Lyrics({required this.lines, required this.synced, this.language, this.source});

  /// Parses LRC text (`[mm:ss.xx]line`), the format used by lrclib.net and
  /// NetEase. Handles several time tags on one line, 1-3 fraction digits, the
  /// `[offset:ms]` header (same sign convention as OpenSubsonic: positive =
  /// sooner) and strips enhanced per-word `<mm:ss.xx>` tags. Lines come out
  /// sorted by start time. Text with no time tags at all becomes plain lyrics.
  ///
  /// [translationLrc] is an LRC of the same song in another language; each
  /// line picks up the translation that starts at the same time (or within
  /// [_translationSlack] of it).
  factory Lyrics.fromLrc(String lrc, {String? translationLrc, String? language}) {
    final lines = _parseLrc(lrc);
    if (lines.isEmpty) return Lyrics.fromPlainText(lrc);

    final translations = translationLrc == null
        ? const <({Duration start, String text})>[]
        : _parseLrc(translationLrc).where((l) => l.text.isNotEmpty).toList();

    String? translationFor(Duration start) {
      ({Duration start, String text})? best;
      var bestGap = _translationSlack + const Duration(milliseconds: 1);
      for (final candidate in translations) {
        final gap = (candidate.start - start).abs();
        if (gap < bestGap) {
          best = candidate;
          bestGap = gap;
        }
      }
      return best?.text;
    }

    return Lyrics(
      synced: true,
      language: language,
      lines: [
        for (final line in lines)
          LyricLine(
            line.text,
            start: line.start,
            translation: line.text.isEmpty ? null : translationFor(line.start),
          ),
      ],
    );
  }

  static const _translationSlack = Duration(milliseconds: 400);

  static final _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final _offsetTag = RegExp(r'^\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false, multiLine: true);
  static final _wordTag = RegExp(r'<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>');

  static List<({Duration start, String text})> _parseLrc(String lrc) {
    final offsetMs = int.tryParse(_offsetTag.firstMatch(lrc)?.group(1) ?? '') ?? 0;
    final parsed = <({Duration start, String text, int order})>[];

    for (final raw in lrc.split(RegExp(r'\r\n|\r|\n'))) {
      var rest = raw.trimLeft();
      final starts = <Duration>[];
      for (var tag = _timeTag.matchAsPrefix(rest); tag != null; tag = _timeTag.matchAsPrefix(rest)) {
        // The fraction is 1-3 digits: ".5" and ".50" are both half a second,
        // ".05" is 50 ms - so pad on the right to milliseconds.
        final fraction = int.parse((tag.group(3) ?? '').padRight(3, '0'));
        final ms = (int.parse(tag.group(1)!) * 60 + int.parse(tag.group(2)!)) * 1000 + fraction;
        starts.add(Duration(milliseconds: math.max(0, ms - offsetMs)));
        rest = rest.substring(tag.end).trimLeft();
      }
      if (starts.isEmpty) continue; // metadata such as [ar:...] or stray text

      final text = rest.replaceAll(_wordTag, '').trim();
      for (final start in starts) {
        parsed.add((start: start, text: text, order: parsed.length));
      }
    }

    // List.sort isn't stable, and lines that share a start must keep their
    // order in the file.
    parsed.sort((a, b) {
      final byTime = a.start.compareTo(b.start);
      return byTime != 0 ? byTime : a.order.compareTo(b.order);
    });
    return [for (final line in parsed) (start: line.start, text: line.text)];
  }

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

  /// Where these lyrics came from, for display (e.g. "lrclib.net"). Set by
  /// whoever looked them up; null if unknown.
  final String? source;

  Lyrics withSource(String source) =>
      Lyrics(lines: lines, synced: synced, language: language, source: source);

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
