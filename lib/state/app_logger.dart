import 'package:flutter/foundation.dart';

enum LogLevel { info, warning, error }

class LogEntry {
  const LogEntry({required this.time, required this.message, required this.level});

  final DateTime time;
  final String message;
  final LogLevel level;
}

/// In-memory session log. A real client would forward these to a proper
/// logging backend; here they just back the "Logs" screen so the action
/// actually shows something instead of being a dead button.
class AppLogger extends ChangeNotifier {
  AppLogger._() {
    log('App started');
  }

  static final AppLogger instance = AppLogger._();

  final List<LogEntry> _entries = [];

  /// Newest first.
  List<LogEntry> get entries => List.unmodifiable(_entries.reversed);

  void log(String message, {LogLevel level = LogLevel.info}) {
    _entries.add(LogEntry(time: DateTime.now(), message: message, level: level));
    notifyListeners();
  }

  /// Test-only: clears everything and re-seeds the "App started" entry a
  /// fresh app process would have. [instance] is a process-wide singleton,
  /// so without this, entries logged by one test (in the same file/isolate)
  /// leak into the next one.
  void resetForTest() {
    _entries.clear();
    log('App started');
  }
}
