import 'package:flutter/widgets.dart';

/// Which of [RootShell]'s tabs is selected. Lives above [RootShell] (in the
/// session's provider tree) so the persistent bottom nav bar in [AppShell]
/// - which is not a descendant of [RootShell] - can read and change it too.
class RootTabController extends ChangeNotifier {
  int _index = 0;

  int get index => _index;

  void setIndex(int value) {
    if (_index == value) return;
    _index = value;
    notifyListeners();
  }

  /// The app's single `Navigator`. [AppShell] sits above it (it wraps the
  /// Navigator via `appBuilder`), so `Navigator.of(context)` from inside
  /// [AppShell] itself has no Navigator ancestor to find - this key reaches
  /// it directly instead, e.g. to pop back to [RootShell] on a nav bar tap.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}
