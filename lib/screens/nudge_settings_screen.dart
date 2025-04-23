import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'package:milo/models/nudge_model.dart';
import 'package:milo/services/nudge_service.dart';
import 'package:milo/theme/app_theme.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// NudgeSettingsScreen allows users to customize their therapeutic nudge experience
///
/// Specifically designed for users 55+ with accessibility in mind,
/// this screen provides options to configure nudge frequency, categories,
/// and delivery preferences.
class NudgeSettingsScreen extends StatefulWidget {
  const NudgeSettingsScreen({Key? key}) : super(key: key);

  @override
  State<NudgeSettingsScreen> createState() => _NudgeSettingsScreenState();
}

/// Represents the current state of the settings screen
enum SettingsScreenState {
  loading,
  loaded,
  saving,
  error,
}

class _NudgeSettingsScreenState extends State<NudgeSettingsScreen> {
  final Logger _logger = Logger();

  // State management using enum
  SettingsScreenState _screenState = SettingsScreenState.loading;
  String _errorMessage = '';
  String _errorContext = ''; // Added to provide more context about the error

  // Settings state
  late NudgeSettings _settings;
  final List<String> _selectedCategories = [];

  // Available nudge categories
  final List<NudgeCategory> _availableCategories = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// Loads user's current nudge settings
  Future<void> _loadSettings() async {
    // Check connectivity first
    bool isConnected = await _checkConnectivity();
    if (!isConnected) {
      setState(() {
        _screenState = SettingsScreenState.error;
        _errorContext = 'connectivity';
        _errorMessage = 'No internet connection. Please check your network and try again.';
      });
      return;
    }

    try {
      setState(() {
        _screenState = SettingsScreenState.loading;
        _errorMessage = '';
        _errorContext = '';
      });

      final nudgeService = Provider.of<NudgeService>(context, listen: false);

      // Load settings and available categories simultaneously
      final settingsFuture = nudgeService.getUserNudgeSettings();
      final categoriesFuture = nudgeService.getAvailableNudgeCategories();

      final results = await Future.wait([settingsFuture, categoriesFuture]);
      final loadedSettings = results[0] as NudgeSettings;
      final loadedCategories = results[1] as List<NudgeCategory>;

      if (!mounted) return;

      setState(() {
        _settings = loadedSettings;
        _availableCategories.clear();
        _availableCategories.addAll(loadedCategories);
        _selectedCategories.clear();
        _selectedCategories.addAll(_settings.enabledCategories);
        _screenState = SettingsScreenState.loaded;
      });
    } catch (e, stackTrace) {
      _logger.e('Failed to load nudge settings', e, stackTrace);

      if (!mounted) return;

      String errorMessage = 'Unable to load settings. ';
      String errorContext = 'general';

      if (e.toString().contains('permission')) {
        errorMessage += 'Permission denied. Please check app permissions.';
        errorContext = 'permission';
      } else if (e.toString().contains('not found')) {
        errorMessage += 'Settings data not found. Default settings will be used.';
        errorContext = 'data';
      } else if (e.toString().contains('timeout')) {
        errorMessage += 'Request timed out. Please try again later.';
        errorContext = 'timeout';
      } else {
        errorMessage += 'Please try again.';
      }

      setState(() {
        _screenState = SettingsScreenState.error;
        _errorMessage = errorMessage;
        _errorContext = errorContext;
      });
    }
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

  /// Saves updated nudge settings
  Future<void> _saveSettings() async {
    if (_screenState == SettingsScreenState.saving) return;

    // Check connectivity before saving
    bool isConnected = await _checkConnectivity();
    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No internet connection. Changes cannot be saved.'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    try {
      setState(() {
        _screenState = SettingsScreenState.saving;
        _errorMessage = '';
        _errorContext = '';
      });

      // Validate settings before saving
      if (_selectedCategories.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select at least one category'),
            backgroundColor: AppTheme.warningColor,
          ),
        );
        setState(() {
          _screenState = SettingsScreenState.loaded;
        });
        return;
      }

      // Update settings object with current values
      _settings = _settings.copyWith(
        isEnabled: _settings.isEnabled,
        maxDailyNudges: _settings.maxDailyNudges,
        enabledCategories: List.from(_selectedCategories),
        morningWindow: _settings.morningWindow,
        noonWindow: _settings.noonWindow,
        eveningWindow: _settings.eveningWindow,
      );

      final nudgeService = Provider.of<NudgeService>(context, listen: false);
      await nudgeService.updateUserNudgeSettings(_settings);

      if (!mounted) return;

      setState(() {
        _screenState = SettingsScreenState.loaded;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved successfully'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    } catch (e, stackTrace) {
      _logger.e('Failed to save nudge settings', e, stackTrace);

      if (!mounted) return;

      String errorMessage = 'Unable to save settings. ';

      if (e.toString().contains('permission')) {
        errorMessage += 'Permission denied to update settings.';
      } else if (e.toString().contains('timeout')) {
        errorMessage += 'Request timed out. Try again later.';
      } else if (e.toString().contains('invalid')) {
        errorMessage += 'Invalid settings data.';
      } else {
        errorMessage += 'Please try again.';
      }

      setState(() {
        _screenState = SettingsScreenState.loaded; // Return to loaded state
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nudge Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        actions: [
          // Save button in app bar
          _screenState == SettingsScreenState.saving
              ? const Padding(
            padding: EdgeInsets.all(16.0),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: AppTheme.gentleTeal,
                strokeWidth: 2,
              ),
            ),
          )
              : IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save Settings',
            onPressed: _screenState == SettingsScreenState.loaded
                ? _saveSettings
                : null, // Disable if not in loaded state
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_screenState) {
      case SettingsScreenState.loading:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: AppTheme.spacingMedium),
              Text('Loading your settings...'),
            ],
          ),
        );

      case SettingsScreenState.error:
        return _buildErrorState();

      case SettingsScreenState.saving:
      case SettingsScreenState.loaded:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Main settings header with description
              Text(
                'Therapeutic Nudge Settings',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppTheme.spacingSmall),
              Text(
                'Customize how you receive therapeutic audio nudges throughout your day',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.textSecondaryColor,
                ),
              ),
              const SizedBox(height: AppTheme.spacingLarge),

              // Enable/Disable nudges
              _buildEnableNudgesSection(),
              const SizedBox(height: AppTheme.spacingLarge),

              // Daily frequency slider
              _buildFrequencySection(),
              const SizedBox(height: AppTheme.spacingLarge),

              // Time windows section
              _buildTimeWindowsSection(),
              const SizedBox(height: AppTheme.spacingLarge),

              // Categories section
              _buildCategoriesSection(),
              const SizedBox(height: AppTheme.spacingLarge),

              // Save button at bottom
              Center(
                child: _screenState == SettingsScreenState.saving
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                  onPressed: _saveSettings,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Settings'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(200, AppTheme.buttonMinHeight),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMedium),
            ],
          ),
        );
    }
  }

  /// Build the error state UI based on error context
  Widget _buildErrorState() {
    IconData errorIcon;
    Color iconColor;

    // Choose appropriate icon based on error context
    switch (_errorContext) {
      case 'connectivity':
        errorIcon = Icons.signal_wifi_off;
        iconColor = AppTheme.warningColor;
        break;
      case 'permission':
        errorIcon = Icons.no_accounts;
        iconColor = AppTheme.errorColor;
        break;
      case 'timeout':
        errorIcon = Icons.timer_off;
        iconColor = AppTheme.warningColor;
        break;
      case 'data':
        errorIcon = Icons.data_array_off;
        iconColor = AppTheme.warningColor;
        break;
      default:
        errorIcon = Icons.error_outline;
        iconColor = AppTheme.errorColor;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              errorIcon,
              color: iconColor,
              size: AppTheme.iconSizeLarge,
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            Text(
              _errorMessage,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            ElevatedButton.icon(
              onPressed: _loadSettings,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.calmBlue,
                minimumSize: const Size(150, AppTheme.buttonMinHeight),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnableNudgesSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enable Therapeutic Nudges',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            Text(
              'Turn therapeutic nudges on or off',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondaryColor,
              ),
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            SwitchListTile(
              title: Text(
                _settings.isEnabled ? 'Nudges are ON' : 'Nudges are OFF',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _settings.isEnabled
                      ? AppTheme.calmGreen
                      : AppTheme.textColor, // Changed for better contrast
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                _settings.isEnabled
                    ? 'You will receive therapeutic nudges'
                    : 'You will not receive any nudges',
              ),
              value: _settings.isEnabled,
              onChanged: (value) {
                setState(() {
                  _settings = _settings.copyWith(isEnabled: value);
                });
              },
              secondary: Icon(
                _settings.isEnabled ? Icons.notifications_active : Icons.notifications_off,
                color: _settings.isEnabled ? AppTheme.calmGreen : AppTheme.textColor, // Changed for better contrast
                size: AppTheme.iconSizeMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrequencySection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily Frequency',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            Text(
              'Choose how many nudges you want to receive each day',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondaryColor,
              ),
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            Row(
              children: [
                const Icon(
                  Icons.notifications_none,
                  color: AppTheme.textColor, // Changed for better contrast
                  size: AppTheme.iconSizeMedium,
                ),
                Expanded(
                  child: Slider(
                    value: _settings.maxDailyNudges.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '${_settings.maxDailyNudges} per day',
                    onChanged: (value) {
                      setState(() {
                        _settings = _settings.copyWith(
                          maxDailyNudges: value.round(),
                        );
                      });
                    },
                  ),
                ),
                const Icon(
                  Icons.notifications_active,
                  color: AppTheme.gentleTeal,
                  size: AppTheme.iconSizeMedium,
                ),
              ],
            ),
            Center(
              child: Text(
                '${_settings.maxDailyNudges} nudge${_settings.maxDailyNudges > 1 ? 's' : ''} per day',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeWindowsSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Time Windows',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            Text(
              'Select when you would like to receive nudges',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondaryColor,
              ),
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            _buildTimeWindowTile(
              title: 'Morning',
              subtitle: 'Between 7:00 AM and 9:00 AM',
              icon: Icons.wb_sunny,
              isEnabled: _settings.morningWindow.isEnabled,
              onChanged: (value) {
                setState(() {
                  final updatedWindow = _settings.morningWindow.copyWith(
                    isEnabled: value,
                  );
                  _settings = _settings.copyWith(
                    morningWindow: updatedWindow,
                  );
                });
              },
            ),
            const Divider(),
            _buildTimeWindowTile(
              title: 'Noon',
              subtitle: 'Between 12:00 PM and 2:00 PM',
              icon: Icons.wb_twighlight,
              isEnabled: _settings.noonWindow.isEnabled,
              onChanged: (value) {
                setState(() {
                  final updatedWindow = _settings.noonWindow.copyWith(
                    isEnabled: value,
                  );
                  _settings = _settings.copyWith(
                    noonWindow: updatedWindow,
                  );
                });
              },
            ),
            const Divider(),
            _buildTimeWindowTile(
              title: 'Evening',
              subtitle: 'Between 6:00 PM and 8:00 PM',
              icon: Icons.nights_stay,
              isEnabled: _settings.eveningWindow.isEnabled,
              onChanged: (value) {
                setState(() {
                  final updatedWindow = _settings.eveningWindow.copyWith(
                    isEnabled: value,
                  );
                  _settings = _settings.copyWith(
                    eveningWindow: updatedWindow,
                  );
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeWindowTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isEnabled,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(subtitle),
      value: isEnabled,
      onChanged: onChanged,
      secondary: Icon(
        icon,
        color: isEnabled ? AppTheme.gentleTeal : AppTheme.textColor, // Changed for better contrast
        size: AppTheme.iconSizeMedium,
      ),
    );
  }

  Widget _buildCategoriesSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nudge Categories',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            Text(
              'Select the types of therapeutic nudges you want to receive',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondaryColor,
              ),
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            if (_availableCategories.isEmpty)
              const Center(
                child: Text(
                  'No categories available',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: AppTheme.textColor, // Changed for better contrast
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _availableCategories.length,
                itemBuilder: (context, index) {
                  final category = _availableCategories[index];
                  final isSelected = _selectedCategories.contains(category.id);

                  return CheckboxListTile(
                    title: Text(
                      category.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(category.description),
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          if (!_selectedCategories.contains(category.id)) {
                            _selectedCategories.add(category.id);
                          }
                        } else {
                          _selectedCategories.remove(category.id);
                        }
                      });
                    },
                    secondary: Icon(
                      _getCategoryIcon(category.name.toLowerCase()),
                      color: isSelected ? AppTheme.gentleTeal : AppTheme.textColor, // Changed for better contrast
                      size: AppTheme.iconSizeMedium,
                    ),
                    controlAffinity: ListTileControlAffinity.trailing,
                  );
                },
              ),
            const SizedBox(height: AppTheme.spacingMedium),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.select_all),
                  label: const Text('Select All'),
                  onPressed: () {
                    setState(() {
                      _selectedCategories.clear();
                      _selectedCategories.addAll(
                        _availableCategories.map((category) => category.id),
                      );
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingMedium,
                      vertical: AppTheme.spacingSmall,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.spacingMedium),
                // Added Deselect All button
                OutlinedButton.icon(
                  icon: const Icon(Icons.deselect),
                  label: const Text('Deselect All'),
                  onPressed: () {
                    setState(() {
                      _selectedCategories.clear();
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingMedium,
                      vertical: AppTheme.spacingSmall,
                    ),
                  ),
                ),
              ],
            ),
            // Add warning if no categories are selected
            if (_selectedCategories.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: AppTheme.spacingMedium),
                child: Center(
                  child: Text(
                    'Please select at least one category to receive nudges',
                    style: TextStyle(
                      color: AppTheme.warningColor,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Returns an icon based on the category name
  IconData _getCategoryIcon(String categoryName) {
    if (categoryName.contains('gratitude')) {
      return Icons.favorite;
    } else if (categoryName.contains('mindfulness')) {
      return Icons.spa;
    } else if (categoryName.contains('reflection')) {
      return Icons.psychology;
    } else if (categoryName.contains('reassurance')) {
      return Icons.security;
    } else if (categoryName.contains('cognitive')) {
      return Icons.psychology_alt;
    } else {
      return Icons.speaker_notes;
    }
  }
}