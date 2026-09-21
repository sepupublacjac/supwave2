import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Thrown when the Subsonic server rejects a request or is unreachable.
class SubsonicException implements Exception {
  const SubsonicException(this.message, {this.code});

  final String message;

  /// Subsonic error code (see
  /// http://www.subsonic.org/pages/api.jsp#getLicense), when the server
  /// returned a structured error response. `40` = wrong credentials,
  /// `50` = user not authorized, etc. Null for network/transport failures.
  final int? code;

  bool get isAuthError => code == 40 || code == 41;

  @override
  String toString() => 'SubsonicException($code): $message';
}

/// Low-level client for the Subsonic API implemented by Navidrome.
///
/// Generates one random salt + md5(password + salt) token per client
/// instance (i.e. per login session) and reuses it for every request, so
/// the plaintext password is never sent over the wire (still requires
/// https to protect the token/salt pair in transit).
///
/// Reusing the same token also matters for correctness, not just for
/// avoiding wasted work: [coverArtUrl] and [streamUrl] hand out URLs that
/// get embedded in `Image`/`CachedNetworkImage` widgets and the audio
/// engine. If the token changed on every call (as it did before), the same
/// cover would resolve to a *different* URL on every rebuild - defeating
/// image caching and making the `Image` widget treat it as a brand-new
/// resource each time, which is what caused the cover art to flicker back
/// to the placeholder repeatedly during playback (every position tick
/// rebuilds the player screen, which re-reads `coverArtUrl`).
class SubsonicClient {
  SubsonicClient({
    required String serverUrl,
    required this.username,
    required this.password,
    http.Client? httpClient,
  }) : baseUrl = _normalizeServerUrl(serverUrl),
       _http = httpClient ?? http.Client();

  static const String _apiVersion = '1.16.1';
  static const String _clientName = 'Supwave';

  final String baseUrl;
  final String username;
  final String password;
  final http.Client _http;

  Map<String, String>? _cachedAuthParams;

  static String _normalizeServerUrl(String input) {
    var url = input.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  Map<String, String> _authParams({bool json = true}) {
    final base = _cachedAuthParams ??= _generateAuthParams();
    return json ? {...base, 'f': 'json'} : base;
  }

  Map<String, String> _generateAuthParams() {
    final random = Random.secure();
    final salt = List.generate(12, (_) => random.nextInt(36).toRadixString(36)).join();
    final token = md5.convert(utf8.encode('$password$salt')).toString();
    return {'u': username, 't': token, 's': salt, 'v': _apiVersion, 'c': _clientName};
  }

  Uri _buildUri(String endpoint, [Map<String, String>? extraParams]) {
    return Uri.parse(
      '$baseUrl/rest/$endpoint',
    ).replace(queryParameters: {..._authParams(), ...?extraParams});
  }

  /// Builds a fully-authenticated URL (e.g. for streaming or cover art)
  /// suitable for handing straight to a network image or audio player.
  /// Omits `f=json`, which only applies to the structured API responses.
  String buildUrl(String endpoint, [Map<String, String>? extraParams]) {
    final uri = Uri.parse(
      '$baseUrl/rest/$endpoint',
    ).replace(queryParameters: {..._authParams(json: false), ...?extraParams});
    return uri.toString();
  }

  /// Performs a GET request against [endpoint] and returns the decoded
  /// `subsonic-response` payload. Throws [SubsonicException] on any
  /// non-"ok" status or transport failure.
  Future<Map<String, dynamic>> get(
    String endpoint, [
    Map<String, String>? params,
  ]) async {
    final uri = _buildUri(endpoint, params);
    final http.Response response;
    try {
      response = await _http.get(uri).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw SubsonicException('Could not reach $baseUrl: $e');
    }

    if (response.statusCode != 200) {
      throw SubsonicException('Server returned HTTP ${response.statusCode}');
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw const SubsonicException('Server response was not valid JSON');
    }

    final payload = body['subsonic-response'] as Map<String, dynamic>?;
    if (payload == null) {
      throw const SubsonicException('Unexpected response shape');
    }
    if (payload['status'] != 'ok') {
      final error = payload['error'] as Map<String, dynamic>?;
      throw SubsonicException(
        (error?['message'] as String?) ?? 'Request failed',
        code: (error?['code'] as num?)?.toInt(),
      );
    }
    return payload;
  }

  Future<void> ping() => get('ping.view');

  String streamUrl(String songId) => buildUrl('stream.view', {'id': songId});

  String coverArtUrl(String coverArtId, {int size = 300}) =>
      buildUrl('getCoverArt.view', {'id': coverArtId, 'size': '$size'});

  void close() => _http.close();
}
