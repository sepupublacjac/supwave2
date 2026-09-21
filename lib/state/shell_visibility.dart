import 'package:flutter/widgets.dart';

/// Whether [AppShell] (the persistent mini player + bottom nav bar) should
/// currently be hidden - true while the full player screen is on top of the
/// navigation stack, since it already shows everything the mini player does.
class ShellVisibility extends ChangeNotifier {
  bool _hidden = false;

  bool get hidden => _hidden;

  void setHidden(bool value) {
    if (_hidden == value) return;
    _hidden = value;
    notifyListeners();
  }
}

/// Feeds [ShellVisibility] from the app's single `Navigator`, hiding it
/// exactly while [hideForRouteName] is pushed - and keeping it hidden for
/// anything pushed *on top* of that route (a bottom sheet or dialog opened
/// from the full player, say), since those aren't a real exit from it.
/// Only a push/pop/removal/replacement *of that route itself* changes the
/// state; unrelated routes above or below it are ignored.
class ShellVisibilityObserver extends NavigatorObserver {
  ShellVisibilityObserver(this.visibility, {required this.hideForRouteName});

  final ShellVisibility visibility;
  final String hideForRouteName;

  bool _matches(Route<dynamic>? route) => route?.settings.name == hideForRouteName;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_matches(route)) visibility.setHidden(true);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_matches(route)) visibility.setHidden(false);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_matches(route)) visibility.setHidden(false);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_matches(oldRoute) && !_matches(newRoute)) visibility.setHidden(false);
    if (_matches(newRoute)) visibility.setHidden(true);
  }
}
