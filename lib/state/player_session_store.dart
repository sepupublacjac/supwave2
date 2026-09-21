import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

/// A previously-persisted playback session, as returned by
/// [PlayerSessionStore.load].
class PersistedSession {
  const PersistedSession({
    required this.queue,
    required this.currentIndex,
    required this.position,
    required this.shuffle,
    required this.repeatModeName,
  });

  final List<Song> queue;
  final int currentIndex;
  final Duration position;
  final bool shuffle;
  final String repeatModeName;
}

/// Persists the current queue/track/position to disk so the mini player
/// survives the app process being killed (backgrounded and later reclaimed,
/// or swiped away) - not just being merely backgrounded in memory.
///
/// Doesn't know about [PlayerRepeatMode] (that lives in `player_controller
/// .dart`, which would create a circular import) - the mode is round-tripped
/// as its plain enum name string instead.
class PlayerSessionStore {
  static const _key = 'player_session_v1';

  Future<void> save({
    required List<Song> queue,
    required int currentIndex,
    required Duration position,
    required bool shuffle,
    required String repeatModeName,
  }) async {
    if (queue.isEmpty || currentIndex < 0 || currentIndex >= queue.length) {
      await clear();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'queue': queue.map((s) => s.toJson()).toList(),
        'currentIndex': currentIndex,
        'positionMs': position.inMilliseconds,
        'shuffle': shuffle,
        'repeatMode': repeatModeName,
      }),
    );
  }

  Future<PersistedSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final queue = (map['queue'] as List)
          .map((e) => Song.fromJson(e as Map<String, dynamic>))
          .toList();
      if (queue.isEmpty) return null;

      final rawIndex = (map['currentIndex'] as num?)?.toInt() ?? 0;
      return PersistedSession(
        queue: queue,
        currentIndex: rawIndex.clamp(0, queue.length - 1),
        position: Duration(milliseconds: (map['positionMs'] as num?)?.toInt() ?? 0),
        shuffle: map['shuffle'] as bool? ?? false,
        repeatModeName: map['repeatMode'] as String? ?? 'off',
      );
    } catch (_) {
      // Malformed/incompatible entry from a previous app version - treat it
      // as no session rather than crashing startup.
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
