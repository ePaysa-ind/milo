// Copyright © 2025 Milo App. All rights reserved.
// Author: Milo Development Team
// File: lib/widgets/audio/nudge_feedback_dialog.dart
// Version: 1.1.0
// Last Updated: April 23, 2025
// Description: Dialog for collecting user feedback about nudges, optimized for elderly users (55+)
// Change History:
// - 1.0.0: Initial implementation
// - 1.1.0: Added improved error handling, performance optimization, enhanced responsiveness,
//          usability improvements, better code structure, and analytics integration

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/nudge_model.dart';
import '../../services/analytics_service.dart';
import '../../services/nudge_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/advanced_logger.dart';

/// Data class to hold feedback information
///
/// This class encapsulates all data related to user feedback for nudges
/// and provides helper methods for creating and modifying feedback objects.
class FeedbackData {
  /// Whether the nudge was helpful (true) or not (false)
  final bool wasHelpful;

  /// Optional detailed feedback text
  final String? detailedFeedback;

  /// Rating from 1-5 stars
  final int? rating;

  /// Additional emotion tags selected by the user
  final List<String>? emotionTags;

  /// Timestamp when feedback was submitted
  final DateTime timestamp;

  /// Creates a feedback data object with the provided values
  ///
  /// [wasHelpful] indicates if the user found the nudge helpful
  /// [detailedFeedback] contains optional text feedback
  /// [rating] is the star rating from 1-5
  /// [emotionTags] is a list of emotion tags selected by the user
  /// [timestamp] is when the feedback was created (defaults to now)
  FeedbackData({
    required this.wasHelpful,
    this.detailedFeedback,
    this.rating,
    this.emotionTags,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Creates a copy of this object with some fields replaced
  ///
  /// This method allows for immutable updates of the feedback data
  /// by creating a new instance with updated values.
  FeedbackData copyWith({
    bool? wasHelpful,
    String? detailedFeedback,
    int? rating,
    List<String>? emotionTags,
    DateTime? timestamp,
  }) {
    return FeedbackData(
      wasHelpful: wasHelpful ?? this.wasHelpful,
      detailedFeedback: detailedFeedback ?? this.detailedFeedback,
      rating: rating ?? this.rating,
      emotionTags: emotionTags ?? this.emotionTags,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Validates the feedback data
  ///
  /// Returns a map of field names to error messages,
  /// or an empty map if the data is valid.
  Map<String, String> validate() {
    final errors = <String, String>{};

    if (rating != null && (rating! < 1 || rating! > 5)) {
      errors['rating'] = 'Rating must be between 1 and 5';
    }

    if (detailedFeedback != null && detailedFeedback!.length > 500) {
      errors['detailedFeedback'] = 'Feedback must be 500 characters or less';
    }

    return errors;
  }

  /// Checks if this feedback contains substantial content
  ///
  /// Returns true if the user provided more than just the helpful flag
  bool get hasSubstantialFeedback =>
      rating != null ||
          (detailedFeedback != null && detailedFeedback!.isNotEmpty) ||
          (emotionTags != null && emotionTags!.isNotEmpty);
}

/// A dialog that collects feedback about nudges from users
///
/// This widget presents a comprehensive feedback collection interface
/// optimized for elderly users with accessibility features and clear
/// visual design.
class NudgeFeedbackDialog extends StatefulWidget {
  /// The nudge to collect feedback for
  final NudgeDelivery nudge;

  /// Optional callback when feedback is submitted
  final Function(NudgeDelivery, FeedbackData)? onFeedbackSubmitted;

  /// Optional callback when dialog is dismissed without submitting
  final VoidCallback? onDismissed;

  /// Whether to enable haptic feedback on interactions
  final bool enableHaptics;

  /// Whether to use larger text and controls for better accessibility
  final bool enhancedAccessibility;

  /// Whether to show analytics consent message
  final bool showAnalyticsConsent;

  /// Whether to enable test mode for automated testing
  final bool testMode;

  /// Creates a dialog for collecting nudge feedback.
  ///
  /// The [nudge] parameter is required and specifies the nudge to collect feedback for.
  ///
  /// The [onFeedbackSubmitted] parameter is called when the user submits feedback.
  ///
  /// The [onDismissed] parameter is called when the dialog is dismissed without
  /// submitting feedback.
  ///
  /// The [enableHaptics] parameter determines if haptic feedback should be used
  /// for interactions. Defaults to true.
  ///
  /// The [enhancedAccessibility] parameter determines if larger text and controls
  /// should be used for better accessibility. Defaults to false.
  ///
  /// The [showAnalyticsConsent] parameter determines if a message about how
  /// feedback data will be used should be displayed. Defaults to true.
  ///
  /// The [testMode] parameter enables a predictable state for automated testing.
  /// Defaults to false.
  const NudgeFeedbackDialog({
    required this.nudge,
    this.onFeedbackSubmitted,
    this.onDismissed,
    this.enableHaptics = true,
    this.enhancedAccessibility = false,
    this.showAnalyticsConsent = true,
    this.testMode = false,
    Key? key,
  }) : super(key: key);

  @override
  State<NudgeFeedbackDialog> createState() => _NudgeFeedbackDialogState();
}

class _NudgeFeedbackDialogState extends State<NudgeFeedbackDialog> {
  // State management approach for better performance
  // Using a ChangeNotifier to avoid rebuilding the entire dialog
  late _FeedbackDialogState _dialogState;

  // Controller for detecting orientation changes
  late OrientationController _orientationController;

  @override
  void initState() {
    super.initState();

    // Initialize dialog state
    _dialogState = _FeedbackDialogState(
      initialWasHelpful: widget.testMode ? true : null,
      initialRating: widget.testMode ? 3 : null,
    );

    // Initialize orientation controller
    _orientationController = OrientationController();

    // Log dialog open for analytics
    _logAnalyticsEvent('nudge_feedback_dialog_opened', {
      'nudge_id': widget.nudge.id,
      'nudge_type': widget.nudge.type,
      'screen': _getCurrentRouteName(),
    });
  }

  @override
  void dispose() {
    _dialogState.dispose();
    _orientationController.dispose();
    super.dispose();
  }

  // Get current route name for analytics
  String _getCurrentRouteName() {
    try {
      final route = ModalRoute.of(context);
      return route?.settings.name ?? 'unknown';
    } catch (e) {
      return 'unknown';
    }
  }

  // Log analytics events
  void _logAnalyticsEvent(String eventName, Map<String, dynamic> parameters) {
    try {
      AnalyticsService.logEvent(eventName, parameters);
    } catch (e) {
      AdvancedLogger.logError(
          'NudgeFeedbackDialog',
          'Failed to log analytics event: $e'
      );
    }
  }

  // Handle back button press
  Future<bool> _onWillPop() async {
    // Only show confirmation if user has entered substantial feedback
    if (_dialogState.feedbackData.hasSubstantialFeedback) {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => _buildExitConfirmationDialog(),
      );

      // Log the result for analytics
      _logAnalyticsEvent('nudge_feedback_exit_confirmation', {
        'nudge_id': widget.nudge.id,
        'result': result == true ? 'confirmed' : 'cancelled',
      });

      return result ?? false;
    }

    // If no substantial feedback, just dismiss
    if (widget.onDismissed != null) {
      widget.onDismissed!();
    }

    _logAnalyticsEvent('nudge_feedback_dialog_dismissed', {
      'nudge_id': widget.nudge.id,
    });

    return true;
  }

  // Build exit confirmation dialog
  Widget _buildExitConfirmationDialog() {
    return AlertDialog(
      title: const Text('Discard Feedback?'),
      content: const Text(
          'You have entered feedback that will be lost if you exit. '
              'Are you sure you want to discard your feedback?'
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep Editing'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Discard'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: AnimatedBuilder(
        animation: _dialogState,
        builder: (context, _) {
          return OrientationBuilder(
            builder: (context, orientation) {
              _orientationController.updateOrientation(orientation);

              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                ),
                elevation: 8.0,
                backgroundColor: AppTheme.cardColor,
                insetPadding: _getInsetPadding(orientation),
                child: _buildDialogContent(orientation),
              );
            },
          );
        },
      ),
    );
  }

  // Get adaptive inset padding based on orientation
  EdgeInsets _getInsetPadding(Orientation orientation) {
    final size = MediaQuery.of(context).size;

    if (orientation == Orientation.landscape) {
      return EdgeInsets.symmetric(
        horizontal: size.width * 0.2,
        vertical: size.height * 0.05,
      );
    } else {
      return EdgeInsets.symmetric(
        horizontal: size.width * 0.08,
        vertical: size.height * 0.05,
      );
    }
  }

  // Build main dialog content with orientation awareness
  Widget _buildDialogContent(Orientation orientation) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 360;
    final needsAccessibility = widget.enhancedAccessibility || isSmallScreen;

    // Adjust for landscape mode
    final isLandscape = orientation == Orientation.landscape;

    // Calculate dialog constraints
    final maxWidth = isLandscape
        ? screenSize.width * 0.8
        : screenSize.width * 0.95;
    final maxHeight = isLandscape
        ? screenSize.height * 0.95
        : screenSize.height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
      child: isLandscape
          ? _buildLandscapeLayout(needsAccessibility)
          : _buildPortraitLayout(needsAccessibility),
    );
  }

  // Build portrait layout
  Widget _buildPortraitLayout(bool needsAccessibility) {
    return SingleChildScrollView(
      key: const Key('portrait_layout'),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(needsAccessibility),
            const SizedBox(height: AppTheme.spacingMedium),
            _buildNudgePreview(needsAccessibility),
            const SizedBox(height: AppTheme.spacingMedium),
            _buildFeedbackControls(needsAccessibility),
            const SizedBox(height: AppTheme.spacingMedium),
            _buildActionButtons(needsAccessibility),
          ],
        ),
      ),
    );
  }

  // Build landscape layout
  Widget _buildLandscapeLayout(bool needsAccessibility) {
    return SingleChildScrollView(
      key: const Key('landscape_layout'),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(needsAccessibility),
                  const SizedBox(height: AppTheme.spacingMedium),
                  _buildNudgePreview(needsAccessibility),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.spacingMedium),
            Expanded(
              flex: 4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildFeedbackControls(needsAccessibility),
                  const SizedBox(height: AppTheme.spacingMedium),
                  _buildActionButtons(needsAccessibility),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build header with title and close button
  Widget _buildHeader(bool needsAccessibility) {
    final titleFontSize = needsAccessibility
        ? AppTheme.fontSizeXLarge
        : AppTheme.fontSizeLarge;

    return Row(
      children: [
        Expanded(
          child: Text(
            'How was this nudge?',
            style: TextStyle(
              fontFamily: AppTheme.primaryFontFamily,
              fontSize: titleFontSize,
              fontWeight: FontWeight.bold,
              color: AppTheme.textColor,
            ),
            semanticsLabel: 'Feedback form for nudge',
          ),
        ),
        IconButton(
          key: const Key('close_button'),
          icon: const Icon(Icons.close),
          onPressed: () => _onWillPop().then((canPop) {
            if (canPop) Navigator.of(context).pop();
          }),
          tooltip: 'Close',
          iconSize: AppTheme.iconSizeSmall,
          padding: const EdgeInsets.all(8.0),
          constraints: const BoxConstraints(
            minWidth: AppTheme.touchTargetMinSize,
            minHeight: AppTheme.touchTargetMinSize,
          ),
        ),
      ],
    );
  }

  // Build nudge content preview
  Widget _buildNudgePreview(bool needsAccessibility) {
    final bodyFontSize = needsAccessibility
        ? AppTheme.fontSizeMedium
        : AppTheme.fontSizeSmall;

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingSmall),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
        border: Border.all(
          color: AppTheme.dividerColor,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nudge content:',
            style: TextStyle(
              fontFamily: AppTheme.primaryFontFamily,
              fontSize: bodyFontSize * 0.9,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.nudge.content,
            style: TextStyle(
              fontFamily: AppTheme.primaryFontFamily,
              fontSize: bodyFontSize,
              fontWeight: FontWeight.w500,
              color: AppTheme.textColor,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  // Build all feedback controls
  Widget _buildFeedbackControls(bool needsAccessibility) {
    final bodyFontSize = needsAccessibility
        ? AppTheme.fontSizeMedium
        : AppTheme.fontSizeSmall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Was this helpful section
        Text(
          'Was this helpful?',
          style: TextStyle(
            fontFamily: AppTheme.primaryFontFamily,
            fontSize: bodyFontSize,
            fontWeight: FontWeight.w600,
            color: AppTheme.textColor,
          ),
          semanticsLabel: 'Was this nudge helpful question',
        ),

        const SizedBox(height: AppTheme.spacingSmall),

        // Yes/No buttons
        Row(
          key: const Key('helpful_buttons'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _FeedbackButton(
              icon: Icons.thumb_up,
              label: 'Yes',
              isSelected: _dialogState.feedbackData.wasHelpful,
              onPressed: () {
                _triggerHaptic();
                _dialogState.updateWasHelpful(true);

                _logAnalyticsEvent('nudge_feedback_helpful_selected', {
                  'nudge_id': widget.nudge.id,
                  'selection': 'yes',
                });
              },
              needsAccessibility: needsAccessibility,
            ),
            const SizedBox(width: AppTheme.spacingMedium),
            _FeedbackButton(
              icon: Icons.thumb_down,
              label: 'No',
              isSelected: _dialogState.feedbackData.wasHelpful == false,
              onPressed: () {
                _triggerHaptic();
                _dialogState.updateWasHelpful(false);

                _logAnalyticsEvent('nudge_feedback_helpful_selected', {
                  'nudge_id': widget.nudge.id,
                  'selection': 'no',
                });
              },
              needsAccessibility: needsAccessibility,
            ),
          ],
        ),

        const SizedBox(height: AppTheme.spacingMedium),

        // Star rating
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rate this nudge:',
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: bodyFontSize,
                fontWeight: FontWeight.w600,
                color: AppTheme.textColor,
              ),
              semanticsLabel: 'Rate this nudge from one to five stars',
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            _StarRatingBar(
              key: const Key('star_rating'),
              currentRating: _dialogState.feedbackData.rating,
              onRatingChanged: (rating) {
                _triggerHaptic();
                _dialogState.updateRating(rating);

                _logAnalyticsEvent('nudge_feedback_rating_selected', {
                  'nudge_id': widget.nudge.id,
                  'rating': rating,
                });
              },
              needsAccessibility: needsAccessibility,
            ),
          ],
        ),

        const SizedBox(height: AppTheme.spacingMedium),

        // Emotion tags
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How did this make you feel? (Select all that apply)',
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: bodyFontSize,
                fontWeight: FontWeight.w600,
                color: AppTheme.textColor,
              ),
              semanticsLabel: 'Select emotions this nudge made you feel',
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            _EmotionTagSelector(
              key: const Key('emotion_tags'),
              selectedTags: _dialogState.feedbackData.emotionTags ?? [],
              onTagToggled: (tag) {
                _triggerHaptic();
                _dialogState.toggleEmotionTag(tag);

                _logAnalyticsEvent('nudge_feedback_emotion_toggled', {
                  'nudge_id': widget.nudge.id,
                  'tag': tag,
                  'action': (_dialogState.feedbackData.emotionTags ?? []).contains(tag)
                      ? 'selected'
                      : 'deselected',
                });
              },
              needsAccessibility: needsAccessibility,
            ),
          ],
        ),

        const SizedBox(height: AppTheme.spacingMedium),

        // Optional detailed feedback
        if (!_dialogState.showDetailedFeedback)
          TextButton(
            key: const Key('show_detailed_feedback'),
            onPressed: () {
              _triggerHaptic();
              _dialogState.setShowDetailedFeedback(true);

              _logAnalyticsEvent('nudge_feedback_detailed_expanded', {
                'nudge_id': widget.nudge.id,
              });

              // Focus the text field when it appears
              Future.delayed(const Duration(milliseconds: 100), () {
                _dialogState.requestTextFieldFocus();
              });
            },
            child: Text(
              'Add detailed feedback (optional)',
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: bodyFontSize,
                color: AppTheme.calmBlue,
              ),
            ),
          ),

        if (_dialogState.showDetailedFeedback) ...[
          _DetailedFeedbackField(
            key: const Key('detailed_feedback'),
            controller: _dialogState.feedbackController,
            focusNode: _dialogState.feedbackFocusNode,
            errorText: _dialogState.validationErrors['detailedFeedback'],
            needsAccessibility: needsAccessibility,
            onTextChanged: (text) {
              _dialogState.updateDetailedFeedback(text);
            },
          ),
        ],

        // Analytics consent
        if (widget.showAnalyticsConsent) ...[
          const SizedBox(height: AppTheme.spacingMedium),
          Text(
            'Your feedback helps us improve our nudges. It will be used anonymously '
                'for quality improvement purposes.',
            style: TextStyle(
              fontFamily: AppTheme.primaryFontFamily,
              fontSize: bodyFontSize * 0.8,
              fontWeight: FontWeight.normal,
              color: AppTheme.textSecondaryColor,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  // Build action buttons
  Widget _buildActionButtons(bool needsAccessibility) {
    final bodyFontSize = needsAccessibility
        ? AppTheme.fontSizeMedium
        : AppTheme.fontSizeSmall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Submit button
        ElevatedButton(
          key: const Key('submit_button'),
          onPressed: _dialogState.isSubmitting ? null : _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.gentleTeal,
            foregroundColor: Colors.black,
            padding: EdgeInsets.symmetric(
              vertical: needsAccessibility ? 20.0 : 16.0,
            ),
            minimumSize: Size(
              double.infinity,
              needsAccessibility ?
              AppTheme.buttonMinHeight + 8 : AppTheme.buttonMinHeight,
            ),
          ),
          child: _dialogState.isSubmitting
              ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 3.0,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.black54),
            ),
          )
              : Text(
            'Submit Feedback',
            style: TextStyle(
              fontFamily: AppTheme.primaryFontFamily,
              fontSize: needsAccessibility ?
              AppTheme.fontSizeMedium : AppTheme.fontSizeSmall,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        const SizedBox(height: AppTheme.spacingSmall),

        // No thanks button
        TextButton(
          key: const Key('dismiss_button'),
          onPressed: () => _onWillPop().then((canPop) {
            if (canPop) Navigator.of(context).pop();
          }),
          child: Text(
            'No thanks',
            style: TextStyle(
              fontFamily: AppTheme.primaryFontFamily,
              fontSize: bodyFontSize,
              color: AppTheme.textSecondaryColor,
            ),
          ),
        ),
      ],
    );
  }

  // Handle haptic feedback if enabled
  void _triggerHaptic() {
    if (widget.enableHaptics) {
      HapticFeedback.mediumImpact();
    }
  }

  // Handle submit with error handling
  Future<void> _handleSubmit() async {
    if (_dialogState.isSubmitting) return;

    // Validate the data
    final errors = _dialogState.feedbackData.validate();
    if (errors.isNotEmpty) {
      _dialogState.setValidationErrors(errors);

      _logAnalyticsEvent('nudge_feedback_validation_failed', {
        'nudge_id': widget.nudge.id,
        'errors': errors.keys.toList(),
      });

      return;
    }

    // Clear validation errors
    _dialogState.setValidationErrors({});

    // Set submitting state
    _dialogState.setSubmitting(true);

    _triggerHaptic();

    try {
      // Submit feedback
      if (widget.onFeedbackSubmitted != null) {
        await widget.onFeedbackSubmitted!(widget.nudge, _dialogState.feedbackData);
      }

      // Log successful submission
      _logAnalyticsEvent('nudge_feedback_submitted', {
        'nudge_id': widget.nudge.id,
        'was_helpful': _dialogState.feedbackData.wasHelpful,
        'rating': _dialogState.feedbackData.rating,
        'has_detailed_feedback': _dialogState.feedbackData.detailedFeedback != null &&
            _dialogState.feedbackData.detailedFeedback!.isNotEmpty,
        'emotion_tags_count': _dialogState.feedbackData.emotionTags?.length ?? 0,
      });

      // Close the dialog
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      // Handle error
      _dialogState.setSubmitting(false);

      _logAnalyticsEvent('nudge_feedback_submit_error', {
        'nudge_id': widget.nudge.id,
        'error': e.toString(),
      });

      AdvancedLogger.logError(
          'NudgeFeedbackDialog',
          'Error submitting feedback: $e'
      );

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit feedback: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Try Again',
              textColor: Colors.white,
              onPressed: _handleSubmit,
            ),
          ),
        );
      }
    }
  }
}

/// Star rating bar with labels
class _StarRatingBar extends StatelessWidget {
  /// The current selected rating
  final int? currentRating;

  /// Function to call when rating is changed
  final Function(int) onRatingChanged;

  /// Whether to use larger sizes for accessibility
  final bool needsAccessibility;

  /// Rating descriptions for tooltips
  final List<String> _ratingDescriptions = [
    'Poor',
    'Fair',
    'Good',
    'Very Good',
    'Excellent',
  ];

  /// Creates a star rating bar.
  _StarRatingBar({
    required this.currentRating,
    required this.onRatingChanged,
    this.needsAccessibility = false,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final size = needsAccessibility ?
    AppTheme.iconSizeMedium : AppTheme.iconSizeSmall;

    // Show selected rating description
    final selectedDescription = currentRating != null && currentRating! > 0 && currentRating! <= 5
        ? _ratingDescriptions[currentRating! - 1]
        : '';

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            5,
                (index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Tooltip(
                message: _ratingDescriptions[index],
                child: GestureDetector(
                  onTap: () => onRatingChanged(index + 1),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0), // Larger tap target
                    child: Icon(
                      (currentRating ?? 0) > index
                          ? Icons.star
                          : Icons.star_border,
                      color: (currentRating ?? 0) > index
                          ? AppTheme.calmBlue
                          : AppTheme.textSecondaryColor,
                      size: size,
                      semanticLabel: 'Rating ${index + 1} star${index > 0 ? 's' : ''}',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Display selected rating description
        if (selectedDescription.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            selectedDescription,
            style: TextStyle(
              fontFamily: AppTheme.primaryFontFamily,
              fontSize: needsAccessibility ?
              AppTheme.fontSizeSmall : AppTheme.fontSizeXSmall,
              fontWeight: FontWeight.w500,
              color: AppTheme.calmBlue,
            ),
          ),
        ],
      ],
    );
  }
}

/// Emotion tag selector with categories
class _EmotionTagSelector extends StatelessWidget {
  /// Currently selected tags
  final List<String> selectedTags;

  /// Function to call when a tag is toggled
  final Function(String) onTagToggled;

  /// Whether to use larger sizes for accessibility
  final bool needsAccessibility;

  /// Categorized emotion tags
  final Map<String, List<String>> _categorizedTags = {
    'Positive': [
      'Helpful', 'Insightful', 'Motivating', 'Comforting',
      'Uplifting', 'Connecting', 'Calming',
    ],
    'Neutral': [
      'Interesting', 'Thought-provoking', 'Surprising',
      'Familiar', 'Nostalgic',
    ],
    'Needs Improvement': [
      'Confusing', 'Irrelevant', 'Too Technical', 'Frustrating',
      'Repetitive', 'Too Long',
    ],
  };

  /// Creates an emotion tag selector.
  _EmotionTagSelector({
    required this.selectedTags,
    required this.onTagToggled,
    this.needsAccessibility = false,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final category in _categorizedTags.keys) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0, top: 8.0),
            child: Text(
              category,
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: needsAccessibility ?
                AppTheme.fontSizeSmall : AppTheme.fontSizeXSmall,
                fontWeight: FontWeight.w600,
                color: _getCategoryColor(category),
              ),
            ),
          ),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: _categorizedTags[category]!.map((tag) {
              final isSelected = selectedTags.contains(tag);
              return _buildEmotionTag(tag, isSelected);
            }).toList(),
          ),
        ],
      ],
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Positive':
        return AppTheme.calmGreen;
      case 'Neutral':
        return AppTheme.calmBlue;
      case 'Needs Improvement':
        return AppTheme.mutedRed;
      default:
        return AppTheme.textSecondaryColor;
    }
  }

  Widget _buildEmotionTag(String tag, bool isSelected) {
    final fontSize = needsAccessibility ?
    AppTheme.fontSizeSmall : AppTheme.fontSizeXSmall;

    Color tagColor;
    // Determine color based on tag category
    for (final entry in _categorizedTags.entries) {
      if (entry.value.contains(tag)) {
        tagColor = _getCategoryColor(entry.key);
        break;
      }
    }
    // Default color if not found
    tagColor = AppTheme.textSecondaryColor;

    return Semantics(
      selected: isSelected,
      button: true,
      onTap: () => onTagToggled(tag),
      label: '${tag} emotion tag, ${isSelected ? 'selected' : 'not selected'}',
      child: GestureDetector(
        onTap: () => onTagToggled(tag),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: needsAccessibility ? 16.0 : 12.0,
            vertical: needsAccessibility ? 12.0 : 8.0,
          ),
          decoration: BoxDecoration(
            color: isSelected ?
            tagColor.withOpacity(0.2) : AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
            border: Border.all(
              color: isSelected ? tagColor : AppTheme.dividerColor,
              width: isSelected ? 2.0 : 1.0,
            ),
          ),
          child: Text(
            tag,
            style: TextStyle(
              fontFamily: AppTheme.primaryFontFamily,
              fontSize: fontSize,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? tagColor : AppTheme.textColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Detailed feedback text field
class _DetailedFeedbackField extends StatelessWidget {
  /// Text controller for the field
  final TextEditingController controller;

  /// Focus node for the field
  final FocusNode focusNode;

  /// Error message to display
  final String? errorText;

  /// Whether to use larger sizes for accessibility
  final bool needsAccessibility;

  /// Callback when text changes
  final Function(String)? onTextChanged;

  /// Creates a detailed feedback text field.
  const _DetailedFeedbackField({
    required this.controller,
    required this.focusNode,
    this.errorText,
    this.needsAccessibility = false,
    this.onTextChanged,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bodyFontSize = needsAccessibility ?
    AppTheme.fontSizeMedium : AppTheme.fontSizeSmall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tell us more (optional):',
          style: TextStyle(
            fontFamily: AppTheme.primaryFontFamily,
            fontSize: bodyFontSize,
            fontWeight: FontWeight.w600,
            color: AppTheme.textColor,
          ),
        ),
        const SizedBox(height: AppTheme.spacingSmall),
        TextField(
          controller: controller,
          focusNode: focusNode,
          maxLines: 4,
          maxLength: 500,
          onChanged: onTextChanged,
          decoration: InputDecoration(
            hintText: 'Share your thoughts...',
            fillColor: AppTheme.backgroundColor,
            contentPadding: EdgeInsets.all(
                needsAccessibility ? 20.0 : 16.0
            ),
            errorText: errorText,
          ),
          style: TextStyle(
            fontFamily: AppTheme.primaryFontFamily,
            fontSize: bodyFontSize,
            color: AppTheme.textColor,
          ),
        ),
      ],
    );
  }
}

/// A feedback button with icon and label for Yes/No responses
class _FeedbackButton extends StatelessWidget {
  /// Icon to display in the button
  final IconData icon;

  /// Text label for the button
  final String label;

  /// Whether this button is selected
  final bool isSelected;

  /// Function to call when button is pressed
  final VoidCallback onPressed;

  /// Whether to use larger sizes for accessibility
  final bool needsAccessibility;

  /// Creates a feedback button.
  const _FeedbackButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onPressed,
    this.needsAccessibility = false,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final iconSize = needsAccessibility ?
    AppTheme.iconSizeMedium : AppTheme.iconSizeSmall;
    final fontSize = needsAccessibility ?
    AppTheme.fontSizeMedium : AppTheme.fontSizeSmall;

    final color = isSelected ? AppTheme.gentleTeal : AppTheme.textSecondaryColor;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label button ${isSelected ? "selected" : "not selected"}',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        child: Padding(
          padding: EdgeInsets.all(needsAccessibility ? 16.0 : 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: color,
                size: iconSize,
              ),
              const SizedBox(height: 8.0),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  fontSize: fontSize,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// State management class for the feedback dialog
///
/// This class improves performance by avoiding rebuilding the entire dialog
/// when only certain parts of the state change.
class _FeedbackDialogState extends ChangeNotifier {
  // Current feedback data
  FeedbackData _feedbackData;

  // Text controller for detailed feedback
  final TextEditingController _feedbackController = TextEditingController();

  // Focus node for the feedback text field
  final FocusNode _feedbackFocusNode = FocusNode();

  // State for tracking if submission is in progress
  bool _isSubmitting = false;

  // State for tracking if text field should be shown
  bool _showDetailedFeedback = false;

  // Validation errors
  Map<String, String> _validationErrors = {};

  // Getters
  FeedbackData get feedbackData => _feedbackData;
  TextEditingController get feedbackController => _feedbackController;
  FocusNode get feedbackFocusNode => _feedbackFocusNode;
  bool get isSubmitting => _isSubmitting;
  bool get showDetailedFeedback => _showDetailedFeedback;
  Map<String, String> get validationErrors => _validationErrors;

  // Constructor with optional initial values
  _FeedbackDialogState({
    bool? initialWasHelpful,
    int? initialRating,
  }) : _feedbackData = FeedbackData(
    wasHelpful: initialWasHelpful ?? true,
    rating: initialRating,
    emotionTags: [],
  );

  // Update wasHelpful value
  void updateWasHelpful(bool wasHelpful) {
    _feedbackData = _feedbackData.copyWith(wasHelpful: wasHelpful);
    notifyListeners();
  }

  // Update rating value
  void updateRating(int rating) {
    _feedbackData = _feedbackData.copyWith(rating: rating);
    notifyListeners();
  }

  // Toggle emotion tag
  void toggleEmotionTag(String tag) {
    final currentTags = _feedbackData.emotionTags ?? [];
    final newTags = List<String>.from(currentTags);

    if (newTags.contains(tag)) {
      newTags.remove(tag);
    } else {
      newTags.add(tag);
    }

    _feedbackData = _feedbackData.copyWith(emotionTags: newTags);
    notifyListeners();
  }

  // Update detailed feedback
  void updateDetailedFeedback(String text) {
    _feedbackData = _feedbackData.copyWith(detailedFeedback: text);
    // Don't notify listeners here to avoid rebuilding on every keystroke
  }

  // Show/hide detailed feedback field
  void setShowDetailedFeedback(bool show) {
    _showDetailedFeedback = show;
    notifyListeners();
  }

  // Set submitting state
  void setSubmitting(bool submitting) {
    _isSubmitting = submitting;
    notifyListeners();
  }

  // Set validation errors
  void setValidationErrors(Map<String, String> errors) {
    _validationErrors = errors;
    notifyListeners();
  }

  // Request focus for the text field
  void requestTextFieldFocus() {
    _feedbackFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    _feedbackFocusNode.dispose();
    super.dispose();
  }
}

/// Controller for handling orientation changes
class OrientationController extends ChangeNotifier {
  Orientation _currentOrientation = Orientation.portrait;

  Orientation get currentOrientation => _currentOrientation;

  void updateOrientation(Orientation newOrientation) {
    if (_currentOrientation != newOrientation) {
      _currentOrientation = newOrientation;
      notifyListeners();
    }
  }
}

/// Helper function to show the nudge feedback dialog
///
/// This function creates and shows a dialog to collect feedback about a nudge.
/// It handles the dialog creation and presentation, and provides callbacks for
/// when feedback is submitted or the dialog is dismissed.
///
/// [context] is the BuildContext for showing the dialog.
/// [nudge] is the nudge to collect feedback for.
/// [onFeedbackSubmitted] is called when the user submits feedback.
/// [onDismissed] is called when the dialog is dismissed without submitting.
/// [enableHaptics] determines if haptic feedback should be used for interactions.
/// [enhancedAccessibility] determines if larger text and controls should be used.
/// [showAnalyticsConsent] determines if analytics consent message should be shown.
Future<void> showNudgeFeedbackDialog({
  required BuildContext context,
  required NudgeDelivery nudge,
  Function(NudgeDelivery, FeedbackData)? onFeedbackSubmitted,
  VoidCallback? onDismissed,
  bool enableHaptics = true,
  bool enhancedAccessibility = false,
  bool showAnalyticsConsent = true,
}) {
  // Log dialog open attempt for analytics
  try {
    AnalyticsService.logEvent('nudge_feedback_dialog_show_attempt', {
      'nudge_id': nudge.id,
      'nudge_type': nudge.type,
    });
  } catch (e) {
    AdvancedLogger.logError(
        'showNudgeFeedbackDialog',
        'Failed to log analytics event: $e'
    );
  }

  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => NudgeFeedbackDialog(
      nudge: nudge,
      onFeedbackSubmitted: onFeedbackSubmitted,
      onDismissed: onDismissed,
      enableHaptics: enableHaptics,
      enhancedAccessibility: enhancedAccessibility,
      showAnalyticsConsent: showAnalyticsConsent,
    ),
  );
}