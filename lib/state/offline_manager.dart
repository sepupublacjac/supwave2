import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../navidrome/navidrome_repository.dart';
import 'app_logger.dart';

/// Downloads songs to app-private storage so they can play back without a
/// network connection, and tracks which ones are already available.
class OfflineManager extends ChangeNotifier {
  OfflineManager(this._repo, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  static const _kDownloadedIds = 'offline_downloaded_song_ids';

  /// How long to wait for the server to start responding, and then for each
  /// next chunk of audio. There is deliberately no cap on the total download
  /// time: a large lossless file on a slow connection is legitimately slow,
  /// it just must keep making progress.
  static const _connectTimeout = Duration(seconds: 60);
  static const _stalledTimeout = Duration(seconds: 60);

  final NavidromeRepository _repo;
  final http.Client _http;

  Directory? _dir;
  final Set<String> _downloadedIds = {};
  final Set<String> _downloadingIds = {};

  bool get isReady => _dir != null;
  int get downloadedCount => _downloadedIds.length;

  bool isDownloaded(String songId) => _downloadedIds.contains(songId);
  bool isDownloading(String songId) => _downloadingIds.contains(songId);

  String? localPathFor(String songId) =>
      isDownloaded(songId) ? '${_dir!.path}/$songId' : null;

  /// Resolves the offline storage directory and reconciles it against the
  /// previously-downloaded id list (dropping any that no longer have a file
  /// on disk). Pass [directoryOverride] in tests to avoid touching
  /// path_provider's platform channel.
  Future<void> init({Directory? directoryOverride}) async {
    if (directoryOverride != null) {
      _dir = directoryOverride;
    } else {
      final docs = await getApplicationDocumentsDirectory();
      _dir = Directory('${docs.path}/offline_songs');
    }
    if (!await _dir!.exists()) {
      await _dir!.create(recursive: true);
    }

    // A download interrupted by the app being killed leaves a half-written
    // `.part` file behind. It can never be played (only finished files are
    // renamed into place), so just reclaim the space.
    await for (final entity in _dir!.list()) {
      if (entity is File && entity.path.endsWith('.part')) {
        await entity.delete();
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final savedIds = prefs.getStringList(_kDownloadedIds) ?? const [];
    for (final id in savedIds) {
      if (await File('${_dir!.path}/$id').exists()) {
        _downloadedIds.add(id);
      }
    }
    if (_downloadedIds.length != savedIds.length) {
      await prefs.setStringList(_kDownloadedIds, _downloadedIds.toList());
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kDownloadedIds, _downloadedIds.toList());
  }

  Future<void> download(Song song) async {
    if (!isReady || _downloadedIds.contains(song.id) || _downloadingIds.contains(song.id)) {
      return;
    }
    _downloadingIds.add(song.id);
    notifyListeners();

    try {
      await _fetchToDisk(song);
      _downloadedIds.add(song.id);
      await _persist();
      AppLogger.instance.log('Downloaded "${song.title}" for offline playback');
    } catch (e) {
      AppLogger.instance.log('Failed to download "${song.title}": $e', level: LogLevel.error);
    } finally {
      _downloadingIds.remove(song.id);
      notifyListeners();
    }
  }

  /// Streams [song] straight to disk instead of buffering it: `http.get`
  /// holds the whole response in memory (and `writeAsBytes` then makes
  /// another copy), which peaked at ~4x the file size - roughly 250 MB of
  /// extra memory for a 64 MB lossless track.
  ///
  /// Written to `<id>.part` and renamed into place only once complete, so a
  /// failed, truncated or killed download never leaves a file that looks
  /// finished (and is later played as a corrupt track).
  Future<void> _fetchToDisk(Song song) async {
    final target = File('${_dir!.path}/${song.id}');
    final partial = File('${target.path}.part');

    final request = http.Request('GET', Uri.parse(_repo.streamUrl(song.id)));
    final response = await _http.send(request).timeout(_connectTimeout);
    if (response.statusCode != 200) {
      await response.stream.drain<void>(); // release the connection
      throw Exception('Server returned HTTP ${response.statusCode}');
    }

    final sink = partial.openWrite();
    try {
      await sink.addStream(response.stream.timeout(_stalledTimeout));
      await sink.close();
      final expected = response.contentLength;
      final written = await partial.length();
      if (expected != null && written != expected) {
        throw Exception('Download was cut short ($written of $expected bytes)');
      }
      await partial.rename(target.path);
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {
        // Already failed; the original error below is the one that matters.
      }
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  Future<void> remove(Song song) async {
    if (!isReady || !_downloadedIds.contains(song.id)) return;
    final file = File('${_dir!.path}/${song.id}');
    if (await file.exists()) {
      await file.delete();
    }
    _downloadedIds.remove(song.id);
    await _persist();
    AppLogger.instance.log('Removed offline download for "${song.title}"');
    notifyListeners();
  }

  Future<void> removeAll() async {
    if (!isReady) return;
    for (final id in List.of(_downloadedIds)) {
      final file = File('${_dir!.path}/$id');
      if (await file.exists()) {
        await file.delete();
      }
    }
    _downloadedIds.clear();
    await _persist();
    AppLogger.instance.log('Removed all offline downloads');
    notifyListeners();
  }
}
