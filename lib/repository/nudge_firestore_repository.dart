// Copyright © 2025 Milo App. All rights reserved.
// Author: Milo Development Team
// File: lib/repository/nudge_firestore_repository.dart
// Version: 1.0.0
//CRUD, caching, rate limiting, resource cleanup
// Last Updated: April 23, 2025


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../models/nudge_model.dart';
import '../models/nudge_error_models.dart';
import '../utils/logger.dart';
import '../utils/nudge_error_handler.dart';
import 'nudge_repository.dart';
import '../theme/app_theme.dart';

/// Implementation of [NudgeRepository] using Firebase Firestore
/// This class handles all nudge-related database operations with Firestore
/// with caching, batched operations, and optimized queries.
///
/// @version 1.0.2
/// @see FirestoreSecurityRules.md for required security rules
class NudgeFirestoreRepository implements NudgeRepository<NudgeModel> {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final NudgeErrorHandler _errorHandler;
  final SharedPreferences _prefs;

  // Collection references
  static const String _nudgesCollection = 'nudges';
  static const String _nudgeTemplatesCollection = 'nudgeTemplates';
  static const String _nudgeSettingsCollection = 'nudgeSettings';
  static const String _nudgeFeedbackCollection = 'nudgeFeedback';

  // Cache keys and settings
  static const String _cacheKeyPrefix = 'nudge_cache_';
  static const Duration _cacheDuration = Duration(minutes: 15);
  static const int _requestLimitPerMinute = 100;

  // Request rate limiting
  final Map<String, int> _requestCounts = {};
  final Map<String, DateTime> _requestTimestamps = {};

  // In-memory cache for frequently accessed data
  final Map<String, _CacheEntry<NudgeModel>> _nudgeCache = {};
  final Map<String, _CacheEntry<Map<String, dynamic>>> _settingsCache = {};
  final Map<String, _CacheEntry<List<NudgeModel>>> _listCache = {};

  // Singleton pattern with lazy initialization
  static NudgeFirestoreRepository? _instance;

  // Factory constructor to return the singleton instance
  factory NudgeFirestoreRepository() {
    _instance ??= NudgeFirestoreRepository._internal(
      FirebaseFirestore.instance,
      FirebaseAuth.instance,
      NudgeErrorHandler(),
      SharedPreferences.getInstance(),
    );
    return _instance!;
  }

  // Private constructor for singleton
  NudgeFirestoreRepository._internal(
      this._firestore,
      this._auth,
      this._errorHandler,
      Future<SharedPreferences> prefsFuture,
      ) : _prefs = SharedPreferences.getInstance().then((prefs) => prefs) as SharedPreferences {
    // Configure Firestore settings for better performance
    _configureFirestore();

    // Start cache cleanup timer
    _startCacheCleanupTimer();
  }

  // Constructor for dependency injection in tests
  @visibleForTesting
  NudgeFirestoreRepository.forTesting(
      this._firestore,
      this._auth,
      this._errorHandler,
      this._prefs,
      ) {
    _configureFirestore();
  }

  /// Configure Firestore settings for better performance
  void _configureFirestore() {
    // Configure persistence if available
    _firestore.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  /// Start a timer to periodically clean up expired cache entries
  void _startCacheCleanupTimer() {
    Timer.periodic(const Duration(minutes: 5), (_) {
      _cleanupExpiredCache();
    });
  }

  /// Clean up expired cache entries
  void _cleanupExpiredCache() {
    final now = DateTime.now();

    // Clean up in-memory caches
    _nudgeCache.removeWhere((key, entry) => now.isAfter(entry.expiresAt));
    _settingsCache.removeWhere((key, entry) => now.isAfter(entry.expiresAt));
    _listCache.removeWhere((key, entry) => now.isAfter(entry.expiresAt));

    // Clean up rate limiting data
    _requestCounts.removeWhere((key, _) {
      final timestamp = _requestTimestamps[key];
      if (timestamp == null) return true;
      return now.difference(timestamp).inMinutes > 1;
    });
    _requestTimestamps.removeWhere((key, timestamp) {
      return now.difference(timestamp).inMinutes > 1;
    });

    Logger.debug('NudgeFirestoreRepository', 'Cache cleanup completed');
  }

  /// Rate limit check for operations
  /// Throws exception if rate limit is exceeded
  void _checkRateLimit(String operationKey) {
    final now = DateTime.now();
    final key = '${operationKey}_${now.minute}';

    // Initialize or update counters
    if (_requestCounts[key] == null || _requestTimestamps[key] == null) {
      _requestCounts[key] = 1;
      _requestTimestamps[key] = now;
    } else {
      _requestCounts[key] = (_requestCounts[key] ?? 0) + 1;
    }

    // Check rate limit
    if ((_requestCounts[key] ?? 0) > _requestLimitPerMinute) {
      throw NudgeRepositoryException(
        'Rate limit exceeded for operation: $operationKey',
        NudgeErrorType.rateLimitExceeded,
      );
    }
  }

  /// Gets the current user ID or throws an exception if not authenticated
  String _getCurrentUserId() {
    final user = _auth.currentUser;
    if (user == null) {
      throw NudgeRepositoryException(
        'User not authenticated',
        NudgeErrorType.authenticationError,
      );
    }
    return user.uid;
  }

  /// Reference to the user's nudges collection
  CollectionReference<Map<String, dynamic>> _getUserNudgesCollection() {
    final userId = _getCurrentUserId();
    return _firestore
        .collection('users')
        .doc(userId)
        .collection(_nudgesCollection);
  }

  /// Retries an operation with exponential backoff
  /// Returns the result of the operation or throws the last exception
  Future<T> _retryWithBackoff<T>({
    required Future<T> Function() operation,
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 200),
  }) async {
    int attempts = 0;
    Duration delay = initialDelay;
    dynamic lastException;
    StackTrace? lastStackTrace;

    while (attempts < maxRetries) {
      try {
        return await operation();
      } catch (e, stackTrace) {
        lastException = e;
        lastStackTrace = stackTrace;

        // Only retry on certain types of errors
        if (e is FirebaseException &&
            (e.code == 'unavailable' || e.code == 'deadline-exceeded')) {
          attempts++;
          if (attempts >= maxRetries) break;

          // Log retry attempt
          Logger.warning(
            'NudgeFirestoreRepository',
            'Retrying operation (${attempts}/${maxRetries}) after error: ${e.code}',
          );

          // Wait with exponential backoff
          await Future.delayed(delay);
          delay *= 2;
        } else {
          // Don't retry on other errors
          rethrow;
        }
      }
    }

    // If we get here, all retries failed
    Error.throwWithStackTrace(lastException, lastStackTrace!);
  }

  @override
  Future<NudgePaginatedResult<NudgeModel>> getNudges({
    int limit = 50,
    String? startAfter,
    String orderBy = 'createdAt',
    bool descending = true,
  }) async {
    try {
      _checkRateLimit('getNudges');
      Logger.info('NudgeFirestoreRepository', 'Fetching nudges for user');

      // Generate cache key
      final cacheKey = 'getNudges_${limit}_${startAfter ?? "null"}_${orderBy}_$descending';

      // Check in-memory cache first
      final cachedList = _listCache[cacheKey];
      if (cachedList != null && DateTime.now().isBefore(cachedList.expiresAt)) {
        Logger.info('NudgeFirestoreRepository', 'Returning cached nudges: ${cachedList.data.length}');
        return NudgePaginatedResult<NudgeModel>(
          items: cachedList.data,
          hasMore: cachedList.data.length >= limit,
          lastDocumentId: cachedList.data.isNotEmpty ? cachedList.data.last.id : null,
        );
      }

      // Build query
      Query<Map<String, dynamic>> query = _getUserNudgesCollection()
          .orderBy(orderBy, descending: descending)
          .limit(limit);

      // Add start after for pagination
      if (startAfter != null) {
        // Get the document to start after
        final startAfterDoc = await _getUserNudgesCollection().doc(startAfter).get();
        if (startAfterDoc.exists) {
          query = query.startAfterDocument(startAfterDoc);
        }
      }

      // Execute query with retry for network issues
      final querySnapshot = await _retryWithBackoff(
        operation: () => query.get(),
      );

      final nudges = querySnapshot.docs
          .map((doc) => NudgeModel.fromMap(doc.data(), doc.id))
          .toList();

      Logger.info('NudgeFirestoreRepository', 'Successfully fetched ${nudges.length} nudges');

      // Cache the results
      _listCache[cacheKey] = _CacheEntry<List<NudgeModel>>(
        nudges,
        DateTime.now().add(_cacheDuration),
      );

      // Cache individual nudges
      for (final nudge in nudges) {
        if (nudge.id != null) {
          _nudgeCache[nudge.id!] = _CacheEntry<NudgeModel>(
            nudge,
            DateTime.now().add(_cacheDuration),
          );
        }
      }

      return NudgePaginatedResult<NudgeModel>(
        items: nudges,
        hasMore: nudges.length >= limit,
        lastDocumentId: nudges.isNotEmpty ? nudges.last.id : null,
      );
    } catch (e, stackTrace) {
      throw _errorHandler.handleRepositoryException(
        e,
        stackTrace,
        'Failed to fetch nudges',
        NudgeErrorType.dataFetchError,
      );
    }
  }

  @override
  Future<NudgeModel?> getNudgeById(String id) async {
    try {
      _checkRateLimit('getNudgeById');
      Logger.info('NudgeFirestoreRepository', 'Fetching nudge with ID: $id');

      // Check in-memory cache first
      final cachedNudge = _nudgeCache[id];
      if (cachedNudge != null && DateTime.now().isBefore(cachedNudge.expiresAt)) {
        Logger.info('NudgeFirestoreRepository', 'Returning cached nudge: $id');
        return cachedNudge.data;
      }

      // Check if we have this nudge cached in shared preferences
      final cacheKey = '${_cacheKeyPrefix}nudge_$id';
      final cachedJson = _prefs.getString(cacheKey);
      if (cachedJson != null) {
        try {
          // Deserialize and check cache timestamp
          final cachedData = await NudgeModel.fromJson(cachedJson);
          final cachedTimestamp = _prefs.getInt('${cacheKey}_timestamp') ?? 0;
          final now = DateTime.now().millisecondsSinceEpoch;

          // If cache is still valid, return it
          if (now - cachedTimestamp < _cacheDuration.inMilliseconds) {
            Logger.info('NudgeFirestoreRepository', 'Returning cached nudge from prefs: $id');

            // Update in-memory cache
            _nudgeCache[id] = _CacheEntry<NudgeModel>(
              cachedData,
              DateTime.now().add(_cacheDuration),
            );

            return cachedData;
          }
        } catch (e) {
          // Ignore cache deserialization errors and fetch from network
          Logger.warning('NudgeFirestoreRepository', 'Cache deserialization error: $e');
        }
      }

      // Fetch from network with retry for network issues
      final docSnapshot = await _retryWithBackoff(
        operation: () => _getUserNudgesCollection().doc(id).get(),
      );

      if (!docSnapshot.exists) {
        Logger.warning('NudgeFirestoreRepository', 'Nudge not found with ID: $id');
        return null;
      }

      final nudge = NudgeModel.fromMap(docSnapshot.data()!, docSnapshot.id);

      // Cache the result in memory
      _nudgeCache[id] = _CacheEntry<NudgeModel>(
        nudge,
        DateTime.now().add(_cacheDuration),
      );

      // Cache the result in shared preferences
      if (nudge.id != null) {
        await _prefs.setString(cacheKey, nudge.toJson());
        await _prefs.setInt(
          '${cacheKey}_timestamp',
          DateTime.now().millisecondsSinceEpoch,
        );
      }

      return nudge;
    } catch (e, stackTrace) {
      throw _errorHandler.handleRepositoryException(
        e,
        stackTrace,
        'Failed to fetch nudge with ID: $id',
        NudgeErrorType.dataFetchError,
      );
    }
  }

  @override
  Future<String?> createNudge(NudgeModel nudge) async {
    try {
      _checkRateLimit('createNudge');
      Logger.info('NudgeFirestoreRepository', 'Creating new nudge');

      // Validate nudge
      if (nudge.content == null || nudge.content!.isEmpty) {
        throw ArgumentError('Nudge content cannot be empty');
      }

      // Create a map without the ID as Firestore will generate one
      final nudgeMap = nudge.toMap();

      // Add created timestamp and user info if not already present
      nudgeMap['createdAt'] ??= FieldValue.serverTimestamp();
      nudgeMap['userId'] ??= _getCurrentUserId();

      // Execute with retry for network issues
      final docRef = await _retryWithBackoff(
        operation: () => _getUserNudgesCollection().add(nudgeMap),
      );

      final id = docRef.id;
      Logger.info('NudgeFirestoreRepository', 'Successfully created nudge with ID: $id');

      // Update the nudge model with the new ID
      final createdNudge = nudge.copyWith(id: id);

      // Cache the newly created nudge
      _nudgeCache[id] = _CacheEntry<NudgeModel>(
        createdNudge,
        DateTime.now().add(_cacheDuration),
      );

      // Invalidate list cache as we've added a new item
      _invalidateListCache();

      return id;
    } catch (e, stackTrace) {
      _errorHandler.handleRepositoryException(
        e,
        stackTrace,
        'Failed to create nudge',
        NudgeErrorType.dataWriteError,
      );
      return null;
    }
  }

  @override
  Future<bool> updateNudge(NudgeModel nudge) async {
    try {
      _checkRateLimit('updateNudge');

      if (nudge.id == null || nudge.id!.isEmpty) {
        throw ArgumentError('Nudge ID cannot be null or empty for update operation');
      }

      Logger.info('NudgeFirestoreRepository', 'Updating nudge with ID: ${nudge.id}');

      // Create a map from the nudge model
      final nudgeMap = nudge.toMap();

      // Add updated timestamp
      nudgeMap['updatedAt'] = FieldValue.serverTimestamp();

      // Execute with retry for network issues
      await _retryWithBackoff(
        operation: () => _getUserNudgesCollection().doc(nudge.id).update(nudgeMap),
      );

      Logger.info('NudgeFirestoreRepository', 'Successfully updated nudge with ID: ${nudge.id}');

      // Update cache
      _nudgeCache[nudge.id!] = _CacheEntry<NudgeModel>(
        nudge,
        DateTime.now().add(_cacheDuration),
      );

      // Update the shared preferences cache
      final cacheKey = '${_cacheKeyPrefix}nudge_${nudge.id}';
      await _prefs.setString(cacheKey, nudge.toJson());
      await _prefs.setInt(
        '${cacheKey}_timestamp',
        DateTime.now().millisecondsSinceEpoch,
      );

      // Invalidate list cache
      _invalidateListCache();

      return true;
    } catch (e, stackTrace) {
      throw _errorHandler.handleRepositoryException(
        e,
        stackTrace,
        'Failed to update nudge with ID: ${nudge.id}',
        NudgeErrorType.dataWriteError,
      );
    }
  }

  @override
  Future<bool> deleteNudge(String id) async {
    try {
      _checkRateLimit('deleteNudge');
      Logger.info('NudgeFirestoreRepository', 'Deleting nudge with ID: $id');

      // Execute with retry for network issues
      await _retryWithBackoff(
        operation: () => _getUserNudgesCollection().doc(id).delete(),
      );

      Logger.info('NudgeFirestoreRepository', 'Successfully deleted nudge with ID: $id');

      // Remove from caches
      _nudgeCache.remove(id);

      final cacheKey = '${_cacheKeyPrefix}nudge_$id';
      await _prefs.remove(cacheKey);
      await _prefs.remove('${cacheKey}_timestamp');

      // Invalidate list cache
      _invalidateListCache();

      return true;
    } catch (e, stackTrace) {
      throw _errorHandler.handleRepositoryException(
        e,
        stackTrace,
        'Failed to delete nudge with ID: $id',
        NudgeErrorType.dataWriteError,
      );
    }
  }

  @override
  Future<List<NudgeModel>> getActiveNudges({int limit = 10}) async {
    try {
      _checkRateLimit('getActiveNudges');
      Logger.info('NudgeFirestoreRepository', 'Fetching active nudges');

      final now = DateTime.now();
      final currentTimeOfDay = now.hour * 60 + now.minute; // Minutes since midnight

      // Generate cache key
      final cacheKey = 'getActiveNudges_${now.day}_${now.hour}';

      // Check in-memory cache first
      final cachedList = _listCache[cacheKey];
      if (cachedList != null && DateTime.now().isBefore(cachedList.expiresAt)) {
        Logger.info('NudgeFirestoreRepository', 'Returning cached active nudges: ${cachedList.data.length}');
        return cachedList.data;
      }

      // Optimized query with compound index
      final querySnapshot = await _retryWithBackoff(
        operation: () => _getUserNudgesCollection()
            .where('isActive', isEqualTo: true)
            .where('scheduledDays', arrayContains: now.weekday) // Weekday: 1-7 (Monday-Sunday)
            .where('scheduledMinutes', isLessThanOrEqualTo: currentTimeOfDay)
            .orderBy('scheduledMinutes', descending: true)
            .limit(limit)
            .get(),
      );

      final nudges = querySnapshot.docs
          .map((doc) => NudgeModel.fromMap(doc.data(), doc.id))
          .toList();

      Logger.info('NudgeFirestoreRepository', 'Successfully fetched ${nudges.length} active nudges');

      // Cache results for a shorter period (active nudges change frequently)
      _listCache[cacheKey] = _CacheEntry<List<NudgeModel>>(
        nudges,
        DateTime.now().add(const Duration(minutes: 5)),
      );

      // Also cache individual nudges
      for (final nudge in nudges) {
        if (nudge.id != null) {
          _nudgeCache[nudge.id!] = _CacheEntry<NudgeModel>(
            nudge,
            DateTime.now().add(_cacheDuration),
          );
        }
      }

      return nudges;
    } catch (e, stackTrace) {
      throw _errorHandler.handleRepositoryException(
        e,
        stackTrace,
        'Failed to fetch active nudges',
        NudgeErrorType.dataFetchError,
      );
    }
  }

  @override
  Future<bool> markNudgeAsDelivered(String id, DateTime deliveredAt) async {
    try {
      _checkRateLimit('markNudgeAsDelivered');
      Logger.info('NudgeFirestoreRepository', 'Marking nudge as delivered: $id');

      await _retryWithBackoff(
        operation: () => _getUserNudgesCollection().doc(id).update({
          'lastDeliveredAt': Timestamp.fromDate(deliveredAt),
          'deliveryCount': FieldValue.increment(1),
        }),
      );

      Logger.info('NudgeFirestoreRepository', 'Successfully marked nudge as delivered: $id');

      // Update cache if we have this nudge cached
      final cachedNudge = _nudgeCache[id]?.data;
      if (cachedNudge != null) {
        final updatedNudge = cachedNudge.copyWith(
          lastDeliveredAt: deliveredAt,
          deliveryCount: (cachedNudge.deliveryCount ?? 0) + 1,
        );

        _nudgeCache[id] = _CacheEntry<NudgeModel>(
          updatedNudge,
          DateTime.now().add(_cacheDuration),
        );
      } else {
        // Invalidate the cache for this nudge
        _nudgeCache.remove(id);
        final cacheKey = '${_cacheKeyPrefix}nudge_$id';
        await _prefs.remove(cacheKey);
        await _prefs.remove('${cacheKey}_timestamp');
      }

      return true;
    } catch (e, stackTrace) {
      throw _errorHandler.handleRepositoryException(
        e,
        stackTrace,
        'Failed to mark nudge as delivered with ID: $id',
        NudgeErrorType.dataWriteError,
      );
    }
  }

  @override
  Future<bool> markNudgeAsActedUpon(String id, DateTime actedAt) async {
    try {
      _checkRateLimit('markNudgeAsActedUpon');
      Logger.info('NudgeFirestoreRepository', 'Marking nudge as acted upon: $id');

      await _retryWithBackoff(
        operation: () => _getUserNudgesCollection().doc(id).update({
          'lastActedAt': Timestamp.fromDate(actedAt),
          'actionCount': FieldValue.increment(1),
        }),
      );

      Logger.info('NudgeFirestoreRepository', 'Successfully marked nudge as acted upon: $id');

      // Update cache if we have this nudge cached
      final cachedNudge = _nudgeCache[id]?.data;
      if (cachedNudge != null) {
        final updatedNudge = cachedNudge.copyWith(
          lastActedAt: actedAt,
          actionCount: (cachedNudge.actionCount ?? 0) + 1,
        );

        _nudgeCache[id] = _CacheEntry<NudgeModel>(
          updatedNudge,
          DateTime.now().add(_cacheDuration),
        );
      } else {
        // Invalidate the cache for this nudge
        _nudgeCache.remove(id);
        final cacheKey = '${_cacheKeyPrefix}nudge_$id';
        await _prefs.remove(cacheKey);
        await _prefs.remove('${cacheKey}_timestamp');
      }

      return true;
    } catch (e, stackTrace) {
      throw _errorHandler.handleRepositoryException(
        e,
        stackTrace,
        'Failed to mark nudge as acted upon with ID: $id',
        NudgeErrorType.dataWriteError,
      );
    }
  }

  @override
  Future<bool> recordNudgeFeedback(String id, int rating, String? comment) async {
    try {
      _checkRateLimit('recordNudgeFeedback');
      Logger.info('NudgeFirestoreRepository', 'Recording feedback for nudge: $id');

      final userId = _getCurrentUserId();

      // Execute feedback creation within a transaction to ensure consistency
      await _firestore.runTransaction((transaction) async {
        // Add feedback document
        final feedbackRef = _firestore.collection(_nudgeFeedbackCollection).doc();
        transaction.set(feedbackRef, {
          'nudgeId': id,
          'userId': userId,
          'rating': rating,
          'comment': comment,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Get current nudge data
        final nudgeRef = _getUserNudgesCollection().doc(id);
        final nudgeSnapshot = await transaction.get(nudgeRef);

        if (nudgeSnapshot.exists) {
          final nudgeData = nudgeSnapshot.data()!;
          final currentRating = nudgeData['averageRating'] ?? 0.0;
          final ratingCount = nudgeData['ratingCount'] ?? 0;

          // Calculate new average
          final newRatingCount = ratingCount + 1;
          final newAverage = ((currentRating * ratingCount) + rating) / newRatingCount;

          // Update the nudge document
          transaction.update(nudgeRef, {
            'averageRating': newAverage,
            'ratingCount': newRatingCount,
            'lastFeedbackAt': FieldValue.serverTimestamp(),
          });
        }
      });

      Logger.info('NudgeFirestoreRepository', 'Successfully recorded feedback for nudge: $id');

      // Invalidate cache for this nudge
      _nudgeCache.remove(id);
      final cacheKey = '${_cacheKeyPrefix}nudge_$id';
      await _prefs.remove(cacheKey);
      await _prefs.remove('${cacheKey}_timestamp');

      return true;
    } catch (e, stackTrace) {
      throw _errorHandler.handleRepositoryException(
        e,
        stackTrace,
        'Failed to record feedback for nudge with ID: $id',
        NudgeErrorType.dataWriteError,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> getNudgeStats() async {
    try {
      _checkRateLimit('getNudgeStats');
      Logger.info('NudgeFirestoreRepository', 'Fetching nudge statistics');

      // Cache key for stats
      final cacheKey = 'nudgeStats_${DateTime.now().day}';

      // Check if we have cached stats
      final cachedStats = _settingsCache[cacheKey];
      if (cachedStats != null && DateTime.now().isBefore(cachedStats.expiresAt)) {
        Logger.info('NudgeFirestoreRepository', 'Returning cached nudge statistics');
        return cachedStats.data;
      }

      // Use aggregation queries if available, otherwise do it client-side
      // For now, using optimized client-side aggregation with limit
      final querySnapshot = await _retryWithBackoff(
        operation: () => _getUserNudgesCollection()
            .limit(1000) // Limiting to prevent excessive reads
            .get(),
      );

      int totalNudges = querySnapshot.docs.length;
      int activeNudges = 0;
      int deliveredNudges = 0;
      int actedUponNudges = 0;
      double averageRating = 0.0;
      int totalRatings = 0;

      for (var doc in querySnapshot.docs) {
        final data = doc.data();

        if (data['isActive'] == true) {
          activeNudges++;
        }

        final deliveryCount = data['deliveryCount'] ?? 0;
        if (deliveryCount > 0) {
          deliveredNudges++;
        }

        final actionCount = data['actionCount'] ?? 0;
        if (actionCount > 0) {
          actedUponNudges++;
        }

        final rating = data['averageRating'] ?? 0.0;
        final ratingCount = data['ratingCount'] ?? 0;

        if (ratingCount > 0) {
          averageRating += rating * ratingCount;
          totalRatings += ratingCount;
        }
      }

      if (totalRatings > 0) {
        averageRating /= totalRatings;
      }

      final stats = {
        'totalNudges': totalNudges,
        'activeNudges': activeNudges,
        'deliveredNudges': deliveredNudges,
        'actedUponNudges': actedUponNudges,
        'averageRating': averageRating,
        'totalRatings': totalRatings,
        'engagementRate': deliveredNudges > 0
            ? (actedUponNudges / deliveredNudges) * 100
            : 0.0,
        'lastUpdated': DateTime.now().toIso8601String(),
      };

      Logger.info('NudgeFirestoreRepository', 'Successfully fetched nudge statistics');

      // Cache the stats for 1 hour
      _settingsCache[cacheKey] = _CacheEntry<Map<String, dynamic>>(
        stats,
        DateTime.now().add(const Duration(hours: 1)),
      );

      return stats;
    } catch (e, stackTrace) {
      // Use defaults if error occurs, but still log it
      _errorHandler.logError(
        e,
        stackTrace,
        'Failed to fetch nudge statistics',
        NudgeErrorType.dataFetchError,
      );

      return {
        'totalNudges': 0,
        'activeNudges': 0,
        'deliveredNudges': 0,
        'actedUponNudges': 0,
        'averageRating': 0.0,
        'totalRatings': 0,
        'engagementRate': 0.0,
        'error': e.toString(),
        'lastUpdated': DateTime.now().toIso8601String(),
      };
    }
  }

  @override
  Stream<List<NudgeModel>> nudgesStream({
    int limit = 50,
    String orderBy = 'createdAt',
    bool descending = true,
  }) {
    try {
      _checkRateLimit('nudgesStream');
      Logger.info('NudgeFirestoreRepository', 'Creating nudges stream');

      final streamController = StreamController<List<NudgeModel>>.broadcast();

      // Set up the Firestore stream with error handling
      final subscription = _getUserNudgesCollection()
          .orderBy(orderBy, descending: descending)
          .limit(limit)
          .snapshots()
          .listen(
            (snapshot) {
          try {
            final nudges = snapshot.docs
                .map((doc) => NudgeModel.fromMap(doc.data(), doc.id))
                .toList();

            // Update cache with new data
            for (final nudge in nudges) {
              if (nudge.id != null) {
                _nudgeCache[nudge.id!] = _CacheEntry<NudgeModel>(
                  nudge,
                  DateTime.now().add(_cacheDuration),
                );
              }
            }

            // Add to stream
            streamController.add(nudges);
          } catch (e, stackTrace) {
            _errorHandler.logError(
              e,
              stackTrace,
              'Error processing nudges stream update',
              NudgeErrorType.streamError,
            );

            // Don't break the stream, return empty list on error
            streamController.add([]);
          }
        },
        onError: (e, stackTrace) {
          _errorHandler.logError(
            e,
            stackTrace,
            'Error in nudges stream',
            NudgeErrorType.streamError,
          );

          // Return empty list on error
          streamController.add([]);
        },
      );

      // Close the stream controller when the stream is cancelled
      streamController.onCancel = () {
        subscription.cancel();
        streamController.close();
      };

      return streamController.stream;
    } catch (e, stackTrace) {
      _errorHandler.logError(
        e,
        stackTrace,
        'Failed to create nudges stream',
        NudgeErrorType.streamError,
      );

      // Return empty stream on error
      return Stream.value(<NudgeModel>[]);
    }
  }

  @override
  Future<bool> performBatchOperations(List<NudgeBatchOperation<NudgeModel>> operations) async {
    try {
      _checkRateLimit('performBatchOperations');
      Logger.info('NudgeFirestoreRepository', 'Performing batch operations: ${operations.length} operations');

      // Split into chunks of max 500 operations (Firestore limit)
      final chunks = <List<NudgeBatchOperation<NudgeModel>>>[];
      for (var i = 0; i < operations.length; i += 500) {
        final end = (i + 500 < operations.length) ? i + 500 : operations.length;
        chunks.add(operations.sublist(i, end));
      }

      // Process each chunk
      for (final chunk in chunks) {
        final batch = _firestore.batch();

        for (final operation in chunk) {
          switch (operation.type) {
            case NudgeBatchOperationType.create:
            // Generate a new document reference for create operations
              final docRef = _getUserNudgesCollection().doc();

              if (operation.data != null) {
                final data = operation.data!.toMap();
                // Add created timestamp and user info if not already present
                data['createdAt'] ??= FieldValue.serverTimestamp();
                data['userId'] ??= _getCurrentUserId();

                batch.set(docRef, data);
              }
              break;

            case NudgeBatchOperationType.update:
              if (operation.id != null && operation.data != null) {
                final data = operation.data!.toMap();
                // Add updated timestamp
                data['updatedAt'] = FieldValue.serverTimestamp();

                batch.update(_getUserNudgesCollection().doc(operation.id), data);
              }
              break;

            case NudgeBatchOperationType.delete:
              if (operation.id != null) {
                batch.delete(_getUserNudgesCollection().doc(operation.id));
              }
              break;
          }
        }

        // Commit the batch
        await _retryWithBackoff(
          operation: () => batch.commit(),
        );
      }

      Logger.info('NudgeFirestoreRepository', 'Successfully performed batch operations');

      // Invalidate caches since we've changed data
      _invalidateAllCaches();

      return true;
    } catch (e, stackTrace) {
      throw _errorHandler.handleRepositoryException(
        e,
        stackTrace,
        'Failed to perform batch operations',
        NudgeErrorType.dataWriteError,
      );
    }
  }

  @override
  Future<R> executeTransaction<R>(Future<R> Function() transaction) async {
    try {
      _checkRateLimit('executeTransaction');
      Logger.info('NudgeFirestoreRepository', 'Executing transaction');

      final result = await _retryWithBackoff(
        operation: () => _firestore.runTransaction<R>((txn) async {
          // Pass transaction context to the callback
          return transaction();
        }),
      );

      Logger.info('NudgeFirestoreRepository', 'Successfully executed transaction');

      // Invalidate caches since transaction may have changed data
      _invalidateAllCaches();

      return result;
    } catch (e, stackTrace) {
      throw _errorHandler.handleRepositoryException(
        e,
        stackTrace,
        'Failed to execute transaction',
        NudgeErrorType.transactionError,
      );
    }
  }

  @override
  Future<int> getUnreadNudgeCount() async {
    try {
      _checkRateLimit('getUnreadNudgeCount');
      Logger.info('NudgeFirestoreRepository', 'Getting unread nudge count');

      // Cache key for unread count
      final cacheKey = 'unreadNudgeCount_${DateTime.now().day}_${DateTime.now().hour}';

      // Check cache first
      final cachedCount = _prefs.getInt(cacheKey);
      if (cachedCount != null) {
        Logger.info('NudgeFirestoreRepository', 'Returning cached unread nudge count: $cachedCount');
        return cachedCount;
      }

      // Get nudges that have been delivered but not acted upon
      final querySnapshot = await _retryWithBackoff(
        operation: () => _getUserNudgesCollection()
            .where('lastDeliveredAt', isNull: false)
            .where('lastActedAt', isNull: true)
            .count()
            .get(),
      );

      final count = querySnapshot.count;

      Logger.info('NudgeFirestoreRepository', 'Unread nudge count: $count');

      // Cache the count for 15 minutes
      await _prefs.setInt(cacheKey, count);

      return count;
    } catch (e, stackTrace) {
      // Log error but return 0 to avoid UI issues
      _errorHandler.logError(
        e,
        stackTrace,
        'Failed to get unread nudge count',
        NudgeErrorType.dataFetchError,
      );
      return 0;
    }
  }

  @override
  Future<bool> clearCache() async {
    try {
      Logger.info('NudgeFirestoreRepository', 'Clearing caches');

      // Clear in-memory caches
      _nudgeCache.clear();
      _settingsCache.clear();
      _listCache.clear();

      // Clear shared preferences cache
      final keys = _prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith(_cacheKeyPrefix)) {
          await _prefs.remove(key);
        }
      }

      Logger.info('NudgeFirestoreRepository', 'Successfully cleared caches');
      return true;
    } catch (e, stackTrace) {
      _errorHandler.logError(
        e,
        stackTrace,
        'Failed to clear cache',
        NudgeErrorType.cacheError,
      );
      return false;
    }
  }

  /// Gets nudge templates from the system templates collection
  Future<List<NudgeModel>> getNudgeTemplates() async {
    try {
      _checkRateLimit('getNudgeTemplates');
      Logger.info('NudgeFirestoreRepository', 'Fetching nudge templates');

      // Cache key for templates
      final cacheKey = 'nudgeTemplates';

      // Check in-memory cache first
      final cachedTemplates = _listCache[cacheKey];
      if (cachedTemplates != null && DateTime.now().isBefore(cachedTemplates.expiresAt)) {
        Logger.info('NudgeFirestoreRepository', 'Returning cached nudge templates: ${cachedTemplates.data.length}');
        return cachedTemplates.data;
      }

      // Templates can be cached longer since they rarely change
      final querySnapshot = await _retryWithBackoff(
        operation: () => _firestore
            .collection(_nudgeTemplatesCollection)
            .get(),
      );

      final templates = querySnapshot.docs
          .map((doc) => NudgeModel.fromMap(doc.data(), doc.id))
          .toList();

      Logger.info('NudgeFirestoreRepository', 'Successfully fetched ${templates.length} nudge templates');

      // Cache templates for 24 hours
      _listCache[cacheKey] = _CacheEntry<List<NudgeModel>>(
        templates,
        DateTime.now().add(const Duration(hours: 24)),
      );

      return templates;
    } catch (e, stackTrace) {
      throw _errorHandler.handleRepositoryException(
        e,
        stackTrace,
        'Failed to fetch nudge templates',
        NudgeErrorType.dataFetchError,
      );
    }
  }

  /// Gets user nudge settings
  Future<Map<String, dynamic>> getNudgeSettings() async {
    try {
      _checkRateLimit('getNudgeSettings');
      Logger.info('NudgeFirestoreRepository', 'Fetching nudge settings');

      // Cache key for settings
      final cacheKey = 'nudgeSettings';

      // Check in-memory cache first
      final cachedSettings = _settingsCache[cacheKey];
      if (cachedSettings != null && DateTime.now().isBefore(cachedSettings.expiresAt)) {
        Logger.info('NudgeFirestoreRepository', 'Returning cached nudge settings');
        return cachedSettings.data;
      }

      final userId = _getCurrentUserId();
      final docSnapshot = await _retryWithBackoff(
        operation: () => _firestore
            .collection(_nudgeSettingsCollection)
            .doc(userId)
            .get(),
      );

      if (!docSnapshot.exists) {
        // Return default settings if none exist
        final defaultSettings = {
          'isEnabled': true,
          'maxDailyNudges': 3,
          'preferredTimeRanges': ['morning', 'evening'],
          'notificationSound': AppTheme.getNotificationSoundForTimeWindow('gentle'),
          'vibrationPattern': AppTheme.getVibrationPattern('default'),
        };

        // Cache default settings
        _settingsCache[cacheKey] = _CacheEntry<Map<String, dynamic>>(
          defaultSettings,
          DateTime.now().add(const Duration(hours: 1)),
        );

        return defaultSettings;
      }

      final settings = docSnapshot.data()!;

      // Cache settings for 1 hour
      _settingsCache[cacheKey] = _CacheEntry<Map<String, dynamic>>(
        settings,
        DateTime.now().add(const Duration(hours: 1)),
      );

      return settings;
    } catch (e, stackTrace) {
      // Return default settings on error, but log the error
      _errorHandler.logError(
        e,
        stackTrace,
        'Failed to fetch nudge settings',
        NudgeErrorType.dataFetchError,
      );

      return {
        'isEnabled': true,
        'maxDailyNudges': 3,
        'preferredTimeRanges': ['morning', 'evening'],
        'notificationSound': AppTheme.getNotificationSoundForTimeWindow('gentle'),
        'vibrationPattern': AppTheme.getVibrationPattern('default'),
        'error': e.toString(),
      };
    }
  }

  /// Saves user nudge settings
  Future<bool> saveNudgeSettings(Map<String, dynamic> settings) async {
    try {
      _checkRateLimit('saveNudgeSettings');
      Logger.info('NudgeFirestoreRepository', 'Saving nudge settings');

      final userId = _getCurrentUserId();

      // Add updated timestamp
      settings['updatedAt'] = FieldValue.serverTimestamp();

      await _retryWithBackoff(
        operation: () => _firestore
            .collection(_nudgeSettingsCollection)
            .doc(userId)
            .set(settings, SetOptions(merge: true)),
      );

      Logger.info('NudgeFirestoreRepository', 'Successfully saved nudge settings');

      // Update settings cache
      _settingsCache['nudgeSettings'] = _CacheEntry<Map<String, dynamic>>(
        settings,
        DateTime.now().add(const Duration(hours: 1)),
      );

      return true;
    } catch (e, stackTrace) {
      throw _errorHandler.handleRepositoryException(
        e,
        stackTrace,
        'Failed to save nudge settings',
        NudgeErrorType.dataWriteError,
      );
    }
  }

  /// Close resources used by the repository
  Future<void> close() async {
    try {
      // Cancel any background tasks or timers
      // Clear caches
      _nudgeCache.clear();
      _settingsCache.clear();
      _listCache.clear();

      Logger.info('NudgeFirestoreRepository', 'Repository closed successfully');
    } catch (e, stackTrace) {
      _errorHandler.logError(
        e,
        stackTrace,
        'Error closing repository',
        NudgeErrorType.resourceError,
      );
    }
  }

  /// Invalidate all list caches
  void _invalidateListCache() {
    _listCache.clear();
  }

  /// Invalidate all caches
  void _invalidateAllCaches() {
    _nudgeCache.clear();
    _settingsCache.clear();
    _listCache.clear();
  }
}

/// Cache entry class for in-memory caching
class _CacheEntry<T> {
  final T data;
  final DateTime expiresAt;

  _CacheEntry(this.data, this.expiresAt);
}