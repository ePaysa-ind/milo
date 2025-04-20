// lib/utils/config.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';

import '../utils/logger.dart';

/// AppConfig handles application-wide configuration settings.
/// It provides methods to access API keys and other configuration values.
class AppConfig {
  static const String _tag = 'AppConfig';

  // Singleton instance
  static final AppConfig _instance = AppConfig._internal();

  // Factory constructor to return the singleton instance
  factory AppConfig() {
    return _instance;
  }

  // Private constructor
  AppConfig._internal();

  // Flag to track if initialization is complete
  bool _isInitialized = false;

  // Device ID for analytics/tracking
  String? _deviceId;

  // API key cache for better performance
  String? _cachedOpenAIApiKey;

  /// Initialize the configuration, loading necessary values.
  /// Call this in main.dart before the app starts.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      Logger.info(_tag, 'Initializing app configuration');

      // Generate a unique device ID for analytics/tracking
      _deviceId = const Uuid().v4();
      Logger.info(_tag, 'Using device ID: ${_deviceId?.substring(0, 8)}...');

      // Load API key from .env file
      await _loadApiKeyFromEnv();

      _isInitialized = true;
      Logger.info(_tag, 'App configuration initialized successfully');
    } catch (e) {
      Logger.error(_tag, 'Failed to initialize app configuration: $e');
      rethrow;
    }
  }

  /// Load the API key from .env file into memory cache
  Future<void> _loadApiKeyFromEnv() async {
    try {
      // Get API key from .env file
      _cachedOpenAIApiKey = dotenv.env['OPENAI_API_KEY'];

      if (_cachedOpenAIApiKey == null || _cachedOpenAIApiKey!.isEmpty) {
        Logger.warning(_tag, 'OpenAI API key not found in .env file');
      } else {
        // Only log that we found a key, never log the key itself
        Logger.info(_tag, 'OpenAI API key loaded successfully from .env file');

        // Validate the key format
        if (!_cachedOpenAIApiKey!.startsWith('sk-')) {
          Logger.warning(_tag, 'OpenAI API key has invalid format (should start with "sk-")');
        }
      }
    } catch (e) {
      Logger.error(_tag, 'Error loading API key from .env: $e');
      _cachedOpenAIApiKey = null;
    }
  }

  /// Get the OpenAI API key from .env file
  String? get openAIApiKey {
    if (_cachedOpenAIApiKey == null || _cachedOpenAIApiKey!.isEmpty) {
      Logger.warning(_tag, 'Attempted to access OpenAI API key but none is configured');
      return null;
    }

    return _cachedOpenAIApiKey;
  }

  /// Reload the API key from .env file (useful if the file is updated at runtime)
  Future<void> reloadApiKey() async {
    try {
      Logger.info(_tag, 'Reloading API key from .env');
      await _loadApiKeyFromEnv();
    } catch (e) {
      Logger.error(_tag, 'Error reloading API key: $e');
    }
  }

  /// Check if an OpenAI API key is configured
  bool get isOpenAIConfigured => _cachedOpenAIApiKey != null && _cachedOpenAIApiKey!.isNotEmpty;

  /// Get the device ID
  String? get deviceId => _deviceId;

  /// Get the status of the OpenAI configuration as a user-friendly message
  String get openAIConfigStatus {
    if (!isOpenAIConfigured) {
      return 'OpenAI API key is not configured. Please check your .env file.';
    }

    if (!(_cachedOpenAIApiKey?.startsWith('sk-') ?? false)) {
      return 'OpenAI API key is configured but may be invalid (does not start with "sk-").';
    }

    return 'OpenAI API is properly configured.';
  }

  /// Log the current configuration status
  void logConfigStatus() {
    Logger.info(_tag, 'Configuration status:');
    Logger.info(_tag, '- Initialized: $_isInitialized');
    Logger.info(_tag, '- OpenAI configured: $isOpenAIConfigured');

    if (isOpenAIConfigured) {
      final keyPrefix = _cachedOpenAIApiKey!.substring(0, 5);
      final keyLength = _cachedOpenAIApiKey!.length;
      Logger.info (_tag, '- API key format: $keyPrefix... (${keyLength} chars)');
    }
  }
}