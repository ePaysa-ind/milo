import 'dart:async';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../utils/logger.dart';

/// Comprehensive error handling models for the nudge feature
///
/// This file defines error types, error models, and exceptions used throughout
/// the nudge feature to provide consistent error handling and reporting.
///
/// @version 1.0.1

/// Enum representing different types of errors that can occur in the nudge feature
/// Used for categorizing errors and determining appropriate handling strategies
enum NudgeErrorType {
  /// Error related to authentication (e.g., user not logged in)
  authenticationError,

  /// Error related to data fetching operations
  dataFetchError,

  /// Error related to data writing operations
  dataWriteError,

  /// Error related to data streams
  streamError,

  /// Error related to transactions
  transactionError,

  /// Error related to background tasks
  backgroundTaskError,

  /// Error related to notification delivery
  notificationError,

  /// Error related to audio playback
  audioPlaybackError,

  /// Error related to permissions
  permissionError,

  /// Error related to caching
  cacheError,

  /// Error related to rate limiting
  rateLimitExceeded,

  /// Error related to resource management
  resourceError,

  /// Error related to feature initialization
  initializationError,

  /// Error related to health checks
  healthCheckError,

  /// Error related to shutdown process
  shutdownError,

  /// Generic or unknown error
  unknown,
}

/// Extension methods for NudgeErrorType
extension NudgeErrorTypeExtension on NudgeErrorType {
  /// Returns a string description of the error type
  String get description {
    switch (this) {
      case NudgeErrorType.authenticationError:
        return 'Authentication Error';
      case NudgeErrorType.dataFetchError:
        return 'Data Fetch Error';
      case NudgeErrorType.dataWriteError:
        return 'Data Write Error';
      case NudgeErrorType.streamError:
        return 'Stream Error';
      case NudgeErrorType.transactionError:
        return 'Transaction Error';
      case NudgeErrorType.backgroundTaskError:
        return 'Background Task Error';
      case NudgeErrorType.notificationError:
        return 'Notification Error';
      case NudgeErrorType.audioPlaybackError:
        return 'Audio Playback Error';
      case NudgeErrorType.permissionError:
        return 'Permission Error';
      case NudgeErrorType.cacheError:
        return 'Cache Error';
      case NudgeErrorType.rateLimitExceeded:
        return 'Rate Limit Exceeded';
      case NudgeErrorType.resourceError:
        return 'Resource Error';
      case NudgeErrorType.initializationError:
        return 'Initialization Error';
      case NudgeErrorType.healthCheckError:
        return 'Health Check Error';
      case NudgeErrorType.shutdownError:
        return 'Shutdown Error';
      case NudgeErrorType.unknown:
        return 'Unknown Error';
    }
  }

  /// Returns severity level for this error type
  NudgeErrorSeverity get severity {
    switch (this) {
      case NudgeErrorType.authenticationError:
        return NudgeErrorSeverity.high;
      case NudgeErrorType.permissionError:
        return NudgeErrorSeverity.high;
      case NudgeErrorType.dataWriteError:
        return NudgeErrorSeverity.high;
      case NudgeErrorType.transactionError:
        return NudgeErrorSeverity.high;
      case NudgeErrorType.notificationError:
        return NudgeErrorSeverity.high;
      case NudgeErrorType.initializationError:
        return NudgeErrorSeverity.critical;
      case NudgeErrorType.shutdownError:
        return NudgeErrorSeverity.high;
      case NudgeErrorType.dataFetchError:
      case NudgeErrorType.streamError:
      case NudgeErrorType.backgroundTaskError:
      case NudgeErrorType.audioPlaybackError:
        return NudgeErrorSeverity.medium;
      case NudgeErrorType.cacheError:
      case NudgeErrorType.rateLimitExceeded:
      case NudgeErrorType.resourceError:
      case NudgeErrorType.healthCheckError:
        return NudgeErrorSeverity.low;
      case NudgeErrorType.unknown:
        return NudgeErrorSeverity.medium;
    }
  }

  /// Returns whether the error should be reported to analytics/crash reporting
  bool get shouldReport {
    return this.severity.level >= NudgeErrorSeverity.medium.level;
  }

  /// Returns whether the error is recoverable
  bool get isRecoverable {
    switch (this) {
      case NudgeErrorType.initializationError:
        return false; // Critical startup error
      case NudgeErrorType.authenticationError:
        return true; // Can recover by re-authenticating
      case NudgeErrorType.dataFetchError:
      case NudgeErrorType.dataWriteError:
      case NudgeErrorType.streamError:
      case NudgeErrorType.transactionError:
      case NudgeErrorType.backgroundTaskError:
      case NudgeErrorType.notificationError:
      case NudgeErrorType.audioPlaybackError:
      case NudgeErrorType.permissionError:
      case NudgeErrorType.cacheError:
      case NudgeErrorType.rateLimitExceeded:
      case NudgeErrorType.resourceError:
      case NudgeErrorType.healthCheckError:
      case NudgeErrorType.shutdownError:
      case NudgeErrorType.unknown:
        return true; // Most errors can be recovered from
    }
  }

  /// Returns the recommended retry count for this error type
  int get recommendedRetryCount {
    switch (this) {
      case NudgeErrorType.dataFetchError:
      case NudgeErrorType.dataWriteError:
      case NudgeErrorType.streamError:
      case NudgeErrorType.transactionError:
        return 3; // Network operations can be retried multiple times
      case NudgeErrorType.backgroundTaskError:
      case NudgeErrorType.notificationError:
      case NudgeErrorType.audioPlaybackError:
        return 2; // System operations can be retried a few times
      case NudgeErrorType.rateLimitExceeded:
        return 0; // Don't retry rate-limited operations immediately
      case NudgeErrorType.permissionError:
      case NudgeErrorType.authenticationError:
        return 1; // One retry after prompting user
      case NudgeErrorType.cacheError:
      case NudgeErrorType.resourceError:
      case NudgeErrorType.healthCheckError:
      case NudgeErrorType.shutdownError:
      case NudgeErrorType.initializationError:
      case NudgeErrorType.unknown:
        return 1; // Other errors get one retry
    }
  }

  /// Returns recommended retry delay in milliseconds
  int get recommendedRetryDelayMs {
    switch (this) {
      case NudgeErrorType.dataFetchError:
      case NudgeErrorType.dataWriteError:
      case NudgeErrorType.streamError:
      case NudgeErrorType.transactionError:
        return 500; // Start with 500ms for network operations
      case NudgeErrorType.rateLimitExceeded:
        return 5000; // Wait longer for rate-limited operations
      default:
        return 1000; // Default 1 second
    }
  }
}

/// Enumeration of error severity levels
enum NudgeErrorSeverity {
  /// Low severity - logging only
  low(1),

  /// Medium severity - report but non-critical
  medium(2),

  /// High severity - important to address
  high(3),

  /// Critical severity - application may not function
  critical(4);

  /// Integer value of severity level for comparisons
  final int level;

  const NudgeErrorSeverity(this.level);
}

/// Structured error information for consistent error tracking and reporting
class NudgeErrorInfo {
  /// The original error or exception that occurred
  final dynamic error;

  /// Stack trace for debugging
  final StackTrace? stackTrace;

  /// Human-readable error message
  final String message;

  /// Type of error for categorization
  final NudgeErrorType type;

  /// Error severity level
  final NudgeErrorSeverity severity;

  /// Timestamp when the error occurred
  final DateTime timestamp;

  /// Additional context data to help with debugging
  final Map<String, dynamic> context;

  /// Unique identifier for this error instance
  final String id;

  /// Whether this error has been reported to analytics/crash reporting
  bool reported = false;

  /// Creates a new error info instance
  NudgeErrorInfo({
    required this.error,
    this.stackTrace,
    required this.message,
    required this.type,
    NudgeErrorSeverity? severity,
    DateTime? timestamp,
    Map<String, dynamic>? context,
    String? id,
  }) :
        this.severity = severity ?? type.severity,
        this.timestamp = timestamp ?? DateTime.now(),
        this.context = context ?? {},
        this.id = id ?? _generateErrorId();

  /// Generate a unique error ID
  static String _generateErrorId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        (1000 + (DateTime.now().microsecond % 9000)).toString();
  }

  /// Converts the error to a map for logging or analytics
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'message': message,
      'type': type.toString(),
      'severity': severity.toString(),
      'error': error.toString(),
      'stackTrace': stackTrace?.toString(),
      'context': context,
      'reported': reported,
    };
  }

  /// Reports the error to Firebase Crashlytics if available
  Future<void> reportToCrashlytics() async {
    if (reported) return;

    try {
      if (!kIsWeb) {
        final crashlytics = FirebaseCrashlytics.instance;

        // Set custom keys for better categorization
        await crashlytics.setCustomKey('error_type', type.toString());
        await crashlytics.setCustomKey('error_severity', severity.toString());
        await crashlytics.setCustomKey('error_id', id);

        // Add custom context data
        for (final entry in context.entries) {
          // Limit value length to avoid Crashlytics limits
          final value = entry.value.toString();
          final truncatedValue = value.length > 100 ? value.substring(0, 97) + '...' : value;
          await crashlytics.setCustomKey(entry.key, truncatedValue);
        }

        // Record the error
        await crashlytics.recordError(
          error,
          stackTrace,
          reason: message,
          fatal: severity == NudgeErrorSeverity.critical,
        );

        reported = true;
      }
    } catch (e) {
      // Don't crash while trying to report a crash
      Logger.error('NudgeErrorInfo', 'Failed to report error to Crashlytics: $e');
    }
  }

  /// Logs the error to the console
  void logToConsole() {
    final severityStr = severity.toString().split('.').last.toUpperCase();
    final typeStr = type.toString().split('.').last;
    final errorStr = error.toString();

    Logger.error(
      'NUDGE_ERROR[$severityStr][$typeStr]',
      'ID: $id - $message - $errorStr',
    );

    if (stackTrace != null) {
      Logger.error('NUDGE_ERROR_STACK', stackTrace.toString());
    }

    if (context.isNotEmpty) {
      Logger.error('NUDGE_ERROR_CONTEXT', context.toString());
    }
  }
}

/// Exception class for nudge repository errors
///
/// This exception is thrown by repository implementations to provide
/// structured error information about what went wrong.
class NudgeRepositoryException implements Exception {
  /// Error message describing what went wrong
  final String message;

  /// Type of error for categorization and handling
  final NudgeErrorType type;

  /// Original error that caused this exception, if any
  final dynamic originalError;

  /// Stack trace where the original error occurred
  final StackTrace? stackTrace;

  /// Additional context data for debugging
  final Map<String, dynamic> context;

  /// Creates a new repository exception
  NudgeRepositoryException(
      this.message,
      this.type, {
        this.originalError,
        this.stackTrace,
        Map<String, dynamic>? context,
      }) : this.context = context ?? {};

  @override
  String toString() {
    return 'NudgeRepositoryException: $message (${type.description})';
  }

  /// Converts the exception to an error info object for reporting
  NudgeErrorInfo toErrorInfo() {
    return NudgeErrorInfo(
      error: originalError ?? this,
      stackTrace: stackTrace,
      message: message,
      type: type,
      context: context,
    );
  }
}

/// Exception class for nudge service errors
///
/// This exception is thrown by service implementations to provide
/// structured error information about what went wrong.
class NudgeServiceException implements Exception {
  /// Error message describing what went wrong
  final String message;

  /// Type of error for categorization and handling
  final NudgeErrorType type;

  /// Original error that caused this exception, if any
  final dynamic originalError;

  /// Stack trace where the original error occurred
  final StackTrace? stackTrace;

  /// Additional context data for debugging
  final Map<String, dynamic> context;

  /// Creates a new service exception
  NudgeServiceException(
      this.message,
      this.type, {
        this.originalError,
        this.stackTrace,
        Map<String, dynamic>? context,
      }) : this.context = context ?? {};

  @override
  String toString() {
    return 'NudgeServiceException: $message (${type.description})';
  }

  /// Converts the exception to an error info object for reporting
  NudgeErrorInfo toErrorInfo() {
    return NudgeErrorInfo(
      error: originalError ?? this,
      stackTrace: stackTrace,
      message: message,
      type: type,
      context: context,
    );
  }
}

/// Exception class for nudge provider errors
///
/// This exception is thrown by provider implementations to provide
/// structured error information about what went wrong.
class NudgeProviderException implements Exception {
  /// Error message describing what went wrong
  final String message;

  /// Type of error for categorization and handling
  final NudgeErrorType type;

  /// Original error that caused this exception, if any
  final dynamic originalError;

  /// Stack trace where the original error occurred
  final StackTrace? stackTrace;

  /// Additional context data for debugging
  final Map<String, dynamic> context;

  /// Creates a new provider exception
  NudgeProviderException(
      this.message,
      this.type, {
        this.originalError,
        this.stackTrace,
        Map<String, dynamic>? context,
      }) : this.context = context ?? {};

  @override
  String toString() {
    return 'NudgeProviderException: $message (${type.description})';
  }

  /// Converts the exception to an error info object for reporting
  NudgeErrorInfo toErrorInfo() {
    return NudgeErrorInfo(
      error: originalError ?? this,
      stackTrace: stackTrace,
      message: message,
      type: type,
      context: context,
    );
  }
}

/// A result class that can contain either a success value or an error
///
/// This is useful for functions that might fail but where you don't want
/// to use exceptions for control flow.
class NudgeResult<T> {
  /// The success value, if the operation succeeded
  final T? data;

  /// The error info, if the operation failed
  final NudgeErrorInfo? error;

  /// Whether the operation succeeded
  final bool isSuccess;

  /// Creates a successful result with the given data
  NudgeResult.success(this.data)
      : error = null,
        isSuccess = true;

  /// Creates a failure result with the given error
  NudgeResult.failure(this.error)
      : data = null,
        isSuccess = false;

  /// Helper method to get the data or throw an exception if there was an error
  T getDataOrThrow() {
    if (isSuccess && data != null) {
      return data!;
    } else if (!isSuccess && error != null) {
      throw NudgeServiceException(
        error!.message,
        error!.type,
        originalError: error!.error,
        stackTrace: error!.stackTrace,
        context: error!.context,
      );
    } else {
      throw NudgeServiceException(
        'Unknown error occurred',
        NudgeErrorType.unknown,
      );
    }
  }

  /// Maps the success value to a new type using the given function
  NudgeResult<R> map<R>(R Function(T) mapper) {
    if (isSuccess && data != null) {
      try {
        return NudgeResult<R>.success(mapper(data!));
      } catch (e, stackTrace) {
        return NudgeResult<R>.failure(
          NudgeErrorInfo(
            error: e,
            stackTrace: stackTrace,
            message: 'Error mapping result: ${e.toString()}',
            type: NudgeErrorType.unknown,
          ),
        );
      }
    } else {
      return NudgeResult<R>.failure(error);
    }
  }

  /// Handles both success and failure cases
  R fold<R>(
      R Function(T) onSuccess,
      R Function(NudgeErrorInfo) onFailure,
      ) {
    if (isSuccess && data != null) {
      return onSuccess(data!);
    } else if (!isSuccess && error != null) {
      return onFailure(error!);
    } else {
      return onFailure(
        NudgeErrorInfo(
          error: 'Unknown error',
          message: 'Unknown error occurred',
          type: NudgeErrorType.unknown,
        ),
      );
    }
  }
}