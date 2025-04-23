// lib/models/nudge_model.dart
//
// Model classes for the therapeutic nudges feature, including templates,
// delivery records, user preferences, and integration with memory features.
//
// This implementation provides robust support for:
// 1. Core nudge functionality
// 2. Advanced personalization
// 3. Memory feature integration
// 4. Enhanced security and privacy controls
// 5. Optimized storage and performance

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:logging/logging.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Constants for document expiration and caching
class NudgeConstants {
  /// Default TTL for nudge deliveries (90 days in milliseconds)
  static const int DEFAULT_DELIVERY_TTL_MS = 90 * 24 * 60 * 60 * 1000;

  /// Default cache duration (1 hour in milliseconds)
  static const int DEFAULT_CACHE_DURATION_MS = 60 * 60 * 1000;

  /// Current schema version for all models
  static const int CURRENT_SCHEMA_VERSION = 1;


  /// Class representing nudge usage statistics
  class NudgeStats {
  /// Current schema version for this model
  static const int CURRENT_VERSION = NudgeConstants.CURRENT_SCHEMA_VERSION;

  /// Total number of nudges received by the user
  final int totalNudgesReceived;

  /// Breakdown of nudges by category
  final Map<NudgeCategory, int> nudgesByCategory;

  /// Breakdown of nudges by time window
  final Map<TimeWindow, int> nudgesByTimeWindow;

  /// Count of nudges rated as helpful
  final int helpfulCount;

  /// Count of nudges rated as unhelpful
  final int unhelpfulCount;

  /// Count of nudges saved as memories
  final int savedAsMemoryCount;

  /// When these stats were last updated
  final DateTime lastUpdated;

  /// Schema version of this document
  final int schemaVersion;

  /// Creates new nudge statistics
  NudgeStats({
  required this.totalNudgesReceived,
  required this.nudgesByCategory,
  required this.nudgesByTimeWindow,
  required this.helpfulCount,
  required this.unhelpfulCount,
  required this.savedAsMemoryCount,
  required this.lastUpdated,
  int? schemaVersion,
  }) : schemaVersion = schemaVersion ?? CURRENT_VERSION;

  /// Creates NudgeStats from a Firestore document
  /// @param doc The DocumentSnapshot from Firestore
  /// @return A new NudgeStats populated with data from Firestore
  factory NudgeStats.fromFirestore(DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>? ?? {};

  // Check schema version for possible migrations
  final int schemaVersion = data['sv'] ?? 1;
  Map<String, dynamic> migratedData = data;

  // Migrate old data formats if needed
  if (schemaVersion < CURRENT_VERSION) {
  migratedData = _migrateStatsData(data, schemaVersion);
  }

  // Parse nudges by category with error handling
  Map<NudgeCategory, int> nudgesByCategory = {};
  try {
  // Try compact format first (new format)
  if (migratedData['nbc'] != null) {
  final categoryMap = migratedData['nbc'] as Map<String, dynamic>;
  for (var entry in categoryMap.entries) {
  try {
  // Try to parse as int first (compact format)
  NudgeCategory? category;
  try {
  final intKey = int.parse(entry.key);
  category = NudgeCategory.fromInt(intKey);
  } catch (e) {
  // Try to use the storage key
  category = NudgeCategory.fromStorageKey(entry.key);

  // Fall back to the full string if needed
  if (category == null) {
  category = NudgeCategory.fromString(entry.key);
  }
  }

  if (category != null) {
  nudgesByCategory[category] = entry.value as int;
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Error parsing category count: $e');
  }
  }
  }
  } else if (migratedData['nudgesByCategory'] != null) {
  // Fall back to old format
  final categoryMap = migratedData['nudgesByCategory'] as Map<String, dynamic>;
  for (var entry in categoryMap.entries) {
  try {
  nudgesByCategory[NudgeCategory.fromString(entry.key)] = entry.value as int;
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Error parsing category count: $e');
  }
  }
  }
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Error parsing nudgesByCategory: $e');
  }
  }

  // Parse nudges by time window with error handling
  Map<TimeWindow, int> nudgesByTimeWindow = {};
  try {
  // Try compact format first (new format)
  if (migratedData['nbtw'] != null) {
  final timeWindowMap = migratedData['nbtw'] as Map<String, dynamic>;
  for (var entry in timeWindowMap.entries) {
  try {
  // Try to parse as int first (compact format)
  TimeWindow? window;
  try {
  final intKey = int.parse(entry.key);
  window = TimeWindow.fromInt(intKey);
  } catch (e) {
  // Try to use the storage key
  for (var w in TimeWindow.values) {
  if (w.storageKey == entry.key) {
  window = w;
  break;
  }
  }

  // Fall back to full string if needed
  if (window == null) {
  window = TimeWindowExtension.fromString(entry.key);
  }
  }

  if (window != null) {
  nudgesByTimeWindow[window] = entry.value as int;
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Error parsing time window count: $e');
  }
  }
  }
  } else if (migratedData['nudgesByTimeWindow'] != null) {
  // Fall back to old format
  final timeWindowMap = migratedData['nudgesByTimeWindow'] as Map<String, dynamic>;
  for (var entry in timeWindowMap.entries) {
  try {
  nudgesByTimeWindow[TimeWindowExtension.fromString(entry.key)] = entry.value as int;
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Error parsing time window count: $e');
  }
  }
  }
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Error parsing nudgesByTimeWindow: $e');
  }
  }

  // Handle timestamp
  DateTime lastUpdated;
  try {
  // Support both Timestamp and epoch milliseconds
  if (migratedData['lu'] is Timestamp) {
  lastUpdated = (migratedData['lu'] as Timestamp?)?.toDate() ?? DateTime.now();
  } else if (migratedData['lu'] is int) {
  lastUpdated = DateTime.fromMillisecondsSinceEpoch(migratedData['lu']);
  } else if (migratedData['lastUpdated'] is Timestamp) {
  lastUpdated = (migratedData['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now();
  } else {
  lastUpdated = DateTime.now();
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Invalid lastUpdated timestamp. Using current time.');
  }
  lastUpdated = DateTime.now();
  }

  return NudgeStats(
  totalNudgesReceived: migratedData['tnr'] ?? migratedData['totalNudgesReceived'] as int? ?? 0,
  nudgesByCategory: nudgesByCategory,
  nudgesByTimeWindow: nudgesByTimeWindow,
  helpfulCount: migratedData['hc'] ?? migratedData['helpfulCount'] as int? ?? 0,
  unhelpfulCount: migratedData['uhc'] ?? migratedData['unhelpfulCount'] as int? ?? 0,
  savedAsMemoryCount: migratedData['smc'] ?? migratedData['savedAsMemoryCount'] as int? ?? 0,
  lastUpdated: lastUpdated,
  schemaVersion: schemaVersion,
  );
  }

  /// Migrate old document formats to current schema
  /// @param data Original document data
  /// @param originalVersion Original schema version
  /// @return Migrated data in current schema format
  static Map<String, dynamic> _migrateStatsData(
  Map<String, dynamic> data, int originalVersion) {
  // Deep copy the data
  final Map<String, dynamic> migrated = Map.from(data);

  // Apply migrations based on version
  if (originalVersion < 1) {
  // Example migration from v0 to v1
  if (migrated['totalNudgesReceived'] != null) {
  migrated['tnr'] = migrated['totalNudgesReceived'];
  migrated.remove('totalNudgesReceived');
  }

  if (migrated['nudgesByCategory'] != null) {
  final Map<String, dynamic> categoryMap = migrated['nudgesByCategory'];
  final compactMap = <String, int>{};

  for (var entry in categoryMap.entries) {
  try {
  final category = NudgeCategory.fromString(entry.key);
  compactMap[category.intValue.toString()] = entry.value as int;
  } catch (e) {
  // Skip invalid entries
  }
  }

  migrated['nbc'] = compactMap;
  migrated.remove('nudgesByCategory');
  }

  if (migrated['nudgesByTimeWindow'] != null) {
  final Map<String, dynamic> timeWindowMap = migrated['nudgesByTimeWindow'];
  final compactMap = <String, int>{};

  for (var entry in timeWindowMap.entries) {
  try {
  final window = TimeWindowExtension.fromString(entry.key);
  compactMap[window.intValue.toString()] = entry.value as int;
  } catch (e) {
  // Skip invalid entries
  }
  }

  migrated['nbtw'] = compactMap;
  migrated.remove('nudgesByTimeWindow');
  }

  if (migrated['helpfulCount'] != null) {
  migrated['hc'] = migrated['helpfulCount'];
  migrated.remove('helpfulCount');
  }

  if (migrated['unhelpfulCount'] != null) {
  migrated['uhc'] = migrated['unhelpfulCount'];
  migrated.remove('unhelpfulCount');
  }

  if (migrated['savedAsMemoryCount'] != null) {
  migrated['smc'] = migrated['savedAsMemoryCount'];
  migrated.remove('savedAsMemoryCount');
  }

  if (migrated['lastUpdated'] != null) {
  if (migrated['lastUpdated'] is Timestamp) {
  migrated['lu'] = (migrated['lastUpdated'] as Timestamp).toDate().millisecondsSinceEpoch;
  }
  migrated.remove('lastUpdated');
  }
  }

  // Update schema version
  migrated['sv'] = CURRENT_VERSION;

  return migrated;
  }

  /// Converts these stats to a map for Firestore storage
  /// @return A Map suitable for writing to Firestore
  Map<String, dynamic> toMap() {
  // Convert nudgesByCategory to a map with compact integer keys
  final categoriesMap = <String, int>{};
  nudgesByCategory.forEach((key, value) {
  categoriesMap[key.intValue.toString()] = value;
  });

  // Convert nudgesByTimeWindow to a map with compact integer keys
  final timeWindowsMap = <String, int>{};
  nudgesByTimeWindow.forEach((key, value) {
  timeWindowsMap[key.intValue.toString()] = value;
  });

  return {
  'tnr': totalNudgesReceived,
  'nbc': categoriesMap,
  'nbtw': timeWindowsMap,
  'hc': helpfulCount,
  'uhc': unhelpfulCount,
  'smc': savedAsMemoryCount,
  'lu': FieldValue.serverTimestamp(),
  'sv': schemaVersion,
  };
  }
  }

  /// Memory model for integration with existing memory feature
  class Memory {
  /// Current schema version for this model
  static const int CURRENT_VERSION = NudgeConstants.CURRENT_SCHEMA_VERSION;

  /// Unique identifier for this memory
  final String id;

  /// The user who owns this memory
  final String userId;

  /// Short title for the memory
  final String title;

  /// Main content of the memory
  final String content;

  /// When this memory was created
  final DateTime createdAt;

  /// Tags for categorizing and searching
  final List<String>? tags;

  /// IDs of nudges related to this memory
  final List<String>? relatedNudgeIds;

  /// Additional data about this memory
  final Map<String, dynamic>? metadata;

  /// Schema version of this document
  final int schemaVersion;

  /// Reference to template ID if this memory was created from a nudge
  final String? nudgeTemplateId;

  /// Compressed content for storage optimization
  String? _compressedContent;

  /// Creates a new memory
  Memory({
  required this.id,
  required this.userId,
  required this.title,
  required this.content,
  required this.createdAt,
  this.tags,
  this.relatedNudgeIds,
  this.metadata,
  int? schemaVersion,
  this.nudgeTemplateId,
  }) : schemaVersion = schemaVersion ?? CURRENT_VERSION;

  /// Creates a Memory from a Firestore document
  /// @param doc The DocumentSnapshot from Firestore
  /// @return A new Memory populated with data from Firestore
  factory Memory.fromFirestore(DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>? ?? {};

  // Check schema version for possible migrations
  final int schemaVersion = data['sv'] ?? 1;
  Map<String, dynamic> migratedData = data;

  // Migrate old data formats if needed
  if (schemaVersion < CURRENT_VERSION) {
  migratedData = _migrateMemoryData(data, schemaVersion);
  }

  // Handle timestamp
  DateTime createdAt;
  try {
  // Support both Timestamp and epoch milliseconds
  if (migratedData['ca'] is Timestamp) {
  createdAt = (migratedData['ca'] as Timestamp?)?.toDate() ?? DateTime.now();
  } else if (migratedData['ca'] is int) {
  createdAt = DateTime.fromMillisecondsSinceEpoch(migratedData['ca']);
  } else if (migratedData['createdAt'] is Timestamp) {
  createdAt = (migratedData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
  } else {
  createdAt = DateTime.now();
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Invalid createdAt timestamp for memory ${doc.id}. Using current time.');
  }
  createdAt = DateTime.now();
  }

  // Handle decompression of content if needed
  String content = '';
  if (migratedData['cmp'] != null) {
  try {
  final List<int> compressed = base64Decode(migratedData['cmp']);
  content = utf8.decode(compressed);
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Failed to decompress content for memory ${doc.id}. Using raw content.');
  }
  content = migratedData['cnt'] ?? migratedData['content'] ?? '';
  }
  } else {
  content = migratedData['cnt'] ?? migratedData['content'] ?? '';
  }

  return Memory(
  id: doc.id,
  userId: migratedData['uid'] ?? migratedData['userId'] ?? '',
  title: migratedData['t'] ?? migratedData['title'] ?? '',
  content: content,
  createdAt: createdAt,
  tags: migratedData['tg'] != null
  ? List<String>.from(migratedData['tg'])
      : (migratedData['tags'] != null
  ? List<String>.from(migratedData['tags'])
      : null),
  relatedNudgeIds: migratedData['rnid'] != null
  ? List<String>.from(migratedData['rnid'])
      : (migratedData['relatedNudgeIds'] != null
  ? List<String>.from(migratedData['relatedNudgeIds'])
      : null),
  metadata: migratedData['md'] ?? migratedData['metadata'],
  schemaVersion: schemaVersion,
  nudgeTemplateId: migratedData['ntid'],
  );
  }

  /// Migrate old document formats to current schema
  /// @param data Original document data
  /// @param originalVersion Original schema version
  /// @return Migrated data in current schema format
  static Map<String, dynamic> _migrateMemoryData(
  Map<String, dynamic> data, int originalVersion) {
  // Deep copy the data
  final Map<String, dynamic> migrated = Map.from(data);

  // Apply migrations based on version
  if (originalVersion < 1) {
  // Example migration from v0 to v1
  if (migrated['userId'] != null) {
  migrated['uid'] = migrated['userId'];
  migrated.remove('userId');
  }

  if (migrated['title'] != null) {
  migrated['t'] = migrated['title'];
  migrated.remove('title');
  }

  if (migrated['content'] != null) {
  final content = migrated['content'] as String;
  // Compress the content
  final contentBytes = utf8.encode(content);
  final compressed = base64Encode(contentBytes);
  migrated['cmp'] = compressed;
  migrated['cnt'] = content; // Keep original for backward compatibility
  migrated.remove('content');
  }

  if (migrated['createdAt'] != null) {
  if (migrated['createdAt'] is Timestamp) {
  migrated['ca'] = (migrated['createdAt'] as Timestamp).toDate().millisecondsSinceEpoch;
  }
  migrated.remove('createdAt');
  }

  if (migrated['tags'] != null) {
  migrated['tg'] = migrated['tags'];
  migrated.remove('tags');
  }

  if (migrated['relatedNudgeIds'] != null) {
  migrated['rnid'] = migrated['relatedNudgeIds'];
  migrated.remove('relatedNudgeIds');
  }

  if (migrated['metadata'] != null) {
  migrated['md'] = migrated['metadata'];
  migrated.remove('metadata');
  }
  }

  // Update schema version
  migrated['sv'] = CURRENT_VERSION;

  return migrated;
  }

  /// Compresses the content to reduce storage size
  String get compressedContent {
  if (_compressedContent == null) {
  final contentBytes = utf8.encode(content);
  _compressedContent = base64Encode(contentBytes);
  }
  return _compressedContent!;
  }

  /// Converts this memory to a map for Firestore storage
  /// @return A Map suitable for writing to Firestore
  Map<String, dynamic> toMap() {
  final map = {
  'uid': userId,
  't': title,
  'cnt': content,
  'cmp': compressedContent, // Store compressed content for large text
  'ca': FieldValue.serverTimestamp(),
  'tg': tags,
  'rnid': relatedNudgeIds,
  'md': metadata,
  'sv': schemaVersion,
  };

  // Only add nudgeTemplateId if it's not null
  if (nudgeTemplateId != null) {
  map['ntid'] = nudgeTemplateId;
  }

  return map;
  }

  /// Creates a copy of this memory with optionally modified fields
  /// @return A new Memory with the updated fields
  Memory copyWith({
  String? id,
  String? userId,
  String? title,
  String? content,
  DateTime? createdAt,
  List<String>? tags,
  List<String>? relatedNudgeIds,
  Map<String, dynamic>? metadata,
  int? schemaVersion,
  String? nudgeTemplateId,
  }) {
  return Memory(
  id: id ?? this.id,
  userId: userId ?? this.userId,
  title: title ?? this.title,
  content: content ?? this.content,
  createdAt: createdAt ?? this.createdAt,
  tags: tags ?? this.tags,
  relatedNudgeIds: relatedNudgeIds ?? this.relatedNudgeIds,
  metadata: metadata ?? this.metadata,
  schemaVersion: schemaVersion ?? this.schemaVersion,
  nudgeTemplateId: nudgeTemplateId ?? this.nudgeTemplateId,
  );
  }

  /// Link this memory to a nudge
  /// @param nudgeId The ID of the nudge to link to
  /// @param templateId Optional template ID if this memory is related to a specific template
  /// @return A new Memory with the nudge relationship established
  Memory linkToNudge(String nudgeId, {String? templateId}) {
  final currentRelatedNudgeIds = relatedNudgeIds ?? [];
  if (!currentRelatedNudgeIds.contains(nudgeId)) {
  return copyWith(
  relatedNudgeIds: [...currentRelatedNudgeIds, nudgeId],
  nudgeTemplateId: templateId ?? nudgeTemplateId,
  );
  }
  return this;
  }
  }

  /// User personalization data for advanced personalization
  class UserPersonalizationData {
  /// Current schema version for this model
  static const int CURRENT_VERSION = NudgeConstants.CURRENT_SCHEMA_VERSION;

  /// The user this personalization data belongs to
  final String userId;

  /// Effectiveness score of each category for this user
  final Map<NudgeCategory, double>? categoryEffectiveness;

  /// Topics the user has shown interest in and when
  final Map<String, DateTime>? topicInterests;

  /// Words the user commonly uses in responses
  final List<String>? frequentlyUsedKeywords;

  /// How responsive the user is during each time window
  final Map<TimeWindow, double>? timeWindowResponsiveness;

  /// User's current reported mood
  final String? currentMood;

  /// When the mood was last updated
  final DateTime? moodLastUpdated;

  /// Additional metrics for personalization
  final Map<String, dynamic>? personalizationMetrics;

  /// Schema version of this document
  final int schemaVersion;

  /// Cache expiration timestamp
  final DateTime? cacheExpiresAt;

  /// Creates new user personalization data
  UserPersonalizationData({
  required this.userId,
  this.categoryEffectiveness,
  this.topicInterests,
  this.frequentlyUsedKeywords,
  this.timeWindowResponsiveness,
  this.currentMood,
  this.moodLastUpdated,
  this.personalizationMetrics,
  int? schemaVersion,
  DateTime? cacheExpiresAt,
  }) :
  schemaVersion = schemaVersion ?? CURRENT_VERSION,
  cacheExpiresAt = cacheExpiresAt ?? DateTime.now().add(
  Duration(milliseconds: NudgeConstants.DEFAULT_CACHE_DURATION_MS));

  /// Creates UserPersonalizationData from a Firestore document
  /// @param doc The DocumentSnapshot from Firestore
  /// @return A new UserPersonalizationData populated with data from Firestore
  factory UserPersonalizationData.fromFirestore(DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>? ?? {};

  // Check schema version for possible migrations
  final int schemaVersion = data['sv'] ?? 1;
  Map<String, dynamic> migratedData = data;

  // Migrate old data formats if needed
  if (schemaVersion < CURRENT_VERSION) {
  migratedData = _migratePersonalizationData(data, schemaVersion);
  }

  // Parse category effectiveness with error handling
  Map<NudgeCategory, double>? categoryEffectiveness;
  if (migratedData['ce'] != null) {
  try {
  categoryEffectiveness = {};
  final Map<String, dynamic> effectivenessMap = migratedData['ce'] as Map<String, dynamic>;
  for (var entry in effectivenessMap.entries) {
  try {
  // Try to parse as int first (compact format)
  NudgeCategory? category;
  try {
  final intKey = int.parse(entry.key);
  category = NudgeCategory.fromInt(intKey);
  } catch (e) {
  // Try to use the storage key
  category = NudgeCategory.fromStorageKey(entry.key);

  // Fall back to the full string if needed
  if (category == null) {
  category = NudgeCategory.fromString(entry.key);
  }
  }

  if (category != null) {
  categoryEffectiveness[category] = (entry.value as num).toDouble();
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Error parsing category effectiveness entry: $e');
  }
  }
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Error parsing categoryEffectiveness: $e');
  }
  }
  } else if (migratedData['categoryEffectiveness'] != null) {
  // Fall back to old format
  try {
  categoryEffectiveness = {};
  final Map<String, dynamic> effectivenessMap = migratedData['categoryEffectiveness'] as Map<String, dynamic>;
  for (var entry in effectivenessMap.entries) {
  categoryEffectiveness[NudgeCategory.fromString(entry.key)] = (entry.value as num).toDouble();
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Error parsing categoryEffectiveness: $e');
  }
  }
  }

  // Parse topic interests with error handling
  Map<String, DateTime>? topicInterests;
  if (migratedData['ti'] != null) {
  try {
  topicInterests = {};
  final Map<String, dynamic> interestsMap = migratedData['ti'] as Map<String, dynamic>;
  for (var entry in interestsMap.entries) {
  if (entry.value is Timestamp) {
  topicInterests[entry.key] = (entry.value as Timestamp).toDate();
  } else if (entry.value is int) {
  topicInterests[entry.key] = DateTime.fromMillisecondsSinceEpoch(entry.value as int);
  }
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Error parsing topicInterests: $e');
  }
  }
  } else if (migratedData['topicInterests'] != null) {
  // Fall back to old format
  try {
  topicInterests = {};
  final Map<String, dynamic> interestsMap = migratedData['topicInterests'] as Map<String, dynamic>;
  for (var entry in interestsMap.entries) {
  topicInterests[entry.key] = (entry.value as Timestamp).toDate();
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Error parsing topicInterests: $e');
  }
  }
  }

  // Parse time window responsiveness with error handling
  Map<TimeWindow, double>? timeWindowResponsiveness;
  if (migratedData['twr'] != null) {
  try {
  timeWindowResponsiveness = {};
  final Map<String, dynamic> responsivenessMap = migratedData['twr'] as Map<String, dynamic>;
  for (var entry in responsivenessMap.entries) {
  try {
  // Try to parse as int first (compact format)
  TimeWindow? window;
  try {
  final intKey = int.parse(entry.key);
  window = TimeWindow.fromInt(intKey);
  } catch (e) {
  // Try to use the storage key
  for (var w in TimeWindow.values) {
  if (w.storageKey == entry.key) {
  window = w;
  break;
  }
  }

  // Fall back to full string if needed
  if (window == null) {
  window = TimeWindowExtension.fromString(entry.key);
  }
  }

  if (window != null) {
  timeWindowResponsiveness[window] = (entry.value as num).toDouble();
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Error parsing time window responsiveness entry: $e');
  }
  }
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Error parsing timeWindowResponsiveness: $e');
  }
  }
  } else if (migratedData['timeWindowResponsiveness'] != null) {
  // Fall back to old format
  try {
  timeWindowResponsiveness = {};
  final Map<String, dynamic> responsivenessMap = migratedData['timeWindowResponsiveness'] as Map<String, dynamic>;
  for (var entry in responsivenessMap.entries) {
  timeWindowResponsiveness[TimeWindowExtension.fromString(entry.key)] = (entry.value as num).toDouble();
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Error parsing timeWindowResponsiveness: $e');
  }
  }
  }

  // Handle mood last updated timestamp
  DateTime? moodLastUpdated;
  if (migratedData['mlu'] != null) {
  try {
  if (migratedData['mlu'] is Timestamp) {
  moodLastUpdated = (migratedData['mlu'] as Timestamp).toDate();
  } else if (migratedData['mlu'] is int) {
  moodLastUpdated = DateTime.fromMillisecondsSinceEpoch(migratedData['mlu']);
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Invalid moodLastUpdated timestamp. Ignoring.');
  }
  }
  } else if (migratedData['moodLastUpdated'] != null) {
  // Fall back to old format
  try {
  moodLastUpdated = (migratedData['moodLastUpdated'] as Timestamp).toDate();
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Invalid moodLastUpdated timestamp. Ignoring.');
  }
  }
  }

  // Handle cache expiration
  DateTime? cacheExpiresAt;
  if (migratedData['cexp'] != null) {
  try {
  if (migratedData['cexp'] is Timestamp) {
  cacheExpiresAt = (migratedData['cexp'] as Timestamp).toDate();
  } else if (migratedData['cexp'] is int) {
  cacheExpiresAt = DateTime.fromMillisecondsSinceEpoch(migratedData['cexp']);
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Invalid cacheExpiresAt timestamp. Ignoring.');
  }
  }
  }

  return UserPersonalizationData(
  userId: migratedData['uid'] ?? migratedData['userId'] ?? doc.id,
  categoryEffectiveness: categoryEffectiveness,
  topicInterests: topicInterests,
  frequentlyUsedKeywords: migratedData['fuk'] != null
  ? List<String>.from(migratedData['fuk'])
      : (migratedData['frequentlyUsedKeywords'] != null
  ? List<String>.from(migratedData['frequentlyUsedKeywords'])
      : null),
  timeWindowResponsiveness: timeWindowResponsiveness,
  currentMood: migratedData['cm'] ?? migratedData['currentMood'],
  moodLastUpdated: moodLastUpdated,
  personalizationMetrics: migratedData['pm'] ?? migratedData['personalizationMetrics'],
  schemaVersion: schemaVersion,
  cacheExpiresAt: cacheExpiresAt,
  );
  }

  /// Migrate old document formats to current schema
  /// @param data Original document data
  /// @param originalVersion Original schema version
  /// @return Migrated data in current schema format
  static Map<String, dynamic> _migratePersonalizationData(
  Map<String, dynamic> data, int originalVersion) {
  // Deep copy the data
  final Map<String, dynamic> migrated = Map.from(data);

  // Apply migrations based on version
  if (originalVersion < 1) {
  // Example migration from v0 to v1
  if (migrated['userId'] != null) {
  migrated['uid'] = migrated['userId'];
  migrated.remove('userId');
  }

  if (migrated['categoryEffectiveness'] != null) {
  final Map<String, dynamic> effectivenessMap = migrated['categoryEffectiveness'];
  final compactMap = <String, double>{};

  for (var entry in effectivenessMap.entries) {
  try {
  final category = NudgeCategory.fromString(entry.key);
  compactMap[category.intValue.toString()] = (entry.value as num).toDouble();
  } catch (e) {
  // Skip invalid entries
  }
  }

  migrated['ce'] = compactMap;
  migrated.remove('categoryEffectiveness');
  }

  if (migrated['topicInterests'] != null) {
  final Map<String, dynamic> interestsMap = migrated['topicInterests'];
  final compactMap = <String, int>{};

  for (var entry in interestsMap.entries) {
  try {
  if (entry.value is Timestamp) {
  compactMap[entry.key] = (entry.value as Timestamp).toDate().millisecondsSinceEpoch;
  }
  } catch (e) {
  // Skip invalid entries
  }
  }

  migrated['ti'] = compactMap;
  migrated.remove('topicInterests');
  }

  if (migrated['frequentlyUsedKeywords'] != null) {
  migrated['fuk'] = migrated['frequentlyUsedKeywords'];
  migrated.remove('frequentlyUsedKeywords');
  }

  if (migrated['timeWindowResponsiveness'] != null) {
  final Map<String, dynamic> responsivenessMap = migrated['timeWindowResponsiveness'];
  final compactMap = <String, double>{};

  for (var entry in responsivenessMap.entries) {
  try {
  final window = TimeWindowExtension.fromString(entry.key);
  compactMap[window.intValue.toString()] = (entry.value as num).toDouble();
  } catch (e) {
  // Skip invalid entries
  }
  }

  migrated['twr'] = compactMap;
  migrated.remove('timeWindowResponsiveness');
  }

  if (migrated['currentMood'] != null) {
  migrated['cm'] = migrated['currentMood'];
  migrated.remove('currentMood');
  }

  if (migrated['moodLastUpdated'] != null) {
  if (migrated['moodLastUpdated'] is Timestamp) {
  migrated['mlu'] = (migrated['moodLastUpdated'] as Timestamp).toDate().millisecondsSinceEpoch;
  }
  migrated.remove('moodLastUpdated');
  }

  if (migrated['personalizationMetrics'] != null) {
  migrated['pm'] = migrated['personalizationMetrics'];
  migrated.remove('personalizationMetrics');
  }

  // Add cache expiration
  migrated['cexp'] = DateTime.now().add(
  Duration(milliseconds: NudgeConstants.DEFAULT_CACHE_DURATION_MS)).millisecondsSinceEpoch;
  }

  // Update schema version
  migrated['sv'] = CURRENT_VERSION;

  return migrated;
  }

  /// Converts this data to a map for Firestore storage
  /// @return A Map suitable for writing to Firestore
  Map<String, dynamic> toMap() {
  // Convert categoryEffectiveness to a map with integer keys
  Map<String, dynamic>? categoryEffectivenessMap;
  if (categoryEffectiveness != null) {
  categoryEffectivenessMap = {};
  categoryEffectiveness!.forEach((key, value) {
  categoryEffectivenessMap![key.intValue.toString()] = value;
  });
  }

  // Convert topicInterests to a map with integer timestamps
  Map<String, dynamic>? topicInterestsMap;
  if (topicInterests != null) {
  topicInterestsMap = {};
  topicInterests!.forEach((key, value) {
  topicInterestsMap![key] = value.millisecondsSinceEpoch;
  });
  }

  // Convert timeWindowResponsiveness to a map with integer keys
  Map<String, dynamic>? responsivenesMap;
  if (timeWindowResponsiveness != null) {
  responsivenesMap = {};
  timeWindowResponsiveness!.forEach((key, value) {
  responsivenesMap![key.intValue.toString()] = value;
  });
  }

  return {
  'uid': userId,
  'ce': categoryEffectivenessMap,
  'ti': topicInterestsMap,
  'fuk': frequentlyUsedKeywords,
  'twr': responsivenesMap,
  'cm': currentMood,
  'mlu': moodLastUpdated != null ? moodLastUpdated!.millisecondsSinceEpoch : null,
  'pm': personalizationMetrics,
  'sv': schemaVersion,
  'cexp': cacheExpiresAt != null ? cacheExpiresAt!.millisecondsSinceEpoch : null,
  };
  }

  /// Update current mood
  /// @param mood The new mood to set
  /// @return A new UserPersonalizationData with updated mood
  UserPersonalizationData updateMood(String mood) {
  return UserPersonalizationData(
  userId: userId,
  categoryEffectiveness: categoryEffectiveness,
  topicInterests: topicInterests,
  frequentlyUsedKeywords: frequentlyUsedKeywords,
  timeWindowResponsiveness: timeWindowResponsiveness,
  currentMood: mood,
  moodLastUpdated: DateTime.now(),
  personalizationMetrics: personalizationMetrics,
  schemaVersion: schemaVersion,
  cacheExpiresAt: cacheExpiresAt,
  );
  }

  /// Check if the cached data is still valid
  /// @return true if the data is still valid, false if it has expired
  bool isCacheValid() {
  if (cacheExpiresAt == null) return false;
  return cacheExpiresAt!.isAfter(DateTime.now());
  }

  /// Refresh the cache expiration timestamp
  /// @return A new UserPersonalizationData with updated cache expiration
  UserPersonalizationData refreshCache() {
  return UserPersonalizationData(
  userId: userId,
  categoryEffectiveness: categoryEffectiveness,
  topicInterests: topicInterests,
  frequentlyUsedKeywords: frequentlyUsedKeywords,
  timeWindowResponsiveness: timeWindowResponsiveness,
  currentMood: currentMood,
  moodLastUpdated: moodLastUpdated,
  personalizationMetrics: personalizationMetrics,
  schemaVersion: schemaVersion,
  cacheExpiresAt: DateTime.now().add(
  Duration(milliseconds: NudgeConstants.DEFAULT_CACHE_DURATION_MS)),
  );
  }
  }

  /// Audit log entry for security
  class AuditLogEntry {
  /// Current schema version for this model
  static const int CURRENT_VERSION = NudgeConstants.CURRENT_SCHEMA_VERSION;

  /// Unique identifier for this log entry
  final String id;

  /// The user who performed the action
  final String userId;

  /// The action that was performed
  final String action;

  /// When the action occurred
  final DateTime timestamp;

  /// The type of resource affected
  final String? resourceType;

  /// The ID of the resource affected
  final String? resourceId;

  /// Additional information about the action
  final Map<String, dynamic>? details;

  /// Schema version of this document
  final int schemaVersion;

  /// When this log entry should expire (TTL)
  final DateTime? expiresAt;

  /// Creates a new audit log entry
  AuditLogEntry({
  required this.id,
  required this.userId,
  required this.action,
  required this.timestamp,
  this.resourceType,
  this.resourceId,
  this.details,
  int? schemaVersion,
  DateTime? expiresAt,
  }) :
  schemaVersion = schemaVersion ?? CURRENT_VERSION,
  expiresAt = expiresAt ?? DateTime.now().add(
  Duration(milliseconds: NudgeConstants.DEFAULT_DELIVERY_TTL_MS));

  /// Creates an AuditLogEntry from a Firestore document
  /// @param doc The DocumentSnapshot from Firestore
  /// @return A new AuditLogEntry populated with data from Firestore
  factory AuditLogEntry.fromFirestore(DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>? ?? {};

  // Check schema version for possible migrations
  final int schemaVersion = data['sv'] ?? 1;
  Map<String, dynamic> migratedData = data;

  // Migrate old data formats if needed
  if (schemaVersion < CURRENT_VERSION) {
  migratedData = _migrateAuditLogData(data, schemaVersion);
  }

  // Handle timestamp
  DateTime timestamp;
  try {
  // Support both Timestamp and epoch milliseconds
  if (migratedData['ts'] is Timestamp) {
  timestamp = (migratedData['ts'] as Timestamp?)?.toDate() ?? DateTime.now();
  } else if (migratedData['ts'] is int) {
  timestamp = DateTime.fromMillisecondsSinceEpoch(migratedData['ts']);
  } else if (migratedData['timestamp'] is Timestamp) {
  timestamp = (migratedData['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
  } else {
  timestamp = DateTime.now();
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Invalid timestamp for audit log ${doc.id}. Using current time.');
  }
  timestamp = DateTime.now();
  }

  // Handle expiration
  DateTime? expiresAt;
  try {
  if (migratedData['exp'] is Timestamp) {
  expiresAt = (migratedData['exp'] as Timestamp?)?.toDate();
  } else if (migratedData['exp'] is int) {
  expiresAt = DateTime.fromMillisecondsSinceEpoch(migratedData['exp']);
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Invalid expiresAt timestamp for audit log ${doc.id}.');
  }
  }

  return AuditLogEntry(
  id: doc.id,
  userId: migratedData['uid'] ?? migratedData['userId'] ?? '',
  action: migratedData['a'] ?? migratedData['action'] ?? 'unknown',
  timestamp: timestamp,
  resourceType: migratedData['rt'] ?? migratedData['resourceType'],
  resourceId: migratedData['rid'] ?? migratedData['resourceId'],
  details: migratedData['d'] ?? migratedData['details'],
  schemaVersion: schemaVersion,
  expiresAt: expiresAt,
  );
  }

  /// Migrate old document formats to current schema
  /// @param data Original document data
  /// @param originalVersion Original schema version
  /// @return Migrated data in current schema format
  static Map<String, dynamic> _migrateAuditLogData(
  Map<String, dynamic> data, int originalVersion) {
  // Deep copy the data
  final Map<String, dynamic> migrated = Map.from(data);

  // Apply migrations based on version
  if (originalVersion < 1) {
  // Example migration from v0 to v1
  if (migrated['userId'] != null) {
  migrated['uid'] = migrated['userId'];
  migrated.remove('userId');
  }

  if (migrated['action'] != null) {
  migrated['a'] = migrated['action'];
  migrated.remove('action');
  }

  if (migrated['timestamp'] != null) {
  if (migrated['timestamp'] is Timestamp) {
  migrated['ts'] = (migrated['timestamp'] as Timestamp).toDate().millisecondsSinceEpoch;
  }
  migrated.remove('timestamp');
  }

  if (migrated['resourceType'] != null) {
  migrated['rt'] = migrated['resourceType'];
  migrated.remove('resourceType');
  }

  if (migrated['resourceId'] != null) {
  migrated['rid'] = migrated['resourceId'];
  migrated.remove('resourceId');
  }

  if (migrated['details'] != null) {
  migrated['d'] = migrated['details'];
  migrated.remove('details');
  }

  // Add expiration
  migrated['exp'] = DateTime.now().add(
  Duration(milliseconds: NudgeConstants.DEFAULT_DELIVERY_TTL_MS)).millisecondsSinceEpoch;
  }

  // Update schema version
  migrated['sv'] = CURRENT_VERSION;

  return migrated;
  }

  /// Converts this entry to a map for Firestore storage
  /// @return A Map suitable for writing to Firestore
  Map<String, dynamic> toMap() {
  return {
  'uid': userId,
  'a': action,
  'ts': FieldValue.serverTimestamp(),
  'rt': resourceType,
  'rid': resourceId,
  'd': details,
  'sv': schemaVersion,
  'exp': expiresAt != null ? expiresAt!.millisecondsSinceEpoch : null,
  };
  }
  }

  /// Model for a complete nudge with content and delivery information
  /// Combines a NudgeDelivery and its associated NudgeTemplate
  class NudgeWithTemplate {
  /// The delivery record for this nudge instance
  final NudgeDelivery delivery;

  /// The template containing the content for this nudge
  final NudgeTemplate template;

  /// Whether the template content has been loaded
  bool _isTemplateContentLoaded = true;

  /// Cache key for template reference
  String get cacheKey => 'nudge_with_template_${delivery.id}';

  /// Creates a new combined nudge with template and delivery information
  NudgeWithTemplate({
  required this.delivery,
  required this.template,
  bool isTemplateContentLoaded = true,
  }) : _isTemplateContentLoaded = isTemplateContentLoaded;

  /// Factory constructor that creates a NudgeWithTemplate with lazy loading
  /// This allows efficient loading of lists without fetching full content
  /// @param delivery The delivery record
  /// @param template The template with minimal data
  /// @return A new NudgeWithTemplate with lazy loading capability
  factory NudgeWithTemplate.withLazyLoading(
  NudgeDelivery delivery,
  NudgeTemplate template,
  ) {
  return NudgeWithTemplate(
  delivery: delivery,
  template: template,
  isTemplateContentLoaded: false,
  );
  }

  /// Helper getter for the content
  /// If lazy loading is enabled, this may trigger a content load
  String get content {
  // In a real implementation, this would check if content is loaded
  // and fetch it if needed from a cache or database.
  // For this example, we'll just return the template content.
  return template.content;
  }

  /// Helper getter for the category
  NudgeCategory get category => template.category;

  /// Helper getter for the audio URL
  String? get audioUrl => template.audioUrl;

  /// Helper getter for the delivery time
  DateTime get deliveredAt => delivery.deliveredAt;

  /// Helper getter for the time window
  TimeWindow get timeWindow => delivery.timeWindow;

  /// Helper getter for personalization factors
  PersonalizedFactors? get personalizedFactors => delivery.personalizedFactors;

  /// Helper getter for emotional tone
  EmotionalTone? get emotionalTone => template.metadata.emotionalTone;

  /// Helper getter for wasHelpful feedback
  bool? get wasHelpful => delivery.wasHelpful;

  /// Helper getter for wasSavedAsMemory flag
  bool get wasSavedAsMemory => delivery.wasSavedAsMemory;

  /// Helper getter for helpfulness rating
  int? get helpfulnessRating => delivery.helpfulnessRating;

  /// Check if the template content is fully loaded
  bool get isTemplateContentLoaded => _isTemplateContentLoaded;

  /// Load the full template content asynchronously if needed
  /// In a real implementation, this would fetch from a cache or database
  /// @param templateService A service to fetch template data
  /// @return A future that completes when the template is loaded
  Future<void> loadTemplateContent(dynamic templateService) async {
  // This is a placeholder for actual implementation
  // In a real app, you would fetch the template from a service
  if (!_isTemplateContentLoaded) {
  // Fetch template content from service
  // template = await templateService.getTemplate(delivery.nudgeTemplateId);
  _isTemplateContentLoaded = true;
  }
  }

  /// Provides a string representation of this nudge with template
  @override
  String toString() {
  return 'NudgeWithTemplate{template: ${template.id}, delivery: ${delivery.id}, '
  'category: $category, deliveredAt: $deliveredAt}';
  }
  }

  /// NudgeCategory defines the types of therapeutic nudges available in the app.
  /// Each category represents a different approach to mental wellness.
  enum NudgeCategory {
  /// Prompts that encourage users to recognize and appreciate positive aspects of life
  gratitude,

  /// Prompts that help users focus on the present moment and be more aware
  mindfulness,

  /// Prompts that encourage introspection and personal growth
  selfReflection,

  /// Prompts that provide comfort and positive affirmation
  reassurance,

  /// Prompts that teach cognitive behavioral therapy techniques
  cognitiveTip;

  /// Returns the string representation of this category
  String get value => toString().split('.').last;

  /// Returns the compact key for storage optimization (first letter)
  String get storageKey => value[0];

  /// Converts a string representation to the corresponding NudgeCategory
  /// @param value The string value to convert, should match the enum name
  /// @return The matching NudgeCategory or selfReflection as fallback
  /// @throws ArgumentError if no matching category is found and throwOnError is true
  static NudgeCategory fromString(String value, {bool throwOnError = false}) {
  try {
  return NudgeCategory.values.firstWhere(
  (element) => element.value == value,
  );
  } catch (e) {
  // Log the error for debugging purposes only in debug mode
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Invalid NudgeCategory string: $value. Using default instead.');
  }

  if (throwOnError) {
  throw ArgumentError('Invalid NudgeCategory string: $value');
  }
  return NudgeCategory.selfReflection;
  }
  }

  /// Converts a storage key to the corresponding NudgeCategory
  /// @param key The compact storage key (first letter of category)
  /// @return The matching NudgeCategory or null if not found
  static NudgeCategory? fromStorageKey(String key) {
  for (var category in NudgeCategory.values) {
  if (category.storageKey == key) {
  return category;
  }
  }
  return null;
  }

  /// Converts a map with compact storage keys to full category map
  /// @param map The map with compact keys from Firestore
  /// @return A map with proper NudgeCategory keys
  static Map<NudgeCategory, bool> expandCategoryMap(Map<String, dynamic> map) {
  final expandedMap = <NudgeCategory, bool>{};
  for (var category in NudgeCategory.values) {
  // Try to find the category using its storage key
  final bool value = map[category.storageKey] ?? false;
  expandedMap[category] = value;
  }
  return expandedMap;
  }

  /// Converts a full category map to a compact map for storage
  /// @param map The map with NudgeCategory keys
  /// @return A map with compact string keys for storage
  static Map<String, bool> compactCategoryMap(Map<NudgeCategory, bool> map) {
  final compactMap = <String, bool>{};
  map.forEach((key, value) {
  compactMap[key.storageKey] = value;
  });
  return compactMap;
  }

  /// Returns a human-readable name for the category
  String get displayName {
  switch (this) {
  case NudgeCategory.gratitude:
  return 'Gratitude';
  case NudgeCategory.mindfulness:
  return 'Mindfulness';
  case NudgeCategory.selfReflection:
  return 'Self Reflection';
  case NudgeCategory.reassurance:
  return 'Reassurance';
  case NudgeCategory.cognitiveTip:
  return 'Cognitive Tip';
  }
  }

  @override
  String toString() => 'NudgeCategory.$name';

  /// Returns the integer value for compact storage
  int get intValue {
  return index;
  }

  /// Creates a NudgeCategory from an integer value
  static NudgeCategory fromInt(int value) {
  if (value >= 0 && value < NudgeCategory.values.length) {
  return NudgeCategory.values[value];
  }
  return NudgeCategory.selfReflection;
  }

  /// Converts these settings to a map for Firestore storage
  /// @return A Map suitable for writing to Firestore
  Map<String, dynamic> toMap() {
  // Use compact representation for time windows
  final timeWindowsMap = TimeWindow.compactTimeWindowMap(enabledTimeWindows);

  // Use compact representation for categories
  final categoriesMap = NudgeCategory.compactCategoryMap(enabledCategories);

  // Convert timeWindowCustomization if available - use integer keys
  Map<String, dynamic>? timeWindowsCustomMap;
  if (timeWindowCustomization != null) {
  timeWindowsCustomMap = {};
  timeWindowCustomization!.forEach((key, value) {
  timeWindowsCustomMap![key.intValue.toString()] = value.toMap();
  });
  }

  // Convert categoryPreferences if available - use integer keys
  Map<String, dynamic>? categoriesPrefsMap;
  if (categoryPreferences != null) {
  categoriesPrefsMap = {};
  categoryPreferences!.forEach((key, value) {
  categoriesPrefsMap![key.intValue.toString()] = value;
  });
  }

  return {
  'ne': nudgesEnabled,
  'etw': timeWindowsMap,
  'ec': categoriesMap,
  'twc': timeWindowsCustomMap,
  'cp': categoriesPrefsMap,
  'adut': allowDeviceUnlockTrigger,
  'atbt': allowTimeBasedTrigger,
  'mnpd': maxNudgesPerDay,
  'pv': preferredVoice,
  'ns': notificationSettings.toMap(),
  'ps': privacySettings.toMap(),
  'pp': personalizationPreferences.toMap(),
  'ua': FieldValue.serverTimestamp(),
  'sv': schemaVersion,
  };
  }

  /// Check if nudges are currently allowed based on settings and time
  /// Uses cached time window value if available for better performance
  /// @return true if nudges are enabled and the current time window is enabled
  bool areNudgesAllowedNow() {
  if (!nudgesEnabled) return false;

  final currentWindow = TimeWindow.currentTimeWindow();
  if (currentWindow == null) return false;

  return enabledTimeWindows[currentWindow] ?? false;
  }

  /// Get a list of currently enabled categories
  /// Uses cached values for better performance
  /// @return List of NudgeCategory that are currently enabled
  List<NudgeCategory> getEnabledCategories() {
  // For better performance, cache this calculation
  return enabledCategories.entries
      .where((entry) => entry.value)
      .map((entry) => entry.key)
      .toList();
  }

  /// Creates a copy of these settings with optionally modified fields
  /// @return New NudgeSettings with the updated fields
  NudgeSettings copyWith({
  String? userId,
  bool? nudgesEnabled,
  Map<TimeWindow, bool>? enabledTimeWindows,
  Map<NudgeCategory, bool>? enabledCategories,
  Map<TimeWindow, TimeWindowCustomization>? timeWindowCustomization,
  Map<NudgeCategory, int>? categoryPreferences,
  bool? allowDeviceUnlockTrigger,
  bool? allowTimeBasedTrigger,
  int? maxNudgesPerDay,
  String? preferredVoice,
  NotificationSettings? notificationSettings,
  PrivacySettings? privacySettings,
  PersonalizationPreferences? personalizationPreferences,
  DateTime? updatedAt,
  int? schemaVersion,
  }) {
  return NudgeSettings(
  userId: userId ?? this.userId,
  nudgesEnabled: nudgesEnabled ?? this.nudgesEnabled,
  enabledTimeWindows: enabledTimeWindows ?? this.enabledTimeWindows,
  enabledCategories: enabledCategories ?? this.enabledCategories,
  timeWindowCustomization: timeWindowCustomization ?? this.timeWindowCustomization,
  categoryPreferences: categoryPreferences ?? this.categoryPreferences,
  allowDeviceUnlockTrigger: allowDeviceUnlockTrigger ?? this.allowDeviceUnlockTrigger,
  allowTimeBasedTrigger: allowTimeBasedTrigger ?? this.allowTimeBasedTrigger,
  maxNudgesPerDay: maxNudgesPerDay ?? this.maxNudgesPerDay,
  preferredVoice: preferredVoice ?? this.preferredVoice,
  notificationSettings: notificationSettings ?? this.notificationSettings,
  privacySettings: privacySettings ?? this.privacySettings,
  personalizationPreferences: personalizationPreferences ?? this.personalizationPreferences,
  updatedAt: updatedAt ?? DateTime.now(),
  schemaVersion: schemaVersion ?? this.schemaVersion,
  );
  }

  /// Provides a string representation of these settings
  @override
  String toString() {
  return 'NudgeSettings{userId: $userId, enabled: $nudgesEnabled, maxPerDay: $maxNudgesPerDay, '
  'timeWindows: ${enabledTimeWindows.entries.length} enabled, '
  'categories: ${enabledCategories.entries.where((e) => e.value).length} enabled}';
  }
  }

  /// TimeWindow defines the time periods during which nudges can be delivered.
  /// These windows allow for scheduled delivery of nudges at appropriate times.
  enum TimeWindow {
  /// Early day period, typically 7-9 AM
  morning,

  /// Middle of the day period, typically 12-2 PM
  midday,

  /// Evening period, typically 6-8 PM
  evening;

  /// Returns the string representation of this time window
  String get value => toString().split('.').last;

  /// Returns the compact key for storage optimization (first letter)
  String get storageKey => value[0];

  /// Returns the start hour of the time window (24-hour format)
  int get startHour {
  switch (this) {
  case TimeWindow.morning:
  return 7;
  case TimeWindow.midday:
  return 12;
  case TimeWindow.evening:
  return 18;
  }
  }

  /// Returns the end hour of the time window (24-hour format)
  int get endHour {
  switch (this) {
  case TimeWindow.morning:
  return 9;
  case TimeWindow.midday:
  return 14;
  case TimeWindow.evening:
  return 20;
  }
  }

  /// Determines if the current time is within this time window
  /// @return true if the current time falls within this window
  bool isCurrentTimeInWindow() {
  final now = DateTime.now();
  return now.hour >= startHour && now.hour < endHour;
  }

  /// Returns the current time window based on the current time
  /// @return The current TimeWindow or null if not in any defined window
  static TimeWindow? currentTimeWindow() {
  for (var window in TimeWindow.values) {
  if (window.isCurrentTimeInWindow()) {
  return window;
  }
  }
  return null;
  }

  /// Returns a human-readable name for the time window
  String get displayName {
  switch (this) {
  case TimeWindow.morning:
  return 'Morning';
  case TimeWindow.midday:
  return 'Midday';
  case TimeWindow.evening:
  return 'Evening';
  }
  }

  @override
  String toString() => 'TimeWindow.$name';

  /// Returns the integer value for compact storage
  int get intValue {
  return index;
  }

  /// Creates a TimeWindow from an integer value
  static TimeWindow fromInt(int value) {
  if (value >= 0 && value < TimeWindow.values.length) {
  return TimeWindow.values[value];
  }
  return TimeWindow.morning;
  }

  /// Converts a map with compact storage keys to full time window map
  /// @param map The map with compact keys from Firestore
  /// @return A map with proper TimeWindow keys
  static Map<TimeWindow, bool> expandTimeWindowMap(Map<String, dynamic> map) {
  final expandedMap = <TimeWindow, bool>{};
  for (var window in TimeWindow.values) {
  // Try to find the window using its storage key
  final bool value = map[window.storageKey] ?? false;
  expandedMap[window] = value;
  }
  return expandedMap;
  }

  /// Converts a full time window map to a compact map for storage
  /// @param map The map with TimeWindow keys
  /// @return A map with compact string keys for storage
  static Map<String, bool> compactTimeWindowMap(Map<TimeWindow, bool> map) {
  final compactMap = <String, bool>{};
  map.forEach((key, value) {
  compactMap[key.storageKey] = value;
  });
  return compactMap;
  }
  }

  /// Converts a string representation to the corresponding TimeWindow
  /// @param value The string value to convert, should match the enum name
  /// @return The matching TimeWindow or morning as fallback
  /// @throws ArgumentError if no matching time window is found and throwOnError is true
  extension TimeWindowExtension on TimeWindow {
  static TimeWindow fromString(String value, {bool throwOnError = false}) {
  try {
  return TimeWindow.values.firstWhere(
  (element) => element.value == value,
  );
  } catch (e) {
  // Log the error for debugging purposes only in debug mode
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Invalid TimeWindow string: $value. Using default instead.');
  }

  if (throwOnError) {
  throw ArgumentError('Invalid TimeWindow string: $value');
  }
  return TimeWindow.morning;
  }
  }
  }

  /// Emotional tone for nudges - used in personalization
  enum EmotionalTone {
  calming,
  uplifting,
  reflective,
  encouraging,
  neutral;

  /// Returns the string representation of this emotional tone
  String get value => toString().split('.').last;

  /// Returns the compact key for storage optimization (first letter)
  String get storageKey => value[0];

  /// Converts a string representation to the corresponding EmotionalTone
  /// @param value The string value to convert, should match the enum name
  /// @return The matching EmotionalTone or neutral as fallback
  /// @throws ArgumentError if no matching tone is found and throwOnError is true
  static EmotionalTone fromString(String value, {bool throwOnError = false}) {
  try {
  return EmotionalTone.values.firstWhere(
  (element) => element.value == value,
  );
  } catch (e) {
  // Log the error for debugging purposes only in debug mode
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Invalid EmotionalTone string: $value. Using default instead.');
  }

  if (throwOnError) {
  throw ArgumentError('Invalid EmotionalTone string: $value');
  }
  return EmotionalTone.neutral;
  }
  }

  /// Returns the integer value for compact storage
  int get intValue {
  return index;
  }

  /// Creates an EmotionalTone from an integer value
  static EmotionalTone fromInt(int value) {
  if (value >= 0 && value < EmotionalTone.values.length) {
  return EmotionalTone.values[value];
  }
  return EmotionalTone.neutral;
  }

  /// Returns a human-readable name for the emotional tone
  String get displayName {
  switch (this) {
  case EmotionalTone.calming:
  return 'Calming';
  case EmotionalTone.uplifting:
  return 'Uplifting';
  case EmotionalTone.reflective:
  return 'Reflective';
  case EmotionalTone.encouraging:
  return 'Encouraging';
  case EmotionalTone.neutral:
  return 'Neutral';
  }
  }
  }

  /// Metadata for nudge templates
  class NudgeMetadata {
  /// The creator of this nudge template
  final String? author;

  /// Original source of the nudge content, if applicable
  final String? source;

  /// Specific user groups this nudge is intended for
  final List<String>? targetAudience;

  /// The emotional quality of this nudge
  final EmotionalTone? emotionalTone;

  /// Complexity level (1-5)
  final int? difficulty;

  /// Keywords for searching and categorization
  final List<String>? tags;

  /// Emotional states this nudge is designed to address
  final List<String>? associatedMood;

  /// When the content was last reviewed
  final DateTime? lastReviewed;

  /// Creates a new nudge metadata object
  NudgeMetadata({
  this.author,
  this.source,
  this.targetAudience,
  this.emotionalTone,
  this.difficulty,
  this.tags,
  this.associatedMood,
  this.lastReviewed,
  });

  /// Creates NudgeMetadata from a map
  /// @param map The map containing metadata fields
  /// @return A new NudgeMetadata populated with data from the map
  factory NudgeMetadata.fromMap(Map<String, dynamic>? map) {
  if (map == null) return NudgeMetadata();

  // Handle potential null or invalid values
  EmotionalTone? toneValue;
  if (map['et'] != null) {
  try {
  // Use the compact representation (integer) if available
  if (map['et'] is int) {
  toneValue = EmotionalTone.fromInt(map['et']);
  } else {
  toneValue = EmotionalTone.fromString(map['et']);
  }
  }

  // Handle timestamp
  DateTime updatedAt;
  try {
  // Support both Timestamp and epoch milliseconds
  if (migratedData['ua'] is Timestamp) {
  updatedAt = (migratedData['ua'] as Timestamp?)?.toDate() ?? DateTime.now();
  } else if (migratedData['ua'] is int) {
  updatedAt = DateTime.fromMillisecondsSinceEpoch(migratedData['ua']);
  } else {
  updatedAt = DateTime.now();
  }
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Invalid updatedAt timestamp. Using current time.');
  }
  updatedAt = DateTime.now();
  }

  return NudgeSettings(
  userId: doc.id,
  nudgesEnabled: migratedData['ne'] ?? true,
  enabledTimeWindows: enabledTimeWindows,
  enabledCategories: enabledCategories,
  timeWindowCustomization: timeWindowCustomization,
  categoryPreferences: categoryPreferences,
  allowDeviceUnlockTrigger: migratedData['adut'] ?? true,
  allowTimeBasedTrigger: migratedData['atbt'] ?? true,
  maxNudgesPerDay: migratedData['mnpd'] ?? 3,
  preferredVoice: migratedData['pv'],
  notificationSettings: NotificationSettings.fromMap(
  migratedData['ns'] as Map<String, dynamic>?
  ),
  privacySettings: PrivacySettings.fromMap(
  migratedData['ps'] as Map<String, dynamic>?
  ),
  personalizationPreferences: PersonalizationPreferences.fromMap(
  migratedData['pp'] as Map<String, dynamic>?
  ),
  updatedAt: updatedAt,
  schemaVersion: schemaVersion,
  );
  }

  /// Migrate old document formats to current schema
  /// @param data Original document data
  /// @param originalVersion Original schema version
  /// @return Migrated data in current schema format
  static Map<String, dynamic> _migrateSettingsData(
  Map<String, dynamic> data, int originalVersion) {
  // Deep copy the data
  final Map<String, dynamic> migrated = Map.from(data);

  // Apply migrations based on version
  if (originalVersion < 1) {
  // Example migration from v0 to v1
  if (migrated['nudgesEnabled'] != null) {
  migrated['ne'] = migrated['nudgesEnabled'];
  migrated.remove('nudgesEnabled');
  }

  if (migrated['enabledTimeWindows'] != null) {
  // Convert to compact format
  final Map<String, dynamic> timeWindowsMap = migrated['enabledTimeWindows'];
  final compactMap = <String, bool>{};
  for (var window in TimeWindow.values) {
  final value = timeWindowsMap[window.value] ?? true;
  compactMap[window.storageKey] = value;
  }
  migrated['etw'] = compactMap;
  migrated.remove('enabledTimeWindows');
  }

  if (migrated['enabledCategories'] != null) {
  // Convert to compact format
  final Map<String, dynamic> categoriesMap = migrated['enabledCategories'];
  final compactMap = <String, bool>{};
  for (var category in NudgeCategory.values) {
  final value = categoriesMap[category.value] ?? true;
  compactMap[category.storageKey] = value;
  }
  migrated['ec'] = compactMap;
  migrated.remove('enabledCategories');
  }

  // More migrations...
  }

  // Update schema version
  migrated['sv'] = CURRENT_VERSION;

  return migrated;
  } catch (e) {
  if (kDebugMode) {
  final logger = Logger('NudgeModel');
  logger.warning('Invalid emotionalTone value: ${map['et']}');
  }
  }
  }

  return NudgeMetadata(
  author: map['a'] as String?,
  source: map['s'] as String?,
  targetAudience: map['ta'] != null
  ? List<String>.from(map['ta'])
      : null,
  emotionalTone: toneValue,
  difficulty: map['d'] as int?,
  tags: map['t'] != null ? List<String>.from(map['t']) : null,
  associatedMood: map['am'] != null
  ? List<String>.from(map['am'])
      : null,
  lastReviewed: map['lr'] != null
  ? (map['lr'] is Timestamp
  ? (map['lr'] as Timestamp).toDate()
      : DateTime.fromMillisecondsSinceEpoch(map['lr']))
      : null,
  );
  }

  /// Converts this metadata to a map for Firestore storage
  /// @return A Map suitable for writing to Firestore
  Map<String, dynamic> toMap() {
  return {
  'a': author,
  's': source,
  'ta': targetAudience,
  'et': emotionalTone?.intValue,
  'd': difficulty,
  't': tags,
  'am': associatedMood,
  'lr': lastReviewed != null ? lastReviewed!.millisecondsSinceEpoch : null,
  };
  }
}

/// Analytics data for nudge templates
class NudgeAnalyticsData {
  /// Total number of times this nudge has been delivered
  final int deliveryCount;

  /// Average rating of helpfulness (0-1 scale)
  final double helpfulRating;

  /// When this nudge was last delivered to any user
  final DateTime? lastDeliveredAt;

  /// Creates a new analytics data object
  NudgeAnalyticsData({
    required this.deliveryCount,
    required this.helpfulRating,
    this.lastDeliveredAt,
  });

  /// Creates NudgeAnalyticsData from a map
  /// @param map The map containing analytics data
  /// @return A new NudgeAnalyticsData populated with data from the map
  factory NudgeAnalyticsData.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return NudgeAnalyticsData(
        deliveryCount: 0,
        helpfulRating: 0.0,
      );
    }

    return NudgeAnalyticsData(
      deliveryCount: map['dc'] as int? ?? 0,
      helpfulRating: map['hr'] as double? ?? 0.0,
      lastDeliveredAt: map['lda'] != null
          ? (map['lda'] is Timestamp
          ? (map['lda'] as Timestamp).toDate()
          : DateTime.fromMillisecondsSinceEpoch(map['lda']))
          : null,
    );
  }

  /// Converts this analytics data to a map for Firestore storage
  /// @return A Map suitable for writing to Firestore
  Map<String, dynamic> toMap() {
    return {
      'dc': deliveryCount,
      'hr': helpfulRating,
      'lda': lastDeliveredAt != null ? lastDeliveredAt!.millisecondsSinceEpoch : null,
    };
  }
}

/// Model class for a Nudge Template stored in Firestore.
/// These are pre-defined therapeutic prompts that can be presented to users.
class NudgeTemplate {
  /// Current schema version for this model
  static const int CURRENT_VERSION = NudgeConstants.CURRENT_SCHEMA_VERSION;

  /// Unique identifier for the template
  final String id;

  /// The text content of the nudge prompt
  final String content;

  /// The therapeutic category this nudge belongs to
  final NudgeCategory category;

  /// Structured metadata for this template
  final NudgeMetadata metadata;

  /// Optional URL to an audio version of this nudge
  final String? audioUrl;

  /// Whether this template is currently active and available for delivery
  final bool isActive;

  /// The version number of this template, used for tracking updates
  final int version;

  /// Schema version of this document
  final int schemaVersion;

  /// When this template was created
  final DateTime createdAt;

  /// When this template was last updated
  final DateTime updatedAt;

  /// Analytics data for this template
  final NudgeAnalyticsData? analyticsData;

  /// Optional compressed content for storage optimization
  String? _compressedContent;

  /// Creates a new nudge template
  NudgeTemplate({
    required this.id,
    required this.content,
    required this.category,
    NudgeMetadata? metadata,
    this.audioUrl,
    this.isActive = true,
    this.version = 1,
    int? schemaVersion,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.analyticsData,
  }) :
        metadata = metadata ?? NudgeMetadata(),
        schemaVersion = schemaVersion ?? CURRENT_VERSION,
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Creates a NudgeTemplate from a Firestore document
  /// @param doc The DocumentSnapshot from Firestore
  /// @return A new NudgeTemplate populated with data from Firestore
  factory NudgeTemplate.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    // Check schema version for possible migrations
    final int schemaVersion = data['sv'] ?? 1;
    Map<String, dynamic> migratedData = data;

    // Migrate old data formats if needed
    if (schemaVersion < CURRENT_VERSION) {
      migratedData = _migrateTemplateData(data, schemaVersion);
    }

    // Handle potential missing or invalid category
    NudgeCategory category;
    try {
      // Check if using the compact int representation
      if (migratedData['c'] is int) {
        category = NudgeCategory.fromInt(migratedData['c']);
      } else {
        category = NudgeCategory.fromString(migratedData['c'] ?? '');
      }
    } catch (e) {
      if (kDebugMode) {
        final logger = Logger('NudgeModel');
        logger.warning('Invalid category for template ${doc.id}. Using default.');
      }
      category = NudgeCategory.selfReflection;
    }

    // Parse timestamps safely
    DateTime createdAt;
    DateTime updatedAt;
    try {
      // Support both Timestamp and epoch milliseconds for flexibility
      if (migratedData['ca'] is Timestamp) {
        createdAt = (migratedData['ca'] as Timestamp).toDate();
      } else if (migratedData['ca'] is int) {
        createdAt = DateTime.fromMillisecondsSinceEpoch(migratedData['ca']);
      } else {
        createdAt = DateTime.now();
      }

      if (migratedData['ua'] is Timestamp) {
        updatedAt = (migratedData['ua'] as Timestamp).toDate();
      } else if (migratedData['ua'] is int) {
        updatedAt = DateTime.fromMillisecondsSinceEpoch(migratedData['ua']);
      } else {
        updatedAt = DateTime.now();
      }
    } catch (e) {
      if (kDebugMode) {
        final logger = Logger('NudgeModel');
        logger.warning('Invalid timestamps for template ${doc.id}. Using current time.');
      }
      createdAt = DateTime.now();
      updatedAt = DateTime.now();
    }

    // Handle compressed content if available
    String content = '';
    if (migratedData['cmp'] != null) {
      try {
        final List<int> compressed = base64Decode(migratedData['cmp']);
        content = utf8.decode(compressed);
      } catch (e) {
        if (kDebugMode) {
          final logger = Logger('NudgeModel');
          logger.warning('Failed to decompress content for ${doc.id}. Using raw content.');
        }
        content = migratedData['cnt'] ?? '';
      }
    } else {
      content = migratedData['cnt'] ?? '';
    }

    return NudgeTemplate(
      id: doc.id,
      content: content,
      category: category,
      metadata: NudgeMetadata.fromMap(migratedData['md'] as Map<String, dynamic>?),
      audioUrl: migratedData['au'],
      isActive: migratedData['ia'] ?? true,
      version: migratedData['v'] ?? 1,
      schemaVersion: schemaVersion,
      createdAt: createdAt,
      updatedAt: updatedAt,
      analyticsData: migratedData['ad'] != null
          ? NudgeAnalyticsData.fromMap(migratedData['ad'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Compresses the content to reduce storage size
  String get compressedContent {
    if (_compressedContent == null) {
      final contentBytes = utf8.encode(content);
      _compressedContent = base64Encode(contentBytes);
    }
    return _compressedContent!;
  }

  /// Converts this template to a map for Firestore storage
  /// @return A Map suitable for writing to Firestore
  Map<String, dynamic> toMap() {
    return {
      'cnt': content,
      'cmp': compressedContent, // Store compressed content for large text
      'c': category.intValue, // Store as integer for compactness
      'md': metadata.toMap(),
      'au': audioUrl,
      'ia': isActive,
      'v': version,
      'sv': schemaVersion,
      'ca': FieldValue.serverTimestamp(), // Use server timestamp consistently
      'ua': FieldValue.serverTimestamp(),
      'ad': analyticsData?.toMap(),
    };
  }

  /// Migrate old document formats to current schema
  /// @param data Original document data
  /// @param originalVersion Original schema version
  /// @return Migrated data in current schema format
  static Map<String, dynamic> _migrateTemplateData(
      Map<String, dynamic> data, int originalVersion) {
    // Deep copy the data
    final Map<String, dynamic> migrated = Map.from(data);

    // Apply migrations based on version
    if (originalVersion < 1) {
      // Example migration from v0 to v1
      // Rename fields, transform data, etc.
      if (migrated['content'] != null) {
        migrated['cnt'] = migrated['content'];
        migrated.remove('content');
      }

      if (migrated['category'] != null) {
        final categoryStr = migrated['category'];
        try {
          final category = NudgeCategory.fromString(categoryStr);
          migrated['c'] = category.intValue;
        } catch (e) {
          migrated['c'] = NudgeCategory.selfReflection.intValue;
        }
        migrated.remove('category');
      }

      // More migrations...
    }

    // Update schema version
    migrated['sv'] = CURRENT_VERSION;

    return migrated;
  }

  /// Creates a copy of this template with optionally modified fields
  /// @return A new NudgeTemplate with the updated fields
  NudgeTemplate copyWith({
    String? id,
    String? content,
    NudgeCategory? category,
    NudgeMetadata? metadata,
    String? audioUrl,
    bool? isActive,
    int? version,
    int? schemaVersion,
    DateTime? createdAt,
    DateTime? updatedAt,
    NudgeAnalyticsData? analyticsData,
  }) {
    return NudgeTemplate(
      id: id ?? this.id,
      content: content ?? this.content,
      category: category ?? this.category,
      metadata: metadata ?? this.metadata,
      audioUrl: audioUrl ?? this.audioUrl,
      isActive: isActive ?? this.isActive,
      version: version ?? this.version,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      analyticsData: analyticsData ?? this.analyticsData,
    );
  }

  /// Provides a string representation of this template
  @override
  String toString() {
    return 'NudgeTemplate{id: $id, content: $content, category: $category, isActive: $isActive, version: $version}';
  }
}

/// Class representing user interaction events with nudges
class InteractionEvent {
  /// Type of interaction (viewed, played, paused, rated, etc.)
  final String eventType;

  /// When the interaction occurred
  final DateTime timestamp;

  /// Additional data about the interaction
  final Map<String, dynamic>? extraData;

  /// Creates a new interaction event
  InteractionEvent({
    required this.eventType,
    required this.timestamp,
    this.extraData,
  });

  /// Creates an InteractionEvent from a map
  /// @param map The map containing event data
  /// @return A new InteractionEvent populated with data from the map
  factory InteractionEvent.fromMap(Map<String, dynamic> map) {
    DateTime timestamp;
    try {
      // Support both Timestamp and epoch milliseconds
      if (map['ts'] is Timestamp) {
        timestamp = (map['ts'] as Timestamp).toDate();
      } else if (map['ts'] is int) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(map['ts']);
      } else {
        timestamp = DateTime.now();
      }
    } catch (e) {
      if (kDebugMode) {
        final logger = Logger('NudgeModel');
        logger.warning('Invalid timestamp for interaction event. Using current time.');
      }
      timestamp = DateTime.now();
    }

    return InteractionEvent(
      eventType: map['et'] as String? ?? 'unknown',
      timestamp: timestamp,
      extraData: map['ed'] as Map<String, dynamic>?,
    );
  }

  /// Converts this event to a map for Firestore storage
  /// @return A Map suitable for writing to Firestore
  Map<String, dynamic> toMap() {
    return {
      'et': eventType,
      'ts': timestamp.millisecondsSinceEpoch, // Store as milliseconds
      'ed': extraData,
    };
  }
}

/// Class representing audio playback statistics
class AudioPlaybackStats {
  /// Whether the user listened to the entire audio
  final bool playbackComplete;

  /// Duration of playback in seconds
  final int playbackDurationSeconds;

  /// Number of times the audio was replayed
  final int replayCount;

  /// When the audio was last replayed
  final DateTime? lastReplayedAt;

  /// Creates new audio playback statistics
  AudioPlaybackStats({
    required this.playbackComplete,
    required this.playbackDurationSeconds,
    this.replayCount = 0,
    this.lastReplayedAt,
  });

  /// Creates AudioPlaybackStats from a map
  /// @param map The map containing playback data
  /// @return A new AudioPlaybackStats populated with data from the map
  factory AudioPlaybackStats.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return AudioPlaybackStats(
        playbackComplete: false,
        playbackDurationSeconds: 0,
      );
    }

    DateTime? lastReplayedAt;
    if (map['lra'] != null) {
      try {
        // Support both Timestamp and epoch milliseconds
        if (map['lra'] is Timestamp) {
          lastReplayedAt = (map['lra'] as Timestamp).toDate();
        } else if (map['lra'] is int) {
          lastReplayedAt = DateTime.fromMillisecondsSinceEpoch(map['lra']);
        }
      } catch (e) {
        if (kDebugMode) {
          final logger = Logger('NudgeModel');
          logger.warning('Invalid lastReplayedAt timestamp. Ignoring.');
        }
      }
    }

    return AudioPlaybackStats(
      playbackComplete: map['pc'] as bool? ?? false,
      playbackDurationSeconds: map['pd'] as int? ?? 0,
      replayCount: map['rc'] as int? ?? 0,
      lastReplayedAt: lastReplayedAt,
    );
  }

  /// Converts these stats to a map for Firestore storage
  /// @return A Map suitable for writing to Firestore
  Map<String, dynamic> toMap() {
    return {
      'pc': playbackComplete,
      'pd': playbackDurationSeconds,
      'rc': replayCount,
      'lra': lastReplayedAt != null ? lastReplayedAt!.millisecondsSinceEpoch : null,
    };
  }

  /// Creates a copy with incremented replay count
  /// @return A new AudioPlaybackStats with updated replay information
  AudioPlaybackStats incrementReplay() {
    return AudioPlaybackStats(
      playbackComplete: playbackComplete,
      playbackDurationSeconds: playbackDurationSeconds,
      replayCount: replayCount + 1,
      lastReplayedAt: DateTime.now(),
    );
  }
}

/// Class representing personalization factors for nudge delivery
class PersonalizedFactors {
  /// User's current emotional state
  final String? userMood;

  /// Emotional tone selected for this nudge
  final EmotionalTone? selectedTone;

  /// Recent topics the user has shown interest in
  final List<String>? recentInterests;

  /// Recent topics from the user's saved memories
  final List<String>? recentMemoryTopics;

  /// How much personalization is applied (1-5)
  final int? adaptationLevel;

  /// Creates a new personalized factors object
  PersonalizedFactors({
    this.userMood,
    this.selectedTone,
    this.recentInterests,
    this.recentMemoryTopics,
    this.adaptationLevel,
  });

  /// Creates PersonalizedFactors from a map
  /// @param map The map containing personalization data
  /// @return A new PersonalizedFactors populated with data from the map
  factory PersonalizedFactors.fromMap(Map<String, dynamic>? map) {
    if (map == null) return PersonalizedFactors();

    EmotionalTone? toneValue;
    if (map['st'] != null) {
      try {
        // Support both string and integer representations
        if (map['st'] is int) {
          toneValue = EmotionalTone.fromInt(map['st']);
        } else {
          toneValue = EmotionalTone.fromString(map['st']);
        }
      } catch (e) {
        if (kDebugMode) {
          final logger = Logger('NudgeModel');
          logger.warning('Invalid selectedTone value: ${map['st']}');
        }
      }
    }

    return PersonalizedFactors(
      userMood: map['um'] as String?,
      selectedTone: toneValue,
      recentInterests: map['ri'] != null
          ? List<String>.from(map['ri'])
          : null,
      recentMemoryTopics: map['rmt'] != null
          ? List<String>.from(map['rmt'])
          : null,
      adaptationLevel: map['al'] as int?,
    );
  }

  /// Converts these factors to a map for Firestore storage
  /// @return A Map suitable for writing to Firestore
  Map<String, dynamic> toMap() {
    return {
      'um': userMood,
      'st': selectedTone?.intValue,
      'ri': recentInterests,
      'rmt': recentMemoryTopics,
      'al': adaptationLevel,
    };
  }
}

/// Model class for a NudgeDelivery that records when a nudge was
/// presented to a user and any user feedback.
class NudgeDelivery {
  /// Current schema version for this model
  static const int CURRENT_VERSION = NudgeConstants.CURRENT_SCHEMA_VERSION;

  /// Unique identifier for this delivery instance
  final String id;

  /// Reference to the template that was delivered
  final String nudgeTemplateId;

  /// The user who received this nudge
  final String userId;

  /// Timestamp when the nudge was delivered
  final DateTime deliveredAt;

  /// The time window during which this nudge was delivered
  final TimeWindow timeWindow;

  /// User feedback on whether the nudge was helpful (null if no feedback)
  final bool? wasHelpful;

  /// More granular rating of helpfulness (1-5 scale)
  final int? helpfulnessRating;

  /// Whether the user saved this nudge to their memories for later reference
  final bool wasSavedAsMemory;

  /// User's text response to the nudge, if any
  final String? userResponse;

  /// ID of a memory created from this nudge
  final String? relatedMemoryId;

  /// Additional data associated with this delivery
  final Map<String, dynamic>? metadata;

  /// Timeline of user interactions with this nudge
  final List<InteractionEvent>? interactionEvents;

  /// Statistics about audio playback
  final AudioPlaybackStats? audioPlaybackStats;

  /// Personalization factors used for this nudge
  final PersonalizedFactors? personalizedFactors;

  /// How this nudge was triggered ("deviceUnlock", "timeScheduled", etc.)
  final String? triggerType;

  /// Schema version of this document
  final int schemaVersion;

  /// When this delivery record should expire (TTL)
  final DateTime? expiresAt;

  /// Creates a new nudge delivery record
  /// If no id is provided, a UUID will be generated
  NudgeDelivery({
    String? id,
    required this.nudgeTemplateId,
    required this.userId,
    required this.deliveredAt,
    required this.timeWindow,
    this.wasHelpful,
    this.helpfulnessRating,
    this.wasSavedAsMemory = false,
    this.userResponse,
    this.relatedMemoryId,
    this.metadata,
    this.interactionEvents,
    this.audioPlaybackStats,
    this.personalizedFactors,
    this.triggerType,
    int? schemaVersion,
    DateTime? expiresAt,
  }) :
        id = id ?? const Uuid().v4(),
        schemaVersion = schemaVersion ?? CURRENT_VERSION,
        expiresAt = expiresAt ?? DateTime.now().add(
            Duration(milliseconds: NudgeConstants.DEFAULT_DELIVERY_TTL_MS));

  /// Creates a NudgeDelivery from a Firestore document
  /// @param doc The DocumentSnapshot from Firestore
  /// @return A new NudgeDelivery populated with data from Firestore
  factory NudgeDelivery.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    // Check schema version for possible migrations
    final int schemaVersion = data['sv'] ?? 1;
    Map<String, dynamic> migratedData = data;

    // Migrate old data formats if needed
    if (schemaVersion < CURRENT_VERSION) {
      migratedData = _migrateDeliveryData(data, schemaVersion);
    }

    // Handle potential null Timestamp
    DateTime deliveredAt;
    try {
      // Support both Timestamp and epoch milliseconds
      if (migratedData['da'] is Timestamp) {
        deliveredAt = (migratedData['da'] as Timestamp?)?.toDate() ?? DateTime.now();
      } else if (migratedData['da'] is int) {
        deliveredAt = DateTime.fromMillisecondsSinceEpoch(migratedData['da']);
      } else {
        deliveredAt = DateTime.now();
      }
    } catch (e) {
      if (kDebugMode) {
        final logger = Logger('NudgeModel');
        logger.warning('Invalid or missing deliveredAt timestamp for delivery ${doc.id}. Using current time.');
      }
      deliveredAt = DateTime.now();
    }

    // Handle expiration date
    DateTime? expiresAt;
    try {
      if (migratedData['exp'] is Timestamp) {
        expiresAt = (migratedData['exp'] as Timestamp?)?.toDate();
      } else if (migratedData['exp'] is int) {
        expiresAt = DateTime.fromMillisecondsSinceEpoch(migratedData['exp']);
      }
    } catch (e) {
      if (kDebugMode) {
        final logger = Logger('NudgeModel');
        logger.warning('Invalid expiresAt timestamp for delivery ${doc.id}.');
      }
    }

    // Use integer representation for time window if available
    final TimeWindow timeWindow;
    if (migratedData['tw'] is int) {
      timeWindow = TimeWindow.fromInt(migratedData['tw']);
    } else {
      final timeWindowStr = migratedData['tw'] as String?;
      timeWindow = TimeWindowExtension.fromString(timeWindowStr ?? 'morning');
    }

    // Parse interaction events
    List<InteractionEvent>? interactionEvents;
    if (migratedData['ie'] != null) {
      try {
        interactionEvents = (migratedData['ie'] as List)
            .map((e) => InteractionEvent.fromMap(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        if (kDebugMode) {
          final logger = Logger('NudgeModel');
          logger.warning('Error parsing interactionEvents for ${doc.id}: $e');
        }
      }
    }

    return NudgeDelivery(
      id: doc.id,
      nudgeTemplateId: migratedData['ntid'] ?? '',
      userId: migratedData['uid'] ?? '',
      deliveredAt: deliveredAt,
      timeWindow: timeWindow,
      wasHelpful: migratedData['wh'],
      helpfulnessRating: migratedData['hr'],
      wasSavedAsMemory: migratedData['wsm'] ?? false,
      userResponse: migratedData['ur'],
      relatedMemoryId: migratedData['rmid'],
      metadata: migratedData['md'],
      interactionEvents: interactionEvents,
      audioPlaybackStats: migratedData['aps'] != null
          ? AudioPlaybackStats.fromMap(migratedData['aps'] as Map<String, dynamic>)
          : null,
      personalizedFactors: migratedData['pf'] != null
          ? PersonalizedFactors.fromMap(migratedData['pf'] as Map<String, dynamic>)
          : null,
      triggerType: migratedData['tt'],
      schemaVersion: schemaVersion,
      expiresAt: expiresAt,
    );
  }

  /// Migrate old document formats to current schema
  /// @param data Original document data
  /// @param originalVersion Original schema version
  /// @return Migrated data in current schema format
  static Map<String, dynamic> _migrateDeliveryData(
      Map<String, dynamic> data, int originalVersion) {
    // Deep copy the data
    final Map<String, dynamic> migrated = Map.from(data);

    // Apply migrations based on version
    if (originalVersion < 1) {
      // Example migration from v0 to v1
      if (migrated['nudgeTemplateId'] != null) {
        migrated['ntid'] = migrated['nudgeTemplateId'];
        migrated.remove('nudgeTemplateId');
      }

      if (migrated['userId'] != null) {
        migrated['uid'] = migrated['userId'];
        migrated.remove('userId');
      }

      if (migrated['timeWindow'] != null) {
        final timeWindowStr = migrated['timeWindow'];
        try {
          final timeWindow = TimeWindowExtension.fromString(timeWindowStr);
          migrated['tw'] = timeWindow.intValue;
        } catch (e) {
          migrated['tw'] = TimeWindow.morning.intValue;
        }
        migrated.remove('timeWindow');
      }

      // More migrations...
    }

    // Update schema version
    migrated['sv'] = CURRENT_VERSION;

    return migrated;
  }

  /// Converts this delivery to a map for Firestore storage
  /// @return A Map suitable for writing to Firestore
  Map<String, dynamic> toMap() {
    return {
      'ntid': nudgeTemplateId,
      'uid': userId,
      'da': FieldValue.serverTimestamp(),
      'tw': timeWindow.intValue, // Store as integer for compactness
      'wh': wasHelpful,
      'hr': helpfulnessRating,
      'wsm': wasSavedAsMemory,
      'ur': userResponse,
      'rmid': relatedMemoryId,
      'md': metadata ?? {},
      'ie': interactionEvents?.map((e) => e.toMap()).toList(),
      'aps': audioPlaybackStats?.toMap(),
      'pf': personalizedFactors?.toMap(),
      'tt': triggerType,
      'sv': schemaVersion,
      'exp': expiresAt != null ? expiresAt!.millisecondsSinceEpoch : null,
    };
  }

  /// Creates a copy of this delivery with optionally modified fields
  /// @return A new NudgeDelivery with the updated fields
  NudgeDelivery copyWith({
    String? id,
    String? nudgeTemplateId,
    String? userId,
    DateTime? deliveredAt,
    TimeWindow? timeWindow,
    bool? wasHelpful,
    int? helpfulnessRating,
    bool? wasSavedAsMemory,
    String? userResponse,
    String? relatedMemoryId,
    Map<String, dynamic>? metadata,
    List<InteractionEvent>? interactionEvents,
    AudioPlaybackStats? audioPlaybackStats,
    PersonalizedFactors? personalizedFactors,
    String? triggerType,
    int? schemaVersion,
    DateTime? expiresAt,
  }) {
    return NudgeDelivery(
      id: id ?? this.id,
      nudgeTemplateId: nudgeTemplateId ?? this.nudgeTemplateId,
      userId: userId ?? this.userId,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      timeWindow: timeWindow ?? this.timeWindow,
      wasHelpful: wasHelpful ?? this.wasHelpful,
      helpfulnessRating: helpfulnessRating ?? this.helpfulnessRating,
      wasSavedAsMemory: wasSavedAsMemory ?? this.wasSavedAsMemory,
      userResponse: userResponse ?? this.userResponse,
      relatedMemoryId: relatedMemoryId ?? this.relatedMemoryId,
      metadata: metadata ?? this.metadata,
      interactionEvents: interactionEvents ?? this.interactionEvents,
      audioPlaybackStats: audioPlaybackStats ?? this.audioPlaybackStats,
      personalizedFactors: personalizedFactors ?? this.personalizedFactors,
      triggerType: triggerType ?? this.triggerType,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  /// Link this nudge to a memory
  /// @param memoryId The ID of the memory to link to
  /// @return A new NudgeDelivery with the memory relationship established
  NudgeDelivery linkToMemory(String memoryId) {
    return copyWith(
      relatedMemoryId: memoryId,
      wasSavedAsMemory: true,
    );
  }

  /// Provides a string representation of this delivery
  @override
  String toString() {
    return 'NudgeDelivery{id: $id, templateId: $nudgeTemplateId, userId: $userId, deliveredAt: $deliveredAt, wasHelpful: $wasHelpful, saved: $wasSavedAsMemory}';
  }
}

/// Privacy settings for user
class PrivacySettings {
  /// Whether to store audio recordings of the user
  final bool storeAudioRecordings;

  /// Whether to collect analytics about nudge usage
  final bool allowAnalyticsCollection;

  /// Whether anonymized data can be shared for research
  final bool shareAnonymizedData;

  /// Whether to store potentially sensitive information
  final bool storeSensitiveInfo;

  /// Creates new privacy settings
  PrivacySettings({
    required this.storeAudioRecordings,
    required this.allowAnalyticsCollection,
    required this.shareAnonymizedData,
    required this.storeSensitiveInfo,
  });

  /// Creates PrivacySettings from a map
  /// @param map The map containing privacy settings
  /// @return A new PrivacySettings populated with data from the map
  factory PrivacySettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return PrivacySettings.defaultSettings();
    }

    return PrivacySettings(
      storeAudioRecordings: map['sar'] as bool? ?? true,
      allowAnalyticsCollection: map['aac'] as bool? ?? true,
      shareAnonymizedData: map['sad'] as bool? ?? false,
      storeSensitiveInfo: map['ssi'] as bool? ?? false,
    );
  }

  /// Converts these settings to a map for Firestore storage
  /// @return A Map suitable for writing to Firestore
  Map<String, dynamic> toMap() {
    return {
      'sar': storeAudioRecordings,
      'aac': allowAnalyticsCollection,
      'sad': shareAnonymizedData,
      'ssi': storeSensitiveInfo,
    };
  }

  /// Default privacy settings with conservative defaults
  factory PrivacySettings.defaultSettings() {
    return PrivacySettings(
      storeAudioRecordings: true,
      allowAnalyticsCollection: true,
      shareAnonymizedData: false,
      storeSensitiveInfo: false,
    );
  }
}

/// Personalization preferences for nudges
class PersonalizationPreferences {
  /// Master toggle for personalization features
  final bool enablePersonalization;

  /// How strongly to personalize (1-5 scale)
  final int adaptationLevel;

  /// Topics the user prefers to receive nudges about
  final List<String>? preferredTopics;

  /// Emotional tones the user prefers for nudges
  final List<EmotionalTone>? preferredTones;

  /// Whether to use mood for personalization
  final bool trackMoodForPersonalization;

  /// Creates new personalization preferences
  PersonalizationPreferences({
    required this.enablePersonalization,
    required this.adaptationLevel,
    this.preferredTopics,
    this.preferredTones,
    required this.trackMoodForPersonalization,
  });

  /// Creates PersonalizationPreferences from a map
  /// @param map The map containing personalization preferences
  /// @return A new PersonalizationPreferences populated with data from the map
  factory PersonalizationPreferences.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return PersonalizationPreferences.defaultSettings();
    }

    List<EmotionalTone>? preferredTones;
    if (map['pt'] != null) {
      try {
        // Support both string and integer arrays
        preferredTones = (map['pt'] as List).map((e) {
          if (e is int) {
            return EmotionalTone.fromInt(e);
          } else {
            return EmotionalTone.fromString(e as String);
          }
        }).toList();
      } catch (e) {
        if (kDebugMode) {
          final logger = Logger('NudgeModel');
          logger.warning('Error parsing preferredTones: $e');
        }
      }
    }

    return PersonalizationPreferences(
      enablePersonalization: map['ep'] as bool? ?? true,
      adaptationLevel: map['al'] as int? ?? 3,
      preferredTopics: map['pts'] != null
          ? List<String>.from(map['pts'])
          : null,
      preferredTones: preferredTones,
      trackMoodForPersonalization: map['tmp'] as bool? ?? true,
    );
  }

  /// Converts these preferences to a map for Firestore storage
  /// @return A Map suitable for writing to Firestore
  Map<String, dynamic> toMap() {
    return {
      'ep': enablePersonalization,
      'al': adaptationLevel,
      'pts': preferredTopics,
      'pt': preferredTones?.map((e) => e.intValue).toList(),
      'tmp': trackMoodForPersonalization,
    };
  }

  /// Default personalization preferences with moderate settings
  factory PersonalizationPreferences.defaultSettings() {
    return PersonalizationPreferences(
      enablePersonalization: true,
      adaptationLevel: 3,
      preferredTopics: null,
      preferredTones: [EmotionalTone.calming, EmotionalTone.uplifting],
      trackMoodForPersonalization: true,
    );
  }
}

/// Notification settings for nudges
class NotificationSettings {
  /// Whether to show nudge content in notifications
  final bool showPreview;

  /// Whether to play sound with notifications
  final bool sound;

  /// Whether to vibrate with notifications
  final bool vibration;

  /// Creates new notification settings
  NotificationSettings({
    required this.showPreview,
    required this.sound,
    required this.vibration,
  });

  /// Creates NotificationSettings from a map
  /// @param map The map containing notification settings
  /// @return A new NotificationSettings populated with data from the map
  factory NotificationSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return NotificationSettings.defaultSettings();
    }

    return NotificationSettings(
      showPreview: map['sp'] as bool? ?? true,
      sound: map['s'] as bool? ?? true,
      vibration: map['v'] as bool? ?? true,
    );
  }

  /// Converts these settings to a map for Firestore storage
  /// @return A Map suitable for writing to Firestore
  Map<String, dynamic> toMap() {
    return {
      'sp': showPreview,
      's': sound,
      'v': vibration,
    };
  }

  /// Default notification settings with all features enabled
  factory NotificationSettings.defaultSettings() {
    return NotificationSettings(
      showPreview: true,
      sound: true,
      vibration: true,
    );
  }
}

/// Class representing customized time window settings
class TimeWindowCustomization {
  /// Start hour (0-23) for this time window
  final int startHour;

  /// End hour (0-23) for this time window
  final int endHour;

  /// Creates a new time window customization
  TimeWindowCustomization({
    required this.startHour,
    required this.endHour,
  });

  /// Creates TimeWindowCustomization from a map
  /// @param map The map containing time window settings
  /// @return A new TimeWindowCustomization populated with data from the map
  factory TimeWindowCustomization.fromMap(Map<String, dynamic> map) {
    return TimeWindowCustomization(
      startHour: map['sh'] as int? ?? 0,
      endHour: map['eh'] as int? ?? 23,
    );
  }

  /// Converts this customization to a map for Firestore storage
  /// @return A Map suitable for writing to Firestore
  Map<String, dynamic> toMap() {
    return {
      'sh': startHour,
      'eh': endHour,
    };
  }
}

/// Model class for user NudgeSettings to control nudge delivery preferences
class NudgeSettings {
  /// Current schema version for this model
  static const int CURRENT_VERSION = NudgeConstants.CURRENT_SCHEMA_VERSION;

  /// The user these settings belong to
  final String userId;

  /// Master toggle for all nudges
  final bool nudgesEnabled;

  /// Map defining which time windows are enabled for nudge delivery
  final Map<TimeWindow, bool> enabledTimeWindows;

  /// Map defining which nudge categories are enabled for the user
  final Map<NudgeCategory, bool> enabledCategories;

  /// Optional custom time ranges for each time window
  final Map<TimeWindow, TimeWindowCustomization>? timeWindowCustomization;

  /// Optional preference weights for categories (1-10 scale)
  final Map<NudgeCategory, int>? categoryPreferences;

  /// Whether nudges can be triggered when the user unlocks their device
  final bool allowDeviceUnlockTrigger;

  /// Whether nudges can be triggered on a scheduled basis
  final bool allowTimeBasedTrigger;

  /// Maximum number of nudges to deliver per day
  final int maxNudgesPerDay;

  /// Preferred voice for TTS audio (e.g., "nova", "shimmer")
  final String? preferredVoice;

  /// Settings for how notifications are presented
  final NotificationSettings notificationSettings;

  /// Settings for privacy and data handling
  final PrivacySettings privacySettings;

  /// Settings for personalization features
  final PersonalizationPreferences personalizationPreferences;

  /// When settings were last updated
  final DateTime updatedAt;

  /// Schema version for this document
  final int schemaVersion;

  /// Creates new nudge settings for a user
  /// Provides sensible defaults for optional parameters
  NudgeSettings({
    required this.userId,
    this.nudgesEnabled = true,
    Map<TimeWindow, bool>? enabledTimeWindows,
    Map<NudgeCategory, bool>? enabledCategories,
    this.timeWindowCustomization,
    this.categoryPreferences,
    this.allowDeviceUnlockTrigger = true,
    this.allowTimeBasedTrigger = true,
    this.maxNudgesPerDay = 3,
    this.preferredVoice = 'nova',
    NotificationSettings? notificationSettings,
    PrivacySettings? privacySettings,
    PersonalizationPreferences? personalizationPreferences,
    DateTime? updatedAt,
    int? schemaVersion,
  }) :
        enabledTimeWindows = enabledTimeWindows ?? {
          TimeWindow.morning: true,
          TimeWindow.midday: true,
          TimeWindow.evening: true,
        },
        enabledCategories = enabledCategories ?? {
          NudgeCategory.gratitude: true,
          NudgeCategory.mindfulness: true,
          NudgeCategory.selfReflection: true,
          NudgeCategory.reassurance: true,
          NudgeCategory.cognitiveTip: true,
        },
        notificationSettings = notificationSettings ?? NotificationSettings.defaultSettings(),
        privacySettings = privacySettings ?? PrivacySettings.defaultSettings(),
        personalizationPreferences = personalizationPreferences ?? PersonalizationPreferences.defaultSettings(),
        updatedAt = updatedAt ?? DateTime.now(),
        schemaVersion = schemaVersion ?? CURRENT_VERSION;

  /// Creates default settings for a user
  /// @param userId The user ID to create settings for
  /// @return A new NudgeSettings with default values
  factory NudgeSettings.defaultSettings(String userId) {
    return NudgeSettings(
      userId: userId,
      nudgesEnabled: true,
      enabledTimeWindows: {
        TimeWindow.morning: true,
        TimeWindow.midday: true,
        TimeWindow.evening: true,
      },
      enabledCategories: {
        NudgeCategory.gratitude: true,
        NudgeCategory.mindfulness: true,
        NudgeCategory.selfReflection: true,
        NudgeCategory.reassurance: true,
        NudgeCategory.cognitiveTip: true,
      },
      allowDeviceUnlockTrigger: true,
      allowTimeBasedTrigger: true,
      maxNudgesPerDay: 3,
      preferredVoice: 'nova',
      notificationSettings: NotificationSettings.defaultSettings(),
      privacySettings: PrivacySettings.defaultSettings(),
      personalizationPreferences: PersonalizationPreferences.defaultSettings(),
      updatedAt: DateTime.now(),
      schemaVersion: CURRENT_VERSION,
    );
  }

  /// Creates NudgeSettings from a Firestore document
  /// @param doc The DocumentSnapshot from Firestore
  /// @return New NudgeSettings populated with data from Firestore
  factory NudgeSettings.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    // Check schema version for possible migrations
    final int schemaVersion = data['sv'] ?? 1;
    Map<String, dynamic> migratedData = data;

    // Migrate old data formats if needed
    if (schemaVersion < CURRENT_VERSION) {
      migratedData = _migrateSettingsData(data, schemaVersion);
    }

    // Parse time windows - use the compact representation if available
    Map<TimeWindow, bool> enabledTimeWindows = {};
    if (migratedData['etw'] != null) {
      // Try the compact map first (new format)
      final timeWindowsData = migratedData['etw'] as Map<String, dynamic>;
      enabledTimeWindows = TimeWindow.expandTimeWindowMap(timeWindowsData);
    } else if (migratedData['enabledTimeWindows'] != null) {
      // Fall back to old format
      final timeWindowsData = migratedData['enabledTimeWindows'] as Map<String, dynamic>;
      for (var window in TimeWindow.values) {
        final key = window.value;
        enabledTimeWindows[window] = timeWindowsData[key] ?? true;
      }
    } else {
      // Default to all enabled
      for (var window in TimeWindow.values) {
        enabledTimeWindows[window] = true;
      }
    }

    // Parse categories - use the compact representation if available
    Map<NudgeCategory, bool> enabledCategories = {};
    if (migratedData['ec'] != null) {
      // Try the compact map first (new format)
      final categoriesData = migratedData['ec'] as Map<String, dynamic>;
      enabledCategories = NudgeCategory.expandCategoryMap(categoriesData);
    } else if (migratedData['enabledCategories'] != null) {
      // Fall back to old format
      final categoriesData = migratedData['enabledCategories'] as Map<String, dynamic>;
      for (var category in NudgeCategory.values) {
        final key = category.value;
        enabledCategories[category] = categoriesData[key] ?? true;
      }
    } else {
      // Default to all enabled
      for (var category in NudgeCategory.values) {
        enabledCategories[category] = true;
      }
    }

    // Parse time window customization if available
    Map<TimeWindow, TimeWindowCustomization>? timeWindowCustomization;
    if (migratedData['twc'] != null) {
      try {
        timeWindowCustomization = {};
        final Map<String, dynamic> customMap = migratedData['twc'] as Map<String, dynamic>;
        for (var entry in customMap.entries) {
          // Try to parse as int first (compact format)
          TimeWindow? window;
          try {
            final intKey = int.parse(entry.key);
            window = TimeWindow.fromInt(intKey);
          } catch (e) {
            // Fall back to string parsing
            window = TimeWindowExtension.fromString(entry.key);
          }

          if (window != null) {
            timeWindowCustomization[window] =
                TimeWindowCustomization.fromMap(entry.value as Map<String, dynamic>);
          }
        }
      } catch (e) {
        if (kDebugMode) {
          final logger = Logger('NudgeModel');
          logger.warning('Error parsing timeWindowCustomization: $e');
        }
      }
    }

    // Parse category preferences if available
    Map<NudgeCategory, int>? categoryPreferences;
    if (migratedData['cp'] != null) {
      try {
        categoryPreferences = {};
        final Map<String, dynamic> prefMap = migratedData['cp'] as Map<String, dynamic>;
        for (var entry in prefMap.entries) {
          // Try to parse as int first (compact format)
          NudgeCategory? category;
          try {
            final intKey = int.parse(entry.key);
            category = NudgeCategory.fromInt(intKey);
          } catch (e) {
            // Fall back to string parsing
            category = NudgeCategory.fromString(entry.key);
          }

          if (category != null) {
            categoryPreferences[category] = entry.value as int;
          }
        }
      } catch (e) {
        if (kDebugMode) {
          final logger = Logger('NudgeModel');
          logger.warning('Error parsing categoryPreferences: $e');
        }
      }