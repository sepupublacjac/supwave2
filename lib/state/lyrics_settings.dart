import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lyrics/lrclib_provider.dart';
import '../lyrics/netease_provider.dart';

/// How lyrics are looked up and shown, persisted across launches.
///
/// Fetching from the internet is **off by default**: it sends each played
/// song's artist, title, album and length to third-party services, which is
/// the only thing this app ever sends anywhere but the user's own server, so
/// it has to be a choice.
class LyricsSettings extends ChangeNotifier {
  static const _kPreferLocal = 'lyrics_prefer_local';
  static const _kFetchFromInternet = 'lyrics_fetch_from_internet';
  static const _kProviders = 'lyrics_providers';
  static const _kNeteaseTranslations = 'lyrics_netease_translations';
  static const _kOffsetMs = 'lyrics_offset_ms';

  /// Every provider the app knows, in the order they're tried by default.
  static const allProviderIds = [NeteaseProvider.providerId, LrcLibProvider.providerId];

  /// Offsets beyond this are certainly a typo, and would push lyrics minutes
  /// away from the audio.
  static const maxOffsetMs = 30000;

  bool _preferLocal = true;
  bool _fetchFromInternet = false;
  List<String> _providerIds = List.of(allProviderIds);
  bool _neteaseTranslations = false;
  int _offsetMs = 0;

  /// Use lyrics from the user's server before looking on the internet (and
  /// the reverse when false).
  bool get preferLocal => _preferLocal;

  /// Look lyrics up on [providerIds] when the server doesn't supply them.
  bool get fetchFromInternet => _fetchFromInternet;

  /// The enabled internet providers, in the order they're tried.
  List<String> get providerIds => List.unmodifiable(_providerIds);

  /// Ask NetEase for translated lyrics and show them under each line.
  bool get neteaseTranslations => _neteaseTranslations;

  /// Shifts every synced line by this many milliseconds: positive shows lyrics
  /// later, negative earlier.
  int get offsetMs => _offsetMs;

  Duration get offset => Duration(milliseconds: _offsetMs);

  /// Changes whenever a setting that decides *which lyrics* a song gets
  /// changes (not the offset, which only affects display) - lets a cache know
  /// when its answers have gone stale.
  String get sourceSignature =>
      '$_preferLocal|$_fetchFromInternet|${_providerIds.join(',')}|$_neteaseTranslations';

  bool isProviderEnabled(String id) => _providerIds.contains(id);

  /// Reads the saved settings. Called once at startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _preferLocal = prefs.getBool(_kPreferLocal) ?? _preferLocal;
    _fetchFromInternet = prefs.getBool(_kFetchFromInternet) ?? _fetchFromInternet;
    _neteaseTranslations = prefs.getBool(_kNeteaseTranslations) ?? _neteaseTranslations;
    _offsetMs = (prefs.getInt(_kOffsetMs) ?? _offsetMs).clamp(-maxOffsetMs, maxOffsetMs);

    final saved = prefs.getStringList(_kProviders);
    if (saved != null) {
      // Ignore ids from a version that had providers this one doesn't know.
      _providerIds = [
        for (final id in saved)
          if (allProviderIds.contains(id)) id,
      ];
    }
    notifyListeners();
  }

  Future<void> setPreferLocal(bool value) => _set(value, _preferLocal, (v) => _preferLocal = v, _kPreferLocal);

  Future<void> setFetchFromInternet(bool value) =>
      _set(value, _fetchFromInternet, (v) => _fetchFromInternet = v, _kFetchFromInternet);

  Future<void> setNeteaseTranslations(bool value) =>
      _set(value, _neteaseTranslations, (v) => _neteaseTranslations = v, _kNeteaseTranslations);

  Future<void> setOffsetMs(int value) async {
    final clamped = math.max(-maxOffsetMs, math.min(maxOffsetMs, value));
    if (clamped == _offsetMs) return;
    _offsetMs = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kOffsetMs, clamped);
  }

  /// Turns one provider on or off. Enabling appends it, so the order of
  /// [providerIds] is the order the user picked them in.
  Future<void> setProviderEnabled(String id, bool enabled) async {
    if (!allProviderIds.contains(id) || enabled == _providerIds.contains(id)) return;
    _providerIds = enabled ? [..._providerIds, id] : _providerIds.where((p) => p != id).toList();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kProviders, _providerIds);
  }

  Future<void> _set(bool value, bool current, void Function(bool) assign, String key) async {
    if (value == current) return;
    assign(value);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}
