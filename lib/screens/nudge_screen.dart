import 'package:flutter/material.dart';
import 'package:milo/services/nudge_service.dart';
import 'package:milo/models/nudge_model.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:milo/theme/app_theme.dart';
import 'package:collection/collection.dart';

/// NudgeScreen is the main interface for users to interact with therapeutic nudges
///
/// Displays the current day's nudges, allows for replay, saving as memory, and
/// providing feedback. Built with accessibility in mind for users 55+.
class NudgeScreen extends StatefulWidget {
  const NudgeScreen({Key? key}) : super(key: key);

  @override
  State<NudgeScreen> createState() => _NudgeScreenState();
}

/// Represents the current view mode for the history section
enum HistoryViewMode {
  today,
  week,
  month,
  helpful,
  category
}

/// Represents the screen's loading state
enum ScreenLoadState {
  loading,
  loaded,
  error
}

class _NudgeScreenState extends State<NudgeScreen> with SingleTickerProviderStateMixin {
  final Logger _logger = Logger();

  // Screen state management
  ScreenLoadState _currentNudgeState = ScreenLoadState.loading;
  ScreenLoadState _historyState = ScreenLoadState.loading;
  bool _isProcessingAction = false;

  // Data storage
  List<NudgeDelivery>? _todayNudges;
  List<NudgeDelivery>? _historyNudges;
  Map<String, List<NudgeDelivery>> _nudgesByDate = {};
  NudgeDelivery? _currentNudge;

  // Category filter data
  List<String> _availableCategories = [];
  String? _selectedCategory;

  // Audio playback state
  bool _isPlaying = false;
  NudgeDelivery? _currentlyPlayingNudge;

  // Error states
  String _currentNudgeErrorMessage = '';
  String _historyErrorMessage = '';

  // History view settings
  HistoryViewMode _historyViewMode = HistoryViewMode.today;
  DateTime _viewStartDate = DateTime.now();
  bool _showExpandedHistory = false;

  // Animation controller for expanding/collapsing history
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize animation controller
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );

    // Load data
    _loadTodayNudges();
    _loadHistoryNudges();
  }

  /// Checks if device is connected to the internet
  Future<bool> _checkConnectivity() async {
    try {
      var connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      _logger.e('Failed to check connectivity', e);
      return true; // Assume connected if we can't check (less disruptive)
    }
  }

  /// Loads today's nudges from the NudgeService
  Future<void> _loadTodayNudges() async {
    // Check connectivity first
    bool isConnected = await _checkConnectivity();
    if (!isConnected) {
      setState(() {
        _currentNudgeState = ScreenLoadState.error;
        _currentNudgeErrorMessage = 'No internet connection. Please check your network and try again.';
      });
      return;
    }

    try {
      setState(() {
        _currentNudgeState = ScreenLoadState.loading;
        _currentNudgeErrorMessage = '';
      });

      final nudgeService = Provider.of<NudgeService>(context, listen: false);
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final nudges = await nudgeService.getNudgeDeliveriesByDateRange(
          startOfDay,
          endOfDay
      );

      if (!mounted) return;

      setState(() {
        _todayNudges = nudges;

        // Set current nudge (latest one)
        if (nudges.isNotEmpty) {
          _currentNudge = nudges.last;
        }

        _currentNudgeState = ScreenLoadState.loaded;
      });
    } catch (e, stackTrace) {
      _logger.e('Failed to load today\'s nudges', e, stackTrace);

      // More specific error messages
      String errorMessage = 'Unable to load nudges. ';
      if (e.toString().contains('permission')) {
        errorMessage += 'Permission denied. Please check app permissions.';
      } else if (e.toString().contains('not found')) {
        errorMessage += 'Nudge data not found.';
      } else if (e.toString().contains('timeout')) {
        errorMessage += 'Request timed out. Please try again.';
      } else {
        errorMessage += 'Please try again later.';
      }

      setState(() {
        _currentNudgeErrorMessage = errorMessage;
        _currentNudgeState = ScreenLoadState.error;
      });
    }
  }

  /// Loads history nudges based on current view mode
  Future<void> _loadHistoryNudges() async {
    // Define date range based on view mode
    DateTime endDate = DateTime.now();
    DateTime startDate;

    switch (_historyViewMode) {
      case HistoryViewMode.today:
        startDate = DateTime(endDate.year, endDate.month, endDate.day);
        break;
      case HistoryViewMode.week:
        startDate = endDate.subtract(const Duration(days: 7));
        break;
      case HistoryViewMode.month:
        startDate = DateTime(endDate.year, endDate.month - 1, endDate.day);
        break;
      case HistoryViewMode.helpful:
      case HistoryViewMode.category:
        startDate = DateTime(endDate.year, endDate.month - 3, endDate.day); // Last 3 months for filtered views
        break;
    }

    _viewStartDate = startDate;

    // Check connectivity
    bool isConnected = await _checkConnectivity();
    if (!isConnected) {
      setState(() {
        _historyState = ScreenLoadState.error;
        _historyErrorMessage = 'No internet connection. Please check your network and try again.';
      });
      return;
    }

    try {
      setState(() {
        _historyState = ScreenLoadState.loading;
        _historyErrorMessage = '';
      });

      final nudgeService = Provider.of<NudgeService>(context, listen: false);

      List<NudgeDelivery> nudges;
      if (_historyViewMode == HistoryViewMode.helpful) {
        // Get helpful nudges (rated positively)
        nudges = await nudgeService.getHelpfulNudges(startDate, endDate);
      } else if (_historyViewMode == HistoryViewMode.category && _selectedCategory != null) {
        // Get nudges by category
        nudges = await nudgeService.getNudgesByCategory(_selectedCategory!, startDate, endDate);
      } else {
        // Get nudges by date range
        nudges = await nudgeService.getNudgeDeliveriesByDateRange(startDate, endDate);
      }

      // Also load available categories for filtering
      final categories = await nudgeService.getAvailableNudgeCategories();

      if (!mounted) return;

      setState(() {
        _historyNudges = nudges;

        // Group nudges by date for display
        _nudgesByDate = _groupNudgesByDate(nudges);

        // Extract category names
        _availableCategories = categories.map((c) => c.name).toList();

        _historyState = ScreenLoadState.loaded;
      });
    } catch (e, stackTrace) {
      _logger.e('Failed to load history nudges', e, stackTrace);

      setState(() {
        _historyErrorMessage = 'Unable to load nudge history. Please try again.';
        _historyState = ScreenLoadState.error;
      });
    }
  }

  /// Groups nudges by date for sectioned display
  Map<String, List<NudgeDelivery>> _groupNudgesByDate(List<NudgeDelivery> nudges) {
    final Map<String, List<NudgeDelivery>> grouped = {};

    for (final nudge in nudges) {
      final dateKey = DateFormat('yyyy-MM-dd').format(nudge.timestamp);
      if (!grouped.containsKey(dateKey)) {
        grouped[dateKey] = [];
      }
      grouped[dateKey]!.add(nudge);
    }

    // Sort nudges within each day by timestamp (newest first)
    grouped.forEach((key, value) {
      value.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    });

    return grouped;
  }

  /// Plays the audio for the selected nudge with improved state management
  Future<void> _playNudgeAudio(NudgeDelivery nudge) async {
    // If already playing the same nudge, stop playback
    if (_isPlaying && _currentlyPlayingNudge?.id == nudge.id) {
      try {
        final nudgeService = Provider.of<NudgeService>(context, listen: false);
        await nudgeService.stopNudgeAudio();

        setState(() {
          _isPlaying = false;
          _currentlyPlayingNudge = null;
        });
        return;
      } catch (e, stackTrace) {
        _logger.e('Failed to stop nudge audio', e, stackTrace);
        // Continue with error handling below
      }
    }

    // If already playing a different nudge, show info message
    if (_isPlaying && _currentlyPlayingNudge != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stopping current playback to play new nudge'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Try to stop the current playback
      try {
        final nudgeService = Provider.of<NudgeService>(context, listen: false);
        await nudgeService.stopNudgeAudio();
      } catch (e, stackTrace) {
        _logger.e('Failed to stop previous nudge audio', e, stackTrace);
        // Continue anyway to try playing the new nudge
      }
    }

    try {
      setState(() {
        _isProcessingAction = true;
        _isPlaying = true;
        _currentlyPlayingNudge = nudge;
      });

      final nudgeService = Provider.of<NudgeService>(context, listen: false);
      await nudgeService.playNudgeAudio(nudge);

      // Setup completion callback
      nudgeService.onPlaybackComplete = () {
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _currentlyPlayingNudge = null;
          });
        }
      };

      setState(() {
        _isProcessingAction = false;
      });
    } catch (e, stackTrace) {
      _logger.e('Failed to play nudge audio', e, stackTrace);

      String errorMessage = 'Unable to play the audio. ';
      if (e.toString().contains('audio format')) {
        errorMessage += 'Audio format not supported.';
      } else if (e.toString().contains('permission')) {
        errorMessage += 'Audio permission denied.';
      } else {
        errorMessage += 'Please try again.';
      }

      setState(() {
        _isPlaying = false;
        _currentlyPlayingNudge = null;
        _isProcessingAction = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  /// Saves the current nudge as a memory
  Future<void> _saveAsMemory(NudgeDelivery nudge) async {
    try {
      setState(() {
        _isProcessingAction = true;
      });

      final nudgeService = Provider.of<NudgeService>(context, listen: false);
      await nudgeService.saveNudgeAsMemory(nudge);

      setState(() {
        _isProcessingAction = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nudge saved as a memory!'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e, stackTrace) {
      _logger.e('Failed to save nudge as memory', e, stackTrace);

      String errorMessage = 'Unable to save as memory. ';
      if (e.toString().contains('storage')) {
        errorMessage += 'Storage access issue.';
      } else if (e.toString().contains('permission')) {
        errorMessage += 'Permission denied.';
      } else {
        errorMessage += 'Please try again.';
      }

      setState(() {
        _isProcessingAction = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  /// Submits user feedback for a nudge with enhanced UI feedback
  Future<void> _submitFeedback(NudgeDelivery nudge, bool isHelpful) async {
    try {
      setState(() {
        _isProcessingAction = true;
      });

      final nudgeService = Provider.of<NudgeService>(context, listen: false);
      await nudgeService.submitNudgeFeedback(nudge.id, isHelpful);

      setState(() {
        _isProcessingAction = false;
      });

      if (mounted) {
        // Use consistent color scheme based on feedback type
        final backgroundColor = isHelpful ? AppTheme.successColor : AppTheme.calmBlue;
        final icon = isHelpful ? Icons.thumb_up : Icons.thumb_down;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  isHelpful
                      ? 'Thank you for your positive feedback!'
                      : 'Thank you for your feedback. We\'ll try to do better.',
                ),
              ],
            ),
            backgroundColor: backgroundColor,
          ),
        );
      }
    } catch (e, stackTrace) {
      _logger.e('Failed to submit nudge feedback', e, stackTrace);

      setState(() {
        _isProcessingAction = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to save feedback. Please try again.'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  /// Toggles the expanded history view
  void _toggleExpandedHistory() {
    setState(() {
      _showExpandedHistory = !_showExpandedHistory;
      if (_showExpandedHistory) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  /// Changes the history view mode and reloads data
  void _changeHistoryViewMode(HistoryViewMode mode) {
    setState(() {
      _historyViewMode = mode;
      _selectedCategory = null; // Reset category filter when changing modes
    });
    _loadHistoryNudges();
  }

  /// Sets category filter and reloads data
  void _setCategoryFilter(String? category) {
    setState(() {
      _selectedCategory = category;
      _historyViewMode = HistoryViewMode.category;
    });
    _loadHistoryNudges();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Daily Nudges'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Nudge Settings',
            onPressed: () {
              Navigator.pushNamed(context, '/nudge_settings')
                  .then((_) => _loadTodayNudges()); // Reload on return
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadTodayNudges();
          await _loadHistoryNudges();
        },
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today\'s Messages',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: AppTheme.spacingMedium),

          // Current Nudge Section with independent loading state
          _buildCurrentNudgeSection(),

          const SizedBox(height: AppTheme.spacingLarge),

          // History Section Header with toggle
          _buildHistoryHeader(),

          // History Filters (only visible when expanded)
          if (_showExpandedHistory) _buildHistoryFilters(),

          // History Content with independent loading state
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: _buildHistorySection(),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryHeader() {
    return GestureDetector(
      onTap: _toggleExpandedHistory,
      child: Row(
        children: [
          Text(
            'Nudge History',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Spacer(),
          IconButton(
            icon: AnimatedIcon(
              icon: AnimatedIcons.menu_close,
              progress: _expandAnimation,
              semanticLabel: _showExpandedHistory ? 'Collapse' : 'Expand',
              size: AppTheme.iconSizeMedium,
            ),
            onPressed: _toggleExpandedHistory,
            tooltip: _showExpandedHistory ? 'Collapse History' : 'Expand History',
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryFilters() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppTheme.spacingMedium),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filter Nudges',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppTheme.spacingMedium),

            // Time period filters
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(
                    label: 'Today',
                    selected: _historyViewMode == HistoryViewMode.today,
                    onSelected: (selected) {
                      if (selected) _changeHistoryViewMode(HistoryViewMode.today);
                    },
                  ),
                  const SizedBox(width: AppTheme.spacingSmall),
                  _buildFilterChip(
                    label: 'This Week',
                    selected: _historyViewMode == HistoryViewMode.week,
                    onSelected: (selected) {
                      if (selected) _changeHistoryViewMode(HistoryViewMode.week);
                    },
                  ),
                  const SizedBox(width: AppTheme.spacingSmall),
                  _buildFilterChip(
                    label: 'This Month',
                    selected: _historyViewMode == HistoryViewMode.month,
                    onSelected: (selected) {
                      if (selected) _changeHistoryViewMode(HistoryViewMode.month);
                    },
                  ),
                  const SizedBox(width: AppTheme.spacingSmall),
                  _buildFilterChip(
                    label: 'Helpful Nudges',
                    selected: _historyViewMode == HistoryViewMode.helpful,
                    onSelected: (selected) {
                      if (selected) _changeHistoryViewMode(HistoryViewMode.helpful);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppTheme.spacingMedium),
            const Divider(),
            const SizedBox(height: AppTheme.spacingSmall),

            // Category filters
            Text(
              'Filter by Category',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppTheme.spacingSmall),

            if (_availableCategories.isEmpty)
              const Text('No categories available')
            else
              Wrap(
                spacing: AppTheme.spacingSmall,
                children: [
                  for (final category in _availableCategories)
                    _buildFilterChip(
                      label: category,
                      selected: _historyViewMode == HistoryViewMode.category &&
                          _selectedCategory == category,
                      onSelected: (selected) {
                        if (selected) {
                          _setCategoryFilter(category);
                        }
                      },
                    ),
                ],
              ),

            const SizedBox(height: AppTheme.spacingSmall),
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Reset Filters'),
                onPressed: () {
                  _changeHistoryViewMode(HistoryViewMode.week);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required Function(bool) onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      selectedColor: AppTheme.gentleTeal.withOpacity(0.3),
      checkmarkColor: AppTheme.gentleTeal,
      labelStyle: TextStyle(
        color: selected ? AppTheme.gentleTeal : AppTheme.textColor,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingSmall,
        vertical: 4,
      ),
    );
  }

  Widget _buildCurrentNudgeSection() {
    switch (_currentNudgeState) {
      case ScreenLoadState.loading:
        return const Card(
          elevation: 4,
          child: Padding(
            padding: EdgeInsets.all(AppTheme.spacingMedium),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: AppTheme.spacingMedium),
                  Text('Loading your latest nudge...'),
                ],
              ),
            ),
          ),
        );

      case ScreenLoadState.error:
        return _buildErrorCard(
          errorMessage: _currentNudgeErrorMessage,
          onRetry: _loadTodayNudges,
        );

      case ScreenLoadState.loaded:
        return _currentNudge == null
            ? _buildEmptyState()
            : _buildCurrentNudgeCard();
    }
  }

  Widget _buildHistorySection() {
    if (!_showExpandedHistory) {
      return const SizedBox.shrink();
    }

    switch (_historyState) {
      case ScreenLoadState.loading:
        return const Padding(
          padding: EdgeInsets.all(AppTheme.spacingMedium),
          child: Center(
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: AppTheme.spacingMedium),
                Text('Loading nudge history...'),
              ],
            ),
          ),
        );

      case ScreenLoadState.error:
        return _buildErrorCard(
          errorMessage: _historyErrorMessage,
          onRetry: _loadHistoryNudges,
        );

      case ScreenLoadState.loaded:
        if (_historyNudges == null || _historyNudges!.isEmpty) {
          return _buildEmptyHistoryMessage();
        }
        return _buildHistoryListView();
    }
  }

  Widget _buildHistoryListView() {
    // Sort dates in reverse chronological order
    final sortedDates = _nudgesByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final dateKey in sortedDates)
          _buildDateSection(dateKey, _nudgesByDate[dateKey]!),
      ],
    );
  }

  Widget _buildDateSection(String dateKey, List<NudgeDelivery> nudges) {
    final date = DateTime.parse(dateKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    String dateText;
    if (date.isAtSameMomentAs(today)) {
      dateText = 'Today';
    } else if (date.isAtSameMomentAs(yesterday)) {
      dateText = 'Yesterday';
    } else {
      dateText = DateFormat.MMMEd().format(date);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppTheme.spacingSmall,
            horizontal: AppTheme.spacingSmall,
          ),
          child: Text(
            dateText,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppTheme.gentleTeal,
            ),
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: nudges.length,
          itemBuilder: (context, index) {
            final nudge = nudges[index];
            return _buildHistoryNudgeItem(nudge);
          },
        ),
        const SizedBox(height: AppTheme.spacingSmall),
        const Divider(),
      ],
    );
  }

  Widget _buildHistoryNudgeItem(NudgeDelivery nudge) {
    return Card(
      margin: const EdgeInsets.symmetric(
        vertical: AppTheme.spacingSmall / 2,
        horizontal: AppTheme.spacingSmall,
      ),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        onTap: () {
          setState(() {
            _currentNudge = nudge;
          });
          // Scroll to top to see the current nudge card
          // This would require a ScrollController
        },
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingSmall),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Category indicator
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getCategoryColor(nudge.template.category),
                      borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
                    ),
                    child: Text(
                      nudge.template.category,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Time indicator
                  Text(
                    DateFormat.jm().format(nudge.timestamp),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingSmall),
              // Nudge content
              Text(
                nudge.template.content,
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppTheme.spacingSmall),
              // Action buttons row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Feedback indicator if available
                  if (nudge.feedback != null)
                    Icon(
                      nudge.feedback!.isHelpful ? Icons.thumb_up : Icons.thumb_down,
                      color: nudge.feedback!.isHelpful ? AppTheme.calmGreen : AppTheme.mutedRed,
                      size: AppTheme.iconSizeSmall,
                    ),
                  const Spacer(),
                  // Play button
                  IconButton(
                    icon: Icon(
                      _isPlaying && _currentlyPlayingNudge?.id == nudge.id
                          ? Icons.stop
                          : Icons.play_arrow,
                      color: _isPlaying && _currentlyPlayingNudge?.id == nudge.id
                          ? AppTheme.calmBlue
                          : AppTheme.gentleTeal,
                    ),
                    onPressed: () => _playNudgeAudio(nudge),
                    tooltip: _isPlaying && _currentlyPlayingNudge?.id == nudge.id
                        ? 'Stop'
                        : 'Play',
                    iconSize: AppTheme.iconSizeSmall,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: AppTheme.spacingMedium),
                  // Save button
                  IconButton(
                    icon: const Icon(
                      Icons.save_alt,
                      color: AppTheme.calmBlue,
                    ),
                    onPressed: () => _saveAsMemory(nudge),
                    tooltip: 'Save as Memory',
                    iconSize: AppTheme.iconSizeSmall,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    if (category.toLowerCase().contains('gratitude')) {
      return Colors.purple;
    } else if (category.toLowerCase().contains('mindfulness')) {
      return Colors.teal;
    } else if (category.toLowerCase().contains('reflection')) {
      return Colors.blue;
    } else if (category.toLowerCase().contains('reassurance')) {
      return Colors.green;
    } else if (category.toLowerCase().contains('cognitive')) {
      return Colors.orange;
    } else {
      return AppTheme.calmBlue;
    }
  }

  Widget _buildEmptyHistoryMessage() {
    String message = 'No nudges found';
    String details = '';

    switch (_historyViewMode) {
      case HistoryViewMode.today:
        message = 'No nudges today';
        details = 'You haven\'t received any nudges today.';
        break;
      case HistoryViewMode.week:
        message = 'No nudges this week';
        details = 'You haven\'t received any nudges in the past week.';
        break;
      case HistoryViewMode.month:
        message = 'No nudges this month';
        details = 'You haven\'t received any nudges in the past month.';
        break;
      case HistoryViewMode.helpful:
        message = 'No helpful nudges';
        details = 'You haven\'t marked any nudges as helpful yet.';
        break;
      case HistoryViewMode.category:
        message = 'No nudges in this category';
        details = 'Try selecting a different category.';
        break;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLarge),
        child: Column(
          children: [
            const Icon(
              Icons.history_toggle_off,
              size: AppTheme.iconSizeLarge,
              color: AppTheme.textSecondaryColor,
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            Text(
              message,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            Text(
              details,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondaryColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Try Different Filters'),
              onPressed: () {
                _changeHistoryViewMode(HistoryViewMode.week);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard({
    required String errorMessage,
    required VoidCallback onRetry,
  }) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppTheme.errorColor,
              size: AppTheme.iconSizeLarge,
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            Text(
              errorMessage,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.calmBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.speaker_notes_off,
              color: AppTheme.textLightColor,
              size: AppTheme.iconSizeLarge,
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            Text(
              'No nudges received today',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            Text(
              'Your therapeutic nudges will appear here\nthroughout the day',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            _isProcessingAction
                ? const CircularProgressIndicator()
                : ElevatedButton.icon(
              onPressed: () async {
                setState(() {
                  _isProcessingAction = true;
                });

                try {
                  final nudgeService = Provider.of<NudgeService>(context, listen: false);
                  await nudgeService.triggerManualNudge();
                  await _loadTodayNudges();
                } catch (e, stackTrace) {
                  _logger.e('Failed to request manual nudge', e, stackTrace);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Unable to request a nudge. Please try again.'),
                        backgroundColor: AppTheme.errorColor,
                      ),
                    );
                  }
                } finally {
                  if (mounted) {
                    setState(() {
                      _isProcessingAction = false;
                    });
                  }
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Request a Nudge Now'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentNudgeCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.speaker_notes,
                  color: AppTheme.calmBlue,
                  size: AppTheme.iconSizeMedium,
                ),
                const SizedBox(width: AppTheme.spacingSmall),
                Text(
                  'Latest Nudge',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
                Text(
                  _formatTime(_currentNudge!.timestamp),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: AppTheme.spacingSmall),
            // Category tag
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: _getCategoryColor(_currentNudge!.template.category).withOpacity(0.2),
                borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
              ),
              child: Text(
                _currentNudge!.template.category,
                style: TextStyle(
                  color: _getCategoryColor(_currentNudge!.template.category),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            Text(
              _currentNudge!.template.content,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Enhanced play button with visual state feedback
                _buildActionButton(
                  icon: _isPlaying && _currentlyPlayingNudge?.id == _currentNudge!.id
                      ? Icons.stop
                      : Icons.play_arrow,
                  label: _isPlaying && _currentlyPlayingNudge?.id == _currentNudge!.id
                      ? 'Stop'
                      : 'Play',
                  onPressed: _isProcessingAction
                      ? null // Disable during processing
                      : () => _playNudgeAudio(_currentNudge!),
                  isLoading: _isProcessingAction && _isPlaying && _currentlyPlayingNudge?.id == _currentNudge!.id,
                  color: _isPlaying && _currentlyPlayingNudge?.id == _currentNudge!.id
                      ? AppTheme.calmBlue
                      : AppTheme.gentleTeal,
                ),
                // Save as memory button
                _buildActionButton(
                  icon: Icons.save,
                  label: 'Save as Memory',
                  onPressed: _isProcessingAction
                      ? null // Disable during processing
                      : () => _saveAsMemory(_currentNudge!),
                  isLoading: _isProcessingAction && !_isPlaying,
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            const Divider(),
            const SizedBox(height: AppTheme.spacingSmall),
            Center(
              child: Text(
                'Was this helpful?',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildFeedbackButton(
                  icon: Icons.thumb_up,
                  color: AppTheme.calmGreen,
                  tooltip: 'This was helpful',
                  onPressed: () => _submitFeedback(_currentNudge!, true),
                ),
                const SizedBox(width: AppTheme.spacingMedium),
                _buildFeedbackButton(
                  icon: Icons.thumb_down,
                  color: AppTheme.mutedRed,
                  tooltip: 'This was not helpful',
                  onPressed: () => _submitFeedback(_currentNudge!, false),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
    Color color = AppTheme.gentleTeal,
  }) {
    return ElevatedButton.icon(
      icon: isLoading
          ? const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2,
        ),
      )
          : Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMedium,
          vertical: AppTheme.spacingSmall,
        ),
        minimumSize: const Size(AppTheme.buttonMinWidth, AppTheme.buttonMinHeight),
        disabledBackgroundColor: color.withOpacity(0.6),
        disabledForegroundColor: Colors.white.withOpacity(0.8),
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildFeedbackButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: _isProcessingAction ? null : onPressed,
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusCircular),
        child: Container(
          padding: const EdgeInsets.all(AppTheme.spacingSmall),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.2),
          ),
          child: Icon(
            icon,
            color: color,
            size: AppTheme.iconSizeMedium,
          ),
        ),
      ),
    );
  }

  /// Formats a timestamp into a readable time string
  /// Uses locale-appropriate time format
  String _formatTime(DateTime timestamp) {
    return DateFormat.jm().format(timestamp);
  }

  @override
  void dispose() {
    // Clean up any resources
    if (_isPlaying) {
      final nudgeService = Provider.of<NudgeService>(context, listen: false);
      nudgeService.stopNudgeAudio();
    }
    _expandController.dispose();
    super.dispose();
  }
}