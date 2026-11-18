import 'package:supwave_gen2/lyrics/lyrics_provider.dart';
import 'package:supwave_gen2/models/lyrics.dart';
import 'package:supwave_gen2/models/song.dart';

/// An in-memory [LyricsProvider]: returns [result] (null = "no lyrics") or
/// throws [error], and records how it was asked.
class FakeLyricsProvider extends LyricsProvider {
  FakeLyricsProvider(this.id, {String? displayName, this.result, this.error}) : displayName = displayName ?? id;

  @override
  final String id;

  @override
  final String displayName;

  Lyrics? result;
  Object? error;

  int calls = 0;
  final List<bool> translationFlags = [];

  @override
  Future<Lyrics?> fetch(Song song, {bool translations = false}) async {
    calls++;
    translationFlags.add(translations);
    final failure = error;
    if (failure != null) throw failure;
    return result;
  }
}
