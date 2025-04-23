// File: lib/screens/nudge_history_view.dart
// Copyright (c) 2025 Milo App. All rights reserved.
// Version: 1.0.1
// This file is part of the Milo therapeutic nudge system.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:milo/lib/models/nudge_model.dart';
import 'package:milo/lib/services/nudge_service.dart';
import 'package:milo/lib/widgets/audio/nudge_audio_player.dart';
import 'package:milo/lib/utils/advanced_logger.dart';
import 'package:milo/lib/theme/app_theme.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:milo/lib/widgets/error_display_widget.dart';
import 'package:milo/lib/widgets/loading_indicator.dart';

/// A screen that displays the history of therapeutic nudges delivered to the user.
///
/// This screen is designed specifically for elderly users (55+) with:
/// - Large text and high contrast elements
/// - Simple, intuitive layout
/// - Clear chronological organization
/// - Ability to replay past nudges
/// - Option to save nudges as memories
///
/// Design considerations:
/// - Implements pagination for better performance with long history lists
/// - Uses memory-efficient data structures
/// - Includes enhanced accessibility features
/// - Provides clear visual and haptic feedback
class NudgeHistoryView extends StatefulWidget {
  /// Days of history to show by default
  final int defaultHistoryDays;

  /// Maximum number of nudges to load per page
  final int nudgesPerPage;

  /// Creates a new NudgeHistoryView widget.
  ///
  /// The [defaultHistoryDays] parameter determines how many days of
  /// history to show by default. Defaults to 7 days.
  ///
  /// The [nudgesPerPage] parameter controls how many nudges are loaded
  /// at once for pagination. Defaults to 20 nudges per page.
  const NudgeHistoryView({
    Key? key,
    this.defaultHistoryDays = 7,
    this.nudgesPerPage = 20,
  }) : super(key: key);

  @override
  State<NudgeHistoryView> createState() => _NudgeHistoryViewState();
}

class _NudgeHistoryViewState extends State<NudgeHistoryView> {
  final NudgeService _nudgeService = GetIt.instance<NudgeService>();
  final AdvancedLogger _logger = GetIt.instance<AdvancedLogger>();
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  List<NudgeDelivery> _nudges = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasError = false;
  String _errorMessage = '';
  String? _errorCode;
  int _displayDays = 7; // Default to a week
  int? _playingNudgeId;
  bool _hasMorePages = true;
  DateTime? _lastLoadedDate;

  // Keep track of the current scroll position
  final ScrollController _scrollController = ScrollController();

  // Group nudges by date for better organization
  // Using LinkedHashMap to maintain insertion order while providing O(1) lookups
  final Map<DateTime, List<NudgeDelivery>> _groupedNudges = {};

  @override
  void initState() {
    super.initState();
    _displayDays = widget.defaultHistoryDays;

    // Set up scroll listener for pagination
    _scrollController.addListener(_scrollListener);

    _loadNudgeHistory(initial: true);

    // Log screen view for analytics
    _analytics.logScreenView(
      screenName: 'nudge_history_view',
      screenClass: 'NudgeHistoryView',
    );
  }

  @override
  void dispose() {
    // Clean up resources
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  /// Scroll listener for implementing pagination
  void _scrollListener() {
    // If we're within 200 pixels of the bottom and not already loading more
    if (_scrollController.position.extentAfter < 200 &&
        !_isLoading &&
        !_isLoadingMore &&
        _hasMorePages) {
      _loadMoreNudges();
    }
  }

  /// Loads the initial set of nudge history from Firestore based on the selected date range.
  ///
  /// [initial] - Whether this is the initial load (true) or a refresh (false)
  ///
  /// Implements error handling and sets appropriate state variables.
  /// Uses pagination to load data in chunks for better performance.
  Future<void> _loadNudgeHistory({bool initial = false}) async {
    if (!mounted) return;

    // Reset pagination variables if this is an initial load
    if (initial) {
      _hasMorePages = true;
      _lastLoadedDate = null;
      _groupedNudges.clear();
      _nudges = [];
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
      _errorCode = null;
    });

    try {
      _logger.info('NudgeHistoryView: Loading nudge history for $_displayDays days (initial: $initial)');

      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: _displayDays - 1));
      final endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

      // Load first page of nudges from service with pagination
      final nudges = await _nudgeService.getNudgesByTimeRangePaginated(
        startDate,
        endDate,
        limit: widget.nudgesPerPage,
        lastTimestamp: _lastLoadedDate,
      );

      if (!mounted) return;

      // Update pagination state
      if (nudges.length < widget.nudgesPerPage) {
        _hasMorePages = false;
      }

      if (nudges.isNotEmpty) {
        _lastLoadedDate = nudges.last.deliveredAt;
      } else {
        _hasMorePages = false;
      }

      // Process and group the nudges
      _processNudges(nudges, initial);

      setState(() {
        _isLoading = false;
      });

      _logger.info('NudgeHistoryView: Loaded ${nudges.length} nudges');

      // Provide haptic feedback on successful load
      HapticFeedback.lightImpact();

    } catch (e, stackTrace) {
      _logger.error('NudgeHistoryView: Error loading nudge history', e, stackTrace);

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Unable to load your previous messages. Please try again.';
        _errorCode = e.runtimeType.toString();
      });

      // Report error to analytics
      _analytics.logEvent(
        name: 'nudge_history_error',
        parameters: {
          'error_type': e.runtimeType.toString(),
          'display_days': _displayDays,
        },
      );
    }
  }

  /// Loads more nudges when the user scrolls near the bottom of the list
  Future<void> _loadMoreNudges() async {
    if (!mounted || !_hasMorePages || _isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      _logger.info('NudgeHistoryView: Loading more nudges');

      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: _displayDays - 1));
      final endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

      // Load next page of nudges
      final nudges = await _nudgeService.getNudgesByTimeRangePaginated(
        startDate,
        endDate,
        limit: widget.nudgesPerPage,
        lastTimestamp: _lastLoadedDate,
      );

      if (!mounted) return;

      // Update pagination state
      if (nudges.length < widget.nudgesPerPage) {
        _hasMorePages = false;
      }

      if (nudges.isNotEmpty) {
        _lastLoadedDate = nudges.last.deliveredAt;
      } else {
        _hasMorePages = false;
      }

      // Process and group the nudges
      _processNudges(nudges, false);

      setState(() {
        _isLoadingMore = false;
      });

      _logger.info('NudgeHistoryView: Loaded ${nudges.length} more nudges');

    } catch (e, stackTrace) {
      _logger.error('NudgeHistoryView: Error loading more nudges', e, stackTrace);

      if (!mounted) return;

      setState(() {
        _isLoadingMore = false;
      });

      // Show error as a snackbar but don't disrupt the existing view
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not load more messages. Please try again.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          duration: Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: _loadMoreNudges,
          ),
        ),
      );

      // Report error to analytics
      _analytics.logEvent(
        name: 'nudge_load_more_error',
        parameters: {
          'error_type': e.runtimeType.toString(),
          'display_days': _displayDays,
        },
      );
    }
  }

  /// Processes nudges and groups them by date
  ///
  /// [nudges] - The list of nudges to process
  /// [clearExisting] - Whether to clear existing nudges (true) or append (false)
  void _processNudges(List<NudgeDelivery> nudges, bool clearExisting) {
    if (clearExisting) {
      _nudges = [];
      _groupedNudges.clear();
    }

    // Add new nudges to the overall list
    _nudges.addAll(nudges);

    // Group nudges by date
    for (var nudge in nudges) {
      final date = DateTime(
        nudge.deliveredAt.year,
        nudge.deliveredAt.month,
        nudge.deliveredAt.day,
      );

      if (!_groupedNudges.containsKey(date)) {
        _groupedNudges[date] = [];
      }

      _groupedNudges[date]!.add(nudge);
    }

    // Sort each group by time (newest first)
    _groupedNudges.forEach((date, nudgeList) {
      nudgeList.sort((a, b) => b.deliveredAt.compareTo(a.deliveredAt));
    });
  }

  /// Handles playing a nudge audio from the history.
  ///
  /// Updates the UI state and logs analytics events.
  /// Provides haptic feedback for user interaction.
  Future<void> _playNudge(NudgeDelivery nudge) async {
    try {
      // Provide haptic feedback for button press
      HapticFeedback.mediumImpact();

      setState(() {
        _playingNudgeId = nudge.id;
      });

      _logger.info('NudgeHistoryView: Playing nudge ${nudge.id}');

      // Log play event
      _analytics.logEvent(
        name: 'nudge_history_replay',
        parameters: {
          'nudge_id': nudge.id,
          'nudge_category': nudge.category.name,
          'days_old': DateTime.now().difference(nudge.deliveredAt).inDays,
        },
      );

      await _nudgeService.playNudgeAudio(nudge);

      if (!mounted) return;

      setState(() {
        _playingNudgeId = null;
      });
    } catch (e, stackTrace) {
      _logger.error('NudgeHistoryView: Error playing nudge', e, stackTrace);

      if (!mounted) return;

      setState(() {
        _playingNudgeId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not play audio message. Please try again.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// Handles saving a nudge as a memory.
  ///
  /// Shows a confirmation dialog before proceeding.
  /// Implements error handling and visual feedback during the process.
  Future<void> _saveAsMemory(NudgeDelivery nudge) async {
    // Show confirmation dialog
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Save as Memory?',
          style: Theme.of(context).dialogTheme.titleTextStyle,
        ),
        content: Text(
          'Would you like to save this message as a lasting memory in your collection?',
          style: Theme.of(context).dialogTheme.contentTextStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Save'),
          ),
        ],
      ),
    );

    if (shouldSave != true || !mounted) return;

    try {
      // Provide haptic feedback
      HapticFeedback.mediumImpact();

      _logger.info('NudgeHistoryView: Saving nudge ${nudge.id} as memory');

      // Show loading indicator
      final loadingOverlay = _showLoadingOverlay('Saving as memory...');

      await _nudgeService.saveNudgeAsMemory(nudge);

      // Dismiss loading indicator
      loadingOverlay.dismiss();

      if (!mounted) return;

      // Show success message with visual indicator
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.check_circle,
                color: AppTheme.successColor,
                size: AppTheme.iconSizeSmall,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Saved as a memory! You can find it in your memories collection.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
          ),
        ),
      );

      // Log event
      _analytics.logEvent(
        name: 'nudge_saved_as_memory',
        parameters: {
          'nudge_id': nudge.id,
          'nudge_category': nudge.category.name,
        },
      );
    } catch (e, stackTrace) {
      _logger.error('NudgeHistoryView: Error saving nudge as memory', e, stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not save as memory. Please try again later.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          duration: Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _saveAsMemory(nudge),
          ),
        ),
      );
    }
  }

  /// Shows a loading overlay with a message.
  ///
  /// Returns a OverlayEntry that can be dismissed.
  OverlayEntry _showLoadingOverlay(String message) {
    final overlay = OverlayEntry(
      builder: (context) => Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
            ),
            child: Padding(
              padding: AppTheme.paddingMedium,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    strokeWidth: 4,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  SizedBox(height: AppTheme.spacingSmall),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(overlay);
    return overlay;
  }

  /// Changes the time range for displayed nudges.
  ///
  /// Provides haptic feedback and resets pagination.
  void _changeTimeRange(int days) {
    if (days != _displayDays) {
      // Provide haptic feedback
      HapticFeedback.selectionClick();

      setState(() {
        _displayDays = days;
      });

      // Reset scroll position
      _scrollController.jumpTo(0);

      // Reload with new time range (this will reset pagination)
      _loadNudgeHistory(initial: true);

      // Log event
      _analytics.logEvent(
        name: 'nudge_history_range_changed',
        parameters: {
          'days': days,
        },
      );
    }
  }

  /// Creates an individual time range button.
  ///
  /// The button uses semantics for improved accessibility.
  Widget _timeRangeButton(String label, int days) {
    final isSelected = days == _displayDays;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Semantics(
        button: true,
        selected: isSelected,
        label: '$label time range filter' + (isSelected ? ' (selected)' : ''),
        child: ElevatedButton(
          onPressed: () => _changeTimeRange(days),
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surface,
            foregroundColor: isSelected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurface,
            elevation: isSelected ? 4 : 1,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the time range selector buttons.
  Widget _buildTimeRangeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).appBarTheme.backgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
          horizontal: AppTheme.spacingSmall,
          vertical: 12.0
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _timeRangeButton('Today', 1),
            _timeRangeButton('Last 3 Days', 3),
            _timeRangeButton('Week', 7),
            _timeRangeButton('2 Weeks', 14),
            _timeRangeButton('Month', 30),
          ],
        ),
      ),
    );
  }

  /// Builds the error view when loading fails.
  ///
  /// Provides specific recovery actions based on error type.
  Widget _buildErrorView() {
    // Determine appropriate actions based on error type
    List<Widget> actions = [
      ElevatedButton.icon(
        onPressed: () => _loadNudgeHistory(initial: true),
        icon: Icon(Icons.refresh),
        label: Text('Try Again'),
        style: Theme.of(context).elevatedButtonTheme.style,
      ),
    ];

    // Add additional options based on error code
    if (_errorCode?.contains('TimeoutException') == true) {
      actions.add(
        TextButton.icon(
          onPressed: () {
            // Change to a smaller time range
            _changeTimeRange(_displayDays > 7 ? 7 : 1);
          },
          icon: Icon(Icons.calendar_today),
          label: Text('Show Fewer Days'),
        ),
      );
    } else if (_errorCode?.contains('PermissionDenied') == true) {
      actions.add(
        TextButton.icon(
          onPressed: () async {
            // Force refresh authentication
            await _nudgeService.refreshAuthentication();
            _loadNudgeHistory(initial: true);
          },
          icon: Icon(Icons.security),
          label: Text('Refresh Authentication'),
        ),
      );
    }

    return ErrorDisplayWidget(
      message: _errorMessage,
      icon: Icons.error_outline,
      iconColor: Theme.of(context).colorScheme.error,
      actions: actions,
    );
  }

  /// Builds a section for a specific date with all nudges from that date.
  ///
  /// Uses proper key strategy for efficient rebuilding.
  Widget _buildDateSection(DateTime date, List<NudgeDelivery> nudges) {
    final dateFormat = DateFormat('EEEE, MMMM d'); // Example: "Monday, January 1"
    final isToday = date.year == DateTime.now().year &&
        date.month == DateTime.now().month &&
        date.day == DateTime.now().day;

    return Column(
      key: ValueKey('date-section-${date.toIso8601String()}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              AppTheme.spacingSmall,
              AppTheme.spacingMedium,
              AppTheme.spacingSmall,
              8
          ),
          child: Semantics(
            header: true,
            child: Text(
              isToday ? "Today" : dateFormat.format(date),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        ListView.builder(
          key: PageStorageKey('nudge-list-${date.toIso8601String()}'),
          physics: NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: nudges.length,
          itemBuilder: (context, index) {
            return _buildNudgeCard(nudges[index]);
          },
        ),
      ],
    );
  }

  /// Builds a card for displaying category information with icon
  ///
  /// Extracted to a separate widget for better reusability and readability.
  Widget _buildCategoryIndicator(NudgeCategory category) {
    // Get category icon and color
    IconData categoryIcon;
    Color categoryColor;
    String semanticLabel;

    switch (category) {
      case NudgeCategory.gratitude:
        categoryIcon = Icons.favorite;
        categoryColor = AppTheme.semanticColors['highlight']!;
        semanticLabel = 'Gratitude message';
        break;
      case NudgeCategory.mindfulness:
        categoryIcon = Icons.spa;
        categoryColor = AppTheme.semanticColors['success']!;
        semanticLabel = 'Mindfulness message';
        break;
      case NudgeCategory.selfReflection:
        categoryIcon = Icons.psychology;
        categoryColor = AppTheme.semanticColors['info']!;
        semanticLabel = 'Self reflection message';
        break;
      case NudgeCategory.reassurance:
        categoryIcon = Icons.security;
        categoryColor = AppTheme.semanticColors['action']!;
        semanticLabel = 'Reassurance message';
        break;
      case NudgeCategory.cognitive:
        categoryIcon = Icons.lightbulb;
        categoryColor = AppTheme.semanticColors['warning']!;
        semanticLabel = 'Cognitive exercise message';
        break;
      default:
        categoryIcon = Icons.message;
        categoryColor = AppTheme.textSecondaryColor;
        semanticLabel = 'Therapeutic message';
    }

    return Semantics(
      label: semanticLabel,
      child: Row(
        children: [
          Icon(categoryIcon, color: categoryColor, size: AppTheme.iconSizeSmall),
          SizedBox(width: 8),
          Text(
            category.name,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: categoryColor,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a card for an individual nudge.
  ///
  /// Enhanced with proper semantics for screen readers.
  /// Uses efficient keys for widget rebuilding.
  Widget _buildNudgeCard(NudgeDelivery nudge) {
    final timeFormat = DateFormat('h:mm a'); // Example: "3:30 PM"
    final isPlaying = _playingNudgeId == nudge.id;

    // Format template message for display
    String displayContent = nudge.templateContent;
    if (displayContent.length > 100) {
      displayContent = displayContent.substring(0, 97) + '...';
    }

    // Create a useful semantics label for screen readers
    final deliveryTime = timeFormat.format(nudge.deliveredAt);
    final semanticsLabel = '${nudge.category.name} message from $deliveryTime. ${displayContent}';

    return Semantics(
      label: semanticsLabel,
      child: Card(
        key: ValueKey('nudge-card-${nudge.id}'),
        margin: EdgeInsets.symmetric(horizontal: AppTheme.spacingSmall, vertical: 8),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        ),
        child: Padding(
          padding: AppTheme.paddingSmall,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with time and category
              Row(
                children: [
                  _buildCategoryIndicator(nudge.category),
                  Spacer(),
                  Text(
                    timeFormat.format(nudge.deliveredAt),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Divider(height: 24),

              // Content
              Text(
                displayContent,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              SizedBox(height: AppTheme.spacingSmall),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Replay button
                  Expanded(
                    child: Semantics(
                      button: true,
                      enabled: !isPlaying,
                      label: isPlaying ? 'Currently playing message' : 'Replay this message',
                      child: TextButton.icon(
                        onPressed: isPlaying ? null : () => _playNudge(nudge),
                        icon: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                        label: Text(
                          isPlaying ? 'Playing...' : 'Replay',
                        ),
                      ),
                    ),
                  ),
                  // Save as memory button
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Save this message as a memory',
                      child: TextButton.icon(
                        onPressed: () => _saveAsMemory(nudge),
                        icon: Icon(Icons.bookmark),
                        label: Text('Save as Memory'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the empty state when no nudges are available.
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: AppTheme.paddingMedium,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_off,
              size: AppTheme.iconSizeLarge,
              color: AppTheme.textSecondaryColor,
              semanticLabel: 'No notifications icon',
            ),
            SizedBox(height: AppTheme.spacingSmall),
            Text(
              'No messages yet',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              _displayDays == 1
                  ? 'You haven\'t received any messages today.'
                  : 'You haven\'t received any messages in the last $_displayDays days.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppTheme.textSecondaryColor,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: AppTheme.spacingMedium),
            if (_displayDays != 30) // Only show if not already at maximum range
              Semantics(
                button: true,
                label: 'Show messages from the last 30 days',
                child: ElevatedButton.icon(
                  onPressed: () => _changeTimeRange(30),
                  icon: Icon(Icons.calendar_month),
                  label: Text('Show Last 30 Days'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Builds a loading indicator for pagination at the bottom of the list
  Widget _buildLoadingMoreIndicator() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: AppTheme.spacingMedium),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          SizedBox(width: 16),
          Text(
            'Loading more messages...',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Message History',
          style: Theme.of(context).appBarTheme.titleTextStyle,
        ),
        centerTitle: true,
        elevation: 2,
        actions: [
          Semantics(
            button: true,
            label: 'Help information about message history',
            child: IconButton(
              icon: Icon(Icons.help_outline, size: AppTheme.iconSizeSmall),
              onPressed: () {
                HapticFeedback.selectionClick();

                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(
                      'About Message History',
                      style: Theme.of(context).dialogTheme.titleTextStyle,
                    ),
                    content: Text(
                      'This screen shows your previous therapeutic messages. '
                          'You can replay them or save them as memories.\n\n'
                          'Use the buttons at the top to change how far back to look.',
                      style: Theme.of(context).dialogTheme.contentTextStyle,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('Got it'),
                      ),
                    ],
                    shape: Theme.of(context).dialogTheme.shape,
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Time range selector
            _buildTimeRangeSelector(),

            // Content
            Expanded(
              child: _isLoading
                  ? Center(
                child: LoadingIndicator(
                  message: 'Loading your messages...',
                ),
              )
                  : _hasError
                  ? _buildErrorView()
                  : _nudges.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                onRefresh: () => _loadNudgeHistory(initial: true),
                color: Theme.of(context).colorScheme.primary,
                child: ListView.builder(
                  controller: _scrollController,
                  physics: AlwaysScrollableScrollPhysics(),
                  itemCount: _groupedNudges.length + (_isLoadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    // Show loading indicator at the bottom when loading more
                    if (index == _groupedNudges.length) {
                      return _buildLoadingMoreIndicator();
                    }

                    final date = _groupedNudges.keys.elementAt(index);
                    final nudges = _groupedNudges[date]!;
                    return _buildDateSection(date, nudges);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A custom widget for displaying errors with actions
///
/// This widget is extracted to improve reusability across the app.
/// It should be moved to a separate file in a real implementation.
class ErrorDisplayWidget extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color iconColor;
  final List<Widget> actions;

  const ErrorDisplayWidget({
    Key? key,
    required this.message,
    this.icon = Icons.error_outline,
    required this.iconColor,
    required this.actions,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppTheme.paddingMedium,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: AppTheme.iconSizeLarge,
              color: iconColor,
            ),
            SizedBox(height: AppTheme.spacingSmall),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: iconColor,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: AppTheme.spacingMedium),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// A custom loading indicator with message
///
/// This widget is extracted to improve reusability across the app.
/// It should be moved to a separate file in a real implementation.
class LoadingIndicator extends StatelessWidget {
  final String message;

  const LoadingIndicator({
    Key? key,
    required this.message,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(
          strokeWidth: 4,
          color: Theme.of(context).colorScheme.primary,
        ),
        SizedBox(height: AppTheme.spacingMedium),
        Text(
          message,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}