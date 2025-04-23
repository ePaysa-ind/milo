import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/nudge_error_models.dart';
import '../services/nudge_error_reporting_service.dart';
import '../utils/logger.dart';

/// Centralized error handling utility for the nudge feature
///
/// This class provides standardized error handling, logging, reporting,
/// and recovery mechanisms for errors that occur in the nudge feature.
///
/// All errors in the nudge feature should be handled through this class
/// to ensure consistent behavior and proper reporting.
///
/// @version 1.0.1
class NudgeErrorHandler {
  // Singleton pattern with lazy initialization
  static final NudgeErrorHandler _instance = NudgeErrorHandler._internal();

  // Factory constructor to return the singleton instance
  factory NudgeErrorHandler() => _instance;

  // Error reporting service - will be initialized later if available
  NudgeErrorReportingService? _errorReportingService;

  // Map of recent errors by ID to prevent duplicates
  final Map<String, DateTime> _recentErrors = {};

  // Configurable options
  bool _reportToCrashlytics = true;
  bool _logToConsole = true;
  bool _deduplicateErrors = true;
  Duration _deduplicationWindow = const Duration(minutes: 10);

  // Private constructor for singleton
  NudgeErrorHandler._internal();

  /// Initialize the error handler with optional dependencies and configuration
  void initialize({
    NudgeErrorReportingService? errorReportingService,
    bool reportToCrashlytics = true,
    bool logToConsole = true,
    bool deduplicateErrors = true,
    Duration? deduplicationWindow,
  }) {
    _errorReportingService = errorReportingService;
    _reportToCrashlytics = reportToCrashlytics;
    _logToConsole = logToConsole;
    _deduplicateErrors = deduplicateErrors;

    if (deduplicationWindow != null) {
      _deduplicationWindow = deduplicationWindow;
    }

    Logger.info('NudgeErrorHandler', 'Initialized');
  }

  /// Set the error reporting service
  /// This is typically called by the feature initializer once all services are registered
  void setErrorReportingService(NudgeErrorReportingService service) {
    _errorReportingService = service;
    Logger.info('NudgeErrorHandler', 'Error reporting service registered');
  }

  /// Log an error without throwing an exception
  ///
  /// @param error The original error or exception
  /// @param stackTrace Stack trace for debugging
  /// @param message Human-readable error message
  /// @param type Type of error for categorization
  /// @param context Additional context data to help with debugging
  void logError(
      dynamic error,
      StackTrace? stackTrace,
      String message,
      NudgeErrorType type, {
        Map<String, dynamic>? context,
      }) {
    final errorInfo = NudgeErrorInfo(
      error: error,
      stackTrace: stackTrace,
      message: message,
      type: type,
      context: context,
    );

    _handleError(errorInfo);
  }

  /// Handle a repository exception and return a default value
  ///
  /// @param error The original error or exception
  /// @param stackTrace Stack trace for debugging
  /// @param message Human-readable error message
  /// @param type Type of error for categorization
  /// @param defaultValue Default value to return on error (optional)
  /// @param context Additional context data to help with debugging
  /// @return Default value of type T
  T handleRepositoryError<T>(
      dynamic error,
      StackTrace? stackTrace,
      String message,
      NudgeErrorType type, {
        T? defaultValue,
        Map<String, dynamic>? context,
      }) {
    final errorInfo = NudgeErrorInfo(
      error: error,
      stackTrace: stackTrace,
      message: message,
      type: type,
      context: context,
    );

    _handleError(errorInfo);

    // Return default value if provided, otherwise throw
    if (defaultValue != null) {
      return defaultValue;
    }

    // Re-throw as repository exception for consistent error handling
    throw NudgeRepositoryException(
      message,
      type,
      originalError: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  /// Handle a repository exception and throw a standardized exception
  ///
  /// @param error The original error or exception
  /// @param stackTrace Stack trace for debugging
  /// @param message Human-readable error message
  /// @param type Type of error for categorization
  /// @param context Additional context data to help with debugging
  /// @return Nothing - always throws an exception
  /// @throws NudgeRepositoryException with standardized format
  NudgeRepositoryException handleRepositoryException(
      dynamic error,
      StackTrace? stackTrace,
      String message,
      NudgeErrorType type, {
        Map<String, dynamic>? context,
      }) {
    final errorInfo = NudgeErrorInfo(
      error: error,
      stackTrace: stackTrace,
      message: message,
      type: type,
      context: context,
    );

    _handleError(errorInfo);

    // Return standardized exception
    return NudgeRepositoryException(
      message,
      type,
      originalError: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  /// Handle a service exception and return a default value
  ///
  /// @param error The original error or exception
  /// @param stackTrace Stack trace for debugging
  /// @param message Human-readable error message
  /// @param type Type of error for categorization
  /// @param defaultValue Default value to return on error (optional)
  /// @param context Additional context data to help with debugging
  /// @return Default value of type T
  T handleServiceError<T>(
      dynamic error,
      StackTrace? stackTrace,
      String message,
      NudgeErrorType type, {
        T? defaultValue,
        Map<String, dynamic>? context,
      }) {
    final errorInfo = NudgeErrorInfo(
      error: error,
      stackTrace: stackTrace,
      message: message,
      type: type,
      context: context,
    );

    _handleError(errorInfo);

    // Return default value if provided, otherwise throw
    if (defaultValue != null) {
      return defaultValue;
    }

    // Re-throw as service exception for consistent error handling
    throw NudgeServiceException(
      message,
      type,
      originalError: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  /// Wrap a function in error handling
  ///
  /// @param function Function to execute
  /// @param errorMessage Message to use if an error occurs
  /// @param type Type of error for categorization
  /// @param defaultValue Default value to return on error (optional)
  /// @param context Additional context data to help with debugging
  /// @return Result of the function or default value on error
  Future<T> wrapAsync<T>(
      Future<T> Function() function,
      String errorMessage,
      NudgeErrorType type, {
        T? defaultValue,
        Map<String, dynamic>? context,
      }) async {
    try {
      return await function();
    } catch (e, stackTrace) {
      return handleServiceError<T>(
        e,
        stackTrace,
        errorMessage,
        type,
        defaultValue: defaultValue,
        context: context,
      );
    }
  }

  /// Wrap a synchronous function in error handling
  ///
  /// @param function Function to execute
  /// @param errorMessage Message to use if an error occurs
  /// @param type Type of error for categorization
  /// @param defaultValue Default value to return on error (optional)
  /// @param context Additional context data to help with debugging
  /// @return Result of the function or default value on error
  T wrapSync<T>(
      T Function() function,
      String errorMessage,
      NudgeErrorType type, {
        T? defaultValue,
        Map<String, dynamic>? context,
      }) {
    try {
      return function();
    } catch (e, stackTrace) {
      return handleServiceError<T>(
        e,
        stackTrace,
        errorMessage,
        type,
        defaultValue: defaultValue,
        context: context,
      );
    }
  }

  /// Retry a function with exponential backoff
  ///
  /// @param function Function to execute
  /// @param errorMessage Message to use if all retries fail
  /// @param type Type of error for categorization
  /// @param maxRetries Maximum number of retries (default: based on error type)
  /// @param initialDelay Initial delay before first retry (default: based on error type)
  /// @param maxDelay Maximum delay between retries (default: 30 seconds)
  /// @param defaultValue Default value to return if all retries fail (optional)
  /// @param context Additional context data to help with debugging
  /// @return Result of the function or default value if all retries fail
  Future<T> retryWithBackoff<T>(
      Future<T> Function() function,
      String errorMessage,
      NudgeErrorType type, {
        int? maxRetries,
        Duration? initialDelay,
        Duration maxDelay = const Duration(seconds: 30),
        T? defaultValue,
        Map<String, dynamic>? context,
      }) async {
    // Use recommended retry count and delay for the error type if not specified
    final retries = maxRetries ?? type.recommendedRetryCount;
    final delay = initialDelay ?? Duration(milliseconds: type.recommendedRetryDelayMs);

    int attempts = 0;
    Duration currentDelay = delay;
    dynamic lastError;
    StackTrace? lastStackTrace;

    // Keep extra context for retry information
    final retryContext = Map<String, dynamic>.from(context ?? {});
    retryContext['max_retries'] = retries;
    retryContext['initial_delay_ms'] = delay.inMilliseconds;

    while (attempts <= retries) {
      try {
        return await function();
      } catch (e, stackTrace) {
        lastError = e;
        lastStackTrace = stackTrace;
        attempts++;

        // Update retry context
        retryContext['attempt'] = attempts;
        retryContext['current_delay_ms'] = currentDelay.inMilliseconds;

        // Log retry attempt
        if (attempts <= retries) {
          Logger.warning(
            'NudgeErrorHandler',
            'Retry $attempts/$retries after error: ${e.toString()}',
          );

          // Wait with exponential backoff
          await Future.delayed(currentDelay);

          // Increase delay for next attempt with exponential backoff
          currentDelay = Duration(
            milliseconds: (currentDelay.inMilliseconds * 2)
                .clamp(0, maxDelay.inMilliseconds),
          );
        }
      }
    }

    // All retries failed
    return handleServiceError<T>(
      lastError,
      lastStackTrace,
      '$errorMessage (after $attempts retries)',
      type,
      defaultValue: defaultValue,
      context: retryContext,
    );
  }

  /// Get a result object with success or failure
  ///
  /// @param function Function to execute
  /// @param errorMessage Message to use if an error occurs
  /// @param type Type of error for categorization
  /// @param context Additional context data to help with debugging
  /// @return NudgeResult with success or failure
  Future<NudgeResult<T>> getResult<T>(
      Future<T> Function() function,
      String errorMessage,
      NudgeErrorType type, {
        Map<String, dynamic>? context,
      }) async {
    try {
      final result = await function();
      return NudgeResult<T>.success(result);
    } catch (e, stackTrace) {
      final errorInfo = NudgeErrorInfo(
        error: e,
        stackTrace: stackTrace,
        message: errorMessage,
        type: type,
        context: context,
      );

      _handleError(errorInfo);

      return NudgeResult<T>.failure(errorInfo);
    }
  }

  /// Internal method to handle errors consistently
  ///
  /// This method is called by all public error handling methods
  /// to ensure consistent behavior for all errors.
  void _handleError(NudgeErrorInfo errorInfo) {
    // Check for duplicate errors if enabled
    if (_deduplicateErrors) {
      final errorKey = '${errorInfo.type}_${errorInfo.message}_${errorInfo.error.toString()}';
      final now = DateTime.now();

      if (_recentErrors.containsKey(errorKey)) {
        final lastReported = _recentErrors[errorKey]!;
        if (now.difference(lastReported) < _deduplicationWindow) {
          // Skip duplicate error within window
          return;
        }
      }

      // Update recent errors map
      _recentErrors[errorKey] = now;

      // Clean up old entries
      _recentErrors.removeWhere((_, timestamp) =>
      now.difference(timestamp) > _deduplicationWindow);
    }

    // Log to console if enabled
    if (_logToConsole) {
      errorInfo.logToConsole();
    }

    // Report to Crashlytics if enabled and error should be reported
    if (_reportToCrashlytics && errorInfo.type.shouldReport) {
      errorInfo.reportToCrashlytics();
    }

    // Report to error reporting service if available
    if (_errorReportingService != null) {
      _errorReportingService!.reportError(
        errorInfo.error,
        errorInfo.stackTrace,
        errorInfo.message,
        errorInfo.type,
        context: errorInfo.context,
      );
    }

    // Attempt recovery if error is recoverable
    if (errorInfo.type.isRecoverable) {
      _attemptRecovery(errorInfo);
    }
  }

  /// Attempt to recover from an error
  ///
  /// This method is called by _handleError for recoverable errors
  /// to attempt automatic recovery where possible.
  void _attemptRecovery(NudgeErrorInfo errorInfo) {
    // Recovery strategies based on error type
    switch (errorInfo.type) {
      case NudgeErrorType.cacheError:
      // Clear cache if cache error
        _clearCache();
        break;

      case NudgeErrorType.authenticationError:
      // Request re-authentication
        _requestReauthentication();
        break;

      default:
      // No specific recovery strategy for other error types
        break;
    }
  }

  /// Clear cache as part of error recovery
  void _clearCache() {
    // This would typically call into a cache service
    // For now, just log that we would clear cache
    Logger.info('NudgeErrorHandler', 'Cache clear requested as part of error recovery');
  }

  /// Request re-authentication as part of error recovery
  void _requestReauthentication() {
    // This would typically call into an auth service
    // For now, just log that we would request re-authentication
    Logger.info('NudgeErrorHandler', 'Re-authentication requested as part of error recovery');
  }
}