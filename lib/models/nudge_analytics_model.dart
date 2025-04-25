import 'dart:convert';

/// Models for the nudge analytics feature
///
/// This file contains models for tracking analytics events,
/// user interactions, and session data for the nudge feature.
///
/// @version 1.0.1

/// Event types for nudge analytics
enum NudgeAnalyticsEventType {
  /// Nudge was delivered to the user
  delivery,

  /// User viewed the nudge
  view,

  /// User interacted with the nudge
  interaction,

  /// User provided feedback on the nudge
  feedback,

  /// User dismissed the nudge
  dismissal,

  /// User completed an action prompted by the nudge
  completion,

  /// Error occurred related to nudges
  error,

  /// Settings changed by the user
  settingsChange,

  /// User session started
  sessionStart,

  /// User session ended
  sessionEnd,

  /// Custom event
  custom,
}

/// Interaction types for nudge analytics
enum NudgeInteractionType {
  /// User tapped on the nudge
  tap,

  /// User swiped the nudge
  swipe,

  /// User long-pressed the nudge
  longPress,

  /// User expanded the nudge
  expand,

  /// User collapsed the nudge
  collapse,

  /// User played audio from the nudge
  playAudio,

  /// User paused audio from the nudge
  pauseAudio,

  /// User stopped audio from the nudge
  stopAudio,

  /// User navigated to a screen from the nudge
  navigation,

  /// User shared the nudge
  share,

  /// User saved the nudge
  save,

  /// Custom interaction
  custom,
}

/// Base class for all analytics events
class NudgeAnalyticsEvent {
  /// Type of analytics event
  final NudgeAnalyticsEventType type;

  /// Unique identifier for the event
  final String id;

  /// Timestamp when the event occurred
  final DateTime timestamp;

  /// User ID associated with the event
  final String? userId;

  /// Nudge ID associated with the event (if applicable)
  final String? nudgeId;

  /// Session ID associated with the event
  final String? sessionId;

  /// Device information
  final Map<String, dynamic>? deviceInfo;

  /// Additional properties for the event
  final Map<String, dynamic> properties;

  /// Constructor
  NudgeAnalyticsEvent({
    required this.type,
    required this.id,
    DateTime? timestamp,
    this.userId,
    this.nudgeId,
    this.sessionId,
    this.deviceInfo,
    Map<String, dynamic>? properties,
  }) :
        this.timestamp = timestamp ?? DateTime.now(),
        this.properties = properties ?? {};

  /// Convert to a map for serialization
  Map<String, dynamic> toMap() {
    return {
      'type': type.toString().split('.').last,
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'userId': userId,
      'nudgeId': nudgeId,
      'sessionId': sessionId,
      'deviceInfo': deviceInfo,
      'properties': properties,
    };
  }

  /// Convert to JSON string
  String toJson() => jsonEncode(toMap());

  /// Create from a map
  factory NudgeAnalyticsEvent.fromMap(Map<String, dynamic> map) {
    return NudgeAnalyticsEvent(
      type: _parseEventType(map['type']),
      id: map['id'],
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : null,
      userId: map['userId'],
      nudgeId: map['nudgeId'],
      sessionId: map['sessionId'],
      deviceInfo: map['deviceInfo'] != null
          ? Map<String, dynamic>.from(map['deviceInfo'])
          : null,
      properties: map['properties'] != null
          ? Map<String, dynamic>.from(map['properties'])
          : null,
    );
  }

  /// Create from JSON string
  factory NudgeAnalyticsEvent.fromJson(String json) =>
      NudgeAnalyticsEvent.fromMap(jsonDecode(json));

  /// Helper to parse event type from string
  static NudgeAnalyticsEventType _parseEventType(String? typeStr) {
    if (typeStr == null) return NudgeAnalyticsEventType.custom;

    try {
      return NudgeAnalyticsEventType.values.firstWhere(
            (e) => e.toString().split('.').last == typeStr,
        orElse: () => NudgeAnalyticsEventType.custom,
      );
    } catch (_) {
      return NudgeAnalyticsEventType.custom;
    }
  }
}

/// Delivery event for when a nudge is delivered to the user
class NudgeDeliveryEvent extends NudgeAnalyticsEvent {
  /// Delivery channel (notification, in-app, etc.)
  final String deliveryChannel;

  /// Whether the delivery was scheduled
  final bool scheduled;

  /// Constructor
  NudgeDeliveryEvent({
    required String id,
    required String nudgeId,
    required this.deliveryChannel,
    this.scheduled = true,
    DateTime? timestamp,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) : super(
    type: NudgeAnalyticsEventType.delivery,
    id: id,
    timestamp: timestamp,
    userId: userId,
    nudgeId: nudgeId,
    sessionId: sessionId,
    deviceInfo: deviceInfo,
    properties: {
      'deliveryChannel': deliveryChannel,
      'scheduled': scheduled,
      ...?properties,
    },
  );

  /// Create from a map
  factory NudgeDeliveryEvent.fromMap(Map<String, dynamic> map) {
    return NudgeDeliveryEvent(
      id: map['id'],
      nudgeId: map['nudgeId'],
      deliveryChannel: map['properties']?['deliveryChannel'] ?? 'unknown',
      scheduled: map['properties']?['scheduled'] ?? true,
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : null,
      userId: map['userId'],
      sessionId: map['sessionId'],
      deviceInfo: map['deviceInfo'] != null
          ? Map<String, dynamic>.from(map['deviceInfo'])
          : null,
      properties: map['properties'] != null
          ? Map<String, dynamic>.from(map['properties'])
          : null,
    );
  }

  /// Create from JSON string
  factory NudgeDeliveryEvent.fromJson(String json) =>
      NudgeDeliveryEvent.fromMap(jsonDecode(json));
}

/// View event for when a user views a nudge
class NudgeViewEvent extends NudgeAnalyticsEvent {
  /// Duration the nudge was viewed (in milliseconds)
  final int? viewDurationMs;

  /// Whether the view was complete (full duration)
  final bool? viewComplete;

  /// Screen or context where the nudge was viewed
  final String? viewContext;

  /// Constructor
  NudgeViewEvent({
    required String id,
    required String nudgeId,
    this.viewDurationMs,
    this.viewComplete,
    this.viewContext,
    DateTime? timestamp,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) : super(
    type: NudgeAnalyticsEventType.view,
    id: id,
    timestamp: timestamp,
    userId: userId,
    nudgeId: nudgeId,
    sessionId: sessionId,
    deviceInfo: deviceInfo,
    properties: {
      if (viewDurationMs != null) 'viewDurationMs': viewDurationMs,
      if (viewComplete != null) 'viewComplete': viewComplete,
      if (viewContext != null) 'viewContext': viewContext,
      ...?properties,
    },
  );

  /// Create from a map
  factory NudgeViewEvent.fromMap(Map<String, dynamic> map) {
    return NudgeViewEvent(
      id: map['id'],
      nudgeId: map['nudgeId'],
      viewDurationMs: map['properties']?['viewDurationMs'],
      viewComplete: map['properties']?['viewComplete'],
      viewContext: map['properties']?['viewContext'],
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : null,
      userId: map['userId'],
      sessionId: map['sessionId'],
      deviceInfo: map['deviceInfo'] != null
          ? Map<String, dynamic>.from(map['deviceInfo'])
          : null,
      properties: map['properties'] != null
          ? Map<String, dynamic>.from(map['properties'])
          : null,
    );
  }

  /// Create from JSON string
  factory NudgeViewEvent.fromJson(String json) =>
      NudgeViewEvent.fromMap(jsonDecode(json));
}

/// Interaction event for when a user interacts with a nudge
class NudgeInteractionEvent extends NudgeAnalyticsEvent {
  /// Type of interaction
  final NudgeInteractionType interactionType;

  /// Target of the interaction (e.g., button ID, link, etc.)
  final String? interactionTarget;

  /// Screen or context where the interaction occurred
  final String? interactionContext;

  /// Constructor
  NudgeInteractionEvent({
    required String id,
    required String nudgeId,
    required this.interactionType,
    this.interactionTarget,
    this.interactionContext,
    DateTime? timestamp,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) : super(
    type: NudgeAnalyticsEventType.interaction,
    id: id,
    timestamp: timestamp,
    userId: userId,
    nudgeId: nudgeId,
    sessionId: sessionId,
    deviceInfo: deviceInfo,
    properties: {
      'interactionType': interactionType.toString().split('.').last,
      if (interactionTarget != null) 'interactionTarget': interactionTarget,
      if (interactionContext != null) 'interactionContext': interactionContext,
      ...?properties,
    },
  );

  /// Create from a map
  factory NudgeInteractionEvent.fromMap(Map<String, dynamic> map) {
    return NudgeInteractionEvent(
      id: map['id'],
      nudgeId: map['nudgeId'],
      interactionType: _parseInteractionType(map['properties']?['interactionType']),
      interactionTarget: map['properties']?['interactionTarget'],
      interactionContext: map['properties']?['interactionContext'],
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : null,
      userId: map['userId'],
      sessionId: map['sessionId'],
      deviceInfo: map['deviceInfo'] != null
          ? Map<String, dynamic>.from(map['deviceInfo'])
          : null,
      properties: map['properties'] != null
          ? Map<String, dynamic>.from(map['properties'])
          : null,
    );
  }

  /// Create from JSON string
  factory NudgeInteractionEvent.fromJson(String json) =>
      NudgeInteractionEvent.fromMap(jsonDecode(json));

  /// Helper to parse interaction type from string
  static NudgeInteractionType _parseInteractionType(String? typeStr) {
    if (typeStr == null) return NudgeInteractionType.custom;

    try {
      return NudgeInteractionType.values.firstWhere(
            (e) => e.toString().split('.').last == typeStr,
        orElse: () => NudgeInteractionType.custom,
      );
    } catch (_) {
      return NudgeInteractionType.custom;
    }
  }
}

/// Feedback event for when a user provides feedback on a nudge
class NudgeFeedbackEvent extends NudgeAnalyticsEvent {
  /// Rating provided by the user (typically 1-5)
  final int rating;

  /// Comment provided by the user
  final String? comment;

  /// Tags or categories selected by the user
  final List<String>? tags;

  /// Constructor
  NudgeFeedbackEvent({
    required String id,
    required String nudgeId,
    required this.rating,
    this.comment,
    this.tags,
    DateTime? timestamp,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) : super(
    type: NudgeAnalyticsEventType.feedback,
    id: id,
    timestamp: timestamp,
    userId: userId,
    nudgeId: nudgeId,
    sessionId: sessionId,
    deviceInfo: deviceInfo,
    properties: {
      'rating': rating,
      if (comment != null) 'comment': comment,
      if (tags != null) 'tags': tags,
      ...?properties,
    },
  );

  /// Create from a map
  factory NudgeFeedbackEvent.fromMap(Map<String, dynamic> map) {
    return NudgeFeedbackEvent(
      id: map['id'],
      nudgeId: map['nudgeId'],
      rating: map['properties']?['rating'] ?? 0,
      comment: map['properties']?['comment'],
      tags: map['properties']?['tags'] != null
          ? List<String>.from(map['properties']['tags'])
          : null,
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : null,
      userId: map['userId'],
      sessionId: map['sessionId'],
      deviceInfo: map['deviceInfo'] != null
          ? Map<String, dynamic>.from(map['deviceInfo'])
          : null,
      properties: map['properties'] != null
          ? Map<String, dynamic>.from(map['properties'])
          : null,
    );
  }

  /// Create from JSON string
  factory NudgeFeedbackEvent.fromJson(String json) =>
      NudgeFeedbackEvent.fromMap(jsonDecode(json));
}

/// Dismissal event for when a user dismisses a nudge
class NudgeDismissalEvent extends NudgeAnalyticsEvent {
  /// Reason for dismissal if provided
  final String? dismissalReason;

  /// Whether the dismissal was explicit (user action) or implicit (timeout)
  final bool isExplicit;

  /// Screen or context where the dismissal occurred
  final String? dismissalContext;

  /// Constructor
  NudgeDismissalEvent({
    required String id,
    required String nudgeId,
    this.dismissalReason,
    this.isExplicit = true,
    this.dismissalContext,
    DateTime? timestamp,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) : super(
    type: NudgeAnalyticsEventType.dismissal,
    id: id,
    timestamp: timestamp,
    userId: userId,
    nudgeId: nudgeId,
    sessionId: sessionId,
    deviceInfo: deviceInfo,
    properties: {
      'isExplicit': isExplicit,
      if (dismissalReason != null) 'dismissalReason': dismissalReason,
      if (dismissalContext != null) 'dismissalContext': dismissalContext,
      ...?properties,
    },
  );

  /// Create from a map
  factory NudgeDismissalEvent.fromMap(Map<String, dynamic> map) {
    return NudgeDismissalEvent(
      id: map['id'],
      nudgeId: map['nudgeId'],
      dismissalReason: map['properties']?['dismissalReason'],
      isExplicit: map['properties']?['isExplicit'] ?? true,
      dismissalContext: map['properties']?['dismissalContext'],
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : null,
      userId: map['userId'],
      sessionId: map['sessionId'],
      deviceInfo: map['deviceInfo'] != null
          ? Map<String, dynamic>.from(map['deviceInfo'])
          : null,
      properties: map['properties'] != null
          ? Map<String, dynamic>.from(map['properties'])
          : null,
    );
  }

  /// Create from JSON string
  factory NudgeDismissalEvent.fromJson(String json) =>
      NudgeDismissalEvent.fromMap(jsonDecode(json));
}

/// Completion event for when a user completes an action prompted by a nudge
class NudgeCompletionEvent extends NudgeAnalyticsEvent {
  /// Type of action that was completed
  final String actionType;

  /// Time taken to complete the action in milliseconds
  final int? completionTimeMs;

  /// Whether the action was completed successfully
  final bool isSuccessful;

  /// Constructor
  NudgeCompletionEvent({
    required String id,
    required String nudgeId,
    required this.actionType,
    this.completionTimeMs,
    this.isSuccessful = true,
    DateTime? timestamp,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) : super(
    type: NudgeAnalyticsEventType.completion,
    id: id,
    timestamp: timestamp,
    userId: userId,
    nudgeId: nudgeId,
    sessionId: sessionId,
    deviceInfo: deviceInfo,
    properties: {
      'actionType': actionType,
      'isSuccessful': isSuccessful,
      if (completionTimeMs != null) 'completionTimeMs': completionTimeMs,
      ...?properties,
    },
  );

  /// Create from a map
  factory NudgeCompletionEvent.fromMap(Map<String, dynamic> map) {
    return NudgeCompletionEvent(
      id: map['id'],
      nudgeId: map['nudgeId'],
      actionType: map['properties']?['actionType'] ?? 'unknown',
      completionTimeMs: map['properties']?['completionTimeMs'],
      isSuccessful: map['properties']?['isSuccessful'] ?? true,
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : null,
      userId: map['userId'],
      sessionId: map['sessionId'],
      deviceInfo: map['deviceInfo'] != null
          ? Map<String, dynamic>.from(map['deviceInfo'])
          : null,
      properties: map['properties'] != null
          ? Map<String, dynamic>.from(map['properties'])
          : null,
    );
  }

  /// Create from JSON string
  factory NudgeCompletionEvent.fromJson(String json) =>
      NudgeCompletionEvent.fromMap(jsonDecode(json));
}

/// Error event for when an error occurs related to nudges
class NudgeErrorEvent extends NudgeAnalyticsEvent {
  /// Error code
  final String errorCode;

  /// Error message
  final String errorMessage;

  /// Error severity (e.g., 'critical', 'warning', 'info')
  final String severity;

  /// Stack trace if available
  final String? stackTrace;

  /// Constructor
  NudgeErrorEvent({
    required String id,
    required this.errorCode,
    required this.errorMessage,
    this.severity = 'error',
    this.stackTrace,
    String? nudgeId,
    DateTime? timestamp,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) : super(
    type: NudgeAnalyticsEventType.error,
    id: id,
    timestamp: timestamp,
    userId: userId,
    nudgeId: nudgeId,
    sessionId: sessionId,
    deviceInfo: deviceInfo,
    properties: {
      'errorCode': errorCode,
      'errorMessage': errorMessage,
      'severity': severity,
      if (stackTrace != null) 'stackTrace': stackTrace,
      ...?properties,
    },
  );

  /// Create from a map
  factory NudgeErrorEvent.fromMap(Map<String, dynamic> map) {
    return NudgeErrorEvent(
      id: map['id'],
      errorCode: map['properties']?['errorCode'] ?? 'unknown',
      errorMessage: map['properties']?['errorMessage'] ?? 'Unknown error',
      severity: map['properties']?['severity'] ?? 'error',
      stackTrace: map['properties']?['stackTrace'],
      nudgeId: map['nudgeId'],
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : null,
      userId: map['userId'],
      sessionId: map['sessionId'],
      deviceInfo: map['deviceInfo'] != null
          ? Map<String, dynamic>.from(map['deviceInfo'])
          : null,
      properties: map['properties'] != null
          ? Map<String, dynamic>.from(map['properties'])
          : null,
    );
  }

  /// Create from JSON string
  factory NudgeErrorEvent.fromJson(String json) =>
      NudgeErrorEvent.fromMap(jsonDecode(json));
}

/// Settings change event for when user changes nudge settings
class NudgeSettingsChangeEvent extends NudgeAnalyticsEvent {
  /// Setting that was changed
  final String settingName;

  /// Previous value of the setting
  final dynamic previousValue;

  /// New value of the setting
  final dynamic newValue;

  /// Constructor
  NudgeSettingsChangeEvent({
    required String id,
    required this.settingName,
    this.previousValue,
    this.newValue,
    DateTime? timestamp,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) : super(
    type: NudgeAnalyticsEventType.settingsChange,
    id: id,
    timestamp: timestamp,
    userId: userId,
    nudgeId: null,
    sessionId: sessionId,
    deviceInfo: deviceInfo,
    properties: {
      'settingName': settingName,
      if (previousValue != null) 'previousValue': previousValue.toString(),
      if (newValue != null) 'newValue': newValue.toString(),
      ...?properties,
    },
  );

  /// Create from a map
  factory NudgeSettingsChangeEvent.fromMap(Map<String, dynamic> map) {
    return NudgeSettingsChangeEvent(
      id: map['id'],
      settingName: map['properties']?['settingName'] ?? 'unknown',
      previousValue: map['properties']?['previousValue'],
      newValue: map['properties']?['newValue'],
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : null,
      userId: map['userId'],
      sessionId: map['sessionId'],
      deviceInfo: map['deviceInfo'] != null
          ? Map<String, dynamic>.from(map['deviceInfo'])
          : null,
      properties: map['properties'] != null
          ? Map<String, dynamic>.from(map['properties'])
          : null,
    );
  }

  /// Create from JSON string
  factory NudgeSettingsChangeEvent.fromJson(String json) =>
      NudgeSettingsChangeEvent.fromMap(jsonDecode(json));
}

/// Session start event for when a user session begins
class NudgeSessionStartEvent extends NudgeAnalyticsEvent {
  /// Platform or device OS
  final String? platform;

  /// App version
  final String? appVersion;

  /// Entry point to the app (e.g., notification, direct launch)
  final String? entryPoint;

  /// Constructor
  NudgeSessionStartEvent({
    required String id,
    required String sessionId,
    this.platform,
    this.appVersion,
    this.entryPoint,
    DateTime? timestamp,
    String? userId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) : super(
    type: NudgeAnalyticsEventType.sessionStart,
    id: id,
    timestamp: timestamp,
    userId: userId,
    nudgeId: null,
    sessionId: sessionId,
    deviceInfo: deviceInfo,
    properties: {
      if (platform != null) 'platform': platform,
      if (appVersion != null) 'appVersion': appVersion,
      if (entryPoint != null) 'entryPoint': entryPoint,
      ...?properties,
    },
  );

  /// Create from a map
  factory NudgeSessionStartEvent.fromMap(Map<String, dynamic> map) {
    return NudgeSessionStartEvent(
      id: map['id'],
      sessionId: map['sessionId'] ?? '',
      platform: map['properties']?['platform'],
      appVersion: map['properties']?['appVersion'],
      entryPoint: map['properties']?['entryPoint'],
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : null,
      userId: map['userId'],
      deviceInfo: map['deviceInfo'] != null
          ? Map<String, dynamic>.from(map['deviceInfo'])
          : null,
      properties: map['properties'] != null
          ? Map<String, dynamic>.from(map['properties'])
          : null,
    );
  }

  /// Create from JSON string
  factory NudgeSessionStartEvent.fromJson(String json) =>
      NudgeSessionStartEvent.fromMap(jsonDecode(json));
}

/// Session end event for when a user session ends
class NudgeSessionEndEvent extends NudgeAnalyticsEvent {
  /// Duration of the session in milliseconds
  final int? durationMs;

  /// Exit point from the app (e.g., home button, back button)
  final String? exitPoint;

  /// Reason for session end (e.g., crash, user action, timeout)
  final String? endReason;

  /// Constructor
  NudgeSessionEndEvent({
    required String id,
    required String sessionId,
    this.durationMs,
    this.exitPoint,
    this.endReason,
    DateTime? timestamp,
    String? userId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) : super(
    type: NudgeAnalyticsEventType.sessionEnd,
    id: id,
    timestamp: timestamp,
    userId: userId,
    nudgeId: null,
    sessionId: sessionId,
    deviceInfo: deviceInfo,
    properties: {
      if (durationMs != null) 'durationMs': durationMs,
      if (exitPoint != null) 'exitPoint': exitPoint,
      if (endReason != null) 'endReason': endReason,
      ...?properties,
    },
  );

  /// Create from a map
  factory NudgeSessionEndEvent.fromMap(Map<String, dynamic> map) {
    return NudgeSessionEndEvent(
      id: map['id'],
      sessionId: map['sessionId'] ?? '',
      durationMs: map['properties']?['durationMs'],
      exitPoint: map['properties']?['exitPoint'],
      endReason: map['properties']?['endReason'],
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : null,
      userId: map['userId'],
      deviceInfo: map['deviceInfo'] != null
          ? Map<String, dynamic>.from(map['deviceInfo'])
          : null,
      properties: map['properties'] != null
          ? Map<String, dynamic>.from(map['properties'])
          : null,
    );
  }

  /// Create from JSON string
  factory NudgeSessionEndEvent.fromJson(String json) =>
      NudgeSessionEndEvent.fromMap(jsonDecode(json));
}

/// Custom event for any other analytics events
class NudgeCustomEvent extends NudgeAnalyticsEvent {
  /// Custom event name
  final String customEventName;

  /// Constructor
  NudgeCustomEvent({
    required String id,
    required this.customEventName,
    String? nudgeId,
    DateTime? timestamp,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) : super(
    type: NudgeAnalyticsEventType.custom,
    id: id,
    timestamp: timestamp,
    userId: userId,
    nudgeId: nudgeId,
    sessionId: sessionId,
    deviceInfo: deviceInfo,
    properties: {
      'customEventName': customEventName,
      ...?properties,
    },
  );

  /// Create from a map
  factory NudgeCustomEvent.fromMap(Map<String, dynamic> map) {
    return NudgeCustomEvent(
      id: map['id'],
      customEventName: map['properties']?['customEventName'] ?? 'unknown',
      nudgeId: map['nudgeId'],
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : null,
      userId: map['userId'],
      sessionId: map['sessionId'],
      deviceInfo: map['deviceInfo'] != null
          ? Map<String, dynamic>.from(map['deviceInfo'])
          : null,
      properties: map['properties'] != null
          ? Map<String, dynamic>.from(map['properties'])
          : null,
    );
  }

  /// Create from JSON string
  factory NudgeCustomEvent.fromJson(String json) =>
      NudgeCustomEvent.fromMap(jsonDecode(json));
}

/// Session data for analytics
class NudgeAnalyticsSession {
  /// Unique identifier for the session
  final String id;

  /// User ID associated with the session
  final String? userId;

  /// Timestamp when the session started
  final DateTime startTime;

  /// Timestamp when the session ended
  final DateTime? endTime;

  /// Duration of the session in milliseconds
  final int? durationMs;

  /// Number of nudges delivered during the session
  final int nudgesDelivered;

  /// Number of nudges viewed during the session
  final int nudgesViewed;

  /// Number of nudge interactions during the session
  final int nudgeInteractions;

  /// Device information
  final Map<String, dynamic>? deviceInfo;

  /// Additional properties for the session
  final Map<String, dynamic> properties;

  /// Constructor
  NudgeAnalyticsSession({
    required this.id,
    required this.startTime,
    this.userId,
    this.endTime,
    this.durationMs,
    this.nudgesDelivered = 0,
    this.nudgesViewed = 0,
    this.nudgeInteractions = 0,
    this.deviceInfo,
    Map<String, dynamic>? properties,
  }) : this.properties = properties ?? {};

  /// Convert to a map for serialization
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'durationMs': durationMs ?? (endTime != null
          ? endTime!.difference(startTime).inMilliseconds
          : null),
      'nudgesDelivered': nudgesDelivered,
      'nudgesViewed': nudgesViewed,
      'nudgeInteractions': nudgeInteractions,
      'deviceInfo': deviceInfo,
      'properties': properties,
    };
  }

  /// Convert to JSON string
  String toJson() => jsonEncode(toMap());

  /// Create from a map
  factory NudgeAnalyticsSession.fromMap(Map<String, dynamic> map) {
    return NudgeAnalyticsSession(
      id: map['id'],
      userId: map['userId'],
      startTime: DateTime.parse(map['startTime']),
      endTime: map['endTime'] != null
          ? DateTime.parse(map['endTime'])
          : null,
      durationMs: map['durationMs'],
      nudgesDelivered: map['nudgesDelivered'] ?? 0,
      nudgesViewed: map['nudgesViewed'] ?? 0,
      nudgeInteractions: map['nudgeInteractions'] ?? 0,
      deviceInfo: map['deviceInfo'] != null
          ? Map<String, dynamic>.from(map['deviceInfo'])
          : null,
      properties: map['properties'] != null
          ? Map<String, dynamic>.from(map['properties'])
          : null,
    );
  }

  /// Create from JSON string
  factory NudgeAnalyticsSession.fromJson(String json) =>
      NudgeAnalyticsSession.fromMap(jsonDecode(json));

  /// Create a copy of this session with updated values
  NudgeAnalyticsSession copyWith({
    String? id,
    String? userId,
    DateTime? startTime,
    DateTime? endTime,
    int? durationMs,
    int? nudgesDelivered,
    int? nudgesViewed,
    int? nudgeInteractions,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) {
    return NudgeAnalyticsSession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationMs: durationMs ?? this.durationMs,
      nudgesDelivered: nudgesDelivered ?? this.nudgesDelivered,
      nudgesViewed: nudgesViewed ?? this.nudgesViewed,
      nudgeInteractions: nudgeInteractions ?? this.nudgeInteractions,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      properties: properties != null
          ? {...this.properties, ...properties}
          : this.properties,
    );
  }
}

/// User analytics data
class NudgeUserAnalytics {
  /// User ID
  final String userId;

  /// Total number of nudges delivered to this user
  final int totalNudgesDelivered;

  /// Total number of nudges viewed by this user
  final int totalNudgesViewed;

  /// Total number of nudge interactions by this user
  final int totalInteractions;

  /// Average rating given by this user
  final double? averageRating;

  /// Total number of ratings given by this user
  final int totalRatings;

  /// Total number of sessions by this user
  final int totalSessions;

  /// Average session duration in milliseconds
  final int? averageSessionDurationMs;

  /// Date of first activity
  final DateTime? firstActivityDate;

  /// Date of most recent activity
  final DateTime? lastActivityDate;

  /// Total time spent engaged with nudges in milliseconds
  final int totalEngagementTimeMs;

  /// User preferences and settings
  final Map<String, dynamic>? preferences;

  /// Additional properties for this user
  final Map<String, dynamic> properties;

  /// Constructor
  NudgeUserAnalytics({
    required this.userId,
    this.totalNudgesDelivered = 0,
    this.totalNudgesViewed = 0,
    this.totalInteractions = 0,
    this.averageRating,
    this.totalRatings = 0,
    this.totalSessions = 0,
    this.averageSessionDurationMs,
    this.firstActivityDate,
    this.lastActivityDate,
    this.totalEngagementTimeMs = 0,
    this.preferences,
    Map<String, dynamic>? properties,
  }) : this.properties = properties ?? {};

  /// Convert to a map for serialization
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'totalNudgesDelivered': totalNudgesDelivered,
      'totalNudgesViewed': totalNudgesViewed,
      'totalInteractions': totalInteractions,
      'averageRating': averageRating,
      'totalRatings': totalRatings,
      'totalSessions': totalSessions,
      'averageSessionDurationMs': averageSessionDurationMs,
      'firstActivityDate': firstActivityDate?.toIso8601String(),
      'lastActivityDate': lastActivityDate?.toIso8601String(),
      'totalEngagementTimeMs': totalEngagementTimeMs,
      'preferences': preferences,
      'properties': properties,
    };
  }

  /// Convert to JSON string
  String toJson() => jsonEncode(toMap());

  /// Create from a map
  factory NudgeUserAnalytics.fromMap(Map<String, dynamic> map) {
    return NudgeUserAnalytics(
      userId: map['userId'],
      totalNudgesDelivered: map['totalNudgesDelivered'] ?? 0,
      totalNudgesViewed: map['totalNudgesViewed'] ?? 0,
      totalInteractions: map['totalInteractions'] ?? 0,
      averageRating: map['averageRating'],
      totalRatings: map['totalRatings'] ?? 0,
      totalSessions: map['totalSessions'] ?? 0,
      averageSessionDurationMs: map['averageSessionDurationMs'],
      firstActivityDate: map['firstActivityDate'] != null
          ? DateTime.parse(map['firstActivityDate'])
          : null,
      lastActivityDate: map['lastActivityDate'] != null
          ? DateTime.parse(map['lastActivityDate'])
          : null,
      totalEngagementTimeMs: map['totalEngagementTimeMs'] ?? 0,
      preferences: map['preferences'] != null
          ? Map<String, dynamic>.from(map['preferences'])
          : null,
      properties: map['properties'] != null
          ? Map<String, dynamic>.from(map['properties'])
          : null,
    );
  }

  /// Create from JSON string
  factory NudgeUserAnalytics.fromJson(String json) =>
      NudgeUserAnalytics.fromMap(jsonDecode(json));

  /// Create a copy of this user analytics with updated values
  NudgeUserAnalytics copyWith({
    String? userId,
    int? totalNudgesDelivered,
    int? totalNudgesViewed,
    int? totalInteractions,
    double? averageRating,
    int? totalRatings,
    int? totalSessions,
    int? averageSessionDurationMs,
    DateTime? firstActivityDate,
    DateTime? lastActivityDate,
    int? totalEngagementTimeMs,
    Map<String, dynamic>? preferences,
    Map<String, dynamic>? properties,
  }) {
    return NudgeUserAnalytics(
      userId: userId ?? this.userId,
      totalNudgesDelivered: totalNudgesDelivered ?? this.totalNudgesDelivered,
      totalNudgesViewed: totalNudgesViewed ?? this.totalNudgesViewed,
      totalInteractions: totalInteractions ?? this.totalInteractions,
      averageRating: averageRating ?? this.averageRating,
      totalRatings: totalRatings ?? this.totalRatings,
      totalSessions: totalSessions ?? this.totalSessions,
      averageSessionDurationMs: averageSessionDurationMs ?? this.averageSessionDurationMs,
      firstActivityDate: firstActivityDate ?? this.firstActivityDate,
      lastActivityDate: lastActivityDate ?? this.lastActivityDate,
      totalEngagementTimeMs: totalEngagementTimeMs ?? this.totalEngagementTimeMs,
      preferences: preferences ?? this.preferences,
      properties: properties != null
          ? {...this.properties, ...properties}
          : this.properties,
    );
  }

  /// Update rating statistics
  NudgeUserAnalytics addRating(int rating) {
    final newTotalRatings = totalRatings + 1;
    final currentTotalRating = (averageRating ?? 0) * totalRatings;
    final newAverageRating = (currentTotalRating + rating) / newTotalRatings;

    return copyWith(
      totalRatings: newTotalRatings,
      averageRating: newAverageRating,
    );
  }

  /// Update activity timestamps
  NudgeUserAnalytics updateActivity(DateTime activityTime) {
    DateTime? newFirstActivityDate = firstActivityDate;
    DateTime newLastActivityDate = activityTime;

    if (firstActivityDate == null || activityTime.isBefore(firstActivityDate!)) {
      newFirstActivityDate = activityTime;
    }

    return copyWith(
      firstActivityDate: newFirstActivityDate,
      lastActivityDate: newLastActivityDate,
    );
  }
}

/// Nudge effectiveness analytics
class NudgeEffectivenessAnalytics {
  /// Nudge ID
  final String nudgeId;

  /// Total number of times this nudge was delivered
  final int totalDeliveries;

  /// Total number of times this nudge was viewed
  final int totalViews;

  /// Total number of interactions with this nudge
  final int totalInteractions;

  /// Average rating for this nudge
  final double? averageRating;

  /// Total number of ratings for this nudge
  final int totalRatings;

  /// Completion rate (percentage of nudges that led to completed actions)
  final double? completionRate;

  /// View rate (percentage of deliveries that were viewed)
  final double? viewRate;

  /// Interaction rate (percentage of views that led to interactions)
  final double? interactionRate;

  /// Average time spent viewing this nudge in milliseconds
  final int? averageViewTimeMs;

  /// Most common interaction type
  final String? mostCommonInteraction;

  /// Additional properties for this nudge
  final Map<String, dynamic> properties;

  /// Constructor
  NudgeEffectivenessAnalytics({
    required this.nudgeId,
    this.totalDeliveries = 0,
    this.totalViews = 0,
    this.totalInteractions = 0,
    this.averageRating,
    this.totalRatings = 0,
    this.completionRate,
    this.viewRate,
    this.interactionRate,
    this.averageViewTimeMs,
    this.mostCommonInteraction,
    Map<String, dynamic>? properties,
  }) : this.properties = properties ?? {};

  /// Convert to a map for serialization
  Map<String, dynamic> toMap() {
    return {
      'nudgeId': nudgeId,
      'totalDeliveries': totalDeliveries,
      'totalViews': totalViews,
      'totalInteractions': totalInteractions,
      'averageRating': averageRating,
      'totalRatings': totalRatings,
      'completionRate': completionRate,
      'viewRate': viewRate,
      'interactionRate': interactionRate,
      'averageViewTimeMs': averageViewTimeMs,
      'mostCommonInteraction': mostCommonInteraction,
      'properties': properties,
    };
  }

  /// Convert to JSON string
  String toJson() => jsonEncode(toMap());

  /// Create from a map
  factory NudgeEffectivenessAnalytics.fromMap(Map<String, dynamic> map) {
    return NudgeEffectivenessAnalytics(
      nudgeId: map['nudgeId'],
      totalDeliveries: map['totalDeliveries'] ?? 0,
      totalViews: map['totalViews'] ?? 0,
      totalInteractions: map['totalInteractions'] ?? 0,
      averageRating: map['averageRating'],
      totalRatings: map['totalRatings'] ?? 0,
      completionRate: map['completionRate'],
      viewRate: map['viewRate'],
      interactionRate: map['interactionRate'],
      averageViewTimeMs: map['averageViewTimeMs'],
      mostCommonInteraction: map['mostCommonInteraction'],
      properties: map['properties'] != null
          ? Map<String, dynamic>.from(map['properties'])
          : null,
    );
  }

  /// Create from JSON string
  factory NudgeEffectivenessAnalytics.fromJson(String json) =>
      NudgeEffectivenessAnalytics.fromMap(jsonDecode(json));

  /// Create a copy of this effectiveness analytics with updated values
  NudgeEffectivenessAnalytics copyWith({
    String? nudgeId,
    int? totalDeliveries,
    int? totalViews,
    int? totalInteractions,
    double? averageRating,
    int? totalRatings,
    double? completionRate,
    double? viewRate,
    double? interactionRate,
    int? averageViewTimeMs,
    String? mostCommonInteraction,
    Map<String, dynamic>? properties,
  }) {
    return NudgeEffectivenessAnalytics(
      nudgeId: nudgeId ?? this.nudgeId,
      totalDeliveries: totalDeliveries ?? this.totalDeliveries,
      totalViews: totalViews ?? this.totalViews,
      totalInteractions: totalInteractions ?? this.totalInteractions,
      averageRating: averageRating ?? this.averageRating,
      totalRatings: totalRatings ?? this.totalRatings,
      completionRate: completionRate ?? this.completionRate,
      viewRate: viewRate ?? this.viewRate,
      interactionRate: interactionRate ?? this.interactionRate,
      averageViewTimeMs: averageViewTimeMs ?? this.averageViewTimeMs,
      mostCommonInteraction: mostCommonInteraction ?? this.mostCommonInteraction,
      properties: properties != null
          ? {...this.properties, ...properties}
          : this.properties,
    );
  }

  /// Update delivery statistics
  NudgeEffectivenessAnalytics incrementDeliveries() {
    final newTotalDeliveries = totalDeliveries + 1;
    final newViewRate = totalViews / newTotalDeliveries;

    return copyWith(
      totalDeliveries: newTotalDeliveries,
      viewRate: newViewRate,
    );
  }

  /// Update view statistics
  NudgeEffectivenessAnalytics incrementViews({int? viewDurationMs}) {
    final newTotalViews = totalViews + 1;
    final newViewRate = newTotalViews / totalDeliveries;
    final newInteractionRate = totalInteractions / newTotalViews;

    // Calculate new average view time
    int? newAverageViewTimeMs;
    if (viewDurationMs != null) {
      final totalPreviousViewTime = (averageViewTimeMs ?? 0) * (totalViews == 0 ? 0 : totalViews);
      newAverageViewTimeMs = (totalPreviousViewTime + viewDurationMs) ~/ newTotalViews;
    }

    return copyWith(
      totalViews: newTotalViews,
      viewRate: newViewRate,
      interactionRate: newInteractionRate,
      averageViewTimeMs: newAverageViewTimeMs ?? averageViewTimeMs,
    );
  }

  /// Update interaction statistics
  NudgeEffectivenessAnalytics incrementInteractions(String interactionType) {
    final newTotalInteractions = totalInteractions + 1;
    final newInteractionRate = totalViews > 0 ? newTotalInteractions / totalViews : 0;

    // Update most common interaction if needed
    String? newMostCommonInteraction = mostCommonInteraction;
    // This is simplified; in a real implementation you'd need to track counts for each type
    if (mostCommonInteraction == null) {
      newMostCommonInteraction = interactionType;
    }

    return copyWith(
      totalInteractions: newTotalInteractions,
      interactionRate: newInteractionRate,
      mostCommonInteraction: newMostCommonInteraction,
    );
  }

  /// Update rating statistics
  NudgeEffectivenessAnalytics addRating(int rating) {
    final newTotalRatings = totalRatings + 1;
    final currentTotalRating = (averageRating ?? 0) * totalRatings;
    final newAverageRating = (currentTotalRating + rating) / newTotalRatings;

    return copyWith(
      totalRatings: newTotalRatings,
      averageRating: newAverageRating,
    );
  }

  /// Update completion rate
  NudgeEffectivenessAnalytics updateCompletionRate(double newCompletionRate) {
    return copyWith(
      completionRate: newCompletionRate,
    );
  }
}

/// Analytics time period
enum NudgeAnalyticsTimePeriod {
  /// Today
  today,

  /// Yesterday
  yesterday,

  /// Last 7 days
  lastWeek,

  /// Last 30 days
  lastMonth,

  /// Last 90 days
  lastQuarter,

  /// Last 365 days
  lastYear,

  /// All time
  allTime,

  /// Custom date range
  custom,
}

/// Analytics summary metrics for a specific time period
class NudgeAnalyticsSummary {
  /// Time period for this summary
  final NudgeAnalyticsTimePeriod timePeriod;

  /// Start date for the time period
  final DateTime startDate;

  /// End date for the time period
  final DateTime endDate;

  /// Total number of nudges delivered during this period
  final int totalDeliveries;

  /// Total number of nudges viewed during this period
  final int totalViews;

  /// Total number of nudge interactions during this period
  final int totalInteractions;

  /// Average rating for nudges during this period
  final double? averageRating;

  /// Total number of sessions during this period
  final int totalSessions;

  /// Average session duration in milliseconds
  final int? averageSessionDurationMs;

  /// Total number of unique users during this period
  final int uniqueUsers;

  /// Total engagement time in milliseconds
  final int totalEngagementTimeMs;

  /// Average engagement time per user in milliseconds
  final int? averageEngagementTimePerUserMs;

  /// Most active user ID
  final String? mostActiveUserId;

  /// Most effective nudge ID
  final String? mostEffectiveNudgeId;

  /// Most common error code (if any)
  final String? mostCommonErrorCode;

  /// Additional metrics for this summary
  final Map<String, dynamic> additionalMetrics;

  /// Constructor
  NudgeAnalyticsSummary({
    required this.timePeriod,
    required this.startDate,
    required this.endDate,
    this.totalDeliveries = 0,
    this.totalViews = 0,
    this.totalInteractions = 0,
    this.averageRating,
    this.totalSessions = 0,
    this.averageSessionDurationMs,
    this.uniqueUsers = 0,
    this.totalEngagementTimeMs = 0,
    this.averageEngagementTimePerUserMs,
    this.mostActiveUserId,
    this.mostEffectiveNudgeId,
    this.mostCommonErrorCode,
    Map<String, dynamic>? additionalMetrics,
  }) : this.additionalMetrics = additionalMetrics ?? {};

  /// Convert to a map for serialization
  Map<String, dynamic> toMap() {
    return {
      'timePeriod': timePeriod.toString().split('.').last,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'totalDeliveries': totalDeliveries,
      'totalViews': totalViews,
      'totalInteractions': totalInteractions,
      'averageRating': averageRating,
      'totalSessions': totalSessions,
      'averageSessionDurationMs': averageSessionDurationMs,
      'uniqueUsers': uniqueUsers,
      'totalEngagementTimeMs': totalEngagementTimeMs,
      'averageEngagementTimePerUserMs': averageEngagementTimePerUserMs,
      'mostActiveUserId': mostActiveUserId,
      'mostEffectiveNudgeId': mostEffectiveNudgeId,
      'mostCommonErrorCode': mostCommonErrorCode,
      'additionalMetrics': additionalMetrics,
    };
  }

  /// Convert to JSON string
  String toJson() => jsonEncode(toMap());

  /// Create from a map
  factory NudgeAnalyticsSummary.fromMap(Map<String, dynamic> map) {
    return NudgeAnalyticsSummary(
      timePeriod: _parseTimePeriod(map['timePeriod']),
      startDate: DateTime.parse(map['startDate']),
      endDate: DateTime.parse(map['endDate']),
      totalDeliveries: map['totalDeliveries'] ?? 0,
      totalViews: map['totalViews'] ?? 0,
      totalInteractions: map['totalInteractions'] ?? 0,
      averageRating: map['averageRating'],
      totalSessions: map['totalSessions'] ?? 0,
      averageSessionDurationMs: map['averageSessionDurationMs'],
      uniqueUsers: map['uniqueUsers'] ?? 0,
      totalEngagementTimeMs: map['totalEngagementTimeMs'] ?? 0,
      averageEngagementTimePerUserMs: map['averageEngagementTimePerUserMs'],
      mostActiveUserId: map['mostActiveUserId'],
      mostEffectiveNudgeId: map['mostEffectiveNudgeId'],
      mostCommonErrorCode: map['mostCommonErrorCode'],
      additionalMetrics: map['additionalMetrics'] != null
          ? Map<String, dynamic>.from(map['additionalMetrics'])
          : null,
    );
  }

  /// Create from JSON string
  factory NudgeAnalyticsSummary.fromJson(String json) =>
      NudgeAnalyticsSummary.fromMap(jsonDecode(json));

  /// Helper to parse time period from string
  static NudgeAnalyticsTimePeriod _parseTimePeriod(String? periodStr) {
    if (periodStr == null) return NudgeAnalyticsTimePeriod.allTime;

    try {
      return NudgeAnalyticsTimePeriod.values.firstWhere(
            (e) => e.toString().split('.').last == periodStr,
        orElse: () => NudgeAnalyticsTimePeriod.allTime,
      );
    } catch (_) {
      return NudgeAnalyticsTimePeriod.allTime;
    }
  }

  /// Calculate view rate
  double get viewRate =>
      totalDeliveries > 0 ? totalViews / totalDeliveries : 0;

  /// Calculate interaction rate
  double get interactionRate =>
      totalViews > 0 ? totalInteractions / totalViews : 0;

  /// Calculate average interactions per user
  double get averageInteractionsPerUser =>
      uniqueUsers > 0 ? totalInteractions / uniqueUsers : 0;
}

/// Factory for creating analytics events
class NudgeAnalyticsEventFactory {
  /// Create a delivery event
  static NudgeDeliveryEvent createDeliveryEvent({
    required String nudgeId,
    required String deliveryChannel,
    bool scheduled = true,
    String? id,
    DateTime? timestamp,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) {
    return NudgeDeliveryEvent(
      id: id ?? _generateId(),
      nudgeId: nudgeId,
      deliveryChannel: deliveryChannel,
      scheduled: scheduled,
      timestamp: timestamp,
      userId: userId,
      sessionId: sessionId,
      deviceInfo: deviceInfo,
      properties: properties,
    );
  }

  /// Create a view event
  static NudgeViewEvent createViewEvent({
    required String nudgeId,
    int? viewDurationMs,
    bool? viewComplete,
    String? viewContext,
    String? id,
    DateTime? timestamp,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) {
    return NudgeViewEvent(
      id: id ?? _generateId(),
      nudgeId: nudgeId,
      viewDurationMs: viewDurationMs,
      viewComplete: viewComplete,
      viewContext: viewContext,
      timestamp: timestamp,
      userId: userId,
      sessionId: sessionId,
      deviceInfo: deviceInfo,
      properties: properties,
    );
  }

  /// Create an interaction event
  static NudgeInteractionEvent createInteractionEvent({
    required String nudgeId,
    required NudgeInteractionType interactionType,
    String? interactionTarget,
    String? interactionContext,
    String? id,
    DateTime? timestamp,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) {
    return NudgeInteractionEvent(
      id: id ?? _generateId(),
      nudgeId: nudgeId,
      interactionType: interactionType,
      interactionTarget: interactionTarget,
      interactionContext: interactionContext,
      timestamp: timestamp,
      userId: userId,
      sessionId: sessionId,
      deviceInfo: deviceInfo,
      properties: properties,
    );
  }

  /// Create a feedback event
  static NudgeFeedbackEvent createFeedbackEvent({
    required String nudgeId,
    required int rating,
    String? comment,
    List<String>? tags,
    String? id,
    DateTime? timestamp,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) {
    return NudgeFeedbackEvent(
      id: id ?? _generateId(),
      nudgeId: nudgeId,
      rating: rating,
      comment: comment,
      tags: tags,
      timestamp: timestamp,
      userId: userId,
      sessionId: sessionId,
      deviceInfo: deviceInfo,
      properties: properties,
    );
  }

  /// Create a dismissal event
  static NudgeDismissalEvent createDismissalEvent({
    required String nudgeId,
    String? dismissalReason,
    bool isExplicit = true,
    String? dismissalContext,
    String? id,
    DateTime? timestamp,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) {
    return NudgeDismissalEvent(
      id: id ?? _generateId(),
      nudgeId: nudgeId,
      dismissalReason: dismissalReason,
      isExplicit: isExplicit,
      dismissalContext: dismissalContext,
      timestamp: timestamp,
      userId: userId,
      sessionId: sessionId,
      deviceInfo: deviceInfo,
      properties: properties,
    );
  }

  /// Create a completion event
  static NudgeCompletionEvent createCompletionEvent({
    required String nudgeId,
    required String actionType,
    int? completionTimeMs,
    bool isSuccessful = true,
    String? id,
    DateTime? timestamp,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) {
    return NudgeCompletionEvent(
      id: id ?? _generateId(),
      nudgeId: nudgeId,
      actionType: actionType,
      completionTimeMs: completionTimeMs,
      isSuccessful: isSuccessful,
      timestamp: timestamp,
      userId: userId,
      sessionId: sessionId,
      deviceInfo: deviceInfo,
      properties: properties,
    );
  }

  /// Create an error event
  static NudgeErrorEvent createErrorEvent({
    required String errorCode,
    required String errorMessage,
    String severity = 'error',
    String? stackTrace,
    String? nudgeId,
    String? id,
    DateTime? timestamp,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) {
    return NudgeErrorEvent(
      id: id ?? _generateId(),
      errorCode: errorCode,
      errorMessage: errorMessage,
      severity: severity,
      stackTrace: stackTrace,
      nudgeId: nudgeId,
      timestamp: timestamp,
      userId: userId,
      sessionId: sessionId,
      deviceInfo: deviceInfo,
      properties: properties,
    );
  }

  /// Create a settings change event
  static NudgeSettingsChangeEvent createSettingsChangeEvent({
    required String settingName,
    dynamic previousValue,
    dynamic newValue,
    String? id,
    DateTime? timestamp,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) {
    return NudgeSettingsChangeEvent(
      id: id ?? _generateId(),
      settingName: settingName,
      previousValue: previousValue,
      newValue: newValue,
      timestamp: timestamp,
      userId: userId,
      sessionId: sessionId,
      deviceInfo: deviceInfo,
      properties: properties,
    );
  }

  /// Create a session start event
  static NudgeSessionStartEvent createSessionStartEvent({
    required String sessionId,
    String? platform,
    String? appVersion,
    String? entryPoint,
    String? id,
    DateTime? timestamp,
    String? userId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) {
    return NudgeSessionStartEvent(
      id: id ?? _generateId(),
      sessionId: sessionId,
      platform: platform,
      appVersion: appVersion,
      entryPoint: entryPoint,
      timestamp: timestamp,
      userId: userId,
      deviceInfo: deviceInfo,
      properties: properties,
    );
  }

  /// Create a session end event
  static NudgeSessionEndEvent createSessionEndEvent({
    required String sessionId,
    int? durationMs,
    String? exitPoint,
    String? endReason,
    String? id,
    DateTime? timestamp,
    String? userId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) {
    return NudgeSessionEndEvent(
      id: id ?? _generateId(),
      sessionId: sessionId,
      durationMs: durationMs,
      exitPoint: exitPoint,
      endReason: endReason,
      timestamp: timestamp,
      userId: userId,
      deviceInfo: deviceInfo,
      properties: properties,
    );
  }

  /// Create a custom event
  static NudgeCustomEvent createCustomEvent({
    required String customEventName,
    String? nudgeId,
    String? id,
    DateTime? timestamp,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? properties,
  }) {
    return NudgeCustomEvent(
      id: id ?? _generateId(),
      customEventName: customEventName,
      nudgeId: nudgeId,
      timestamp: timestamp,
      userId: userId,
      sessionId: sessionId,
      deviceInfo: deviceInfo,
      properties: properties,
    );
  }

  /// Generate a unique ID
  static String _generateId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (1000 + (DateTime.now().microsecond % 9000)).toString();
    return 'evt_${timestamp}_$random';
  }
}

/// Analytics data processor for summarizing and analyzing events
class NudgeAnalyticsProcessor {
  /// Process events to create a user analytics summary
  static NudgeUserAnalytics processUserEvents({
    required String userId,
    required List<NudgeAnalyticsEvent> events,
  }) {
    if (events.isEmpty) {
      return NudgeUserAnalytics(userId: userId);
    }

    // Initialize counters and accumulators
    int totalNudgesDelivered = 0;
    int totalNudgesViewed = 0;
    int totalInteractions = 0;
    int totalRatings = 0;
    double ratingsSum = 0;
    int totalSessions = 0;
    int totalSessionDurationMs = 0;
    int totalEngagementTimeMs = 0;

    // Track timestamps
    DateTime? firstActivityDate;
    DateTime? lastActivityDate;

    // Process all events
    for (final event in events) {
      // Update activity timestamps
      if (firstActivityDate == null || event.timestamp.isBefore(firstActivityDate)) {
        firstActivityDate = event.timestamp;
      }

      if (lastActivityDate == null || event.timestamp.isAfter(lastActivityDate)) {
        lastActivityDate = event.timestamp;
      }

      // Process specific event types
      switch (event.type) {
        case NudgeAnalyticsEventType.delivery:
          totalNudgesDelivered++;
          break;

        case NudgeAnalyticsEventType.view:
          totalNudgesViewed++;
          final viewEvent = event as NudgeViewEvent;
          if (viewEvent.viewDurationMs != null) {
            totalEngagementTimeMs += viewEvent.viewDurationMs!;
          }
          break;

        case NudgeAnalyticsEventType.interaction:
          totalInteractions++;
          break;

        case NudgeAnalyticsEventType.feedback:
          final feedbackEvent = event as NudgeFeedbackEvent;
          totalRatings++;
          ratingsSum += feedbackEvent.rating;
          break;

        case NudgeAnalyticsEventType.sessionStart:
          totalSessions++;
          break;

        case NudgeAnalyticsEventType.sessionEnd:
          final sessionEndEvent = event as NudgeSessionEndEvent;
          if (sessionEndEvent.durationMs != null) {
            totalSessionDurationMs += sessionEndEvent.durationMs!;
          }
          break;

        default:
        // No special processing for other event types
          break;
      }
    }

    // Calculate averages
    final double? averageRating = totalRatings > 0 ? ratingsSum / totalRatings : null;
    final int? averageSessionDurationMs =
    totalSessions > 0 ? totalSessionDurationMs ~/ totalSessions : null;

    // Create user analytics object
    return NudgeUserAnalytics(
      userId: userId,
      totalNudgesDelivered: totalNudgesDelivered,
      totalNudgesViewed: totalNudgesViewed,
      totalInteractions: totalInteractions,
      averageRating: averageRating,
      totalRatings: totalRatings,
      totalSessions: totalSessions,
      averageSessionDurationMs: averageSessionDurationMs,
      firstActivityDate: firstActivityDate,
      lastActivityDate: lastActivityDate,
      totalEngagementTimeMs: totalEngagementTimeMs,
    );
  }

  /// Process events to create a nudge effectiveness summary
  static NudgeEffectivenessAnalytics processNudgeEvents({
    required String nudgeId,
    required List<NudgeAnalyticsEvent> events,
  }) {
    if (events.isEmpty) {
      return NudgeEffectivenessAnalytics(nudgeId: nudgeId);
    }

    // Initialize counters and accumulators
    int totalDeliveries = 0;
    int totalViews = 0;
    int totalInteractions = 0;
    int totalRatings = 0;
    double ratingsSum = 0;
    int totalCompletedActions = 0;
    int totalViewDurationMs = 0;

    // Track interaction types
    Map<String, int> interactionTypes = {};

    // Process all events
    for (final event in events) {
      if (event.nudgeId != nudgeId) continue;

      // Process specific event types
      switch (event.type) {
        case NudgeAnalyticsEventType.delivery:
          totalDeliveries++;
          break;

        case NudgeAnalyticsEventType.view:
          totalViews++;
          final viewEvent = event as NudgeViewEvent;
          if (viewEvent.viewDurationMs != null) {
            totalViewDurationMs += viewEvent.viewDurationMs!;
          }
          break;

        case NudgeAnalyticsEventType.interaction:
          totalInteractions++;
          final interactionEvent = event as NudgeInteractionEvent;
          final interactionType = interactionEvent.interactionType.toString().split('.').last;
          interactionTypes[interactionType] = (interactionTypes[interactionType] ?? 0) + 1;
          break;

        case NudgeAnalyticsEventType.feedback:
          final feedbackEvent = event as NudgeFeedbackEvent;
          totalRatings++;
          ratingsSum += feedbackEvent.rating;
          break;

        case NudgeAnalyticsEventType.completion:
          totalCompletedActions++;
          break;

        default:
        // No special processing for other event types
          break;
      }
    }

    // Calculate metrics
    final double? averageRating = totalRatings > 0 ? ratingsSum / totalRatings : null;
    final double viewRate = totalDeliveries > 0 ? totalViews / totalDeliveries : 0;
    final double interactionRate = totalViews > 0 ? totalInteractions / totalViews : 0;
    final double completionRate = totalViews > 0 ? totalCompletedActions / totalViews : 0;
    final int? averageViewTimeMs = totalViews > 0 ? totalViewDurationMs ~/ totalViews : null;

    // Determine most common interaction type
    String? mostCommonInteraction;
    int maxInteractionCount = 0;
    interactionTypes.forEach((type, count) {
      if (count > maxInteractionCount) {
        mostCommonInteraction = type;
        maxInteractionCount = count;
      }
    });

    // Create effectiveness analytics object
    return NudgeEffectivenessAnalytics(
      nudgeId: nudgeId,
      totalDeliveries: totalDeliveries,
      totalViews: totalViews,
      totalInteractions: totalInteractions,
      averageRating: averageRating,
      totalRatings: totalRatings,
      completionRate: completionRate,
      viewRate: viewRate,
      interactionRate: interactionRate,
      averageViewTimeMs: averageViewTimeMs,
      mostCommonInteraction: mostCommonInteraction,
    );
  }

  /// Process events to create an analytics summary for a time period
  static NudgeAnalyticsSummary processPeriodEvents({
    required NudgeAnalyticsTimePeriod timePeriod,
    required DateTime startDate,
    required DateTime endDate,
    required List<NudgeAnalyticsEvent> events,
  }) {
    if (events.isEmpty) {
      return NudgeAnalyticsSummary(
        timePeriod: timePeriod,
        startDate: startDate,
        endDate: endDate,
      );
    }

    // Filter events within the time period
    final periodEvents = events.where((event) =>
    !event.timestamp.isBefore(startDate) &&
        !event.timestamp.isAfter(endDate)).toList();

    if (periodEvents.isEmpty) {
      return NudgeAnalyticsSummary(
        timePeriod: timePeriod,
        startDate: startDate,
        endDate: endDate,
      );
    }

    // Initialize counters and accumulators
    int totalDeliveries = 0;
    int totalViews = 0;
    int totalInteractions = 0;
    int totalRatings = 0;
    double ratingsSum = 0;
    int totalSessions = 0;
    int totalSessionDurationMs = 0;
    int totalEngagementTimeMs = 0;

    // Track unique users and nudges
    Set<String> uniqueUserIds = {};
    Set<String> uniqueNudgeIds = {};
    Map<String, int> userInteractions = {};
    Map<String, int> nudgeInteractions = {};
    Map<String, int> errorCodes = {};

    // Process all events in the period
    for (final event in periodEvents) {
      // Track unique users
      if (event.userId != null) {
        uniqueUserIds.add(event.userId!);
        userInteractions[event.userId!] = (userInteractions[event.userId!] ?? 0) + 1;
      }

      // Track unique nudges
      if (event.nudgeId != null) {
        uniqueNudgeIds.add(event.nudgeId!);
        nudgeInteractions[event.nudgeId!] = (nudgeInteractions[event.nudgeId!] ?? 0) + 1;
      }

      // Process specific event types
      switch (event.type) {
        case NudgeAnalyticsEventType.delivery:
          totalDeliveries++;
          break;

        case NudgeAnalyticsEventType.view:
          totalViews++;
          final viewEvent = event as NudgeViewEvent;
          if (viewEvent.viewDurationMs != null) {
            totalEngagementTimeMs += viewEvent.viewDurationMs!;
          }
          break;

        case NudgeAnalyticsEventType.interaction:
          totalInteractions++;
          break;

        case NudgeAnalyticsEventType.feedback:
          final feedbackEvent = event as NudgeFeedbackEvent;
          totalRatings++;
          ratingsSum += feedbackEvent.rating;
          break;

        case NudgeAnalyticsEventType.sessionStart:
          totalSessions++;
          break;

        case NudgeAnalyticsEventType.sessionEnd:
          final sessionEndEvent = event as NudgeSessionEndEvent;
          if (sessionEndEvent.durationMs != null) {
            totalSessionDurationMs += sessionEndEvent.durationMs!;
          }
          break;

        case NudgeAnalyticsEventType.error:
          final errorEvent = event as NudgeErrorEvent;
          errorCodes[errorEvent.errorCode] = (errorCodes[errorEvent.errorCode] ?? 0) + 1;
          break;

        default:
        // No special processing for other event types
          break;
      }
    }

    // Calculate metrics
    final double? averageRating = totalRatings > 0 ? ratingsSum / totalRatings : null;
    final int? averageSessionDurationMs =
    totalSessions > 0 ? totalSessionDurationMs ~/ totalSessions : null;
    final int? averageEngagementTimePerUserMs = uniqueUserIds.isNotEmpty
        ? totalEngagementTimeMs ~/ uniqueUserIds.length : null;

    // Determine most active user
    String? mostActiveUserId;
    int maxUserInteractions = 0;
    userInteractions.forEach((userId, count) {
      if (count > maxUserInteractions) {
        mostActiveUserId = userId;
        maxUserInteractions = count;
      }
    });

    // Determine most effective nudge (based on interactions)
    String? mostEffectiveNudgeId;
    int maxNudgeInteractions = 0;
    nudgeInteractions.forEach((nudgeId, count) {
      if (count > maxNudgeInteractions) {
        mostEffectiveNudgeId = nudgeId;
        maxNudgeInteractions = count;
      }
    });

    // Determine most common error code
    String? mostCommonErrorCode;
    int maxErrorCount = 0;
    errorCodes.forEach((code, count) {
      if (count > maxErrorCount) {
        mostCommonErrorCode = code;
        maxErrorCount = count;
      }
    });

    // Create summary object
    return NudgeAnalyticsSummary(
      timePeriod: timePeriod,
      startDate: startDate,
      endDate: endDate,
      totalDeliveries: totalDeliveries,
      totalViews: totalViews,
      totalInteractions: totalInteractions,
      averageRating: averageRating,
      totalSessions: totalSessions,
      averageSessionDurationMs: averageSessionDurationMs,
      uniqueUsers: uniqueUserIds.length,
      totalEngagementTimeMs: totalEngagementTimeMs,
      averageEngagementTimePerUserMs: averageEngagementTimePerUserMs,
      mostActiveUserId: mostActiveUserId,
      mostEffectiveNudgeId: mostEffectiveNudgeId,
      mostCommonErrorCode: mostCommonErrorCode,
    );
  }
}

/// Analytics data exporter for exporting data in various formats
class NudgeAnalyticsExporter {
  /// Export events to CSV format
  static String exportEventsToCSV(List<NudgeAnalyticsEvent> events) {
    if (events.isEmpty) {
      return 'No events to export';
    }

    // Create header row
    final StringBuffer csv = StringBuffer();
    csv.writeln('Event ID,Type,Timestamp,User ID,Nudge ID,Session ID,JSON Properties');

    // Add data rows
    for (final event in events) {
      csv.writeln([
        event.id,
        event.type.toString().split('.').last,
        event.timestamp.toIso8601String(),
        event.userId ?? '',
        event.nudgeId ?? '',
        event.sessionId ?? '',
        jsonEncode(event.properties),
      ].map((field) => '"${field.toString().replaceAll('"', '""')}"').join(','));
    }

    return csv.toString();
  }

  /// Export user analytics to CSV format
  static String exportUserAnalyticsToCSV(List<NudgeUserAnalytics> userAnalytics) {
    if (userAnalytics.isEmpty) {
      return 'No user analytics to export';
    }

    // Create header row
    final StringBuffer csv = StringBuffer();
    csv.writeln('User ID,Total Nudges Delivered,Total Nudges Viewed,Total Interactions,'
        'Average Rating,Total Ratings,Total Sessions,Average Session Duration (ms),'
        'First Activity Date,Last Activity Date,Total Engagement Time (ms)');

    // Add data rows
    for (final ua in userAnalytics) {
      csv.writeln([
        ua.userId,
        ua.totalNudgesDelivered,
        ua.totalNudgesViewed,
        ua.totalInteractions,
        ua.averageRating ?? '',
        ua.totalRatings,
        ua.totalSessions,
        ua.averageSessionDurationMs ?? '',
        ua.firstActivityDate?.toIso8601String() ?? '',
        ua.lastActivityDate?.toIso8601String() ?? '',
        ua.totalEngagementTimeMs,
      ].map((field) => '"${field.toString().replaceAll('"', '""')}"').join(','));
    }

    return csv.toString();
  }

  /// Export nudge effectiveness analytics to CSV format
  static String exportNudgeEffectivenessToCSV(List<NudgeEffectivenessAnalytics> nudgeAnalytics) {
    if (nudgeAnalytics.isEmpty) {
      return 'No nudge effectiveness analytics to export';
    }

    // Create header row
    final StringBuffer csv = StringBuffer();
    csv.writeln('Nudge ID,Total Deliveries,Total Views,Total Interactions,'
        'Average Rating,Total Ratings,Completion Rate,View Rate,Interaction Rate,'
        'Average View Time (ms),Most Common Interaction');

    // Add data rows
    for (final na in nudgeAnalytics) {
      csv.writeln([
        na.nudgeId,
        na.totalDeliveries,
        na.totalViews,
        na.totalInteractions,
        na.averageRating ?? '',
        na.totalRatings,
        na.completionRate ?? '',
        na.viewRate ?? '',
        na.interactionRate ?? '',
        na.averageViewTimeMs ?? '',
        na.mostCommonInteraction ?? '',
      ].map((field) => '"${field.toString().replaceAll('"', '""')}"').join(','));
    }

    return csv.toString();
  }

  /// Export analytics summary to CSV format
  static String exportAnalyticsSummaryToCSV(List<NudgeAnalyticsSummary> summaries) {
    if (summaries.isEmpty) {
      return 'No analytics summaries to export';
    }

    // Create header row
    final StringBuffer csv = StringBuffer();
    csv.writeln('Time Period,Start Date,End Date,Total Deliveries,Total Views,'
        'Total Interactions,Average Rating,Total Sessions,Average Session Duration (ms),'
        'Unique Users,Total Engagement Time (ms),Average Engagement Time Per User (ms)');

    // Add data rows
    for (final summary in summaries) {
      csv.writeln([
        summary.timePeriod.toString().split('.').last,
        summary.startDate.toIso8601String(),
        summary.endDate.toIso8601String(),
        summary.totalDeliveries,
        summary.totalViews,
        summary.totalInteractions,
        summary.averageRating ?? '',
        summary.totalSessions,
        summary.averageSessionDurationMs ?? '',
        summary.uniqueUsers,
        summary.totalEngagementTimeMs,
        summary.averageEngagementTimePerUserMs ?? '',
      ].map((field) => '"${field.toString().replaceAll('"', '""')}"').join(','));
    }

    return csv.toString();
  }

  /// Export data to JSON format
  static String exportToJSON(dynamic data) {
    if (data is List<NudgeAnalyticsEvent>) {
      return jsonEncode(data.map((e) => e.toMap()).toList());
    } else if (data is List<NudgeUserAnalytics>) {
      return jsonEncode(data.map((ua) => ua.toMap()).toList());
    } else if (data is List<NudgeEffectivenessAnalytics>) {
      return jsonEncode(data.map((na) => na.toMap()).toList());
    } else if (data is List<NudgeAnalyticsSummary>) {
      return jsonEncode(data.map((s) => s.toMap()).toList());
    } else if (data is Map) {
      return jsonEncode(data);
    } else {
      return 'Unsupported data format for JSON export';
    }
  }
}