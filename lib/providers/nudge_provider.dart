//lib/providers/nudge_provider.dart
// Copyright © 2025 Milo App. All rights reserved.
// Author: Milo Development Team
// Version: 1.0.0
// Last Updated: April 23, 2025

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/nudge_model.dart';
import '../repository/nudge_repository.dart';
import '../utils/logger.dart';
import '../utils/nudge_error_handler.dart';
import '../services/nudge_analytics_service.dart';
import '../models/nudge_error_models.dart';

/// Provider class that manages nudge state across the application
/// Uses ChangeNotifier pattern from Provider package for state management
///
/// Includes:
/// - State persistence
/// - Debounced operations
/// - Memoization
/// - Cancelable operations
/// - Optimized notifications
///
/// @version 1.0.3
class NudgeProvider extends ChangeNotifier {
  // Dependencies
  final NudgeRepository<NudgeModel> _repository;
  final NudgeErrorHandler _errorHandler;
  final NudgeAnalyticsService _analyticsService;
  final SharedPreferences _prefs;

  // State
  List<NudgeModel> _nudges = [];
  bool _isLoading = false;
  String? _error;
  NudgeModel? _selectedNudge;
  Map<String, dynamic> _nudgeSettings = {};
  Map<String, dynamic> _nudgeStats = {};
  int _unreadCount = 0;

  // Memoized state
  Map<String, List<NudgeModel>> _memoizedFilteredNudges = {};

  // Stream subscriptions
  StreamSubscription<List<NudgeModel>>? _nudgesSubscription;

  // Debounce timers
  Timer? _saveSettingsDebounceTimer;
  Timer? _notifyListenersDebounceTimer;

  // Cancelable operations
  final Map<String, Completer<void>> _cancelableOperations = {};

  // State persistence keys
  static const String _selectedNudgeIdKey = 'nudge_provider_selected_nudge_id';
  static const String _nudgeSettingsKey = 'nudge_provider_settings';

  /// Constructor that takes in dependencies
  NudgeProvider({
    required NudgeRepository<NudgeModel> repository,
    required NudgeErrorHandler errorHandler,
    required NudgeAnalyticsService analyticsService,
    required SharedPreferences prefs,
  }) :
        _repository = repository,
        _errorHandler = errorHandler,
        _analyticsService = analyticsService,
        _prefs = prefs {
    // Initialize by loading nudges and settings
    _initializeProvider();
  }

  // Getters with memoization
  List<NudgeModel> get nudges => _nudges;
  bool get isLoading => _isLoading;
  String? get error => _error;
  NudgeModel? get selectedNudge => _selectedNudge;
  Map<String, dynamic> get nudgeSettings => _nudgeSettings;
  Map<String, dynamic> get nudgeStats => _nudgeStats;
  int get unreadCount => _unreadCount;

  /// Returns active nudges (memoized)
  List<NudgeModel> get activeNudges {
    return _getMemoizedFilteredNudges('active', (nudge) =>
    nudge.isActive == true);
  }

  /// Returns delivered nudges (memoized)
  List<NudgeModel> get deliveredNudges {
    return _getMemoizedFilteredNudges('delivered', (nudge) =>
    nudge.deliveryCount != null && nudge.deliveryCount! > 0);
  }

  /// Returns acted upon nudges (memoized)
  List<NudgeModel> get actedUponNudges {
    return _getMemoizedFilteredNudges('actedUpon', (nudge) =>
    nudge.actionCount != null && nudge.actionCount! > 0);
  }

  /// Returns nudges sorted by rating (memoized)
  List<NudgeModel> get nudgesByRating {
    return _getMemoizedFilteredNudges('byRating', (nudge) => true,
        sorter: (a, b) => (b.averageRating ?? 0.0).compareTo(a.averageRating ?? 0.0));
  }

  /// Returns nudges created in the last 7 days (memoized)
  List<NudgeModel> get recentNudges {
    final oneWeekAgo = DateTime.now().subtract(const Duration(days: 7));
    return _getMemoizedFilteredNudges('recent', (nudge) =>
    nudge.createdAt != null && nudge.createdAt!.isAfter(oneWeekAgo));
  }

  /// Helper method for memoized filtered nudges
  List<NudgeModel> _getMemoizedFilteredNudges(
      String key,
      bool Function(NudgeModel) filter, {
        int Function(NudgeModel, NudgeModel)? sorter,
      }) {
    // Invalidate memoization if nudges have changed
    if (!_memoizedFilteredNudges.containsKey(key) ||
        _nudges.length != _memoizedFilteredNudges[key]?.length) {
      final filtered = _nudges.where(filter).toList();

      if (sorter != null) {
        filtered.sort(sorter);
      }

      _memoizedFilteredNudges[key] = filtered;
    }

    return _memoizedFilteredNudges[key] ?? [];
  }

  /// Initialize the provider by loading data and subscribing to updates
  Future<void> _initializeProvider() async {
    Logger.info('NudgeProvider', 'Initializing provider');

    // Restore persisted state
    _restorePersistedState();

    // Load data
    await loadNudges();
    await loadNudgeSettings();
    await loadNudgeStats();
    await loadUnreadCount();

    // Subscribe to updates
    _subscribeToNudgeUpdates();

    // Start periodic refresh of unread count
    _startUnreadCountRefresh();
  }

  /// Restore persisted state from SharedPreferences
  void _restorePersistedState() {
    try {
      // Restore selected nudge ID
      final selectedNudgeId = _prefs.getString(_selectedNudgeIdKey);
      if (selectedNudgeId != null) {
        // We'll select the nudge after loading nudges
        Logger.info('NudgeProvider', 'Found persisted selected nudge ID: $selectedNudgeId');
      }

      // Restore settings
      final settingsJson = _prefs.getString(_nudgeSettingsKey);
      if (settingsJson != null) {
        try {
          _nudgeSettings = Map<String, dynamic>.from(
              const JsonDecoder().convert(settingsJson)
          );
          Logger.info('NudgeProvider', 'Restored persisted nudge settings');
        } catch (e) {
          Logger.warning('NudgeProvider', 'Failed to parse persisted settings: $e');
        }
      }
    } catch (e, stackTrace) {
      _errorHandler.logError(
        e,
        stackTrace,
        'Failed to restore persisted state',
        NudgeErrorType.persistenceError,
      );
    }
  }

  /// Persist state to SharedPreferences
  Future<void> _persistState() async {
    try {
      // Persist selected nudge ID
      if (_selectedNudge != null && _selectedNudge!.id != null) {
        await _prefs.setString(_selectedNudgeIdKey, _selectedNudge!.id!);
      } else {
        await _prefs.remove(_selectedNudgeIdKey);
      }

      // Persist settings
      if (_nudgeSettings.isNotEmpty) {
        await _prefs.setString(
            _nudgeSettingsKey,
            const JsonEncoder().convert(_nudgeSettings)
        );
      }
    } catch (e, stackTrace) {
      _errorHandler.logError(
        e,
        stackTrace,
        'Failed to persist state',
        NudgeErrorType.persistenceError,
      );
    }
  }

  /// Load all nudges from the repository
  Future<void> loadNudges() async {
    if (_isLoading) return;

    try {
      _setLoading(true);
      _clearError();

      // Cancel any ongoing load operation
      _cancelOperation('loadNudges');
      final completer = _createCancelableOperation('loadNudges');

      Logger.info('NudgeProvider', 'Loading nudges');
      final result = await _repository.getNudges();

      // Check if operation was canceled
      if (completer.isCompleted) return;

      _nudges = result.items;
      Logger.info('NudgeProvider', 'Successfully loaded ${_nudges.length} nudges');

      // Invalidate memoized filtered lists
      _memoizedFilteredNudges.clear();

      // Try to restore selected nudge if we have an ID
      final selectedNudgeId = _prefs.getString(_selectedNudgeIdKey);
      if (selectedNudgeId != null) {
        final nudge = _nudges.firstWhere(
              (n) => n.id == selectedNudgeId,
          orElse: () => null as NudgeModel,
        );
        if (nudge != null) {
          _selectedNudge = nudge;
          Logger.info('NudgeProvider', 'Restored selected nudge: ${nudge.id}');
        }
      }

      // Log analytics event
      _analyticsService.logEvent(
        'nudges_loaded',
        {'count': _nudges.length},
      );

      // Mark operation as complete
      completer.complete();

      // Notify listeners using optimized notification
      _debouncedNotifyListeners();
    } catch (e, stackTrace) {
      final errorMessage = 'Failed to load nudges';
      _setError(errorMessage);
      _errorHandler.logError(
        e,
        stackTrace,
        errorMessage,
        NudgeErrorType.dataFetchError,
      );
    } finally {
      _setLoading(false);
    }
  }

  /// Load nudge settings from the repository
  Future<void> loadNudgeSettings() async {
    try {
      // Cancel any ongoing operation
      _cancelOperation('loadNudgeSettings');
      final completer = _createCancelableOperation('loadNudgeSettings');

      Logger.info('NudgeProvider', 'Loading nudge settings');

      // Cast to correct repository type to access specific methods
      final repoWithSettings = _repository as dynamic;

      if (repoWithSettings.getNudgeSettings != null) {
        final settings = await repoWithSettings.getNudgeSettings();

        // Check if operation was canceled
        if (completer.isCompleted) return;

        _nudgeSettings = settings;
        Logger.info('NudgeProvider', 'Successfully loaded nudge settings');

        // Persist settings
        await _persistState();

        // Log analytics event
        _analyticsService.logEvent(
          'nudge_settings_loaded',
          {'enabled': settings['isEnabled'] ?? false},
        );

        // Mark operation as complete
        completer.complete();

        // Notify listeners using optimized notification
        _debouncedNotifyListeners();
      }
    } catch (e, stackTrace) {
      final errorMessage = 'Failed to load nudge settings';
      _errorHandler.logError(
        e,
        stackTrace,
        errorMessage,
        NudgeErrorType.dataFetchError,
      );
      // Don't set UI error for settings to avoid disrupting the main flow
    }
  }

  /// Load nudge statistics from the repository
  Future<void> loadNudgeStats() async {
    try {
      // Cancel any ongoing operation
      _cancelOperation('loadNudgeStats');
      final completer = _createCancelableOperation('loadNudgeStats');

      Logger.info('NudgeProvider', 'Loading nudge statistics');

      final stats = await _repository.getNudgeStats();

      // Check if operation was canceled
      if (completer.isCompleted) return;

      _nudgeStats = stats;
      Logger.info('NudgeProvider', 'Successfully loaded nudge statistics');

      // Mark operation as complete
      completer.complete();

      // Notify listeners using optimized notification
      _debouncedNotifyListeners();
    } catch (e, stackTrace) {
      final errorMessage = 'Failed to load nudge statistics';
      _errorHandler.logError(
        e,
        stackTrace,
        errorMessage,
        NudgeErrorType.dataFetchError,
      );
      // Don't set UI error for stats to avoid disrupting the main flow
    }
  }

  /// Load unread nudge count
  Future<void> loadUnreadCount() async {
    try {
      // Cast to correct repository type to access specific methods
      final repoWithCountMethod = _repository as dynamic;

      if (repoWithCountMethod.getUnreadNudgeCount != null) {
        final count = await repoWithCountMethod.getUnreadNudgeCount();

        // Only notify if count has changed
        if (_unreadCount != count) {
          _unreadCount = count;
          Logger.info('NudgeProvider', 'Unread nudge count: $_unreadCount');

          // Notify listeners using optimized notification
          _debouncedNotifyListeners();
        }
      }
    } catch (e, stackTrace) {
      _errorHandler.logError(
        e,
        stackTrace,
        'Failed to load unread nudge count',
        NudgeErrorType.dataFetchError,
      );
    }
  }

  /// Start periodic refresh of unread count
  void _startUnreadCountRefresh() {
    // Refresh unread count every 5 minutes
    Timer.periodic(const Duration(minutes: 5), (_) {
      loadUnreadCount();
    });
  }

  /// Subscribe to real-time nudge updates
  void _subscribeToNudgeUpdates() {
    try {
      Logger.info('NudgeProvider', 'Subscribing to nudge updates');

      // Cancel any existing subscription
      _nudgesSubscription?.cancel();

      // Subscribe to the nudges stream
      _nudgesSubscription = _repository.nudgesStream().listen(
            (updatedNudges) {
          Logger.info('NudgeProvider', 'Received updated nudges: ${updatedNudges.length}');

          // Update nudges
          _nudges = updatedNudges;

          // Invalidate memoized filtered lists
          _memoizedFilteredNudges.clear();

          // Update selected nudge if it's in the list
          if (_selectedNudge != null) {
            _selectedNudge = _nudges.firstWhere(
                  (nudge) => nudge.id == _selectedNudge!.id,
              orElse: () => _selectedNudge!,
            );
          }

          // Refresh unread count
          loadUnreadCount();

          // Notify listeners using optimized notification
          _debouncedNotifyListeners();
        },
        onError: (e, stackTrace) {
          _errorHandler.logError(
            e,
            stackTrace,
            'Error in nudge updates stream',
            NudgeErrorType.streamError,
          );
        },
      );
    } catch (e, stackTrace) {
      _errorHandler.logError(
        e,
        stackTrace,
        'Failed to subscribe to nudge updates',
        NudgeErrorType.streamError,
      );
    }
  }

  /// Set a nudge as the selected nudge
  void selectNudge(String? nudgeId) {
    if (nudgeId == null) {
      _selectedNudge = null;
    } else {
      final nudge = _nudges.firstWhere(
            (nudge) => nudge.id == nudgeId,
        orElse: () => null as NudgeModel,
      );

      // Only update if nudge found and different from current selection
      if (nudge != null && (_selectedNudge?.id != nudge.id)) {
        _selectedNudge = nudge;

        // Persist selected nudge ID
        _persistState();

        // Log analytics event
        _analyticsService.logEvent(
          'nudge_selected',
          {'nudge_id': nudgeId},
        );
      }
    }

    // Notify listeners using optimized notification
    _debouncedNotifyListeners();
  }

  /// Create a new nudge
  Future<String?> createNudge(NudgeModel nudge) async {
    if (_isLoading) return null;

    try {
      _setLoading(true);
      _clearError();

      // Cancel any ongoing operation
      _cancelOperation('createNudge');
      final completer = _createCancelableOperation('createNudge');

      Logger.info('NudgeProvider', 'Creating new nudge');
      final nudgeId = await _repository.createNudge(nudge);

      // Check if operation was canceled
      if (completer.isCompleted) return null;

      if (nudgeId != null) {
        Logger.info('NudgeProvider', 'Successfully created nudge with ID: $nudgeId');

        // Refresh stats
        loadNudgeStats();

        // Log analytics event
        _analyticsService.logEvent(
          'nudge_created',
          {'nudge_id': nudgeId},
        );

        // Mark operation as complete
        completer.complete();
      }

      return nudgeId;
    } catch (e, stackTrace) {
      final errorMessage = 'Failed to create nudge';
      _setError(errorMessage);
      _errorHandler.logError(
        e,
        stackTrace,
        errorMessage,
        NudgeErrorType.dataWriteError,
      );
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Update an existing nudge
  Future<bool> updateNudge(NudgeModel nudge) async {
    if (_isLoading) return false;

    try {
      _setLoading(true);
      _clearError();

      // Cancel any ongoing operation
      _cancelOperation('updateNudge');
      final completer = _createCancelableOperation('updateNudge');

      Logger.info('NudgeProvider', 'Updating nudge with ID: ${nudge.id}');
      final success = await _repository.updateNudge(nudge);

      // Check if operation was canceled
      if (completer.isCompleted) return false;

      if (success) {
        Logger.info('NudgeProvider', 'Successfully updated nudge with ID: ${nudge.id}');

        // Update selected nudge if it's the one being updated
        if (_selectedNudge?.id == nudge.id) {
          _selectedNudge = nudge;

          // Persist selected nudge
          _persistState();
        }

        // Refresh stats
        loadNudgeStats();

        // Log analytics event
        _analyticsService.logEvent(
          'nudge_updated',
          {'nudge_id': nudge.id},
        );

        // Mark operation as complete
        completer.complete();
      }

      return success;
    } catch (e, stackTrace) {
      final errorMessage = 'Failed to update nudge';
      _setError(errorMessage);
      _errorHandler.logError(
        e,
        stackTrace,
        errorMessage,
        NudgeErrorType.dataWriteError,
      );
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Delete a nudge
  Future<bool> deleteNudge(String id) async {
    if (_isLoading) return false;

    try {
      _setLoading(true);
      _clearError();

      // Cancel any ongoing operation
      _cancelOperation('deleteNudge');
      final completer = _createCancelableOperation('deleteNudge');

      Logger.info('NudgeProvider', 'Deleting nudge with ID: $id');
      final success = await _repository.deleteNudge(id);

      // Check if operation was canceled
      if (completer.isCompleted) return false;

      if (success) {
        Logger.info('NudgeProvider', 'Successfully deleted nudge with ID: $id');

        // Clear selected nudge if it's the one being deleted
        if (_selectedNudge?.id == id) {
          _selectedNudge = null;

          // Update persisted state
          _persistState();
        }

        // Refresh stats
        loadNudgeStats();

        // Log analytics event
        _analyticsService.logEvent(
          'nudge_deleted',
          {'nudge_id': id},
        );

        // Mark operation as complete
        completer.complete();
      }

      return success;
    } catch (e, stackTrace) {
      final errorMessage = 'Failed to delete nudge';
      _setError(errorMessage);
      _errorHandler.logError(
        e,
        stackTrace,
        errorMessage,
        NudgeErrorType.dataWriteError,
      );
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Record user feedback for a nudge
  Future<bool> recordNudgeFeedback(String id, int rating, String? comment) async {
    try {
      // Cancel any ongoing operation
      _cancelOperation('recordNudgeFeedback');
      final completer = _createCancelableOperation('recordNudgeFeedback');

      Logger.info('NudgeProvider', 'Recording feedback for nudge with ID: $id');
      final success = await _repository.recordNudgeFeedback(id, rating, comment);

      // Check if operation was canceled
      if (completer.isCompleted) return false;

      if (success) {
        Logger.info('NudgeProvider', 'Successfully recorded feedback for nudge with ID: $id');

        // Refresh stats
        loadNudgeStats();

        // Log analytics event
        _analyticsService.logEvent(
          'nudge_feedback_recorded',
          {
            'nudge_id': id,
            'rating': rating,
            'has_comment': comment != null && comment.isNotEmpty,
          },
        );

        // Mark operation as complete
        completer.complete();
      }

      return success;
    } catch (e, stackTrace) {
      final errorMessage = 'Failed to record feedback for nudge';
      _errorHandler.logError(
        e,
        stackTrace,
        errorMessage,
        NudgeErrorType.dataWriteError,
      );
      return false;
    }
  }

  /// Save user nudge settings
  Future<bool> saveNudgeSettings(Map<String, dynamic> settings) async {
    // Cancel any previous debounce timer
    _saveSettingsDebounceTimer?.cancel();

    // Debounce save operation to avoid excessive writes
    return await _debounce<bool>(
          () async {
        try {
          Logger.info('NudgeProvider', 'Saving nudge settings');

          // Cast to correct repository type to access specific methods
          final repoWithSettings = _repository as dynamic;

          if (repoWithSettings.saveNudgeSettings != null) {
            final success = await repoWithSettings.saveNudgeSettings(settings);

            if (success) {
              Logger.info('NudgeProvider', 'Successfully saved nudge settings');
              _nudgeSettings = settings;

              // Persist settings
              await _persistState();

              // Log analytics event
              _analyticsService.logEvent(
                'nudge_settings_updated',
                {'enabled': settings['isEnabled'] ?? false},
              );

              // Notify listeners using optimized notification
              _debouncedNotifyListeners();
            }

            return success;
          }

          return false;
        } catch (e, stackTrace) {
          final errorMessage = 'Failed to save nudge settings';
          _errorHandler.logError(
            e,
            stackTrace,
            errorMessage,
            NudgeErrorType.dataWriteError,
          );
          return false;
        }
      },
      key: 'saveNudgeSettings',
      delay: const Duration(milliseconds: 500),
    );
  }

  /// Mark a nudge as delivered
  Future<bool> markNudgeAsDelivered(String id) async {
    try {
      Logger.info('NudgeProvider', 'Marking nudge as delivered with ID: $id');
      final deliveredAt = DateTime.now();
      final success = await _repository.markNudgeAsDelivered(id, deliveredAt);

      if (success) {
        Logger.info('NudgeProvider', 'Successfully marked nudge as delivered with ID: $id');

        // Update local nudge if it's in the list
        final index = _nudges.indexWhere((n) => n.id == id);
        if (index >= 0) {
          final updatedNudge = _nudges[index].copyWith(
            lastDeliveredAt: deliveredAt,
            deliveryCount: (_nudges[index].deliveryCount ?? 0) + 1,
          );

          // Update nudge in list
          _nudges[index] = updatedNudge;

          // Update selected nudge if needed
          if (_selectedNudge?.id == id) {
            _selectedNudge = updatedNudge;
          }

          // Invalidate memoized filtered lists
          _memoizedFilteredNudges.clear();

          // Refresh unread count
          loadUnreadCount();

          // Notify listeners using optimized notification
          _debouncedNotifyListeners();
        }

        // Log analytics event
        _analyticsService.logEvent(
          'nudge_delivered',
          {'nudge_id': id},
        );
      }

      return success;
    } catch (e, stackTrace) {
      final errorMessage = 'Failed to mark nudge as delivered';
      _errorHandler.logError(
        e,
        stackTrace,
        errorMessage,
        NudgeErrorType.dataWriteError,
      );
      return false;
    }
  }

  /// Mark a nudge as acted upon
  Future<bool> markNudgeAsActedUpon(String id) async {
    try {
      Logger.info('NudgeProvider', 'Marking nudge as acted upon with ID: $id');
      final actedAt = DateTime.now();
      final success = await _repository.markNudgeAsActedUpon(id, actedAt);

      if (success) {
        Logger.info('NudgeProvider', 'Successfully marked nudge as acted upon with ID: $id');

        // Update local nudge if it's in the list
        final index = _nudges.indexWhere((n) => n.id == id);
        if (index >= 0) {
          final updatedNudge = _nudges[index].copyWith(
            lastActedAt: actedAt,
            actionCount: (_nudges[index].actionCount ?? 0) + 1,
          );

          // Update nudge in list
          _nudges[index] = updatedNudge;

          // Update selected nudge if needed
          if (_selectedNudge?.id == id) {
            _selectedNudge = updatedNudge;
          }

          // Invalidate memoized filtered lists
          _memoizedFilteredNudges.clear();

          // Refresh unread count
          loadUnreadCount();

          // Notify listeners using optimized notification
          _debouncedNotifyListeners();
        }

        // Log analytics event
        _analyticsService.logEvent(
          'nudge_acted_upon',
          {'nudge_id': id},
        );
      }

      return success;
    } catch (e, stackTrace) {
      final errorMessage = 'Failed to mark nudge as acted upon';
      _errorHandler.logError(
        e,
        stackTrace,
        errorMessage,
        NudgeErrorType.dataWriteError,
      );
      return false;
    }
  }

  /// Get active nudges that should be triggered now
  Future<List<NudgeModel>> getActiveNudges() async {
    try {
      Logger.info('NudgeProvider', 'Getting active nudges');
      final activeNudges = await _repository.getActiveNudges();

      Logger.info('NudgeProvider', 'Found ${activeNudges.length} active nudges');
      return activeNudges;
    } catch (e, stackTrace) {
      final errorMessage = 'Failed to get active nudges';
      _errorHandler.logError(
        e,
        stackTrace,
        errorMessage,
        NudgeErrorType.dataFetchError,
      );
      return [];
    }
  }

  /// Helper method to create a cancelable operation
  Completer<void> _createCancelableOperation(String key) {
    final completer = Completer<void>();
    _cancelableOperations[key] = completer;
    return completer;
  }

  /// Helper method to cancel an operation
  void _cancelOperation(String key) {
    final completer = _cancelableOperations[key];
    if (completer != null && !completer.isCompleted) {
      completer.complete();
      Logger.info('NudgeProvider', 'Canceled operation: $key');
    }
    _cancelableOperations.remove(key);
  }

  /// Generic debounce method
  Future<T> _debounce<T>(
      Future<T> Function() operation, {
        required String key,
        required Duration delay,
      }) {
    final completer = Completer<T>();

    // Cancel previous timer
    _saveSettingsDebounceTimer?.cancel();

    // Start new timer
    _saveSettingsDebounceTimer = Timer(delay, () async {
      try {
        final result = await operation();
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (e, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(e, stackTrace);
        }
      }
    });

    return completer.future;
  }

  /// Helper method to set loading state
  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;

      // Notify listeners immediately for loading state changes
      notifyListeners();
    }
  }

  /// Helper method to set error state
  void _setError(String? errorMessage) {
    _error = errorMessage;

    if (errorMessage != null) {
      // Log analytics error event
      _analyticsService.logEvent(
        'nudge_provider_error',
        {'error': errorMessage},
      );
    }

    // Notify listeners immediately for error state changes
    notifyListeners();
  }

  /// Helper method to clear error state
  void _clearError() {
    if (_error != null) {
      _error = null;
      // We'll notify listeners when the operation completes
    }
  }

  /// Debounced notifyListeners to avoid excessive rebuilds
  void _debouncedNotifyListeners() {
    _notifyListenersDebounceTimer?.cancel();
    _notifyListenersDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      notifyListeners();
    });
  }

  /// Clears all cached data and reloads from repository
  Future<void> refresh() async {
    // Clear memoized data
    _memoizedFilteredNudges.clear();

    // Clear repository cache if available
    try {
      final repoWithCache = _repository as dynamic;
      if (repoWithCache.clearCache != null) {
        await repoWithCache.clearCache();
      }
    } catch (e) {
      // Ignore cast errors
    }

    // Reload all data
    await loadNudges();
    await loadNudgeSettings();
    await loadNudgeStats();
    await loadUnreadCount();
  }

  // Clean up resources when provider is disposed
  @override
  void dispose() {
    // Cancel subscriptions
    _nudgesSubscription?.cancel();

    // Cancel timers
    _saveSettingsDebounceTimer?.cancel();
    _notifyListenersDebounceTimer?.cancel();

    // Cancel all operations
    for (final key in _cancelableOperations.keys) {
      _cancelOperation(key);
    }

    super.dispose();
  }
}