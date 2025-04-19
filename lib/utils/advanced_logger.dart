import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

enum LogLevel {
  debug,
  info,
  warning,
  error,
  critical,
}

class AdvancedLogger {
  static final AdvancedLogger _instance = AdvancedLogger._internal();
  factory AdvancedLogger() => _instance;
  AdvancedLogger._internal();

  // Session identifier for grouping logs
  static String? _sessionId;
  static String get sessionId {
    _sessionId ??= _generateSessionId();
    return _sessionId!;
  }

  static String _generateSessionId() {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    final random = DateTime.now().microsecondsSinceEpoch.toString();
    final bytes = utf8.encode('$now-$random');
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 8);
  }

  // Set minimum log level based on environment
  static LogLevel _minimumLogLevel = kDebugMode ? LogLevel.debug : LogLevel.info;

  static void setMinimumLogLevel(LogLevel level) {
    _minimumLogLevel = level;
  }

  // Log with full context
  static void log(LogLevel level, String tag, String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? data,
    bool sendToCrashlytics = false,
  }) {
    if (level.index < _minimumLogLevel.index) return;

    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());

    // Build log entry with context
    final logEntry = {
      'timestamp': timestamp,
      'session_id': sessionId,
      'level': level.toString(),
      'tag': tag,
      'message': message,
      'data': data,
    };

    // Format console output
    final levelIndicator = _getLevelIndicator(level);
    final coloredTag = _getColoredTag(tag, level);

    print('[$timestamp] $levelIndicator $coloredTag: $message');

    // If data is provided, print it on the next line
    if (data != null && data.isNotEmpty) {
      print('   └─ Data: ${_sanitizeData(data)}');
    }

    // Handle errors specifically
    if (error != null) {
      print('   └─ Error: $error');
      if (stackTrace != null) {
        print('   └─ Stack trace:\n$stackTrace');
      }

      // Send to Crashlytics in non-debug modes if requested
      if (sendToCrashlytics && !kDebugMode) {
        FirebaseCrashlytics.instance.recordError(
          error,
          stackTrace,
          reason: message,
          information: [
            'Tag: $tag',
            'Session ID: $sessionId',
            if (data != null) 'Data: ${_sanitizeData(data)}',
          ],
        );
      }
    }

    // TODO: Add remote logging storage here if needed
  }

  // Sanitize sensitive data before logging
  static Map<String, dynamic> _sanitizeData(Map<String, dynamic> data) {
    final sanitized = Map<String, dynamic>.from(data);

    // List of keys containing sensitive information
    const sensitiveKeys = [
      'password', 'token', 'secret', 'apiKey', 'key', 'credential',
      'auth', 'email', 'phone', 'address', 'user', 'account'
    ];

    sanitized.forEach((key, value) {
      // Check if this key might contain sensitive data
      bool isSensitive = sensitiveKeys.any((k) =>
          key.toLowerCase().contains(k.toLowerCase()));

      if (isSensitive && value is String) {
        if (key.toLowerCase().contains('email')) {
          // Mask email as username@***
          final parts = value.split('@');
          if (parts.length > 1) {
            sanitized[key] = '${parts[0]}@***';
          } else {
            sanitized[key] = '***';
          }
        } else {
          // Mask other sensitive data
          sanitized[key] = value.isEmpty ? '***' :
          '${value.substring(0, 1)}***${value.length > 5 ? value.substring(value.length - 1) : ''}';
        }
      } else if (value is Map) {
        // Recursively sanitize nested maps
        sanitized[key] = _sanitizeData(Map<String, dynamic>.from(value));
      }
    });

    return sanitized;
  }

  // Console formatting helpers
  static String _getLevelIndicator(LogLevel level) {
    switch (level) {
      case LogLevel.debug: return '\x1B[90m🔍\x1B[0m'; // Gray magnifying glass
      case LogLevel.info: return '\x1B[32m✓\x1B[0m';   // Green checkmark
      case LogLevel.warning: return '\x1B[33m⚠\x1B[0m'; // Yellow warning
      case LogLevel.error: return '\x1B[31m✗\x1B[0m';  // Red X
      case LogLevel.critical: return '\x1B[41m\x1B[37m❗\x1B[0m'; // White on red background
    }
  }

  static String _getColoredTag(String tag, LogLevel level) {
    String color;
    switch (level) {
      case LogLevel.debug: color = '\x1B[90m'; break;  // Gray
      case LogLevel.info: color = '\x1B[36m'; break;   // Cyan
      case LogLevel.warning: color = '\x1B[33m'; break; // Yellow
      case LogLevel.error: color = '\x1B[31m'; break;  // Red
      case LogLevel.critical: color = '\x1B[35m'; break; // Purple
    }
    return '$color$tag\x1B[0m';
  }

  // Convenience methods
  static void debug(String tag, String message, {Map<String, dynamic>? data}) {
    log(LogLevel.debug, tag, message, data: data);
  }

  static void info(String tag, String message, {Map<String, dynamic>? data}) {
    log(LogLevel.info, tag, message, data: data);
  }

  static void warning(String tag, String message, {
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(LogLevel.warning, tag, message, data: data, error: error, stackTrace: stackTrace);
  }

  static void error(String tag, String message, {
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
    bool sendToCrashlytics = true,
  }) {
    log(LogLevel.error, tag, message,
      data: data,
      error: error,
      stackTrace: stackTrace,
      sendToCrashlytics: sendToCrashlytics,
    );
  }

  static void critical(String tag, String message, {
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(LogLevel.critical, tag, message,
      data: data,
      error: error,
      stackTrace: stackTrace,
      sendToCrashlytics: true,
    );
  }
}