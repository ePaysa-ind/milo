import 'dart:async';
import 'dart:convert';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/nudge_error_models.dart';
import '../utils/logger.dart';
import '../utils/nudge_error_handler.dart';

/// Service for reporting errors to various destinations
///
/// This service handles reporting errors to:
/// - Firebase Crashlytics
/// - Custom error tracking service (if configured)
/// - Developer console logs
/// - Analytics (for non-fatal errors)
///
/// It provides centralized error reporting capabilities for the nudge feature.
///
/// @version 1.0.1
class NudgeErrorReportingService {
  // Dependencies
  final NudgeErrorHandler _errorHandler;

  // Configuration
  bool _enableCrashlytics = true;
  bool _enableRemoteErrorReporting = false;
  bool _enableLocalErrorLogging = true;
  bool _enableAnalyticsErrorTracking = true;

  // Remote error reporting endpoint (if configured)
  String? _remoteErrorEndpoint;

  // HTTP client for remote error reporting
  final http.Client _httpClient = http.Client();

  // Rate limiting for error reporting
  final Map<String, DateTime> _reportedErrors = {};
  final Duration _rateLimitWindow = const Duration(hours: 1);
  final int _maxErrorsPerWindow = 10;

  // Batch error reporting
  final List<NudgeErrorInfo> _errorQueue = [];
  Timer? _batchReportingTimer;
  final Duration _batchReportingInterval = const Duration(minutes: 5);
  final int _maxBatchSize = 20;
  bool _batchReportingEnabled = false;

  /// Constructor with required dependencies
  NudgeErrorReportingService({
    required NudgeErrorHandler errorHandler,
    bool enableCrashlytics = true,
    bool enableRemoteErrorReporting = false,
    bool enableLocalErrorLogging = true,
    bool enableAnalyticsErrorTracking = true,
    String? remoteErrorEndpoint,
    bool enableBatchReporting = false,
  }) : _errorHandler = errorHandler {
    _enableCrashlytics = enableCrashlytics;
    _enableRemoteErrorReporting = enableRemoteErrorReporting;
    _enableLocalErrorLogging = enableLocalErrorLogging;
    _enableAnalyticsErrorTracking = enableAnalyticsErrorTracking;
    _remoteErrorEndpoint = remoteErrorEndpoint;
    _batchReportingEnabled = enableBatchReporting;

    if (_batchReportingEnabled) {
      _startBatchReportingTimer();
    }

    Logger.info('NudgeErrorReportingService', 'Initialized');
  }

  /// Initialize Firebase Crashlytics with custom keys
  Future<void> initializeCrashlytics() async {
    if (!_enableCrashlytics || kIsWeb) return;

    try {
      // Set up Crashlytics
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

      // Set custom keys for better error categorization
      await FirebaseCrashlytics.instance.setCustomKey('feature', 'nudge');
      await FirebaseCrashlytics.instance.setCustomKey('app_version', '1.0.0'); // This should come from app config

      Logger.info('NudgeErrorReportingService', 'Crashlytics initialized');
    } catch (e, stackTrace) {
      // Avoid using the error handler here to prevent potential infinite loops
      Logger.error('NudgeErrorReportingService', 'Failed to initialize Crashlytics: $e');
      Logger.error('NudgeErrorReportingService', 'Stack trace: $stackTrace');
    }
  }

  /// Report an error to all configured destinations
  ///
  /// @param error The original error or exception
  /// @param stackTrace Stack trace for debugging
  /// @param message Human-readable error message
  /// @param type Type of error for categorization
  /// @param context Additional context data to help with debugging
  /// @param isFatal Whether the error is fatal to the application
  Future<void> reportError(
      dynamic error,
      StackTrace? stackTrace,
      String message,
      NudgeErrorType type, {
        Map<String, dynamic>? context,
        bool isFatal = false,
      }) async {
    // Create error info
    final errorInfo = NudgeErrorInfo(
      error: error,
      stackTrace: stackTrace,
      message: message,
      type: type,
      severity: isFatal ? NudgeErrorSeverity.critical : null,
      context: context,
    );

    // Apply rate limiting
    if (!_shouldReportError(errorInfo)) {
      Logger.debug('NudgeErrorReportingService', 'Error reporting rate limited: ${errorInfo.message}');
      return;
    }

    // Report to local logs
    if (_enableLocalErrorLogging) {
      _reportToLogs(errorInfo);
    }

    // Report to Crashlytics
    if (_enableCrashlytics && !kIsWeb) {
      await _reportToCrashlytics(errorInfo, isFatal);
    }

    // Report to remote error service
    if (_enableRemoteErrorReporting && _remoteErrorEndpoint != null) {
      if (_batchReportingEnabled) {
        _queueForBatchReporting(errorInfo);
      } else {
        await _reportToRemoteService(errorInfo);
      }
    }

    // Report to analytics
    if (_enableAnalyticsErrorTracking) {
      _reportToAnalytics(errorInfo);
    }
  }

  /// Report error to local logs
  void _reportToLogs(NudgeErrorInfo errorInfo) {
    final severityStr = errorInfo.severity.toString().split('.').last.toUpperCase();
    final typeStr = errorInfo.type.toString().split('.').last;

    Logger.error(
      'NUDGE_ERROR[$severityStr][$typeStr]',
      '${errorInfo.message} - ${errorInfo.error.toString()}',
    );

    if (errorInfo.stackTrace != null) {
      Logger.error('NUDGE_ERROR_STACK', errorInfo.stackTrace.toString());
    }

    if (errorInfo.context.isNotEmpty) {
      Logger.error('NUDGE_ERROR_CONTEXT', jsonEncode(errorInfo.context));
    }
  }

  /// Report error to Crashlytics
  Future<void> _reportToCrashlytics(NudgeErrorInfo errorInfo, bool isFatal) async {
    try {
      final crashlytics = FirebaseCrashlytics.instance;

      // Set custom keys for better categorization
      await crashlytics.setCustomKey('error_type', errorInfo.type.toString());
      await crashlytics.setCustomKey('error_severity', errorInfo.severity.toString());
      await crashlytics.setCustomKey('error_id', errorInfo.id);

      // Add custom context data
      for (final entry in errorInfo.context.entries) {
        // Limit value length to avoid Crashlytics limits
        final value = entry.value.toString();
        final truncatedValue = value.length > 100 ? value.substring(0, 97) + '...' : value;
        await crashlytics.setCustomKey(entry.key, truncatedValue);
      }

      // Log a message with the error details
      await crashlytics.log('Error details: ${errorInfo.message}');

      // Record the error with appropriate fatality setting
      await crashlytics.recordError(
        errorInfo.error,
        errorInfo.stackTrace,
        reason: errorInfo.message,
        fatal: isFatal || errorInfo.severity == NudgeErrorSeverity.critical,
      );

      // Mark as reported
      errorInfo.reported = true;

      Logger.debug('NudgeErrorReportingService', 'Error reported to Crashlytics: ${errorInfo.id}');
    } catch (e, stackTrace) {
      // Avoid using the error handler here to prevent potential infinite loops
      Logger.error('NudgeErrorReportingService', 'Failed to report to Crashlytics: $e');
      Logger.error('NudgeErrorReportingService', 'Stack trace: $stackTrace');
    }
  }

  /// Report error to remote service
  Future<void> _reportToRemoteService(NudgeErrorInfo errorInfo) async {
    if (_remoteErrorEndpoint == null) return;

    try {
      final response = await _httpClient
          .post(
        Uri.parse(_remoteErrorEndpoint!),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(errorInfo.toMap()),
      )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        Logger.debug('NudgeErrorReportingService', 'Error reported to remote service: ${errorInfo.id}');
      } else {
        Logger.warning(
          'NudgeErrorReportingService',
          'Failed to report error to remote service: ${response.statusCode}',
        );
      }
    } catch (e, stackTrace) {
      // Avoid using the error handler here to prevent potential infinite loops
      Logger.error('NudgeErrorReportingService', 'Failed to report to remote service: $e');
      Logger.error('NudgeErrorReportingService', 'Stack trace: $stackTrace');
    }
  }

  /// Report error to analytics
  void _reportToAnalytics(NudgeErrorInfo errorInfo) {
    // This would typically use an analytics service
    // For now, just log that we would report to analytics
    Logger.debug('NudgeErrorReportingService', 'Error reported to analytics: ${errorInfo.id}');
  }

  /// Check if error should be reported based on rate limiting
  bool _shouldReportError(NudgeErrorInfo errorInfo) {
    // Always report critical errors
    if (errorInfo.severity == NudgeErrorSeverity.critical) {
      return true;
    }

    // Create a key from error characteristics
    final errorKey = '${errorInfo.type}_${errorInfo.message}_${errorInfo.error.toString()}';
    final now = DateTime.now();

    // Check if this error has been reported recently
    if (_reportedErrors.containsKey(errorKey)) {
      final lastReported = _reportedErrors[errorKey]!;

      // Allow reporting again after rate limit window
      if (now.difference(lastReported) > _rateLimitWindow) {
        _reportedErrors[errorKey] = now;
        return true;
      }

      // Rate limit this error
      return false;
    }

    // Check if we've reported too many errors in this window
    final recentErrors = _reportedErrors.values
        .where((time) => now.difference(time) <= _rateLimitWindow)
        .length;

    if (recentErrors >= _maxErrorsPerWindow) {
      // Rate limit all errors due to volume
      return false;
    }

    // Record this error and allow reporting
    _reportedErrors[errorKey] = now;

    // Clean up old entries
    _reportedErrors.removeWhere((_, time) => now.difference(time) > _rateLimitWindow);

    return true;
  }

  /// Queue error for batch reporting
  void _queueForBatchReporting(NudgeErrorInfo errorInfo) {
    _errorQueue.add(errorInfo);

    // If queue exceeds max size, send batch immediately
    if (_errorQueue.length >= _maxBatchSize) {
      _sendBatchReport();
    }
  }

  /// Start timer for batch reporting
  void _startBatchReportingTimer() {
    _batchReportingTimer?.cancel();
    _batchReportingTimer = Timer.periodic(_batchReportingInterval, (_) {
      if (_errorQueue.isNotEmpty) {
        _sendBatchReport();
      }
    });
  }

  /// Send batch report
  Future<void> _sendBatchReport() async {
    if (_errorQueue.isEmpty || _remoteErrorEndpoint == null) return;

    try {
      // Create batch report
      final batch = _errorQueue.map((error) => error.toMap()).toList();

      // Clear queue
      final errorCount = _errorQueue.length;
      _errorQueue.clear();

      // Send batch report
      final response = await _httpClient
          .post(
        Uri.parse('${_remoteErrorEndpoint!}/batch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'errors': batch}),
      )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        Logger.debug('NudgeErrorReportingService', 'Batch error report sent: $errorCount errors');
      } else {
        Logger.warning(
          'NudgeErrorReportingService',
          'Failed to send batch error report: ${response.statusCode}',
        );
      }
    } catch (e, stackTrace) {
      // Avoid using the error handler here to prevent potential infinite loops
      Logger.error('NudgeErrorReportingService', 'Failed to send batch error report: $e');
      Logger.error('NudgeErrorReportingService', 'Stack trace: $stackTrace');

      // Return errors to queue for next attempt
      // But limit the queue size to avoid memory issues
      if (_errorQueue.length < _maxBatchSize * 2) {
        _errorQueue.addAll(_errorQueue.take(_maxBatchSize));
      }
    }
  }

  /// Configure the service with new settings
  void configure({
    bool? enableCrashlytics,
    bool? enableRemoteErrorReporting,
    bool? enableLocalErrorLogging,
    bool? enableAnalyticsErrorTracking,
    bool? enableBatchReporting,
    String? remoteErrorEndpoint,
  }) {
    if (enableCrashlytics != null) {
      _enableCrashlytics = enableCrashlytics;
    }

    if (enableRemoteErrorReporting != null) {
      _enableRemoteErrorReporting = enableRemoteErrorReporting;
    }

    if (enableLocalErrorLogging != null) {
      _enableLocalErrorLogging = enableLocalErrorLogging;
    }

    if (enableAnalyticsErrorTracking != null) {
      _enableAnalyticsErrorTracking = enableAnalyticsErrorTracking;
    }

    if (remoteErrorEndpoint != null) {
      _remoteErrorEndpoint = remoteErrorEndpoint;
    }

    if (enableBatchReporting != null) {
      _batchReportingEnabled = enableBatchReporting;

      if (_batchReportingEnabled) {
        _startBatchReportingTimer();
      } else {
        _batchReportingTimer?.cancel();

        // Send any queued errors immediately
        if (_errorQueue.isNotEmpty) {
          _sendBatchReport();
        }
      }
    }

    Logger.info('NudgeErrorReportingService', 'Configuration updated');
  }

  /// Clear error reporting history
  void clearHistory() {
    _reportedErrors.clear();
    Logger.info('NudgeErrorReportingService', 'Error reporting history cleared');
  }

  /// Dispose resources
  void dispose() {
    _batchReportingTimer?.cancel();
    _httpClient.close();

    // Send any remaining errors
    if (_errorQueue.isNotEmpty) {
      _sendBatchReport();
    }

    Logger.info('NudgeErrorReportingService', 'Disposed');
  }
}