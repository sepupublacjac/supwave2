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
      final response = await _http
          .get(Uri.parse(_repo.streamUrl(song.id)))
          .timeout(const Duration(minutes: 5));
      if (response.statusCode != 200) {
        throw Exception('Server returned HTTP ${response.statusCode}');
      }
      await File('${_dir!.path}/${song.id}').writeAsBytes(response.bodyBytes);
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
