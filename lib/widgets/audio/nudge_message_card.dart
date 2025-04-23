// Copyright © 2025 Milo App. All rights reserved.
// Author: Milo Development Team
// File: lib/widgets/audio/nudge_message_card.dart
// Version: 1.2.0
// Last Updated: April 23, 2025
// Description: Card for displaying nudge messages, optimized for elderly users (55+)
// Change History:
// - 1.0.0: Initial implementation
// - 1.1.0: Added performance optimizations, responsive design
// - 1.2.0: Enhanced error recovery, UX refinements, privacy features, and integration improvements

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/nudge_model.dart';
import '../../services/nudge_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/advanced_logger.dart';
import '../../services/caregiver_service.dart';
import 'nudge_audio_player.dart';
import 'nudge_feedback_dialog.dart';

/// Enum for retry policies for operations
enum RetryPolicy {
  /// No retry
  none,

  /// Retry immediately once
  immediate,

  /// Retry with exponential backoff
  exponentialBackoff,

  /// Always queue for later when operation fails
  alwaysQueue
}

/// Privacy level for nudge content
enum PrivacyLevel {
  /// Public content, can be shared without restrictions
  public,

  /// Private content, should not be shared outside the app
  private,

  /// Sensitive content, requires confirmation before sharing
  sensitive,

  /// Medical content that should be handled with extra care
  medical,

  /// Temporary content that expires
  temporary
}

/// Class for managing queued operations
class _QueuedOperation {
  /// Type of operation
  final String type;

  /// Nudge ID
  final String nudgeId;

  /// Additional data for the operation
  final Map<String, dynamic> data;

  /// Number of retry attempts
  int retryCount = 0;

  /// When this operation was queued
  final DateTime queuedAt;

  /// Creates a queued operation
  _QueuedOperation({
    required this.type,
    required this.nudgeId,
    required this.data,
    DateTime? queuedAt,
  }) : queuedAt = queuedAt ?? DateTime.now();

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'nudgeId': nudgeId,
      'data': data,
      'retryCount': retryCount,
      'queuedAt': queuedAt.toIso8601String(),
    };
  }

  /// Create from JSON data
  factory _QueuedOperation.fromJson(Map<String, dynamic> json) {
    return _QueuedOperation(
      type: json['type'],
      nudgeId: json['nudgeId'],
      data: Map<String, dynamic>.from(json['data']),
      queuedAt: DateTime.parse(json['queuedAt']),
    )..retryCount = json['retryCount'];
  }
}

/// State class for the NudgeMessageCard to improve performance
/// by avoiding unnecessary rebuilds
///
/// This class manages the state of the card and notifies
/// listeners only when necessary, reducing rebuilds.
class _NudgeMessageCardState extends ChangeNotifier {
  /// Whether the card is expanded to show full content
  bool _isExpanded = false;

  /// Whether the card is marked as read
  bool _isRead = false;

  /// Whether the card shows favorite animation
  bool _showFavoriteAnimation = false;

  /// Whether the card is favorited
  bool _isFavorited = false;

  /// Whether the audio player is currently visible
  bool _isAudioPlayerVisible = false;

  /// Whether the share options are visible
  bool _isShareOptionsVisible = false;

  /// Whether the message is being saved
  bool _isSaving = false;

  /// Whether there was an error saving
  bool _hasSaveError = false;

  /// Whether the card is currently being processed
  bool _isProcessing = false;

  /// Whether the card is in recovery mode from an error
  bool _isRecovering = false;

  /// Whether reminder options are visible
  bool _isReminderOptionsVisible = false;

  /// Whether the privacy options are visible
  bool _isPrivacyOptionsVisible = false;

  /// Whether the caregiver sharing options are visible
  bool _isCaregiverShareVisible = false;

  /// Whether content expiration is enabled
  bool _isExpirationEnabled = false;

  /// The current privacy level of the nudge
  PrivacyLevel _privacyLevel = PrivacyLevel.public;

  /// Expiration date for the nudge if set
  DateTime? _expirationDate;

  /// Queue of pending operations
  final List<_QueuedOperation> _operationQueue = [];

  /// Timer for auto-hiding elements
  Timer? _autoHideTimer;

  /// Timer for retry operations
  Timer? _retryTimer;

  /// Counter for retry attempts
  int _retryCount = 0;

  /// Maximum number of retry attempts
  final int _maxRetryAttempts = 3;

  /// Error message if any
  String? _errorMessage;

  /// Basic getters
  bool get isExpanded => _isExpanded;
  bool get isRead => _isRead;
  bool get showFavoriteAnimation => _showFavoriteAnimation;
  bool get isFavorited => _isFavorited;
  bool get isAudioPlayerVisible => _isAudioPlayerVisible;
  bool get isShareOptionsVisible => _isShareOptionsVisible;
  bool get isSaving => _isSaving;
  bool get hasSaveError => _hasSaveError;
  bool get isProcessing => _isProcessing;
  bool get isRecovering => _isRecovering;
  String? get errorMessage => _errorMessage;

  /// Enhanced UX getters
  bool get isReminderOptionsVisible => _isReminderOptionsVisible;
  bool get isPrivacyOptionsVisible => _isPrivacyOptionsVisible;
  bool get isCaregiverShareVisible => _isCaregiverShareVisible;
  bool get isExpirationEnabled => _isExpirationEnabled;
  PrivacyLevel get privacyLevel => _privacyLevel;
  DateTime? get expirationDate => _expirationDate;
  List<_QueuedOperation> get operationQueue => List.unmodifiable(_operationQueue);

  /// Constructor
  _NudgeMessageCardState({
    required NudgeDelivery nudge,
  }) {
    _isRead = nudge.isRead;
    _isFavorited = nudge.isFavorited;
    _privacyLevel = _getPrivacyLevelFromString(nudge.privacyLevel ?? 'public');
    _expirationDate = nudge.expirationDate;
    _isExpirationEnabled = nudge.expirationDate != null;

    // Load queued operations from storage
    _loadQueuedOperations(nudge.id);
  }

  /// Load queued operations from storage
  Future<void> _loadQueuedOperations(String nudgeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queuedOpsJson = prefs.getString('queued_ops_$nudgeId');

      if (queuedOpsJson != null) {
        final List<dynamic> queuedOps = jsonDecode(queuedOpsJson);
        _operationQueue.addAll(
            queuedOps.map((op) => _QueuedOperation.fromJson(op)).toList()
        );

        if (_operationQueue.isNotEmpty) {
          notifyListeners();
        }
      }
    } catch (e) {
      AdvancedLogger.logError(
          '_NudgeMessageCardState',
          'Error loading queued operations: $e'
      );
    }
  }

  /// Save queued operations to storage
  Future<void> _saveQueuedOperations(String nudgeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queuedOpsJson = jsonEncode(
          _operationQueue.map((op) => op.toJson()).toList()
      );

      await prefs.setString('queued_ops_$nudgeId', queuedOpsJson);
    } catch (e) {
      AdvancedLogger.logError(
          '_NudgeMessageCardState',
          'Error saving queued operations: $e'
      );
    }
  }

  /// Process queued operations
  Future<void> _processQueuedOperations() async {
    if (_operationQueue.isEmpty) return;

    // Process a copy of the queue to avoid modification during iteration
    final queueCopy = List<_QueuedOperation>.from(_operationQueue);

    for (final operation in queueCopy) {
      // Log processing
      AdvancedLogger.logInfo(
          '_NudgeMessageCardState',
          'Processing queued operation: ${operation.type}'
      );

      // For simplicity, just remove the operation
      // In a real implementation, you would handle each operation type
      _operationQueue.remove(operation);

      // Notify listeners after each operation
      notifyListeners();
    }

    // Save updated queue
    await _saveQueuedOperations(queueCopy.first.nudgeId);
  }

  /// Add operation to queue
  Future<void> queueOperation(String type, String nudgeId, Map<String, dynamic> data) async {
    final operation = _QueuedOperation(
      type: type,
      nudgeId: nudgeId,
      data: data,
    );

    _operationQueue.add(operation);
    await _saveQueuedOperations(nudgeId);
    notifyListeners();
  }

  /// Toggle expanded state
  void toggleExpanded() {
    _isExpanded = !_isExpanded;
    notifyListeners();
  }

  /// Mark as read
  void markAsRead() {
    if (!_isRead) {
      _isRead = true;
      notifyListeners();
    }
  }

  /// Toggle favorite state with animation
  Future<void> toggleFavorite() async {
    _isFavorited = !_isFavorited;
    _showFavoriteAnimation = _isFavorited;
    notifyListeners();

    if (_showFavoriteAnimation) {
      // Hide animation after delay
      await Future.delayed(const Duration(milliseconds: 1500));
      if (_isFavorited) { // Only hide if still favorited
        _showFavoriteAnimation = false;
        notifyListeners();
      }
    }
  }

  /// Show audio player
  void showAudioPlayer() {
    _isAudioPlayerVisible = true;
    _cancelAutoHideTimer();
    notifyListeners();
  }

  /// Hide audio player
  void hideAudioPlayer() {
    _isAudioPlayerVisible = false;
    notifyListeners();
  }

  /// Toggle share options
  void toggleShareOptions() {
    _isShareOptionsVisible = !_isShareOptionsVisible;

    if (_isShareOptionsVisible) {
      // Hide other overlays
      _isReminderOptionsVisible = false;
      _isPrivacyOptionsVisible = false;
      _isCaregiverShareVisible = false;

      _startAutoHideTimer();
    } else {
      _cancelAutoHideTimer();
    }

    notifyListeners();
  }

  /// Toggle reminder options
  void toggleReminderOptions() {
    _isReminderOptionsVisible = !_isReminderOptionsVisible;

    if (_isReminderOptionsVisible) {
      // Hide other overlays
      _isShareOptionsVisible = false;
      _isPrivacyOptionsVisible = false;
      _isCaregiverShareVisible = false;

      _startAutoHideTimer();
    } else {
      _cancelAutoHideTimer();
    }

    notifyListeners();
  }

  /// Toggle privacy options
  void togglePrivacyOptions() {
    _isPrivacyOptionsVisible = !_isPrivacyOptionsVisible;

    if (_isPrivacyOptionsVisible) {
      // Hide other overlays
      _isShareOptionsVisible = false;
      _isReminderOptionsVisible = false;
      _isCaregiverShareVisible = false;

      _startAutoHideTimer();
    } else {
      _cancelAutoHideTimer();
    }

    notifyListeners();
  }

  /// Toggle caregiver sharing options
  void toggleCaregiverShare() {
    _isCaregiverShareVisible = !_isCaregiverShareVisible;

    if (_isCaregiverShareVisible) {
      // Hide other overlays
      _isShareOptionsVisible = false;
      _isReminderOptionsVisible = false;
      _isPrivacyOptionsVisible = false;

      _startAutoHideTimer();
    } else {
      _cancelAutoHideTimer();
    }

    notifyListeners();
  }

  /// Toggle expiration setting
  void toggleExpiration() {
    _isExpirationEnabled = !_isExpirationEnabled;

    if (!_isExpirationEnabled) {
      _expirationDate = null;
    } else if (_expirationDate == null) {
      // Default to 30 days from now
      _expirationDate = DateTime.now().add(const Duration(days: 30));
    }

    notifyListeners();
  }

  /// Set expiration date
  void setExpirationDate(DateTime date) {
    _expirationDate = date;
    _isExpirationEnabled = true;
    notifyListeners();
  }

  /// Set privacy level
  void setPrivacyLevel(PrivacyLevel level) {
    _privacyLevel = level;
    notifyListeners();
  }

  /// Start auto-hide timer for UI elements
  void _startAutoHideTimer() {
    _cancelAutoHideTimer();
    _autoHideTimer = Timer(const Duration(seconds: 5), () {
      _isShareOptionsVisible = false;
      _isReminderOptionsVisible = false;
      _isPrivacyOptionsVisible = false;
      _isCaregiverShareVisible = false;
      notifyListeners();
    });
  }

  /// Cancel auto-hide timer
  void _cancelAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
  }

  /// Set saving state
  void setSaving(bool saving) {
    _isSaving = saving;
    if (saving) {
      _hasSaveError = false;
      _errorMessage = null;
    }
    notifyListeners();
  }

  /// Set save error
  void setSaveError(String message) {
    _isSaving = false;
    _hasSaveError = true;
    _errorMessage = message;
    notifyListeners();
  }

  /// Set processing state
  void setProcessing(bool processing) {
    _isProcessing = processing;
    notifyListeners();
  }

  /// Set recovering state
  void setRecovering(bool recovering) {
    _isRecovering = recovering;
    notifyListeners();
  }

  /// Clear error state
  void clearError() {
    _hasSaveError = false;
    _errorMessage = null;
    _isRecovering = false;
    notifyListeners();
  }

  /// Attempt retry for failed operation
  void retryFailedOperation(RetryPolicy policy, Function operation) {
    _retryCount++;

    if (_retryCount > _maxRetryAttempts) {
      AdvancedLogger.logWarning(
          '_NudgeMessageCardState',
          'Maximum retry attempts reached'
      );
      return;
    }

    switch (policy) {
      case RetryPolicy.immediate:
      // Cancel any existing retry timer
        _cancelRetryTimer();

        // Try again immediately
        operation();
        break;

      case RetryPolicy.exponentialBackoff:
        _cancelRetryTimer();

        // Calculate backoff time (2^retry_count * 1000ms)
        final backoffMs = (1 << _retryCount) * 1000;

        _retryTimer = Timer(Duration(milliseconds: backoffMs), () {
          setRecovering(true);
          operation();
        });
        break;

      case RetryPolicy.alwaysQueue:
      // Implementation would depend on the operation type
      // This would be handled by queueOperation method
        break;

      case RetryPolicy.none:
      default:
      // Do nothing
        break;
    }
  }

  /// Reset retry count
  void resetRetryCount() {
    _retryCount = 0;
  }

  /// Cancel retry timer
  void _cancelRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Get privacy level enum from string
  PrivacyLevel _getPrivacyLevelFromString(String level) {
    switch (level.toLowerCase()) {
      case 'private':
        return PrivacyLevel.private;
      case 'sensitive':
        return PrivacyLevel.sensitive;
      case 'medical':
        return PrivacyLevel.medical;
      case 'temporary':
        return PrivacyLevel.temporary;
      case 'public':
      default:
        return PrivacyLevel.public;
    }
  }

  @override
  void dispose() {
    _cancelAutoHideTimer();
    _cancelRetryTimer();
    super.dispose();
  }
}

/// A card for displaying nudge messages with various interaction options
///
/// This widget presents nudge messages in a visually appealing card format
/// with support for expansion, audio playback, favoriting, and sharing.
/// It is optimized for elderly users with accessibility features.
class NudgeMessageCard extends StatefulWidget {
  /// The nudge data to display
  final NudgeDelivery nudge;

  /// Whether to automatically expand the card
  final bool autoExpand;

  /// Whether to automatically mark as read when viewed
  final bool autoMarkAsRead;

  /// Retry policy for failed operations
  final RetryPolicy retryPolicy;

  /// Callback when nudge read status changes
  final Function(NudgeDelivery, bool)? onReadStatusChanged;

  /// Callback when nudge favorite status changes
  final Function(NudgeDelivery, bool)? onFavoriteStatusChanged;

  /// Callback when feedback is submitted
  final Function(NudgeDelivery, FeedbackData)? onFeedbackSubmitted;

  /// Callback when nudge is saved as memory
  final Function(NudgeDelivery)? onSaveAsMemory;

  /// Callback when nudge is shared
  final Function(NudgeDelivery, String)? onShare;

  /// Callback when nudge is shared with caregiver
  final Function(NudgeDelivery, String)? onShareWithCaregiver;

  /// Callback when nudge is deleted
  final Function(NudgeDelivery)? onDelete;

  /// Callback when nudge privacy level is changed
  final Function(NudgeDelivery, PrivacyLevel)? onPrivacyLevelChanged;

  /// Callback when nudge expiration is set
  final Function(NudgeDelivery, DateTime?)? onExpirationSet;

  /// Callback when nudge is scheduled as reminder
  final Function(NudgeDelivery, DateTime, String)? onScheduleReminder;

  /// Whether to enable haptic feedback
  final bool enableHaptics;

  /// Whether to use enhanced accessibility features
  final bool enhancedAccessibility;

  /// Additional padding around the card
  final EdgeInsets padding;

  /// Background color for the card
  final Color? backgroundColor;

  /// Maximum number of lines to show in collapsed state
  final int collapsedLineCount;

  /// Creates a nudge message card.
  ///
  /// The [nudge] parameter is required and specifies the nudge to display.
  ///
  /// The [autoExpand] parameter determines if the card should be expanded by default.
  ///
  /// The [autoMarkAsRead] parameter determines if the nudge should be automatically
  /// marked as read when the card is displayed.
  ///
  /// The [retryPolicy] parameter determines how failed operations should be retried.
  /// Defaults to RetryPolicy.exponentialBackoff.
  ///
  /// The [onReadStatusChanged] parameter is called when the nudge is marked as read.
  ///
  /// The [onFavoriteStatusChanged] parameter is called when the nudge is favorited or unfavorited.
  ///
  /// The [onFeedbackSubmitted] parameter is called when feedback is submitted for the nudge.
  ///
  /// The [onSaveAsMemory] parameter is called when the nudge is saved as a memory.
  ///
  /// The [onShare] parameter is called when the nudge is shared, with the share method.
  ///
  /// The [onShareWithCaregiver] parameter is called when the nudge is shared with a caregiver.
  ///
  /// The [onDelete] parameter is called when the nudge is deleted.
  ///
  /// The [onPrivacyLevelChanged] parameter is called when the privacy level is changed.
  ///
  /// The [onExpirationSet] parameter is called when the expiration date is set or changed.
  ///
  /// The [onScheduleReminder] parameter is called when a reminder is scheduled.
  ///
  /// The [enableHaptics] parameter determines if haptic feedback should be used
  /// for interactions. Defaults to true.
  ///
  /// The [enhancedAccessibility] parameter determines if larger text and controls
  /// should be used for better accessibility. Defaults to false.
  ///
  /// The [padding] parameter specifies additional padding around the card.
  /// Defaults to 12 pixels on all sides.
  ///
  /// The [backgroundColor] parameter specifies the background color for the card.
  /// If null, the card color from AppTheme is used.
  ///
  /// The [collapsedLineCount] parameter specifies how many lines of the message
  /// to show when the card is collapsed. Defaults to 3.
  const NudgeMessageCard({
    required this.nudge,
    this.autoExpand = false,
    this.autoMarkAsRead = true,
    this.retryPolicy = RetryPolicy.exponentialBackoff,
    this.onReadStatusChanged,
    this.onFavoriteStatusChanged,
    this.onFeedbackSubmitted,
    this.onSaveAsMemory,
    this.onShare,
    this.onShareWithCaregiver,
    this.onDelete,
    this.onPrivacyLevelChanged,
    this.onExpirationSet,
    this.onScheduleReminder,
    this.enableHaptics = true,
    this.enhancedAccessibility = false,
    this.padding = const EdgeInsets.all(12.0),
    this.backgroundColor,
    this.collapsedLineCount = 3,
    Key? key,
  }) : super(key: key);

  @override
  State<NudgeMessageCard> createState() => _NudgeMessageCardState();
}

class _NudgeMessageCardState extends State<NudgeMessageCard> with SingleTickerProviderStateMixin {
  /// State manager for the card
  late _NudgeMessageCardState _cardState;

  /// Animation controller for the card
  late AnimationController _animationController;

  /// Animation for the card expansion
  late Animation<double> _expandAnimation;

  /// Focus node for the card
  final FocusNode _cardFocusNode = FocusNode();

  /// Key for scrolling to this card
  final GlobalKey _cardKey = GlobalKey();

  /// User preferences placeholder
  bool _hasCaregivers = false;

  @override
  void initState() {
    super.initState();

    // Initialize state manager
    _cardState = _NudgeMessageCardState(nudge: widget.nudge);

    // Set up animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    // Set initial expansion state
    if (widget.autoExpand) {
      _cardState.toggleExpanded();
      _animationController.value = 1.0;
    }

    // Auto mark as read if needed
    if (widget.autoMarkAsRead && !widget.nudge.isRead) {
      _markAsRead();
    }

    // Check for expiring content
    _checkExpiringContent();

    // Load user preferences - simplified for this example
    _loadUserPreferences();

    // Log view event
    AdvancedLogger.logInfo(
        'NudgeMessageCard',
        'Card viewed: ${widget.nudge.id}'
    );
  }

  /// Load user preferences
  Future<void> _loadUserPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _hasCaregivers = prefs.getBool('has_caregivers') ?? false;
      });
    } catch (e) {
      AdvancedLogger.logError(
          'NudgeMessageCard',
          'Error loading user preferences: $e'
      );
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _cardState.dispose();
    _cardFocusNode.dispose();
    super.dispose();
  }

  /// Check if content is expiring soon and show warning
  void _checkExpiringContent() {
    if (_cardState.expirationDate != null) {
      final now = DateTime.now();
      final daysUntilExpiration = _cardState.expirationDate!.difference(now).inDays;

      if (daysUntilExpiration <= 7 && daysUntilExpiration > 0) {
        // Show warning about expiring content
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'This nudge will expire in $daysUntilExpiration day${daysUntilExpiration == 1 ? '' : 's'}',
                ),
                backgroundColor: AppTheme.warningColor,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Change',
                  textColor: Colors.black,
                  onPressed: () {
                    _cardState.togglePrivacyOptions();
                  },
                ),
              ),
            );
          }
        });
      } else if (daysUntilExpiration <= 0) {
        // Content has expired, update UI to reflect this
        _cardState.setSaveError('This nudge has expired');
      }
    }
  }

  /// Handle haptic feedback if enabled
  void _triggerHaptic() {
    if (widget.enableHaptics) {
      HapticFeedback.mediumImpact();
    }
  }

  /// Toggle expanded state with animation
  void _toggleExpanded() {
    _triggerHaptic();

    _cardState.toggleExpanded();

    if (_cardState.isExpanded) {
      _animationController.forward();
      _markAsRead();
    } else {
      _animationController.reverse();
    }

    AdvancedLogger.logInfo(
        'NudgeMessageCard',
        'Card expanded: ${_cardState.isExpanded}'
    );
  }

  /// Mark nudge as read and notify parent
  Future<void> _markAsRead() async {
    if (!widget.nudge.isRead) {
      _cardState.markAsRead();

      try {
        // Notify parent
        if (widget.onReadStatusChanged != null) {
          await widget.onReadStatusChanged!(widget.nudge, true);
        }

        AdvancedLogger.logInfo(
            'NudgeMessageCard',
            'Marked as read: ${widget.nudge.id}'
        );
      } catch (e) {
        AdvancedLogger.logError(
            'NudgeMessageCard',
            'Error marking nudge as read: $e'
        );

        // Handle error with retry
        _handleOperationError(
            e,
            'mark_as_read',
            _markAsRead,
            'Failed to mark as read'
        );
      }
    }
  }

  /// Toggle favorite status and notify parent
  Future<void> _toggleFavorite() async {
    _triggerHaptic();

    final previousState = _cardState.isFavorited;
    await _cardState.toggleFavorite();

    try {
      // Notify parent
      if (widget.onFavoriteStatusChanged != null) {
        await widget.onFavoriteStatusChanged!(widget.nudge, _cardState.isFavorited);
      }

      AdvancedLogger.logInfo(
          'NudgeMessageCard',
          'Favorite toggled: ${_cardState.isFavorited}'
      );

      // Reset retry count on success
      _cardState.resetRetryCount();
    } catch (e) {
      // Handle error with retry
      _handleOperationError(
          e,
          'toggle_favorite',
          _toggleFavorite,
          'Failed to ${previousState ? 'remove from' : 'add to'} favorites'
      );
    }
  }

  /// Show audio player
  void _showAudioPlayer() {
    _triggerHaptic();
    _cardState.showAudioPlayer();

    AdvancedLogger.logInfo(
        'NudgeMessageCard',
        'Audio player opened'
    );
  }

  /// Hide audio player
  void _hideAudioPlayer() {
    _cardState.hideAudioPlayer();

    AdvancedLogger.logInfo(
        'NudgeMessageCard',
        'Audio player closed'
    );
  }

  /// Toggle share options
  void _toggleShareOptions() {
    _triggerHaptic();
    _cardState.toggleShareOptions();

    AdvancedLogger.logInfo(
        'NudgeMessageCard',
        'Share options toggled: ${_cardState.isShareOptionsVisible}'
    );
  }

  /// Toggle reminder options
  void _toggleReminderOptions() {
    _triggerHaptic();
    _cardState.toggleReminderOptions();

    AdvancedLogger.logInfo(
        'NudgeMessageCard',
        'Reminder options toggled: ${_cardState.isReminderOptionsVisible}'
    );
  }

  /// Toggle privacy options
  void _togglePrivacyOptions() {
    _triggerHaptic();
    _cardState.togglePrivacyOptions();

    AdvancedLogger.logInfo(
        'NudgeMessageCard',
        'Privacy options toggled: ${_cardState.isPrivacyOptionsVisible}'
    );
  }

  /// Toggle caregiver sharing options
  void _toggleCaregiverShare() {
    _triggerHaptic();
    _cardState.toggleCaregiverShare();

    AdvancedLogger.logInfo(
        'NudgeMessageCard',
        'Caregiver share toggled: ${_cardState.isCaregiverShareVisible}'
    );
  }

  /// Show feedback dialog
  Future<void> _showFeedbackDialog() async {
    _triggerHaptic();

    try {
      await showNudgeFeedbackDialog(
        context: context,
        nudge: widget.nudge,
        onFeedbackSubmitted: widget.onFeedbackSubmitted,
        enableHaptics: widget.enableHaptics,
        enhancedAccessibility: widget.enhancedAccessibility,
      );

      AdvancedLogger.logInfo(
          'NudgeMessageCard',
          'Feedback dialog completed'
      );
    } catch (e) {
      AdvancedLogger.logError(
          'NudgeMessageCard',
          'Error showing feedback dialog: $e'
      );

      // We don't retry showing the dialog since it's not a critical operation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Unable to open feedback form'),
          backgroundColor: AppTheme.errorColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Save nudge as memory
  Future<void> _saveAsMemory() async {
    _triggerHaptic();

    if (_cardState.isSaving) return;

    _cardState.setSaving(true);

    try {
      // Notify parent
      if (widget.onSaveAsMemory != null) {
        await widget.onSaveAsMemory!(widget.nudge);
      }

      _cardState.setSaving(false);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved as a memory'),
            backgroundColor: AppTheme.successColor,
            duration: Duration(seconds: 2),
          ),
        );
      }

      AdvancedLogger.logInfo(
          'NudgeMessageCard',
          'Saved as memory'
      );

      // Reset retry count on success
      _cardState.resetRetryCount();
    } catch (e) {
      // Handle error with retry
      _handleOperationError(
          e,
          'save_as_memory',
          _saveAsMemory,
          'Failed to save as memory'
      );
    }
  }

  /// Share nudge with specified method
  Future<void> _shareNudge(String method) async {
    _triggerHaptic();

    // Check privacy level before sharing
    if (_cardState.privacyLevel == PrivacyLevel.private ||
        _cardState.privacyLevel == PrivacyLevel.sensitive ||
        _cardState.privacyLevel == PrivacyLevel.medical) {

      // Confirm sharing of sensitive content
      final confirmed = await _confirmSensitiveShare(method);
      if (!confirmed) return;
    }

    // Hide share options
    _cardState.toggleShareOptions();

    _cardState.setProcessing(true);

    try {
      // Notify parent
      if (widget.onShare != null) {
        await widget.onShare!(widget.nudge, method);
      }

      _cardState.setProcessing(false);

      AdvancedLogger.logInfo(
          'NudgeMessageCard',
          'Shared nudge via: $method'
      );

      // Reset retry count on success
      _cardState.resetRetryCount();
    } catch (e) {
      // Handle error with retry
      _handleOperationError(
          e,
          'share_nudge',
              () => _shareNudge(method),
          'Failed to share'
      );
    }
  }

  /// Share nudge with caregiver
  Future<void> _shareWithCaregiver(String caregiverId) async {
    _triggerHaptic();

    // Hide caregiver share options
    _cardState.toggleCaregiverShare();

    _cardState.setProcessing(true);

    try {
      // Notify parent
      if (widget.onShareWithCaregiver != null) {
        await widget.onShareWithCaregiver!(widget.nudge, caregiverId);
      }

      _cardState.setProcessing(false);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Shared with caregiver'),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      AdvancedLogger.logInfo(
          'NudgeMessageCard',
          'Shared with caregiver: $caregiverId'
      );

      // Reset retry count on success
      _cardState.resetRetryCount();
    } catch (e) {
      // Handle error with retry
      _handleOperationError(
          e,
          'share_with_caregiver',
              () => _shareWithCaregiver(caregiverId),
          'Failed to share with caregiver'
      );
    }
  }

  /// Update privacy level
  Future<void> _updatePrivacyLevel(PrivacyLevel level) async {
    _triggerHaptic();

    final previousLevel = _cardState.privacyLevel;
    _cardState.setPrivacyLevel(level);

    try {
      // Notify parent
      if (widget.onPrivacyLevelChanged != null) {
        await widget.onPrivacyLevelChanged!(widget.nudge, level);
      }

      // Show confirmation message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Privacy level updated to ${_getPrivacyLevelName(level)}'),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      AdvancedLogger.logInfo(
          'NudgeMessageCard',
          'Privacy level changed: ${level.toString()}'
      );

      // Reset retry count on success
      _cardState.resetRetryCount();
    } catch (e) {
      // Revert UI state on error
      _cardState.setPrivacyLevel(previousLevel);

      // Handle error with retry
      _handleOperationError(
          e,
          'update_privacy_level',
              () => _updatePrivacyLevel(level),
          'Failed to update privacy level'
      );
    }
  }

  /// Update expiration date
  Future<void> _updateExpirationDate(DateTime? date) async {
    _triggerHaptic();

    final previousDate = _cardState.expirationDate;
    if (date != null) {
      _cardState.setExpirationDate(date);
    } else {
      _cardState.toggleExpiration();
    }

    try {
      // Notify parent
      if (widget.onExpirationSet != null) {
        await widget.onExpirationSet!(widget.nudge, _cardState.isExpirationEnabled ?
        _cardState.expirationDate : null);
      }

      // Show confirmation message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_cardState.isExpirationEnabled ?
            'Content will expire on ${_formatDate(_cardState.expirationDate!)}' :
            'Content expiration disabled'),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      AdvancedLogger.logInfo(
          'NudgeMessageCard',
          'Expiration updated: ${_cardState.isExpirationEnabled ? _cardState.expirationDate?.toString() : "disabled"}'
      );

      // Reset retry count on success
      _cardState.resetRetryCount();
    } catch (e) {
      // Revert UI state on error
      if (date != null && previousDate != null) {
        _cardState.setExpirationDate(previousDate);
      } else {
        _cardState.toggleExpiration();
      }

      // Handle error with retry
      _handleOperationError(
          e,
          'update_expiration_date',
              () => _updateExpirationDate(date),
          'Failed to update expiration date'
      );
    }
  }

  /// Schedule reminder for the nudge
  Future<void> _scheduleReminder(DateTime reminderTime, String notes) async {
    _triggerHaptic();

    _cardState.setProcessing(true);

    try {
      // Notify parent
      if (widget.onScheduleReminder != null) {
        await widget.onScheduleReminder!(widget.nudge, reminderTime, notes);
      }

      _cardState.setProcessing(false);

      // Hide reminder options
      _cardState.toggleReminderOptions();

      // Show confirmation message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reminder scheduled for ${_formatDateTime(reminderTime)}'),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      AdvancedLogger.logInfo(
          'NudgeMessageCard',
          'Reminder scheduled: ${reminderTime.toString()}'
      );

      // Reset retry count on success
      _cardState.resetRetryCount();
    } catch (e) {
      // Handle error with retry
      _handleOperationError(
          e,
          'schedule_reminder',
              () => _scheduleReminder(reminderTime, notes),
          'Failed to schedule reminder'
      );
    }
  }

  /// Delete nudge with confirmation
  Future<void> _confirmDelete() async {
    _triggerHaptic();

    try {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Nudge?'),
          content: const Text('Are you sure you want to delete this nudge? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.errorColor,
              ),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await _deleteNudge();
      }
    } catch (e) {
      AdvancedLogger.logError(
          'NudgeMessageCard',
          'Error in delete confirmation: $e'
      );
    }
  }

  /// Confirm sharing of sensitive content
  Future<bool> _confirmSensitiveShare(String method) async {
    try {
      final levelName = _getPrivacyLevelName(_cardState.privacyLevel);

      return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Share ${levelName.toLowerCase()} content?'),
          content: Text(
              'This nudge is marked as $levelName. '
                  'Are you sure you want to share it via $method?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Share Anyway'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.warningColor,
              ),
            ),
          ],
        ),
      ) ?? false;
    } catch (e) {
      AdvancedLogger.logError(
          'NudgeMessageCard',
          'Error in sensitive share confirmation: $e'
      );
      return false;
    }
  }

  /// Delete nudge
  Future<void> _deleteNudge() async {
    _cardState.setProcessing(true);

    try {
      // Notify parent
      if (widget.onDelete != null) {
        await widget.onDelete!(widget.nudge);
      }

      _cardState.setProcessing(false);

      AdvancedLogger.logInfo(
          'NudgeMessageCard',
          'Nudge deleted'
      );

      // Reset retry count on success
      _cardState.resetRetryCount();
    } catch (e) {
      // Handle error with retry
      _handleOperationError(
          e,
          'delete_nudge',
          _deleteNudge,
          'Failed to delete nudge'
      );
    }
  }

  /// Handle operation errors with retry policy
  void _handleOperationError(
      dynamic error,
      String operationType,
      Function operation,
      String userErrorMessage
      ) {
    AdvancedLogger.logError(
        'NudgeMessageCard',
        'Error in operation $operationType: $error'
    );

    _cardState.setProcessing(false);

    // Check if we should retry
    if (widget.retryPolicy != RetryPolicy.none) {
      // For always queue policy, queue the operation
      if (widget.retryPolicy == RetryPolicy.alwaysQueue) {
        _cardState.queueOperation(
            operationType,
            widget.nudge.id,
            {'error': error.toString()}
        );

        // Show queued message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Operation queued for later'),
              backgroundColor: AppTheme.warningColor,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // For other retry policies, attempt retry
      _cardState.retryFailedOperation(widget.retryPolicy, operation);

      // Show retry message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$userErrorMessage - retrying...'),
            backgroundColor: AppTheme.warningColor,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      // No retry, just show error
      _cardState.setSaveError('$userErrorMessage: ${error.toString()}');

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userErrorMessage),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Try Again',
              textColor: Colors.white,
              onPressed: () {
                _cardState.clearError();
                operation();
              },
            ),
          ),
        );
      }
    }
  }

  /// Show more options menu
  void _showMoreOptions() {
    _triggerHaptic();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppTheme.backgroundColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppTheme.borderRadiusMedium),
            topRight: Radius.circular(AppTheme.borderRadiusMedium),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Save as Memory'),
                onTap: () {
                  Navigator.of(context).pop();
                  _saveAsMemory();
                },
              ),
              ListTile(
                leading: const Icon(Icons.security),
                title: const Text('Privacy Settings'),
                onTap: () {
                  Navigator.of(context).pop();
                  _togglePrivacyOptions();
                },
              ),
              if (_hasCaregivers) ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Share with Caregiver'),
                onTap: () {
                  Navigator.of(context).pop();
                  _toggleCaregiverShare();
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(
                  Icons.delete,
                  color: AppTheme.errorColor,
                ),
                title: Text(
                  'Delete',
                  style: TextStyle(
                    color: AppTheme.errorColor,
                  ),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _confirmDelete();
                },
              ),
            ],
          ),
        ),
      ),
    );

    AdvancedLogger.logInfo(
        'NudgeMessageCard',
        'More options opened'
    );
  }

  /// Get color for category
  Color _getCategoryColor() {
    switch (widget.nudge.category.toLowerCase()) {
      case 'health':
        return AppTheme.healthColor;
      case 'memory':
        return AppTheme.memoryColor;
      case 'activity':
        return AppTheme.activityColor;
      case 'social':
        return AppTheme.socialColor;
      case 'medication':
        return AppTheme.medicationColor;
      case 'appointment':
        return AppTheme.appointmentColor;
      case 'important':
        return AppTheme.importantColor;
      default:
        return AppTheme.gentleTeal;
    }
  }

  /// Format timestamp for display
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays == 0) {
      // Today
      return 'Today, ${_formatTime(timestamp)}';
    } else if (difference.inDays == 1) {
      // Yesterday
      return 'Yesterday, ${_formatTime(timestamp)}';
    } else if (difference.inDays < 7) {
      // Within a week
      return '${_getDayOfWeek(timestamp)}, ${_formatTime(timestamp)}';
    } else {
      // Older
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  /// Format time
  String _formatTime(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour < 12 ? 'AM' : 'PM';

    return '$hour:$minute $period';
  }

  /// Format date
  String _formatDate(DateTime date) {
    final day = date.day;
    final month = _getMonthName(date.month);
    final year = date.year;

    return '$day $month $year';
  }

  /// Format date and time
  String _formatDateTime(DateTime dateTime) {
    return '${_formatDate(dateTime)} at ${_formatTime(dateTime)}';
  }

  /// Get day of week name
  String _getDayOfWeek(DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      default:
        return '';
    }
  }

  /// Get month name
  String _getMonthName(int month) {
    switch (month) {
      case 1:
        return 'Jan';
      case 2:
        return 'Feb';
      case 3:
        return 'Mar';
      case 4:
        return 'Apr';
      case 5:
        return 'May';
      case 6:
        return 'Jun';
      case 7:
        return 'Jul';
      case 8:
        return 'Aug';
      case 9:
        return 'Sep';
      case 10:
        return 'Oct';
      case 11:
        return 'Nov';
      case 12:
        return 'Dec';
      default:
        return '';
    }
  }

  /// Get privacy level name
  String _getPrivacyLevelName(PrivacyLevel level) {
    switch (level) {
      case PrivacyLevel.private:
        return 'Private';
      case PrivacyLevel.sensitive:
        return 'Sensitive';
      case PrivacyLevel.medical:
        return 'Medical';
      case PrivacyLevel.temporary:
        return 'Temporary';
      case PrivacyLevel.public:
        return 'Public';
    }
  }

  /// Get privacy level color
  Color _getPrivacyLevelColor(PrivacyLevel level) {
    switch (level) {
      case PrivacyLevel.private:
        return AppTheme.privateColor;
      case PrivacyLevel.sensitive:
        return AppTheme.sensitiveColor;
      case PrivacyLevel.medical:
        return AppTheme.medicalColor;
      case PrivacyLevel.temporary:
        return AppTheme.temporaryColor;
      case PrivacyLevel.public:
        return AppTheme.publicColor;
    }
  }

  /// Get border color based on state
  Color _getBorderColor(_NudgeMessageCardState state) {
    if (state.hasSaveError) {
      return AppTheme.errorColor;
    } else if (state.isRecovering) {
      return AppTheme.warningColor;
    } else if (state.isFavorited) {
      return AppTheme.favoriteColor;
    } else if (!state.isRead) {
      return _getCategoryColor();
    } else {
      return Colors.transparent;
    }
  }

  /// Check if content is expandable
  bool _isContentExpandable() {
    // Only show expand button if content needs it
    // This is a simplification, in a real app you would calculate this
    return widget.nudge.content.length > 100 || widget.nudge.additionalContent != null;
  }

  /// Handle keyboard events for accessibility
  KeyEventResult _handleKeyboard(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.enter) {
        _toggleExpanded();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _cardState,
      child: Consumer<_NudgeMessageCardState>(
        builder: (context, state, _) {
          return Focus(
            focusNode: _cardFocusNode,
            onKeyEvent: _handleKeyboard,
            child: Card(
              key: _cardKey,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                side: BorderSide(
                  color: _getBorderColor(state),
                  width: 1.5,
                ),
              ),
              margin: EdgeInsets.zero,
              color: widget.backgroundColor ?? AppTheme.cardColor,
              child: Stack(
                children: [
                  // Main content
                  Padding(
                    padding: widget.padding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(state),
                        const SizedBox(height: AppTheme.spacingSmall),
                        _buildContent(state),
                        _buildActionButtons(state),
                      ],
                    ),
                  ),

                  // Processing overlay
                  if (state.isProcessing)
                    _buildProcessingOverlay(),

                  // Favorite animation
                  if (state.showFavoriteAnimation)
                    _buildFavoriteAnimation(),

                  // Audio player overlay
                  if (state.isAudioPlayerVisible)
                    _buildAudioPlayerOverlay(),

                  // Share options overlay
                  if (state.isShareOptionsVisible)
                    _buildShareOptionsOverlay(state),

                  // Reminder options overlay
                  if (state.isReminderOptionsVisible)
                    _buildReminderOptionsOverlay(state),

                  // Privacy options overlay
                  if (state.isPrivacyOptionsVisible)
                    _buildPrivacyOptionsOverlay(state),

                  // Caregiver sharing overlay
                  if (state.isCaregiverShareVisible)
                    _buildCaregiverShareOverlay(state),

                  // Expiration indicator
                  if (state.isExpirationEnabled)
                    _buildExpirationIndicator(state),

                  // Privacy level indicator
                  _buildPrivacyLevelIndicator(state),

                  // Queued operations indicator
                  if (state.operationQueue.isNotEmpty)
                    _buildQueuedOperationsIndicator(state),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Build header with title and timestamp
  Widget _buildHeader(_NudgeMessageCardState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category indicator
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _getCategoryColor(),
            shape: BoxShape.circle,
          ),
        ),

        const SizedBox(width: AppTheme.spacingSmall),

        // Title and timestamp
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                widget.nudge.title,
                style: TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  fontSize: widget.enhancedAccessibility ?
                  AppTheme.fontSizeLarge : AppTheme.fontSizeMedium,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textColor,
                ),
              ),

              // Timestamp
              Text(
                _formatTimestamp(widget.nudge.timestamp),
                style: TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  fontSize: widget.enhancedAccessibility ?
                  AppTheme.fontSizeSmall : AppTheme.fontSizeXSmall,
                  color: AppTheme.subtleTextColor,
                ),
              ),
            ],
          ),
        ),

        // Favorite button
        IconButton(
          onPressed: _toggleFavorite,
          icon: Icon(
            state.isFavorited ? Icons.favorite : Icons.favorite_border,
            color: state.isFavorited ? AppTheme.favoriteColor : AppTheme.iconColor,
            size: widget.enhancedAccessibility ? 28.0 : 24.0,
          ),
          tooltip: state.isFavorited ? 'Remove from favorites' : 'Add to favorites',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  /// Build the content section
  Widget _buildContent(_NudgeMessageCardState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Main content
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: state.isExpanded ? double.infinity :
              widget.enhancedAccessibility ? 120.0 : 80.0,
            ),
            child: Text(
              widget.nudge.content,
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: widget.enhancedAccessibility ?
                AppTheme.fontSizeMedium : AppTheme.fontSizeSmall,
                color: AppTheme.textColor,
                height: 1.4,
              ),
              maxLines: state.isExpanded ? null : widget.collapsedLineCount,
              overflow: state.isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
          ),
        ),

        // Show additional content when expanded
        if (state.isExpanded && widget.nudge.additionalContent != null)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacingMedium),
            child: Text(
              widget.nudge.additionalContent!,
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: widget.enhancedAccessibility ?
                AppTheme.fontSizeMedium : AppTheme.fontSizeSmall,
                color: AppTheme.textColor,
                height: 1.4,
              ),
            ),
          ),

        // Error message if any
        if (state.hasSaveError)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacingSmall),
            child: Text(
              state.errorMessage ?? 'An error occurred',
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: widget.enhancedAccessibility ?
                AppTheme.fontSizeSmall : AppTheme.fontSizeXSmall,
                color: AppTheme.errorColor,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),

        // Show expand button if content is expandable
        if (_isContentExpandable())
          TextButton(
            onPressed: _toggleExpanded,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.isExpanded ? 'Show less' : 'Show more',
                  style: TextStyle(
                    fontFamily: AppTheme.primaryFontFamily,
                    fontSize: widget.enhancedAccessibility ?
                    AppTheme.fontSizeSmall : AppTheme.fontSizeXSmall,
                    color: AppTheme.accentColor,
                  ),
                ),
                Icon(
                  state.isExpanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  color: AppTheme.accentColor,
                  size: widget.enhancedAccessibility ? 24.0 : 18.0,
                ),
              ],
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
      ],
    );
  }

  /// Build action buttons
  Widget _buildActionButtons(_NudgeMessageCardState state) {
    final spacing = widget.enhancedAccessibility ?
    AppTheme.spacingMedium : AppTheme.spacingSmall;

    return Padding(
      padding: EdgeInsets.only(top: AppTheme.spacingMedium),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left-side buttons
          Row(
            children: [
              // Audio button (if audio available)
              if (widget.nudge.audioUrl != null)
                _ActionButton(
                  icon: Icons.volume_up,
                  label: 'Audio',
                  onPressed: _showAudioPlayer,
                  isActive: state.isAudioPlayerVisible,
                  enhancedAccessibility: widget.enhancedAccessibility,
                ),

              SizedBox(width: spacing),

              // Reminder button
              _ActionButton(
                icon: Icons.notifications,
                label: 'Reminder',
                onPressed: _toggleReminderOptions,
                isActive: state.isReminderOptionsVisible,
                enhancedAccessibility: widget.enhancedAccessibility,
              ),
            ],
          ),

          // Right-side buttons
          Row(
            children: [
              // Share button
              _ActionButton(
                icon: Icons.share,
                label: 'Share',
                onPressed: _toggleShareOptions,
                isActive: state.isShareOptionsVisible,
                enhancedAccessibility: widget.enhancedAccessibility,
              ),

              SizedBox(width: spacing),

              // Feedback button
              _ActionButton(
                icon: Icons.thumb_up,
                label: 'Feedback',
                onPressed: _showFeedbackDialog,
                enhancedAccessibility: widget.enhancedAccessibility,
              ),

              SizedBox(width: spacing),

              // More options button
              _ActionButton(
                icon: Icons.more_horiz,
                label: 'More',
                onPressed: _showMoreOptions,
                enhancedAccessibility: widget.enhancedAccessibility,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build processing overlay
  Widget _buildProcessingOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: AppTheme.spacingMedium),
              Text(
                'Processing...',
                style: TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  fontSize: widget.enhancedAccessibility ?
                  AppTheme.fontSizeMedium : AppTheme.fontSizeSmall,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build favorite animation
  Widget _buildFavoriteAnimation() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: _cardState.showFavoriteAnimation ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Icon(
              Icons.favorite,
              color: AppTheme.favoriteColor,
              size: 80.0,
            ),
          ),
        ),
      ),
    );
  }

  /// Build share options overlay
  Widget _buildShareOptionsOverlay(_NudgeMessageCardState state) {
    final needsAccessibility = widget.enhancedAccessibility;

    return Positioned.fill(
      child: GestureDetector(
        onTap: _toggleShareOptions, // Close on background tap
        child: Container(
          color: Colors.transparent,
          child: Stack(
            children: [
              // Share options panel
              Positioned(
                bottom: 60,
                left: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () {}, // Prevent taps from passing through
                  child: Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingMedium,
                    ),
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(
                        needsAccessibility ?
                        AppTheme.spacingLarge :
                        AppTheme.spacingMedium,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          Text(
                            'Share via',
                            style: TextStyle(
                              fontFamily: AppTheme.primaryFontFamily,
                              fontSize: needsAccessibility ?
                              AppTheme.fontSizeMedium : AppTheme.fontSizeSmall,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textColor,
                            ),
                          ),

                          const SizedBox(height: AppTheme.spacingSmall),

                          // Share options
                          Wrap(
                            spacing: needsAccessibility ?
                            AppTheme.spacingMedium : AppTheme.spacingSmall,
                            runSpacing: needsAccessibility ?
                            AppTheme.spacingMedium : AppTheme.spacingSmall,
                            children: [
                              _ShareOptionButton(
                                icon: Icons.message,
                                label: 'Message',
                                onPressed: () => _shareNudge('message'),
                                needsAccessibility: needsAccessibility,
                              ),
                              _ShareOptionButton(
                                icon: Icons.email,
                                label: 'Email',
                                onPressed: () => _shareNudge('email'),
                                needsAccessibility: needsAccessibility,
                              ),
                              _ShareOptionButton(
                                icon: Icons.copy,
                                label: 'Copy',
                                onPressed: () => _shareNudge('copy'),
                                needsAccessibility: needsAccessibility,
                              ),
                              if (_hasCaregivers) _ShareOptionButton(
                                icon: Icons.people,
                                label: 'Caregiver',
                                onPressed: _toggleCaregiverShare,
                                needsAccessibility: needsAccessibility,
                              ),
                            ],
                          ),

                          const SizedBox(height: AppTheme.spacingMedium),

                          // Privacy note
                          if (state.privacyLevel != PrivacyLevel.public)
                            Container(
                              padding: const EdgeInsets.all(AppTheme.spacingSmall),
                              decoration: BoxDecoration(
                                color: _getPrivacyLevelColor(state.privacyLevel).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
                                border: Border.all(
                                  color: _getPrivacyLevelColor(state.privacyLevel),
                                  width: 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.warning,
                                    color: _getPrivacyLevelColor(state.privacyLevel),
                                    size: needsAccessibility ? 24.0 : 16.0,
                                  ),
                                  const SizedBox(width: AppTheme.spacingSmall),
                                  Expanded(
                                    child: Text(
                                      'This content is marked as ${_getPrivacyLevelName(state.privacyLevel).toLowerCase()}. ' +
                                          'Be careful when sharing.',
                                      style: TextStyle(
                                        fontFamily: AppTheme.primaryFontFamily,
                                        fontSize: needsAccessibility ?
                                        AppTheme.fontSizeSmall : AppTheme.fontSizeXSmall,
                                        color: AppTheme.textColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build reminder options overlay
  Widget _buildReminderOptionsOverlay(_NudgeMessageCardState state) {
    final needsAccessibility = widget.enhancedAccessibility;

    return Positioned.fill(
      child: GestureDetector(
        onTap: _toggleReminderOptions, // Close on background tap
        child: Container(
          color: Colors.transparent,
          child: Stack(
            children: [
              // Reminder options panel
              Positioned(
                bottom: 60,
                left: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () {}, // Prevent taps from passing through
                  child: Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingMedium,
                    ),
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(
                        needsAccessibility ?
                        AppTheme.spacingLarge :
                        AppTheme.spacingMedium,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          Text(
                            'Set Reminder',
                            style: TextStyle(
                              fontFamily: AppTheme.primaryFontFamily,
                              fontSize: needsAccessibility ?
                              AppTheme.fontSizeMedium : AppTheme.fontSizeSmall,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textColor,
                            ),
                          ),

                          const SizedBox(height: AppTheme.spacingMedium),

                          // Quick reminder options
                          Text(
                            'Quick options:',
                            style: TextStyle(
                              fontFamily: AppTheme.primaryFontFamily,
                              fontSize: needsAccessibility ?
                              AppTheme.fontSizeSmall : AppTheme.fontSizeXSmall,
                              color: AppTheme.subtleTextColor,
                            ),
                          ),

                          const SizedBox(height: AppTheme.spacingSmall),

                          // Quick option buttons
                          Wrap(
                            spacing: needsAccessibility ?
                            AppTheme.spacingMedium : AppTheme.spacingSmall,
                            runSpacing: needsAccessibility ?
                            AppTheme.spacingMedium : AppTheme.spacingSmall,
                            children: [
                              _ReminderChip(
                                label: 'Tomorrow',
                                onPressed: () => _scheduleReminder(
                                  DateTime.now().add(const Duration(days: 1)),
                                  'Reminder from nudge: ${widget.nudge.title}',
                                ),
                                needsAccessibility: needsAccessibility,
                              ),
                              _ReminderChip(
                                label: 'Next week',
                                onPressed: () => _scheduleReminder(
                                  DateTime.now().add(const Duration(days: 7)),
                                  'Reminder from nudge: ${widget.nudge.title}',
                                ),
                                needsAccessibility: needsAccessibility,
                              ),
                              _ReminderChip(
                                label: 'Custom',
                                onPressed: _showCustomReminderPicker,
                                needsAccessibility: needsAccessibility,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show custom reminder picker
  Future<void> _showCustomReminderPicker() async {
    _triggerHaptic();

    // Hide reminder options
    _cardState.toggleReminderOptions();

    try {
      // Show date picker
      final date = await showDatePicker(
        context: context,
        initialDate: DateTime.now().add(const Duration(days: 1)),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              dialogBackgroundColor: AppTheme.backgroundColor,
              colorScheme: ColorScheme.light(
                primary: AppTheme.accentColor,
                onPrimary: Colors.white,
                surface: AppTheme.backgroundColor,
                onSurface: AppTheme.textColor,
              ),
            ),
            child: child!,
          );
        },
      );

      if (date == null) return;

      // Show time picker
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              dialogBackgroundColor: AppTheme.backgroundColor,
              colorScheme: ColorScheme.light(
                primary: AppTheme.accentColor,
                onPrimary: Colors.white,
                surface: AppTheme.backgroundColor,
                onSurface: AppTheme.textColor,
              ),
            ),
            child: child!,
          );
        },
      );

      if (time == null) return;

      // Combine date and time
      final reminderDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );

      // Show notes dialog
      final notes = await _showReminderNotesDialog();

      if (notes != null) {
        await _scheduleReminder(
          reminderDateTime,
          notes,
        );
      }
    } catch (e) {
      AdvancedLogger.logError(
          'NudgeMessageCard',
          'Error in custom reminder picker: $e'
      );

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to set reminder'),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Show reminder notes dialog
  Future<String?> _showReminderNotesDialog() async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Notes'),
        content: TextField(
          maxLines: 3,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
            ),
            hintText: 'Optional notes for this reminder',
          ),
          controller: TextEditingController(
            text: 'Reminder for: ${widget.nudge.title}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final controller = ModalRoute.of(context)!
                  .findRenderObject() as RenderBox;
              final textField = controller
                  .descendant(of: controller, matching: (renderObject) =>
                  renderObject.runtimeType.toString().contains('RenderEditable'))
              as RenderEditable;

              Navigator.of(context).pop(textField.text?.toPlainText() ?? '');
            },
            child: const Text('Set Reminder'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.accentColor,
            ),
          ),
        ],
      ),
    );
  }

  /// Build privacy options overlay
  Widget _buildPrivacyOptionsOverlay(_NudgeMessageCardState state) {
    final needsAccessibility = widget.enhancedAccessibility;

    return Positioned.fill(
      child: GestureDetector(
        onTap: _togglePrivacyOptions, // Close on background tap
        child: Container(
          color: Colors.transparent,
          child: Stack(
            children: [
              // Privacy options panel
              Positioned(
                bottom: 60,
                left: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () {}, // Prevent taps from passing through
                  child: Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingMedium,
                    ),
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(
                        needsAccessibility ?
                        AppTheme.spacingLarge :
                        AppTheme.spacingMedium,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          Text(
                            'Privacy Settings',
                            style: TextStyle(
                              fontFamily: AppTheme.primaryFontFamily,
                              fontSize: needsAccessibility ?
                              AppTheme.fontSizeMedium : AppTheme.fontSizeSmall,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textColor,
                            ),
                          ),

                          const SizedBox(height: AppTheme.spacingMedium),

                          // Privacy levels
                          Text(
                            'Privacy level:',
                            style: TextStyle(
                              fontFamily: AppTheme.primaryFontFamily,
                              fontSize: needsAccessibility ?
                              AppTheme.fontSizeSmall : AppTheme.fontSizeXSmall,
                              color: AppTheme.subtleTextColor,
                            ),
                          ),

                          const SizedBox(height: AppTheme.spacingSmall),

                          // Privacy level options
                          Wrap(
                            spacing: needsAccessibility ?
                            AppTheme.spacingMedium : AppTheme.spacingSmall,
                            runSpacing: needsAccessibility ?
                            AppTheme.spacingMedium : AppTheme.spacingSmall,
                            children: [
                              _PrivacyLevelChip(
                                label: 'Public',
                                isSelected: state.privacyLevel == PrivacyLevel.public,
                                color: AppTheme.publicColor,
                                onPressed: () => _updatePrivacyLevel(PrivacyLevel.public),
                                needsAccessibility: needsAccessibility,
                              ),
                              _PrivacyLevelChip(
                                label: 'Private',
                                isSelected: state.privacyLevel == PrivacyLevel.private,
                                color: AppTheme.privateColor,
                                onPressed: () => _updatePrivacyLevel(PrivacyLevel.private),
                                needsAccessibility: needsAccessibility,
                              ),
                              _PrivacyLevelChip(
                                label: 'Sensitive',
                                isSelected: state.privacyLevel == PrivacyLevel.sensitive,
                                color: AppTheme.sensitiveColor,
                                onPressed: () => _updatePrivacyLevel(PrivacyLevel.sensitive),
                                needsAccessibility: needsAccessibility,
                              ),
                              _PrivacyLevelChip(
                                label: 'Medical',
                                isSelected: state.privacyLevel == PrivacyLevel.medical,
                                color: AppTheme.medicalColor,
                                onPressed: () => _updatePrivacyLevel(PrivacyLevel.medical),
                                needsAccessibility: needsAccessibility,
                              ),
                            ],
                          ),

                          const SizedBox(height: AppTheme.spacingMedium),

                          // Expiration options
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Content expiration:',
                                  style: TextStyle(
                                    fontFamily: AppTheme.primaryFontFamily,
                                    fontSize: needsAccessibility ?
                                    AppTheme.fontSizeSmall : AppTheme.fontSizeXSmall,
                                    color: AppTheme.subtleTextColor,
                                  ),
                                ),
                              ),
                              Switch(
                                value: state.isExpirationEnabled,
                                onChanged: (value) => _updateExpirationDate(null),
                                activeColor: AppTheme.accentColor,
                              ),
                            ],
                          ),

                          // Expiration date picker
                          if (state.isExpirationEnabled)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(AppTheme.spacingSmall),
                              decoration: BoxDecoration(
                                color: AppTheme.cardColor,
                                borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
                                border: Border.all(
                                  color: AppTheme.borderColor,
                                  width: 1.0,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Expires on:',
                                    style: TextStyle(
                                      fontFamily: AppTheme.primaryFontFamily,
                                      fontSize: needsAccessibility ?
                                      AppTheme.fontSizeXSmall : AppTheme.fontSizeXXSmall,
                                      color: AppTheme.subtleTextColor,
                                    ),
                                  ),

                                  const SizedBox(height: AppTheme.spacingXSmall),

                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          state.expirationDate != null ?
                                          _formatDate(state.expirationDate!) :
                                          'Not set',
                                          style: TextStyle(
                                            fontFamily: AppTheme.primaryFontFamily,
                                            fontSize: needsAccessibility ?
                                            AppTheme.fontSizeSmall : AppTheme.fontSizeXSmall,
                                            color: AppTheme.textColor,
                                          ),
                                        ),
                                      ),

                                      TextButton(
                                        onPressed: _showExpirationDatePicker,
                                        child: Text(
                                          'Change',
                                          style: TextStyle(
                                            fontFamily: AppTheme.primaryFontFamily,
                                            fontSize: needsAccessibility ?
                                            AppTheme.fontSizeXSmall : AppTheme.fontSizeXXSmall,
                                            color: AppTheme.accentColor,
                                          ),
                                        ),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: AppTheme.spacingSmall,
                                            vertical: AppTheme.spacingXSmall,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                          const SizedBox(height: AppTheme.spacingMedium),

                          // Privacy explanation
                          Container(
                            padding: const EdgeInsets.all(AppTheme.spacingSmall),
                            decoration: BoxDecoration(
                              color: AppTheme.infoColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
                              border: Border.all(
                                color: AppTheme.infoColor,
                                width: 1.0,
                              ),
                            ),
                            child: Text(
                              'Privacy levels control how content is shared. ' +
                                  'Expiration automatically removes content after the set date.',
                              style: TextStyle(
                                fontFamily: AppTheme.primaryFontFamily,
                                fontSize: needsAccessibility ?
                                AppTheme.fontSizeXSmall : AppTheme.fontSizeXXSmall,
                                color: AppTheme.textColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show expiration date picker
  Future<void> _showExpirationDatePicker() async {
    _triggerHaptic();

    try {
      // Default to 30 days from now if not set
      final initialDate = _cardState.expirationDate ??
          DateTime.now().add(const Duration(days: 30));

      // Show date picker
      final date = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              dialogBackgroundColor: AppTheme.backgroundColor,
              colorScheme: ColorScheme.light(
                primary: AppTheme.accentColor,
                onPrimary: Colors.white,
                surface: AppTheme.backgroundColor,
                onSurface: AppTheme.textColor,
              ),
            ),
            child: child!,
          );
        },
      );

      if (date != null) {
        _updateExpirationDate(date);
      }
    } catch (e) {
      AdvancedLogger.logError(
          'NudgeMessageCard',
          'Error in expiration date picker: $e'
      );
    }
  }

  /// Build caregiver share overlay
  Widget _buildCaregiverShareOverlay(_NudgeMessageCardState state) {
    final needsAccessibility = widget.enhancedAccessibility;

    return Positioned.fill(
      child: GestureDetector(
        onTap: _toggleCaregiverShare, // Close on background tap
        child: Container(
          color: Colors.transparent,
          child: Stack(
            children: [
              // Caregiver share panel
              Positioned(
                bottom: 60,
                left: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () {}, // Prevent taps from passing through
                  child: Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingMedium,
                    ),
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(
                        needsAccessibility ?
                        AppTheme.spacingLarge :
                        AppTheme.spacingMedium,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          Text(
                            'Share with Caregiver',
                            style: TextStyle(
                              fontFamily: AppTheme.primaryFontFamily,
                              fontSize: needsAccessibility ?
                              AppTheme.fontSizeMedium : AppTheme.fontSizeSmall,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textColor,
                            ),
                          ),

                          const SizedBox(height: AppTheme.spacingMedium),

                          // Get caregivers from service
                          FutureBuilder<List<Map<String, dynamic>>>(
                            future: Provider.of<CaregiverService>(context, listen: false).getCaregivers(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              if (snapshot.hasError) {
                                return Center(
                                  child: Text(
                                    'Error loading caregivers',
                                    style: TextStyle(
                                      fontFamily: AppTheme.primaryFontFamily,
                                      fontSize: needsAccessibility ?
                                      AppTheme.fontSizeSmall : AppTheme.fontSizeXSmall,
                                      color: AppTheme.errorColor,
                                    ),
                                  ),
                                );
                              }

                              final caregivers = snapshot.data ?? [];

                              if (caregivers.isEmpty) {
                                return Center(
                                  child: Text(
                                    'No caregivers found',
                                    style: TextStyle(
                                      fontFamily: AppTheme.primaryFontFamily,
                                      fontSize: needsAccessibility ?
                                      AppTheme.fontSizeSmall : AppTheme.fontSizeXSmall,
                                      color: AppTheme.subtleTextColor,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                );
                              }

                              return Column(
                                children: caregivers.map((caregiver) => Padding(
                                  padding: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
                                  child: _CaregiverItem(
                                    name: caregiver['name'] as String,
                                    role: caregiver['role'] as String,
                                    onPressed: () => _shareWithCaregiver(caregiver['id'] as String),
                                    needsAccessibility: needsAccessibility,
                                  ),
                                )).toList(),
                              );
                            },
                          ),

                          const SizedBox(height: AppTheme.spacingMedium),

                          // Privacy note
                          if (state.privacyLevel != PrivacyLevel.public)
                            Container(
                              padding: const EdgeInsets.all(AppTheme.spacingSmall),
                              decoration: BoxDecoration(
                                color: _getPrivacyLevelColor(state.privacyLevel).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
                                border: Border.all(
                                  color: _getPrivacyLevelColor(state.privacyLevel),
                                  width: 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info,
                                    color: _getPrivacyLevelColor(state.privacyLevel),
                                    size: needsAccessibility ? 24.0 : 16.0,
                                  ),
                                  const SizedBox(width: AppTheme.spacingSmall),
                                  Expanded(
                                    child: Text(
                                      'This content is marked as ${_getPrivacyLevelName(state.privacyLevel).toLowerCase()}. ' +
                                          'Caregivers will be notified of this privacy level.',
                                      style: TextStyle(
                                        fontFamily: AppTheme.primaryFontFamily,
                                        fontSize: needsAccessibility ?
                                        AppTheme.fontSizeSmall : AppTheme.fontSizeXSmall,
                                        color: AppTheme.textColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build expiration indicator
  Widget _buildExpirationIndicator(_NudgeMessageCardState state) {
    if (state.expirationDate == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final daysUntilExpiration = state.expirationDate!.difference(now).inDays;

    // Color based on how close to expiration
    Color indicatorColor;
    if (daysUntilExpiration <= 0) {
      indicatorColor = AppTheme.errorColor;
    } else if (daysUntilExpiration <= 7) {
      indicatorColor = AppTheme.warningColor;
    } else {
      indicatorColor = AppTheme.temporaryColor;
    }

    return Positioned(
      top: 8,
      right: 8,
      child: GestureDetector(
        onTap: _togglePrivacyOptions,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 6.0,
            vertical: 2.0,
          ),
          decoration: BoxDecoration(
            color: indicatorColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
            border: Border.all(
              color: indicatorColor,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer,
                color: indicatorColor,
                size: 12.0,
              ),
              const SizedBox(width: 2.0),
              Text(
                daysUntilExpiration <= 0 ?
                'Expired' :
                '$daysUntilExpiration ${daysUntilExpiration == 1 ? 'day' : 'days'}',
                style: TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  fontSize: AppTheme.fontSizeXXSmall,
                  color: indicatorColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build privacy level indicator
  Widget _buildPrivacyLevelIndicator(_NudgeMessageCardState state) {
    if (state.privacyLevel == PrivacyLevel.public) return const SizedBox.shrink();

    return Positioned(
      top: 8,
      left: 8,
      child: GestureDetector(
        onTap: _togglePrivacyOptions,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 6.0,
            vertical: 2.0,
          ),
          decoration: BoxDecoration(
            color: _getPrivacyLevelColor(state.privacyLevel).withOpacity(0.2),
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
            border: Border.all(
              color: _getPrivacyLevelColor(state.privacyLevel),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock,
                color: _getPrivacyLevelColor(state.privacyLevel),
                size: 12.0,
              ),
              const SizedBox(width: 2.0),
              Text(
                _getPrivacyLevelName(state.privacyLevel),
                style: TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  fontSize: AppTheme.fontSizeXXSmall,
                  color: _getPrivacyLevelColor(state.privacyLevel),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build queued operations indicator
  Widget _buildQueuedOperationsIndicator(_NudgeMessageCardState state) {
    return Positioned(
      bottom: 8,
      right: 8,
      child: GestureDetector(
        onTap: () {
          // Process queued operations
          _cardState._processQueuedOperations();
        },
        child: Container(
          padding: const EdgeInsets.all(4.0),
          decoration: BoxDecoration(
            color: AppTheme.accentColor,
            shape: BoxShape.circle,
          ),
          child: Text(
            state.operationQueue.length.toString(),
            style: TextStyle(
              fontFamily: AppTheme.primaryFontFamily,
              fontSize: AppTheme.fontSizeXXSmall,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

/// Action button for nudge message card
class _ActionButton extends StatelessWidget {
  /// Icon to display
  final IconData icon;

  /// Label for the button
  final String label;

  /// Callback when pressed
  final VoidCallback onPressed;

  /// Whether the button is active
  final bool isActive;

  /// Whether to use enhanced accessibility
  final bool enhancedAccessibility;

  /// Creates an action button.
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isActive = false,
    this.enhancedAccessibility = false,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Icon button
        IconButton(
          onPressed: onPressed,
          icon: Icon(
            icon,
            color: isActive ? AppTheme.accentColor : AppTheme.iconColor,
            size: enhancedAccessibility ? 28.0 : 24.0,
          ),
          padding: EdgeInsets.all(enhancedAccessibility ? 8.0 : 4.0),
          constraints: const BoxConstraints(),
          tooltip: label,
        ),

        // Label
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTheme.primaryFontFamily,
            fontSize: enhancedAccessibility ?
            AppTheme.fontSizeXSmall : AppTheme.fontSizeXXSmall,
            color: isActive ? AppTheme.accentColor : AppTheme.subtleTextColor,
          ),
        ),
      ],
    );
  }
}

/// Share option button for share options overlay
class _ShareOptionButton extends StatelessWidget {
  /// Icon to display
  final IconData icon;

  /// Label for the button
  final String label;

  /// Callback when pressed
  final VoidCallback onPressed;

  /// Whether to use enhanced accessibility
  final bool needsAccessibility;

  /// Creates a share option button.
  const _ShareOptionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.needsAccessibility = false,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final size = needsAccessibility ? 80.0 : 60.0;

    return SizedBox(
      width: size,
      height: size,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
          ),
          backgroundColor: AppTheme.cardColor,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: AppTheme.accentColor,
              size: needsAccessibility ? 32.0 : 24.0,
            ),
            const SizedBox(height: 4.0),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: needsAccessibility ?
                AppTheme.fontSizeXSmall : AppTheme.fontSizeXXSmall,
                color: AppTheme.textColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Reminder chip for reminder options overlay
class _ReminderChip extends StatelessWidget {
  /// Label for the chip
  final String label;

  /// Callback when pressed
  final VoidCallback onPressed;

  /// Whether to use enhanced accessibility
  final bool needsAccessibility;

  /// Creates a reminder chip.
  const _ReminderChip({
    required this.label,
    required this.onPressed,
    this.needsAccessibility = false,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.primaryFontFamily,
          fontSize: needsAccessibility ?
          AppTheme.fontSizeSmall : AppTheme.fontSizeXSmall,
          color: AppTheme.textColor,
        ),
      ),
      backgroundColor: AppTheme.cardColor,
      onPressed: onPressed,
      padding: EdgeInsets.symmetric(
        horizontal: needsAccessibility ? 12.0 : 8.0,
        vertical: needsAccessibility ? 8.0 : 4.0,
      ),
    );
  }
}

/// Privacy level chip for privacy options overlay
class _PrivacyLevelChip extends StatelessWidget {
  /// Label for the chip
  final String label;

  /// Whether the chip is selected
  final bool isSelected;

  /// Color for the chip
  final Color color;

  /// Callback when pressed
  final VoidCallback onPressed;

  /// Whether to use enhanced accessibility
  final bool needsAccessibility;

  /// Creates a privacy level chip.
  const _PrivacyLevelChip({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onPressed,
    this.needsAccessibility = false,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.primaryFontFamily,
          fontSize: needsAccessibility ?
          AppTheme.fontSizeSmall : AppTheme.fontSizeXSmall,
          color: isSelected ? Colors.white : AppTheme.textColor,
        ),
      ),
      selected: isSelected,
      onSelected: (_) => onPressed(),
      backgroundColor: AppTheme.cardColor,
      selectedColor: color,
      padding: EdgeInsets.symmetric(
        horizontal: needsAccessibility ? 12.0 : 8.0,
        vertical: needsAccessibility ? 8.0 : 4.0,
      ),
    );
  }
}

/// Caregiver item for caregiver share overlay
class _CaregiverItem extends StatelessWidget {
  /// Name of the caregiver
  final String name;

  /// Role of the caregiver
  final String role;

  /// Callback when pressed
  final VoidCallback onPressed;

  /// Whether to use enhanced accessibility
  final bool needsAccessibility;

  /// Creates a caregiver item.
  const _CaregiverItem({
    required this.name,
    required this.role,
    required this.onPressed,
    this.needsAccessibility = false,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMedium,
            vertical: needsAccessibility ?
            AppTheme.spacingMedium : AppTheme.spacingSmall,
          ),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                backgroundColor: AppTheme.accentColor.withOpacity(0.2),
                child: Text(
                  name.substring(0, 1),
                  style: TextStyle(
                    fontFamily: AppTheme.primaryFontFamily,
                    fontSize: needsAccessibility ?
                    AppTheme.fontSizeMedium : AppTheme.fontSizeSmall,
                    color: AppTheme.accentColor,
                  ),
                ),
                radius: needsAccessibility ? 24.0 : 20.0,
              ),

              const SizedBox(width: AppTheme.spacingMedium),

              // Name and role
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontFamily: AppTheme.primaryFontFamily,
                        fontSize: needsAccessibility ?
                        AppTheme.fontSizeMedium : AppTheme.fontSizeSmall,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textColor,
                      ),
                    ),

                    Text(
                      role,
                      style: TextStyle(
                        fontFamily: AppTheme.primaryFontFamily,
                        fontSize: needsAccessibility ?
                        AppTheme.fontSizeSmall : AppTheme.fontSizeXSmall,
                        color: AppTheme.subtleTextColor,
                      ),
                    ),
                  ],
                ),
              ),

              // Share icon
              Icon(
                Icons.send,
                color: AppTheme.accentColor,
                size: needsAccessibility ? 28.0 : 24.0,
              ),
            ],
          ),
        ),
      ),
    );
  }
}