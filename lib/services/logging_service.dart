import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

/// Logging service that writes to file and provides in-memory access
class LoggingService extends ChangeNotifier {
  final List<LogEntry> _logs = [];
  File? _logFile;
  bool _initialized = false;

  List<LogEntry> get logs => List.unmodifiable(_logs);
  bool get initialized => _initialized;

  /// Initialize the logging service
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final logDir = Directory(p.join(appDir.path, 'audiobook_validator', 'logs'));
      await logDir.create(recursive: true);

      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      _logFile = File(p.join(logDir.path, 'scan_$dateStr.log'));
      
      _initialized = true;
      info('Logging service initialized');
    } catch (e) {
      debugPrint('Failed to initialize logging: $e');
    }
  }

  /// Log an info message
  void info(String message) {
    _log(LogLevel.info, message);
  }

  /// Log a warning message
  void warning(String message) {
    _log(LogLevel.warning, message);
  }

  /// Log an error message
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    final fullMessage = error != null ? '$message: $error' : message;
    _log(LogLevel.error, fullMessage);
    if (stackTrace != null) {
      _log(LogLevel.error, stackTrace.toString());
    }
  }

  /// Log a debug message
  void debug(String message) {
    _log(LogLevel.debug, message);
  }

  /// Internal logging method
  void _log(LogLevel level, String message) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
    );

    _logs.add(entry);
    
    // Keep only last 10000 entries in memory
    if (_logs.length > 10000) {
      _logs.removeRange(0, _logs.length - 10000);
    }

    // Write to file
    _writeToFile(entry);
    
    // Debug print
    debugPrint('[${entry.levelString}] $message');
    
    notifyListeners();
  }

  /// Write log entry to file
  Future<void> _writeToFile(LogEntry entry) async {
    if (_logFile == null) return;

    try {
      await _logFile!.writeAsString(
        '${entry.formattedLine}\n',
        mode: FileMode.append,
      );
    } catch (e) {
      debugPrint('Failed to write log: $e');
    }
  }

  /// Clear in-memory logs
  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  /// Get logs filtered by level
  List<LogEntry> getLogsByLevel(LogLevel level) {
    return _logs.where((l) => l.level == level).toList();
  }

  /// Get log file path
  String? get logFilePath => _logFile?.path;

  /// Export logs to a file
  Future<String?> exportLogs(String outputPath) async {
    try {
      final buffer = StringBuffer();
      for (final log in _logs) {
        buffer.writeln(log.formattedLine);
      }
      
      final file = File(outputPath);
      await file.writeAsString(buffer.toString());
      return file.path;
    } catch (e) {
      error('Failed to export logs', e);
      return null;
    }
  }
}

/// Log level enumeration
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// A single log entry
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  String get levelString {
    switch (level) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
    }
  }

  String get formattedTimestamp {
    return DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(timestamp);
  }

  String get formattedLine {
    return '[$formattedTimestamp] [$levelString] $message';
  }
}
