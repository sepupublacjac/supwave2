import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../navidrome/subsonic_client.dart';
import 'app_logger.dart';

/// Holds the current Navidrome session (server URL / username / password)
/// and persists it locally so the user doesn't have to log in every launch.
///
/// The password is stored in plain text via shared_preferences, which is
/// fine for a personal test client but should move to secure storage
/// (flutter_secure_storage / Keychain / Keystore) before any real release.
class AuthController extends ChangeNotifier {
  static const _kServerUrl = 'auth_server_url';
  static const _kUsername = 'auth_username';
  static const _kPassword = 'auth_password';

  AuthController();

  /// Seeds an already-authenticated session directly, bypassing the network
  /// ping and shared_preferences round trip. Used by widget tests that mount
  /// the authenticated app surface without going through the login screen.
  @visibleForTesting
  AuthController.authenticated({
    required String serverUrl,
    required String username,
    required String password,
    // ignore: prefer_initializing_formals
  }) : _serverUrl = serverUrl,
       // ignore: prefer_initializing_formals
       _username = username,
       // ignore: prefer_initializing_formals
       _password = password,
       _isRestoring = false;

  String? _serverUrl;
  String? _username;
  String? _password;

  /// True only while the very first [restoreSession] call (app startup) is
  /// in flight. [AuthGate] uses this - and only this - to decide whether to
  /// show a splash spinner instead of the login screen, so a later [login]
  /// call (which flips [isLoading]) doesn't blow away whatever the user
  /// typed into the login form.
  bool _isRestoring = true;

  /// True while a [login] call is in flight. [LoginScreen] uses this to
  /// disable its fields and show a button spinner.
  bool _isLoading = false;
  String? _error;

  String? get serverUrl => _serverUrl;
  String? get username => _username;
  String? get password => _password;
  bool get isRestoring => _isRestoring;
  bool get isLoading => _isLoading;
  String? get error => _error;

  bool get isLoggedIn => _serverUrl != null && _username != null && _password != null;

  /// Reads a previously saved session, if any. Called once at startup.
  Future<void> restoreSession() async {
    _isRestoring = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString(_kServerUrl);
    _username = prefs.getString(_kUsername);
    _password = prefs.getString(_kPassword);

    _isRestoring = false;
    notifyListeners();
  }

  /// Verifies the given credentials against the server (via `ping`) and,
  /// on success, persists and adopts them. Returns true on success.
  Future<bool> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final client = SubsonicClient(serverUrl: serverUrl, username: username, password: password);
    try {
      await client.ping();
    } on SubsonicException catch (e) {
      _error = e.isAuthError ? 'Incorrect username or password' : e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } finally {
      client.close();
    }

    _serverUrl = client.baseUrl;
    _username = username;
    _password = password;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServerUrl, _serverUrl!);
    await prefs.setString(_kUsername, username);
    await prefs.setString(_kPassword, password);

    AppLogger.instance.log('Signed in to $_serverUrl as $username');
    _isLoading = false;
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    AppLogger.instance.log('Signed out');
    _serverUrl = null;
    _username = null;
    _password = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kServerUrl);
    await prefs.remove(_kUsername);
    await prefs.remove(_kPassword);
    notifyListeners();
  }
}
