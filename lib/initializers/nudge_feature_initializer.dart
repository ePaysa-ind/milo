//lib/initializers/nudge_feature_initializer.dart
// Copyright © 2025 Milo App. All rights reserved.
// Author: Milo Development Team
// Version: 1.0.0
// Last Updated: April 23, 2025

import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../utils/logger.dart';
import '../utils/nudge_error_handler.dart';
import '../repository/nudge_repository.dart';
import '../repository/nudge_firestore_repository.dart';
import '../providers/nudge_provider.dart';
import '../services/nudge_service.dart';
import '../services/nudge_notification_helper.dart';
import '../services/nudge_trigger_handler.dart';
import '../services/nudge_analytics_service.dart';
import '../services/nudge_preferences_service.dart';
import '../services/nudge_workmanager_service.dart';
import '../services/nudge_battery_optimization_service.dart';
import '../services/nudge_error_reporting_service.dart';
import '../config/nudge_remote_config_defaults.dart';
import '../utils/nudge_permission_handler.dart';
import '../utils/nudge_scheduler.dart';
import '../utils/nudge_accessibility_helper.dart';
import '../models/nudge_modelimport 'package:get_it/get_it.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';
import '../utils/nudge_error_handler.dart';
import '../repository/nudge_repository.dart';
import '../repository/nudge_firestore_repository.dart';
import '../providers/nudge_provider.dart';
import '../services/nudge_service.dart';
import '../services/nudge_notification_helper.dart';
import '../services/nudge_trigger_handler.dart';
import '../services/nudge_analytics_service.dart';
import '../services/nudge_preferences_service.dart';
import '../services/nudge_workmanager_service.dart';
import '../services/nudge_battery_optimization_service.dart';
import '../config/nudge_remote_config_defaults.dart';
import '../utils/nudge_permission_handler.dart';
import '../utils/nudge_scheduler.dart';
import '../utils/nudge_accessibility_helper.dart';

/// Class responsible for initializing all nudge-related components
/// Following a modular initializer pattern for better organized code
class NudgeFeatureInitializer {
  final GetIt _locator;

  // Singleton pattern
  static final NudgeFeatureInitializer _instance = NudgeFeatureInitializer._internal(GetIt.instance);

  // Factory constructor to return the singleton instance
  factory NudgeFeatureInitializer() => _instance;

  // Private constructor for singleton
  NudgeFeatureInitializer._internal(this._locator);

  // Flag to track initialization status
  bool _isInitialized = false;

  /// Initialize the nudge feature and all its dependencies
  /// Returns true if initialization was successful
  Future<bool> initialize() async {
    // Skip if already initialized
    if (_isInitialized) {
      Logger.info('NudgeFeatureInitializer', 'Nudge feature already initialized');
      return true;
    }

    try {
      Logger.info('NudgeFeatureInitializer', 'Initializing nudge feature');

      // Register services in the correct dependency order
      await _registerUtilities();
      await _registerRepositories();
      await _registerServices();
      await _registerProviders();

      // Configure and initialize components
      await _configureServices();

      _isInitialized = true;
      Logger.info('NudgeFeatureInitializer', 'Nudge feature initialized successfully');
      return true;
    } catch (e, stackTrace) {
      Logger.error('NudgeFeatureInitializer', 'Failed to initialize nudge feature: $e');
      Logger.error('NudgeFeatureInitializer', 'Stack trace: $stackTrace');
      return false;
    }
  }

  /// Register utility classes with the service locator
  Future<void> _registerUtilities() async {
    Logger.info('NudgeFeatureInitializer', 'Registering utility classes');

    // Register error handler
    _locator.registerSingleton<NudgeErrorHandler>(NudgeErrorHandler());

    // Register scheduler
    _locator.registerSingleton<NudgeScheduler>(NudgeScheduler());

    // Register permission handler
    _locator.registerSingleton<NudgePermissionHandler>(NudgePermissionHandler());

    // Register accessibility helper
    _locator.registerSingleton<NudgeAccessibilityHelper>(NudgeAccessibilityHelper());

    // Register shared preferences
    final sharedPrefs = await SharedPreferences.getInstance();
    _locator.registerSingleton<SharedPreferences>(sharedPrefs);
  }

  /// Register repositories with the service locator
  Future<void> _registerRepositories() async {
    Logger.info('NudgeFeatureInitializer', 'Registering repositories');

    // Register nudge repository
    _locator.registerSingleton<NudgeRepository>(NudgeFirestoreRepository());
  }

  /// Register services with the service locator
  Future<void> _registerServices() async {
    Logger.info('NudgeFeatureInitializer', 'Registering services');

    // Register preferences service
    _locator.registerSingleton<NudgePreferencesService>(
      NudgePreferencesService(
        _locator<SharedPreferences>(),
      ),
    );

    // Register analytics service
    _locator.registerSingleton<NudgeAnalyticsService>(
      NudgeAnalyticsService(),
    );

    // Register battery optimization service
    _locator.registerSingleton<NudgeBatteryOptimizationService>(
      NudgeBatteryOptimizationService(),
    );

    // Register notification helper
    _locator.registerSingleton<NudgeNotificationHelper>(
      NudgeNotificationHelper(
        errorHandler: _locator<NudgeErrorHandler>(),
      ),
    );

    // Register trigger handler
    _locator.registerSingleton<NudgeTriggerHandler>(
      NudgeTriggerHandler(
        scheduler: _locator<NudgeScheduler>(),
        notificationHelper: _locator<NudgeNotificationHelper>(),
        errorHandler: _locator<NudgeErrorHandler>(),
        batteryOptimization: _locator<NudgeBatteryOptimizationService>(),
      ),
    );

    // Register workmanager service
    _locator.registerSingleton<NudgeWorkmanagerService>(
      NudgeWorkmanagerService(
        triggerHandler: _locator<NudgeTriggerHandler>(),
        errorHandler: _locator<NudgeErrorHandler>(),
      ),
    );

    // Register nudge service
    _locator.registerSingleton<NudgeService>(
      NudgeService(
        repository: _locator<NudgeRepository>(),
        notificationHelper: _locator<NudgeNotificationHelper>(),
        triggerHandler: _locator<NudgeTriggerHandler>(),
        errorHandler: _locator<NudgeErrorHandler>(),
        analyticsService: _locator<NudgeAnalyticsService>(),
        workmanagerService: _locator<NudgeWorkmanagerService>(),
      ),
    );

    // Initialize Remote Config with default values
    await _initializeRemoteConfig();
  }

  /// Register providers with the service locator
  Future<void> _registerProviders() async {
    Logger.info('NudgeFeatureInitializer', 'Registering providers');

    // Register nudge provider
    _locator.registerSingleton<NudgeProvider>(
      NudgeProvider(
        repository: _locator<NudgeRepository>(),
        errorHandler: _locator<NudgeErrorHandler>(),
        analyticsService: _locator<NudgeAnalyticsService>(),
      ),
    );
  }

  /// Configure and initialize all registered services
  Future<void> _configureServices() async {
    Logger.info('NudgeFeatureInitializer', 'Configuring services');

    // Initialize notification channels
    await _locator<NudgeNotificationHelper>().initializeNotificationChannels();

    // Initialize workmanager for background tasks
    await _locator<NudgeWorkmanagerService>().initialize();

    // Initialize battery optimization service
    await _locator<NudgeBatteryOptimizationService>().initialize();

    // Request required permissions
    await _locator<NudgePermissionHandler>().requestRequiredPermissions();

    // Initialize main nudge service
    await _locator<NudgeService>().initialize();
  }

  /// Initialize Firebase Remote Config with default values
  Future<void> _initializeRemoteConfig() async {
    try {
      Logger.info('NudgeFeatureInitializer', 'Initializing Remote Config');

      final remoteConfig = FirebaseRemoteConfig.instance;

      // Set default values from our constants
      await remoteConfig.setDefaults(NudgeRemoteConfigDefaults.defaultValues);

      // Set fetch settings based on environment
      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(minutes: 1),
          minimumFetchInterval: kDebugMode
              ? Duration.zero
              : const Duration(hours: 6),
        ),
      );

      // Fetch and activate
      await remoteConfig.fetchAndActivate();

      Logger.info('NudgeFeatureInitializer', 'Remote Config initialized successfully');
    } catch (e, stackTrace) {
      Logger.error('NudgeFeatureInitializer', 'Failed to initialize Remote Config: $e');
      Logger.error('NudgeFeatureInitializer', 'Stack trace: $stackTrace');
      // Continue initialization even if Remote Config fails
    }
  }

  /// Get the service locator instance
  GetIt get locator => _locator;

  /// Check if the feature is initialized
  bool get isInitialized => _isInitialized;
}