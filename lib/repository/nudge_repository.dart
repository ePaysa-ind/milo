// Copyright © 2025 Milo App. All rights reserved.
// Author: Milo Development Team
// File: lib/repository/nudge_repository.dart
// Version: 1.0.0
// Last Updated: April 23, 2025
//NudgeRepository<T> interface with comprehensive type parameters, methods with param desc,
// pagination, batch ops, txn support, cache clearing & unread count tracking

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

import '../models/nudge_model.dart';
import '../models/nudge_error_models.dart';
import '../utils/logger.dart';
import '../utils/nudge_error_handler.dart';

/// Repository interface for nudge data operations
///
/// This follows the repository pattern to abstract data sources from business logic.
/// Generic type T allows for different types of nudge models in different implementations.
/// All methods should handle expected errors and throw typed NudgeRepositoryException.
///
/// @version 1.0.1
/// @see NudgeFirestoreRepository for implementation
abstract class NudgeRepository<T extends NudgeModel> {
  /// Fetches all nudges for the current user with pagination support
  ///
  /// @param limit Maximum number of nudges to fetch (default: 50)
  /// @param startAfter Document ID to start after for pagination (optional)
  /// @param orderBy Field to order results by (default: 'createdAt')
  /// @param descending Whether to order in descending order (default: true)
  /// @return Future with list of nudge models and pagination metadata
  /// @throws NudgeRepositoryException with type DataFetchError if operation fails
  Future<NudgePaginatedResult<T>> getNudges({
    int limit = 50,
    String? startAfter,
    String orderBy = 'createdAt',
    bool descending = true,
  });

  /// Fetches a specific nudge by ID
  ///
  /// @param id Unique identifier of the nudge to fetch
  /// @return Future with the nudge model or null if not found
  /// @throws NudgeRepositoryException with type DataFetchError if operation fails
  Future<T?> getNudgeById(String id);

  /// Creates a new nudge in the data store
  ///
  /// @param nudge The nudge model to create
  /// @return Future with the created nudge ID or null if creation failed
  /// @throws NudgeRepositoryException with type DataWriteError if operation fails
  Future<String?> createNudge(T nudge);

  /// Updates an existing nudge
  ///
  /// @param nudge The nudge model with updated values (must have valid ID)
  /// @return Future with success flag
  /// @throws NudgeRepositoryException with type DataWriteError if operation fails
  /// @throws ArgumentError if nudge ID is null or empty
  Future<bool> updateNudge(T nudge);

  /// Deletes a nudge by ID
  ///
  /// @param id Unique identifier of the nudge to delete
  /// @return Future with success flag
  /// @throws NudgeRepositoryException with type DataWriteError if operation fails
  Future<bool> deleteNudge(String id);

  /// Gets the active nudges for the current time period
  ///
  /// @param limit Maximum number of active nudges to fetch (default: 10)
  /// @return Future with list of active nudge models
  /// @throws NudgeRepositoryException with type DataFetchError if operation fails
  Future<List<T>> getActiveNudges({int limit = 10});

  /// Marks a nudge as delivered
  ///
  /// @param id Unique identifier of the nudge
  /// @param deliveredAt Timestamp when the nudge was delivered
  /// @return Future with success flag
  /// @throws NudgeRepositoryException with type DataWriteError if operation fails
  Future<bool> markNudgeAsDelivered(String id, DateTime deliveredAt);

  /// Marks a nudge as acted upon (user interacted with it)
  ///
  /// @param id Unique identifier of the nudge
  /// @param actedAt Timestamp when the user acted on the nudge
  /// @return Future with success flag
  /// @throws NudgeRepositoryException with type DataWriteError if operation fails
  Future<bool> markNudgeAsActedUpon(String id, DateTime actedAt);

  /// Records user feedback for a nudge
  ///
  /// @param id Unique identifier of the nudge
  /// @param rating Numeric rating (typically 1-5)
  /// @param comment Optional user comment
  /// @return Future with success flag
  /// @throws NudgeRepositoryException with type DataWriteError if operation fails
  Future<bool> recordNudgeFeedback(String id, int rating, String? comment);

  /// Gets nudge statistics for analytics
  ///
  /// @return Future with map of statistics
  /// @throws NudgeRepositoryException with type DataFetchError if operation fails
  Future<Map<String, dynamic>> getNudgeStats();

  /// Stream of nudges that updates in real-time
  ///
  /// @param limit Maximum number of nudges to stream (default: 50)
  /// @param orderBy Field to order results by (default: 'createdAt')
  /// @param descending Whether to order in descending order (default: true)
  /// @return Stream of nudge model lists
  /// @throws NudgeRepositoryException with type StreamError if stream creation fails
  Stream<List<T>> nudgesStream({
    int limit = 50,
    String orderBy = 'createdAt',
    bool descending = true,
  });

  /// Performs batch operations on multiple nudges
  ///
  /// @param operations List of operations to perform
  /// @return Future with success flag
  /// @throws NudgeRepositoryException with type DataWriteError if operation fails
  Future<bool> performBatchOperations(List<NudgeBatchOperation<T>> operations);

  /// Executes a transaction that performs multiple operations atomically
  ///
  /// @param transaction Function that performs operations within a transaction
  /// @return Future with transaction result
  /// @throws NudgeRepositoryException with type TransactionError if operation fails
  Future<R> executeTransaction<R>(Future<R> Function() transaction);

  /// Gets unread nudge count
  ///
  /// @return Future with count of unread nudges
  /// @throws NudgeRepositoryException with type DataFetchError if operation fails
  Future<int> getUnreadNudgeCount();

  /// Clears cached data (if implementation supports caching)
  ///
  /// @return Future with success flag
  Future<bool> clearCache();
}

/// Container class for paginated results
class NudgePaginatedResult<T> {
  final List<T> items;
  final bool hasMore;
  final String? lastDocumentId;

  NudgePaginatedResult({
    required this.items,
    required this.hasMore,
    this.lastDocumentId,
  });
}

/// Container class for batch operations
class NudgeBatchOperation<T> {
  final NudgeBatchOperationType type;
  final String? id;
  final T? data;

  NudgeBatchOperation.create(T nudge) :
        type = NudgeBatchOperationType.create,
        id = null,
        data = nudge;

  NudgeBatchOperation.update(T nudge) :
        type = NudgeBatchOperationType.update,
        id = nudge.id,
        data = nudge;

  NudgeBatchOperation.delete(String nudgeId) :
        type = NudgeBatchOperationType.delete,
        id = nudgeId,
        data = null;
}

/// Enum for batch operation types
enum NudgeBatchOperationType {
  create,
  update,
  delete,
}