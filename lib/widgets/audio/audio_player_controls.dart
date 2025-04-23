// Copyright © 2025 Milo App. All rights reserved.
// Author: Milo Development Team
// File: lib/widgets/audio/audio_player_controls.dart
// Version: 2.0.0
// Last Updated: April 22, 2025
// Description: Reusable audio player control components optimized for elderly users (55+)
//
// Change history:
// 1.0.0 - Initial implementation with basic accessibility features
// 2.0.0 - Added enhanced features:
//   - Orientation-specific layouts (portrait/landscape)
//   - Accessibility announcements for screen readers
//   - User setting persistence between sessions
//   - Background audio control integration
//   - Emergency stop functionality
//   - Enhanced error recovery mechanisms

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min, max, pi, sin;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';
import '../../services/audio_player_service.dart';
import '../../utils/advanced_logger.dart';
import '../../utils/error_reporter.dart';

/// Constants for accessibility
const kWaveformDataPreferenceKey = 'audio_player_waveform_data';
const kVolumePreferenceKey = 'audio_player_volume';
const kSpeedPreferenceKey = 'audio_player_speed';
const kLastPositionPreferenceKey = 'audio_player_last_position';
const kA11yAnnouncementsEnabledKey = 'audio_player_a11y_announcements_enabled';

/// Log tags for consistent logging
const String _logTag = 'AudioPlayerControls';

/// Model holding the state of audio player controls
class AudioControlsState extends ChangeNotifier {
  // Player state
  bool _isPlaying = false;
  bool _isBuffering = false;
  double _volume = 0.8;
  double _speed = 1.0;
  double _progress = 0.0;
  int _positionMs = 0;
  int _durationMs = 0;
  bool _isFocusMode = false;
  bool _isRampingSpeed = false;
  double _targetSpeed = 1.0;
  double _currentRampSpeed = 0.5;
  bool _isUserDragging = false;
  double _dragValue = 0.0;

  // NEW: Background control settings
  bool _isBackgroundControlEnabled = true;
  String? _mediaId;
  Map<String, dynamic>? _mediaMetadata;

  // NEW: Error recovery state
  bool _isInErrorRecoveryMode = false;
  int _errorRecoveryAttempts = 0;
  Timer? _errorRecoveryTimer;

  // NEW: Last known position for each audio source
  final Map<String, int> _lastPositions = {};

  // NEW: User preferences storage
  SharedPreferences? _preferences;
  bool _preferencesLoaded = false;

  // NEW: Orientation state
  Orientation _currentOrientation = Orientation.portrait;

  // NEW: Accessibility announcement state
  bool _accessibilityAnnouncementsEnabled = true;

  // Getters
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  double get volume => _volume;
  double get speed => _speed;
  double get progress => _isUserDragging ? _dragValue : _progress;
  int get positionMs => _positionMs;
  int get durationMs => _durationMs;
  bool get isFocusMode => _isFocusMode;
  bool get isRampingSpeed => _isRampingSpeed;
  double get currentSpeed => _isRampingSpeed ? _currentRampSpeed : _speed;

  // NEW: Background control getters
  bool get isBackgroundControlEnabled => _isBackgroundControlEnabled;
  String? get mediaId => _mediaId;
  Map<String, dynamic>? get mediaMetadata => _mediaMetadata;

  // NEW: Error recovery getters
  bool get isInErrorRecoveryMode => _isInErrorRecoveryMode;
  int get errorRecoveryAttempts => _errorRecoveryAttempts;

  // NEW: Orientation getter
  Orientation get currentOrientation => _currentOrientation;

  // NEW: Accessibility getter
  bool get accessibilityAnnouncementsEnabled => _accessibilityAnnouncementsEnabled;

  // Setters
  set isPlaying(bool value) {
    if (_isPlaying != value) {
      _isPlaying = value;
      notifyListeners();

      // NEW: Announce state change to screen readers
      if (_accessibilityAnnouncementsEnabled) {
        _announcePlaybackStateChange(value);
      }
    }
  }

  set isBuffering(bool value) {
    if (_isBuffering != value) {
      _isBuffering = value;
      notifyListeners();

      // NEW: Announce buffering to screen readers
      if (_accessibilityAnnouncementsEnabled && value) {
        _announceBuffering();
      }
    }
  }

  set volume(double value) {
    if (_volume != value) {
      _volume = value;
      notifyListeners();

      // NEW: Save volume preference
      _savePreference(kVolumePreferenceKey, value);

      // NEW: Announce volume change to screen readers
      if (_accessibilityAnnouncementsEnabled) {
        _announceVolumeChange(value);
      }
    }
  }

  set speed(double value) {
    if (_speed != value) {
      _speed = value;
      notifyListeners();

      // NEW: Save speed preference
      _savePreference(kSpeedPreferenceKey, value);

      // NEW: Announce speed change to screen readers
      if (_accessibilityAnnouncementsEnabled) {
        _announceSpeedChange(value);
      }
    }
  }

  set progress(double value) {
    if (_progress != value) {
      _progress = value;
      notifyListeners();
    }
  }

  set positionMs(int value) {
    if (_positionMs != value) {
      _positionMs = value;
      _progress = _durationMs > 0 ? _positionMs / _durationMs : 0.0;
      notifyListeners();

      // NEW: Save last position if we have a media ID
      if (_mediaId != null) {
        _lastPositions[_mediaId!] = value;
        _saveLastPosition(_mediaId!, value);
      }
    }
  }

  set durationMs(int value) {
    if (_durationMs != value) {
      _durationMs = value;
      _progress = _durationMs > 0 ? _positionMs / _durationMs : 0.0;
      notifyListeners();
    }
  }

  // NEW: Background control setters
  set isBackgroundControlEnabled(bool value) {
    if (_isBackgroundControlEnabled != value) {
      _isBackgroundControlEnabled = value;
      notifyListeners();
    }
  }

  set mediaId(String? value) {
    if (_mediaId != value) {
      _mediaId = value;
      notifyListeners();

      // Load the last position for this media if available
      if (value != null) {
        _loadLastPosition(value);
      }
    }
  }

  set mediaMetadata(Map<String, dynamic>? value) {
    _mediaMetadata = value;
    notifyListeners();
  }

  // NEW: Orientation setter
  set currentOrientation(Orientation value) {
    if (_currentOrientation != value) {
      _currentOrientation = value;
      notifyListeners();

      // NEW: Announce orientation change to screen readers
      if (_accessibilityAnnouncementsEnabled) {
        _announceOrientationChange(value);
      }
    }
  }

  // NEW: Accessibility setter
  set accessibilityAnnouncementsEnabled(bool value) {
    if (_accessibilityAnnouncementsEnabled != value) {
      _accessibilityAnnouncementsEnabled = value;
      notifyListeners();

      // Save the preference
      _savePreference(kA11yAnnouncementsEnabledKey, value);
    }
  }

  // User dragging the progress bar
  void startDragging(double value) {
    _isUserDragging = true;
    _dragValue = value;
    notifyListeners();
  }

  void updateDragValue(double value) {
    if (_isUserDragging) {
      _dragValue = value;
      notifyListeners();
    }
  }

  void endDragging() {
    _isUserDragging = false;
    notifyListeners();
  }

  // Focus mode management
  void activateFocusMode() {
    _cancelFocusModeTimer();
    _isFocusMode = true;
    notifyListeners();

    // Auto-deactivate after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      _isFocusMode = false;
      notifyListeners();
    });
  }

  void _cancelFocusModeTimer() {
    // Cancel any existing timer
  }

  // Speed ramping
  void startSpeedRamp(double targetSpeed) {
    _isRampingSpeed = true;
    _targetSpeed = targetSpeed;
    _currentRampSpeed = 0.5; // Start at half speed
    notifyListeners();
  }

  void updateRampSpeed(double newSpeed) {
    if (_isRampingSpeed) {
      _currentRampSpeed = newSpeed;
      notifyListeners();
    }
  }

  void stopSpeedRamp() {
    _isRampingSpeed = false;
    notifyListeners();
  }

  // Update state from PlaybackStatus
  void updateFromStatus(PlaybackStatus status) {
    isPlaying = status.state == AudioPlayerState.playing;
    isBuffering = status.buffering;
    volume = status.volume;
    speed = status.speed;
    positionMs = status.positionMs;
    durationMs = status.durationMs;

    // NEW: Update mediaId if available
    if (status.path != null && _mediaId != status.path) {
      mediaId = status.path;
    }

    // NEW: Update metadata if available
    if (status.nudge != null) {
      mediaMetadata = {
        'title': status.nudge!.title,
        'category': status.nudge!.category,
        'timeWindow': status.nudge!.timeWindow,
      };
    }
  }

  // NEW: Initialize preferences
  Future<void> initializePreferences() async {
    if (_preferencesLoaded) return;

    try {
      _preferences = await SharedPreferences.getInstance();

      // Load saved volume
      final savedVolume = _preferences!.getDouble(kVolumePreferenceKey);
      if (savedVolume != null) {
        _volume = savedVolume;
      }

      // Load saved speed
      final savedSpeed = _preferences!.getDouble(kSpeedPreferenceKey);
      if (savedSpeed != null) {
        _speed = savedSpeed;
      }

      // Load accessibility setting
      final savedA11yEnabled = _preferences!.getBool(kA11yAnnouncementsEnabledKey);
      if (savedA11yEnabled != null) {
        _accessibilityAnnouncementsEnabled = savedA11yEnabled;
      }

      _preferencesLoaded = true;
      notifyListeners();

      AdvancedLogger.i(_logTag, 'Preferences loaded successfully');
    } catch (e, stackTrace) {
      AdvancedLogger.e(_logTag, 'Failed to load preferences: $e', stackTrace);
      ErrorReporter.reportError('AudioControlsState.initializePreferences', e, stackTrace);

      // Continue with default values
      _preferencesLoaded = true;
    }
  }

  // NEW: Save a preference
  Future<void> _savePreference(String key, dynamic value) async {
    if (_preferences == null) {
      await initializePreferences();
    }

    try {
      if (value is double) {
        await _preferences!.setDouble(key, value);
      } else if (value is int) {
        await _preferences!.setInt(key, value);
      } else if (value is bool) {
        await _preferences!.setBool(key, value);
      } else if (value is String) {
        await _preferences!.setString(key, value);
      } else if (value is List<String>) {
        await _preferences!.setStringList(key, value);
      }
    } catch (e, stackTrace) {
      AdvancedLogger.e(_logTag, 'Failed to save preference: $key, $e', stackTrace);
      ErrorReporter.reportError('AudioControlsState._savePreference', e, stackTrace);
    }
  }

  // NEW: Save last position for a media item
  Future<void> _saveLastPosition(String mediaId, int positionMs) async {
    final key = '${kLastPositionPreferenceKey}_$mediaId';
    await _savePreference(key, positionMs);
  }

  // NEW: Load last position for a media item
  Future<void> _loadLastPosition(String mediaId) async {
    if (_preferences == null) {
      await initializePreferences();
    }

    try {
      final key = '${kLastPositionPreferenceKey}_$mediaId';
      final savedPosition = _preferences!.getInt(key);

      if (savedPosition != null && savedPosition > 0) {
        _lastPositions[mediaId] = savedPosition;
        AdvancedLogger.d(_logTag, 'Loaded last position for $mediaId: $savedPosition ms');
      }
    } catch (e, stackTrace) {
      AdvancedLogger.e(_logTag, 'Failed to load last position for $mediaId: $e', stackTrace);
      ErrorReporter.reportError('AudioControlsState._loadLastPosition', e, stackTrace);
    }
  }

  // NEW: Get last position for a media item
  int? getLastPosition(String mediaId) {
    return _lastPositions[mediaId];
  }

  // NEW: Start error recovery
  void startErrorRecovery() {
    if (_isInErrorRecoveryMode) return;

    _isInErrorRecoveryMode = true;
    _errorRecoveryAttempts = 0;
    notifyListeners();

    AdvancedLogger.w(_logTag, 'Starting error recovery mode');

    // Schedule first recovery attempt
    _scheduleErrorRecoveryAttempt();
  }

  // NEW: Schedule error recovery attempt
  void _scheduleErrorRecoveryAttempt() {
    _cancelErrorRecoveryTimer();

    // Exponential backoff: 1s, 2s, 4s, 8s, 16s
    final delayMs = 1000 * pow(2, min(_errorRecoveryAttempts, 4));

    _errorRecoveryTimer = Timer(Duration(milliseconds: delayMs), () {
      _errorRecoveryAttempts++;
      notifyListeners();

      // Notify that we're ready for another attempt
      if (_errorRecoveryAttempts <= 5) {
        AdvancedLogger.i(_logTag, 'Error recovery attempt $_errorRecoveryAttempts scheduled');
      } else {
        // Give up after 5 attempts
        stopErrorRecovery();
      }
    });
  }

  // NEW: Stop error recovery
  void stopErrorRecovery() {
    if (!_isInErrorRecoveryMode) return;

    _cancelErrorRecoveryTimer();
    _isInErrorRecoveryMode = false;
    _errorRecoveryAttempts = 0;
    notifyListeners();

    AdvancedLogger.i(_logTag, 'Stopping error recovery mode');
  }

  // NEW: Cancel error recovery timer
  void _cancelErrorRecoveryTimer() {
    _errorRecoveryTimer?.cancel();
    _errorRecoveryTimer = null;
  }

  // NEW: Make accessibility announcements
  void _announcePlaybackStateChange(bool isPlaying) {
    final message = isPlaying ? 'Playback started' : 'Playback paused';
    _makeAccessibilityAnnouncement(message);
  }

  void _announceBuffering() {
    _makeAccessibilityAnnouncement('Loading audio, please wait');
  }

  void _announceVolumeChange(double volume) {
    final percentage = (volume * 100).round();
    _makeAccessibilityAnnouncement('Volume set to $percentage percent');
  }

  void _announceSpeedChange(double speed) {
    _makeAccessibilityAnnouncement('Speed set to ${speed.toStringAsFixed(1)} times');
  }

  void _announceOrientationChange(Orientation orientation) {
    final message = orientation == Orientation.portrait
        ? 'Portrait mode'
        : 'Landscape mode';
    _makeAccessibilityAnnouncement(message);
  }

  void announcePosition(int positionMs, int durationMs) {
    if (!_accessibilityAnnouncementsEnabled) return;

    // Only announce every 10 seconds or at key points
    if (positionMs % 10000 >= 1000) return;

    final positionMinutes = positionMs ~/ 60000;
    final positionSeconds = (positionMs % 60000) ~/ 1000;

    final durationMinutes = durationMs ~/ 60000;
    final durationSeconds = (durationMs % 60000) ~/ 1000;

    final position = '$positionMinutes minutes, $positionSeconds seconds';
    final duration = '$durationMinutes minutes, $durationSeconds seconds';

    // Calculate percentage
    final percentage = durationMs > 0 ? (positionMs * 100 ~/ durationMs) : 0;

    if (percentage % 25 == 0 && percentage > 0) {
      // Announce at 25%, 50%, 75%
      _makeAccessibilityAnnouncement('$percentage percent complete');
    } else if (positionMs % 30000 < 1000) {
      // Announce position every 30 seconds
      _makeAccessibilityAnnouncement('Position $position of $duration');
    }
  }

  void _makeAccessibilityAnnouncement(String message) {
    if (!_accessibilityAnnouncementsEnabled) return;

    AdvancedLogger.d(_logTag, 'Accessibility announcement: $message');
    SemanticsService.announce(message, TextDirection.ltr);
  }

  // NEW: Register with system media controls
  Future<void> registerWithSystemMediaControls(
      VoidCallback onPlay,
      VoidCallback onPause,
      VoidCallback onStop,
      ValueChanged<int> onSeek
      ) async {
    if (!_isBackgroundControlEnabled) return;

    try {
      // Set up handler for system media button events
      await SystemChannels.platform.invokeMethod<void>(
        'SystemMediaControls.setup',
        <String, dynamic>{
          'androidNotificationChannelName': 'Milo Audio Player',
          'androidNotificationChannelDescription':
          'Controls for audio playback in Milo app',
          'androidNotificationIcon': 'mipmap/ic_launcher',
          'androidShowNotificationBadge': true,
          'androidNotificationClickStartsActivity': true,
          'androidNotificationOngoing': true,
          'androidStopForegroundOnPause': false,
        },
      );

      // Register callbacks for media button events
      ServicesBinding.instance.defaultBinaryMessenger.setMessageHandler(
        'flutter/media_controls',
            (ByteData? message) async {
          if (message == null) return null;

          final methodCall = const StandardMethodCodec()
              .decodeMethodCall(message);

          switch (methodCall.method) {
            case 'play':
              onPlay();
              break;
            case 'pause':
              onPause();
              break;
            case 'stop':
              onStop();
              break;
            case 'seekTo':
              final positionMs = methodCall.arguments as int?;
              if (positionMs != null) {
                onSeek(positionMs);
              }
              break;
          }

          return null;
        },
      );

      AdvancedLogger.i(_logTag, 'Registered with system media controls');
    } catch (e, stackTrace) {
      AdvancedLogger.e(
          _logTag,
          'Failed to register with system media controls: $e',
          stackTrace
      );
      ErrorReporter.reportError(
          'AudioControlsState.registerWithSystemMediaControls',
          e,
          stackTrace
      );

      // Disable background controls on failure
      _isBackgroundControlEnabled = false;
    }
  }

  // NEW: Update system media controls metadata
  Future<void> updateSystemMediaControlsMetadata({
    required String title,
    String? artist,
    String? album,
    int? duration,
    int? position,
    bool isPlaying = false,
  }) async {
    if (!_isBackgroundControlEnabled) return;

    try {
      await SystemChannels.platform.invokeMethod<void>(
        'SystemMediaControls.updateMetadata',
        <String, dynamic>{
          'title': title,
          'artist': artist ?? 'Milo Nudge',
          'album': album ?? 'Therapeutic Audio',
          'duration': duration,
          'playbackState': isPlaying ? 'playing' : 'paused',
          'position': position,
        },
      );
    } catch (e, stackTrace) {
      AdvancedLogger.e(
          _logTag,
          'Failed to update system media controls metadata: $e',
          stackTrace
      );
      ErrorReporter.reportError(
          'AudioControlsState.updateSystemMediaControlsMetadata',
          e,
          stackTrace
      );
    }
  }

  // Cleanup resources
  @override
  void dispose() {
    _cancelFocusModeTimer();
    _cancelErrorRecoveryTimer();

    try {
      // Unregister from system media controls
      if (_isBackgroundControlEnabled) {
        SystemChannels.platform.invokeMethod<void>(
          'SystemMediaControls.release',
        );
      }
    } catch (e) {
      AdvancedLogger.e(_logTag, 'Error during dispose: $e');
    }

    super.dispose();
  }
}

/// A button with haptic feedback and larger touch area for improved accessibility
class AccessibleButton extends StatefulWidget {
  /// Function to call when button is pressed
  final VoidCallback onPressed;

  /// Function to call when button is long pressed
  /// NEW: Added for emergency stop functionality
  final VoidCallback? onLongPress;

  /// Icon to display in the button
  final IconData icon;

  /// Size of the icon
  final double size;

  /// Color of the icon
  final Color color;

  /// Accessibility label for screen readers
  final String semanticLabel;

  /// Whether the button is enabled
  final bool isEnabled;

  /// Whether to apply focus mode scaling
  final bool applyFocusMode;

  /// Scale factor when in focus mode
  final double focusModeScale;

  /// Whether to apply haptic feedback when pressed
  final bool enableHaptics;

  /// Optional tooltip text to display on hover
  final String? tooltip;

  /// NEW: Whether this is an emergency stop button
  final bool isEmergencyButton;

  /// Creates an accessible button.
  ///
  /// The [onPressed], [icon], and [semanticLabel] parameters are required.
  ///
  /// The [size] parameter defaults to the medium icon size defined in AppTheme.
  ///
  /// The [color] parameter defaults to the teal color defined in AppTheme.
  ///
  /// The [isEnabled] parameter determines if the button can be pressed.
  ///
  /// The [applyFocusMode] parameter determines if the button should scale up in focus mode.
  ///
  /// The [focusModeScale] parameter determines how much to scale the button in focus mode.
  ///
  /// The [enableHaptics] parameter determines if haptic feedback is provided on press.
  ///
  /// The [tooltip] parameter provides optional tooltip text on hover or long press.
  ///
  /// The [isEmergencyButton] parameter marks this as an emergency stop button with special styling.
  const AccessibleButton({
    Key? key,
    required this.onPressed,
    required this.icon,
    required this.semanticLabel,
    this.onLongPress,
    this.size = AppTheme.iconSizeMedium,
    this.color = AppTheme.gentleTeal,
    this.isEnabled = true,
    this.applyFocusMode = false,
    this.focusModeScale = 1.2,
    this.enableHaptics = true,
    this.tooltip,
    this.isEmergencyButton = false,
  }) : super(key: key);

  @override
  State<AccessibleButton> createState() => _AccessibleButtonState();
}

class _AccessibleButtonState extends State<AccessibleButton> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.focusModeScale).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Check for focus mode if configured
    if (widget.applyFocusMode) {
      final controlsState = Provider.of<AudioControlsState>(context);
      if (controlsState.isFocusMode) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }

    // NEW: Check orientation
    final orientation = MediaQuery.of(context).orientation;

    // NEW: Adjust size based on orientation
    final adjustedSize = orientation == Orientation.landscape
        ? widget.size * 0.85  // Slightly smaller in landscape
        : widget.size;

    // NEW: Apply emergency styling if needed
    final buttonColor = widget.isEmergencyButton
        ? AppTheme.errorColor
        : widget.color;

    final backgroundOpacity = widget.isEmergencyButton ? 0.2 : 0.1;
    final splashOpacity = widget.isEmergencyButton ? 0.4 : 0.3;

    // NEW: Apply elevation for emergency button
    final elevation = widget.isEmergencyButton ? 8.0 : 0.0;

    final Widget buttonContent = ScaleTransition(
      scale: _scaleAnimation,
      child: Semantics(
        button: true,
        enabled: widget.isEnabled,
        label: widget.semanticLabel,
        child: Material(
          elevation: elevation,
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusCircular),
          child: InkWell(
            onTap: widget.isEnabled
                ? () {
              if (widget.enableHaptics) {
                HapticFeedback.mediumImpact();
              }
              widget.onPressed();
            }
                : null,
            onLongPress: widget.isEnabled && widget.onLongPress != null
                ? () {
              if (widget.enableHaptics) {
                HapticFeedback.heavyImpact();
              }
              widget.onLongPress!();
            }
                : null,
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusCircular),
            splashColor: buttonColor.withOpacity(splashOpacity),
            highlightColor: buttonColor.withOpacity(backgroundOpacity),
            focusNode: _focusNode,
            focusColor: AppTheme.focusIndicatorColor.withOpacity(0.3),
            child: Container(
              constraints: BoxConstraints(
                minWidth: AppTheme.touchTargetMinSize,
                minHeight: AppTheme.touchTargetMinSize,
              ),
              padding: const EdgeInsets.all(12),
              decoration: widget.isEmergencyButton
                  ? BoxDecoration(
                color: AppTheme.errorColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(AppTheme.borderRadiusCircular),
                border: Border.all(
                  color: AppTheme.errorColor,
                  width: 2.0,
                ),
              )
                  : null,
              child: Icon(
                widget.icon,
                size: adjustedSize,
                color: widget.isEnabled ? buttonColor : buttonColor.withOpacity(0.4),
                semanticLabel: widget.semanticLabel,
              ),
            ),
          ),
        ),
      ),
    );

    // Add tooltip if provided
    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        preferBelow: false,
        waitDuration: const Duration(seconds: 1),
        showDuration: const Duration(seconds: 2),
        textStyle: TextStyle(
          fontFamily: AppTheme.primaryFontFamily,
          fontSize: AppTheme.fontSizeSmall,
          color: Colors.white,
        ),
        child: buttonContent,
      );
    }

    return buttonContent;
  }
}

/// A progress bar with waveform visualization and time labels
class ProgressBar extends StatefulWidget {
  /// Current position in milliseconds
  final int positionMs;

  /// Total duration in milliseconds
  final int durationMs;

  /// Whether the audio is currently buffering
  final bool isBuffering;

  /// Buffered position in milliseconds
  final int bufferPositionMs;

  /// Function called when position is changed
  final ValueChanged<int> onPositionChanged;

  /// Function called to replay the last N seconds
  final ValueChanged<int> onReplay;

  /// Whether the progress bar is enabled
  final bool isEnabled;

  /// Waveform data for visualization (null if not available)
  final List<double>? waveformData;

  /// Whether to show waveform visualization
  final bool showWaveform;

  /// Accent color for the progress bar
  final Color accentColor;

  /// Inactive color for the progress bar
  final Color inactiveColor;

  /// Number of seconds to replay in the replay button
  final int replaySeconds;

  /// Whether to show time remaining instead of duration
  final bool showTimeRemaining;

  /// NEW: Callback when user starts to drag the slider
  final VoidCallback? onDragStart;

  /// NEW: Callback when user ends dragging the slider
  final VoidCallback? onDragEnd;

  /// NEW: Current orientation (for layout adjustment)
  final Orientation orientation;

  /// Creates a progress bar with waveform visualization.
  ///
  /// The [positionMs], [durationMs], [onPositionChanged], and [onReplay]
  /// parameters are required.
  ///
  /// The [isBuffering] parameter indicates if the audio is currently buffering.
  ///
  /// The [bufferPositionMs] parameter is the buffered position in milliseconds.
  ///
  /// The [isEnabled] parameter determines if the seek controls are enabled.
  ///
  /// The [waveformData] parameter is optional data for waveform visualization.
  ///
  /// The [showWaveform] parameter determines if the waveform should be displayed.
  ///
  /// The [accentColor] parameter is the color for the active part of the progress bar.
  ///
  /// The [inactiveColor] parameter is the color for the inactive part of the progress bar.
  ///
  /// The [replaySeconds] parameter is the number of seconds to replay when the replay
  /// button is pressed. Defaults to 10 seconds.
  ///
  /// The [showTimeRemaining] parameter determines whether to show remaining time
  /// instead of total duration. Defaults to false.
  ///
  /// The [onDragStart] parameter is called when the user starts dragging the slider.
  ///
  /// The [onDragEnd] parameter is called when the user finishes dragging the slider.
  ///
  /// The [orientation] parameter is used to adjust the layout based on the device orientation.
  const ProgressBar({
    Key? key,
    required this.positionMs,
    required this.durationMs,
    required this.onPositionChanged,
    required this.onReplay,
    this.isBuffering = false,
    this.bufferPositionMs = 0,
    this.isEnabled = true,
    this.waveformData,
    this.showWaveform = true,
    this.accentColor = AppTheme.gentleTeal,
    this.inactiveColor = AppTheme.dividerColor,
    this.replaySeconds = 10,
    this.showTimeRemaining = false,
    this.onDragStart,
    this.onDragEnd,
    this.orientation = Orientation.portrait,
  }) : super(key: key);

  @override
  State<ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<ProgressBar> {
  bool _isDragging = false;
  double _dragValue = 0.0;
  final FocusNode _sliderFocusNode = FocusNode();

  @override
  void dispose() {
    _sliderFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate progress percentage
    final progress = widget.durationMs > 0 ? widget.positionMs / widget.durationMs : 0.0;
    final bufferProgress = widget.durationMs > 0 ? widget.bufferPositionMs / widget.durationMs : 0.0;

    // Use drag value if dragging, otherwise use actual progress
    final currentProgress = _isDragging ? _dragValue : progress;

    // Calculate time remaining (if enabled)
    final timeRemainingMs = max(0, widget.durationMs - widget.positionMs);

    // NEW: Different layouts for portrait and landscape
    if (widget.orientation == Orientation.landscape) {
      return _buildLandscapeLayout(
          context,
          currentProgress,
          bufferProgress,
          timeRemainingMs
      );
    } else {
      return _buildPortraitLayout(
          context,
          currentProgress,
          bufferProgress,
          timeRemainingMs
      );
    }
  }

  // NEW: Portrait layout (vertical, similar to original)
  Widget _buildPortraitLayout(
      BuildContext context,
      double currentProgress,
      double bufferProgress,
      int timeRemainingMs
      ) {
    final isSmallScreen = MediaQuery.of(context).size.width < 300;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Time labels and replay button
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8.0 : 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Replay button
              _buildReplayButton(isSmallScreen),

              // Time display
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _formatDuration(Duration(milliseconds: widget.positionMs)),
                      style: TextStyle(
                        fontFamily: AppTheme.primaryFontFamily,
                        fontSize: isSmallScreen ? AppTheme.fontSizeXSmall : AppTheme.fontSizeSmall,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondaryColor,
                      ),
                    ),
                    const Text(' / '),
                    Text(
                      widget.showTimeRemaining
                          ? '-${_formatDuration(Duration(milliseconds: timeRemainingMs))}'
                          : _formatDuration(Duration(milliseconds: widget.durationMs)),
                      style: TextStyle(
                        fontFamily: AppTheme.primaryFontFamily,
                        fontSize: isSmallScreen ? AppTheme.fontSizeXSmall : AppTheme.fontSizeSmall,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),

              // Buffering indicator or spacer
              widget.isBuffering
                  ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                  valueColor: AlwaysStoppedAnimation<Color>(widget.accentColor),
                ),
              )
                  : const SizedBox(width: 16),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Progress bar with waveform
        _buildProgressBar(currentProgress, bufferProgress),
      ],
    );
  }

  // NEW: Landscape layout (more horizontal, compact)
  Widget _buildLandscapeLayout(
      BuildContext context,
      double currentProgress,
      double bufferProgress,
      int timeRemainingMs
      ) {
    final isSmallScreen = MediaQuery.of(context).size.height < 400;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Compact layout with everything in a single row
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8.0 : 16.0),
          child: Row(
            children: [
              // Replay button (smaller in landscape)
              SizedBox(
                height: 34,
                child: _buildReplayButton(true), // Use compact style
              ),

              // Time - current position
              Text(
                _formatDuration(Duration(milliseconds: widget.positionMs)),
                style: TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  fontSize: AppTheme.fontSizeXSmall,
                  color: AppTheme.textSecondaryColor,
                ),
              ),

              // Progress bar - expanded to fill available space
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: _buildProgressBar(currentProgress, bufferProgress),
                ),
              ),

              // Time - duration or remaining
              Text(
                widget.showTimeRemaining
                    ? '-${_formatDuration(Duration(milliseconds: timeRemainingMs))}'
                    : _formatDuration(Duration(milliseconds: widget.durationMs)),
                style: TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  fontSize: AppTheme.fontSizeXSmall,
                  color: AppTheme.textSecondaryColor,
                ),
              ),

              // Buffering indicator if needed
              if (widget.isBuffering)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      valueColor: AlwaysStoppedAnimation<Color>(widget.accentColor),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build the waveform visualization
  Widget _buildWaveform(BoxConstraints constraints, double progress) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 32,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
          child: CustomPaint(
            painter: WaveformPainter(
              waveformData: widget.waveformData!,
              color: widget.inactiveColor,
              progressColor: widget.accentColor,
              progress: progress.clamp(0.0, 1.0),
            ),
            size: Size(constraints.maxWidth - 32, 32),
          ),
        ),
      ),
    );
  }

  // NEW: Build the actual progress bar component (extracted for reuse)
  Widget _buildProgressBar(double currentProgress, double bufferProgress) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Waveform visualization (if available and enabled)
        if (widget.showWaveform && widget.waveformData != null && widget.waveformData!.isNotEmpty)
          LayoutBuilder(
              builder: (context, constraints) {
                return _buildWaveform(constraints, currentProgress);
              }
          ),

        // Main progress bar
        SliderTheme(
          data: SliderThemeData(
            trackHeight: widget.orientation == Orientation.landscape ? 6.0 : 8.0,
            activeTrackColor: widget.showWaveform && widget.waveformData != null && widget.waveformData!.isNotEmpty
                ? Colors.transparent
                : widget.accentColor,
            inactiveTrackColor: widget.showWaveform && widget.waveformData != null && widget.waveformData!.isNotEmpty
                ? Colors.transparent
                : widget.inactiveColor,
            thumbColor: widget.accentColor,
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: widget.orientation == Orientation.landscape ? 9.0 : 12.0,
              elevation: 4.0,
              pressedElevation: 8.0,
            ),
            overlayShape: RoundSliderOverlayShape(
              overlayRadius: widget.orientation == Orientation.landscape ? 18.0 : 24.0,
            ),
            // Better keyboard focus indicator
            focusTheme: FocusThemeData(
              glowFactor: 0.0,
              // Custom focus overlay for better visibility
            ),
          ),
          child: Focus(
            focusNode: _sliderFocusNode,
            onKey: _handleKeyboardNavigation,
            child: SizedBox(
              height: widget.orientation == Orientation.landscape ? 32 : 40, // Smaller in landscape
              child: Slider(
                value: currentProgress.clamp(0.0, 1.0),
                min: 0.0,
                max: 1.0,
                onChanged: widget.isEnabled ? (value) {
                  setState(() {
                    _isDragging = true;
                    _dragValue = value;
                  });

                  // NEW: Notify drag start
                  if (!_isDragging && widget.onDragStart != null) {
                    widget.onDragStart!();
                  }
                } : null,
                onChangeEnd: widget.isEnabled ? (value) {
                  setState(() {
                    _isDragging = false;
                  });
                  final newPositionMs = (value * widget.durationMs).round();
                  widget.onPositionChanged(newPositionMs);

                  // NEW: Notify drag end
                  if (widget.onDragEnd != null) {
                    widget.onDragEnd!();
                  }
                } : null,
              ),
            ),
          ),
        ),

        // Buffer indicator (positioned beneath the main slider)
        if (bufferProgress > 0 && bufferProgress < 1.0)
          LayoutBuilder(
              builder: (context, constraints) {
                return Positioned(
                  left: 16 + (constraints.maxWidth - 32) * bufferProgress,
                  child: Container(
                    width: 4,
                    height: 8,
                    decoration: BoxDecoration(
                      color: widget.accentColor.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }
          ),
      ],
    );
  }

  /// Build the replay button
  Widget _buildReplayButton(bool isCompact) {
    // Determine if replay is available (position > replaySeconds)
    final canReplay = widget.positionMs > widget.replaySeconds * 1000;

    return TextButton.icon(
      onPressed: canReplay
          ? () => widget.onReplay(widget.replaySeconds * 1000)
          : null,
      icon: Icon(
        Icons.replay_10,
        size: isCompact ? AppTheme.iconSizeSmall * 0.8 : AppTheme.iconSizeSmall,
      ),
      label: Text('${widget.replaySeconds}s'),
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 4.0 : 8.0,
          vertical: 0,
        ),
        minimumSize: Size.zero,
        foregroundColor: widget.accentColor,
        textStyle: TextStyle(
          fontFamily: AppTheme.primaryFontFamily,
          fontSize: isCompact ? AppTheme.fontSizeXSmall : AppTheme.fontSizeSmall,
        ),
        // Disabled style
        disabledForegroundColor: widget.accentColor.withOpacity(0.3),
      ),
    );
  }

  /// Handle keyboard navigation for the slider
  KeyEventResult _handleKeyboardNavigation(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && widget.isEnabled) {
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        // Move forward 5 seconds
        final newPosition = min(widget.positionMs + 5000, widget.durationMs);
        widget.onPositionChanged(newPosition);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        // Move backward 5 seconds
        final newPosition = max(widget.positionMs - 5000, 0);
        widget.onPositionChanged(newPosition);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.home) {
        // Move to start
        widget.onPositionChanged(0);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.end) {
        // Move to end
        widget.onPositionChanged(widget.durationMs);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  /// Format a duration as mm:ss
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Custom painter for drawing waveform visualization
class WaveformPainter extends CustomPainter {
  /// Waveform amplitude data (values between 0.0 and 1.0)
  final List<double> waveformData;

  /// Color for the inactive part of the waveform
  final Color color;

  /// Color for the active part of the waveform
  final Color progressColor;

  /// Current progress (0.0-1.0)
  final double progress;

  /// Creates a waveform painter.
  ///
  /// The [waveformData] parameter is required and contains amplitude values between 0.0 and 1.0.
  ///
  /// The [color] parameter is the color for the inactive part of the waveform.
  ///
  /// The [progressColor] parameter is the color for the active part of the waveform.
  ///
  /// The [progress] parameter is the current playback progress (0.0-1.0).
  WaveformPainter({
    required this.waveformData,
    required this.color,
    required this.progressColor,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint inactivePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final Paint activePaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final barWidth = size.width / waveformData.length;
    final progressBarCount = (waveformData.length * progress).round();

    for (int i = 0; i < waveformData.length; i++) {
      final barHeight = waveformData[i] * size.height;
      final startY = size.height / 2 - barHeight / 2;

      final rect = Rect.fromLTWH(
          i * barWidth,
          startY,
          barWidth * 0.6, // Leave some space between bars
          barHeight
      );

      canvas.drawRect(rect, i < progressBarCount ? activePaint : inactivePaint);
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.progressColor != progressColor;
  }
}

/// A button for selecting playback speed with options for progressive speed ramping
class SpeedButton extends StatelessWidget {
  /// Current playback speed
  final double currentSpeed;

  /// Function called when speed is changed
  final ValueChanged<double> onSpeedChanged;

  /// Function called when speed ramping is requested
  final ValueChanged<double> onSpeedRampRequested;

  /// Whether speed ramping is currently active
  final bool isRampingSpeed;

  /// Whether the button is enabled
  final bool isEnabled;

  /// Available speed presets
  final List<double> speedPresets;

  /// Button color
  final Color color;

  /// NEW: Current orientation for layout adjustment
  final Orientation orientation;

  /// Creates a speed selection button.
  ///
  /// The [currentSpeed] parameter is the current playback speed.
  ///
  /// The [onSpeedChanged] parameter is called when a new speed is selected.
  ///
  /// The [onSpeedRampRequested] parameter is called when speed ramping is requested.
  ///
  /// The [isRampingSpeed] parameter indicates if progressive speed ramping is active.
  ///
  /// The [isEnabled] parameter determines if the button is enabled.
  ///
  /// The [speedPresets] parameter is the list of available speed presets.
  ///
  /// The [color] parameter is the button color.
  ///
  /// The [orientation] parameter is used to adjust the layout based on device orientation.
  const SpeedButton({
    Key? key,
    required this.currentSpeed,
    required this.onSpeedChanged,
    required this.onSpeedRampRequested,
    this.isRampingSpeed = false,
    this.isEnabled = true,
    this.speedPresets = const [0.5, 0.75, 1.0, 1.25, 1.5],
    this.color = AppTheme.gentleTeal,
    this.orientation = Orientation.portrait,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // NEW: Adjust layout for orientation
    final isLandscape = orientation == Orientation.landscape;
    final fontSize = isLandscape ? AppTheme.fontSizeXSmall : AppTheme.fontSizeSmall;
    final iconSize = isLandscape ? AppTheme.iconSizeSmall * 0.9 : AppTheme.iconSizeSmall;

    return PopupMenuButton<String>(
      tooltip: 'Change playback speed',
      enabled: isEnabled,
      onSelected: (value) {
        // Handle special ramp option
        if (value == 'ramp') {
          onSpeedRampRequested(1.0);
          return;
        }

        // Handle normal speed options
        final speed = double.tryParse(value);
        if (speed != null) {
          onSpeedChanged(speed);
        }
      },
      itemBuilder: (context) => [
        // Build menu items for each speed preset
        ...speedPresets.map((speed) => _buildSpeedMenuItem(speed.toString(), _getSpeedLabel(speed))),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'ramp',
          child: Row(
            children: [
              Icon(
                Icons.trending_up,
                color: AppTheme.calmBlue,
                size: iconSize,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Progressive Speed\n(Start slow, gradually increase)',
                  style: TextStyle(
                    fontFamily: AppTheme.primaryFontFamily,
                    fontSize: fontSize,
                    fontWeight: isRampingSpeed ? FontWeight.bold : FontWeight.normal,
                    color: isRampingSpeed ? AppTheme.calmBlue : AppTheme.textColor,
                  ),
                ),
              ),
              if (isRampingSpeed)
                Icon(
                  Icons.check,
                  color: AppTheme.calmBlue,
                  size: iconSize,
                ),
            ],
          ),
        ),
      ],
      offset: const Offset(0, -240),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
      ),
      color: AppTheme.cardColor,
      child: Padding(
        padding: EdgeInsets.all(isLandscape ? 6.0 : 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isRampingSpeed ? Icons.trending_up : Icons.speed,
              color: isEnabled ? color : color.withOpacity(0.4),
              size: iconSize,
            ),
            SizedBox(height: isLandscape ? 2 : 4),
            Text(
              '${currentSpeed.toStringAsFixed(1)}x',
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                color: isEnabled ? AppTheme.textColor : AppTheme.textColor.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build a menu item for a speed preset
  PopupMenuItem<String> _buildSpeedMenuItem(String speedValue, String label) {
    final speed = double.tryParse(speedValue) ?? 1.0;
    final isSelected = speed == currentSpeed && !isRampingSpeed;

    return PopupMenuItem<String>(
      value: speedValue,
      child: Row(
        children: [
          Text(
            '$speedValue× - $label',
            style: TextStyle(
              fontFamily: AppTheme.primaryFontFamily,
              fontSize: AppTheme.fontSizeMedium,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? color : AppTheme.textColor,
            ),
          ),
          const Spacer(),
          if (isSelected)
            Icon(
              Icons.check,
              color: color,
              size: AppTheme.iconSizeSmall,
            ),
        ],
      ),
    );
  }

  /// Get a human-readable label for a speed value
  String _getSpeedLabel(double speed) {
    if (speed <= 0.5) return 'Very Slow';
    if (speed <= 0.75) return 'Slow';
    if (speed <= 0.9) return 'Moderate';
    if (speed >= 1.0 && speed < 1.1) return 'Normal';
    if (speed >= 1.25) return 'Fast';
    if (speed >= 1.5) return 'Very Fast';
    return 'Custom';
  }
}

/// A button for adjusting volume with presets
class VolumeButton extends StatelessWidget {
  /// Current volume level
  final double currentVolume;

  /// Function called when volume is changed
  final ValueChanged<double> onVolumeChanged;

  /// Whether the button is enabled
  final bool isEnabled;

  /// Available volume presets
  final List<double> volumePresets;

  /// Button color
  final Color color;

  /// NEW: Current orientation for layout adjustment
  final Orientation orientation;

  /// Creates a volume adjustment button.
  ///
  /// The [currentVolume] parameter is the current volume level (0.0-1.0).
  ///
  /// The [onVolumeChanged] parameter is called when the volume is adjusted.
  ///
  /// The [isEnabled] parameter determines if the button is enabled.
  ///
  /// The [volumePresets] parameter is the list of available volume presets.
  ///
  /// The [color] parameter is the button color.
  ///
  /// The [orientation] parameter is used to adjust the layout based on device orientation.
  const VolumeButton({
    Key? key,
    required this.currentVolume,
    required this.onVolumeChanged,
    this.isEnabled = true,
    this.volumePresets = const [0.0, 0.25, 0.5, 0.75, 1.0],
    this.color = AppTheme.gentleTeal,
    this.orientation = Orientation.portrait,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // NEW: Adjust layout for orientation
    final isLandscape = orientation == Orientation.landscape;
    final fontSize = isLandscape ? AppTheme.fontSizeXSmall : AppTheme.fontSizeSmall;
    final iconSize = isLandscape ? AppTheme.iconSizeSmall * 0.9 : AppTheme.iconSizeSmall;

    return PopupMenuButton<double>(
      tooltip: 'Adjust volume',
      enabled: isEnabled,
      itemBuilder: (context) => [
        PopupMenuItem<double>(
          value: -1, // Special value for slider
          enabled: false,
          child: SizedBox(
            width: 200,
            child: _buildVolumeSlider(),
          ),
        ),
        const PopupMenuDivider(),
        ...volumePresets.map((volume) => _buildVolumeMenuItem(volume, _getVolumeLabel(volume))),
      ],
      offset: const Offset(0, -250),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
      ),
      color: AppTheme.cardColor,
      child: Padding(
        padding: EdgeInsets.all(isLandscape ? 6.0 : 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getVolumeIcon(),
              color: isEnabled ? color : color.withOpacity(0.4),
              size: iconSize,
            ),
            SizedBox(height: isLandscape ? 2 : 4),
            Text(
              '${(currentVolume * 100).toInt()}%',
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                color: isEnabled ? AppTheme.textColor : AppTheme.textColor.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build a volume slider widget
  Widget _buildVolumeSlider() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(
            'Volume: ${(currentVolume * 100).toInt()}%',
            style: TextStyle(
              fontFamily: AppTheme.primaryFontFamily,
              fontSize: AppTheme.fontSizeSmall,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondaryColor,
            ),
          ),
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 8.0,
            activeTrackColor: color,
            inactiveTrackColor: AppTheme.dividerColor,
            thumbColor: color,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 16.0,
              elevation: 4.0,
              pressedElevation: 8.0,
            ),
            overlayShape: const RoundSliderOverlayShape(
              overlayRadius: 28.0,
            ),
            valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
            showValueIndicator: ShowValueIndicator.always,
          ),
          child: Slider(
            value: currentVolume,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            label: '${(currentVolume * 100).toInt()}%',
            onChanged: (value) {
              // Update volume in real-time
              onVolumeChanged(value);
            },
          ),
        ),
      ],
    );
  }

  /// Build a menu item for a volume preset
  PopupMenuItem<double> _buildVolumeMenuItem(double volume, String label) {
    final volumePercent = (volume * 100).toInt();
    final isSelected = (currentVolume * 100).round() == volumePercent;

    return PopupMenuItem<double>(
      value: volume,
      onTap: () => onVolumeChanged(volume),
      child: Row(
        children: [
          Icon(
            _getVolumeIconForLevel(volume),
            color: isSelected ? color : AppTheme.textColor,
            size: AppTheme.iconSizeSmall,
          ),
          const SizedBox(width: 12),
          Text(
            '$label ($volumePercent%)',
            style: TextStyle(
              fontFamily: AppTheme.primaryFontFamily,
              fontSize: AppTheme.fontSizeMedium,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? color : AppTheme.textColor,
            ),
          ),
          const Spacer(),
          if (isSelected)
            Icon(
              Icons.check,
              color: color,
              size: AppTheme.iconSizeSmall,
            ),
        ],
      ),
    );
  }

  /// Get icon for current volume level
  IconData _getVolumeIcon() {
    return _getVolumeIconForLevel(currentVolume);
  }

  /// Get icon for a specific volume level
  IconData _getVolumeIconForLevel(double volume) {
    if (volume <= 0.01) {
      return Icons.volume_off;
    } else if (volume < 0.3) {
      return Icons.volume_mute;
    } else if (volume < 0.7) {
      return Icons.volume_down;
    } else {
      return Icons.volume_up;
    }
  }

  /// Get a human-readable label for a volume level
  String _getVolumeLabel(double volume) {
    if (volume <= 0.01) return 'Muted';
    if (volume <= 0.25) return 'Low';
    if (volume <= 0.5) return 'Medium';
    if (volume <= 0.75) return 'High';
    return 'Maximum';
  }
}

/// A control panel with basic playback controls (play, pause, stop)
class BasicControls extends StatelessWidget {
  /// Whether audio is currently playing
  final bool isPlaying;

  /// Function called when play button is pressed
  final VoidCallback onPlay;

  /// Function called when pause button is pressed
  final VoidCallback onPause;

  /// Function called when stop button is pressed
  final VoidCallback onStop;

  /// Function called when restart button is pressed
  final VoidCallback onRestart;

  /// NEW: Emergency stop functionality
  final VoidCallback onEmergencyStop;

  /// Whether controls are enabled
  final bool isEnabled;

  /// Whether to show stop button
  final bool showStopButton;

  /// Whether to show restart button
  final bool showRestartButton;

  /// NEW: Whether to show emergency stop button
  final bool showEmergencyStop;

  /// Size of the main play/pause button
  final double mainButtonSize;

  /// Size of secondary buttons (stop, restart)
  final double secondaryButtonSize;

  /// Color for the controls
  final Color color;

  /// Whether to apply focus mode scaling
  final bool applyFocusMode;

  /// NEW: Current orientation for layout adjustment
  final Orientation orientation;

  /// Creates a basic control panel with play, pause, stop buttons.
  ///
  /// The [isPlaying] parameter indicates if audio is currently playing.
  ///
  /// The [onPlay], [onPause], [onStop], and [onRestart] parameters are
  /// callbacks for the respective actions.
  ///
  /// The [onEmergencyStop] parameter is called for immediate stop with higher priority.
  ///
  /// The [isEnabled] parameter determines if the controls are enabled.
  ///
  /// The [showStopButton] parameter determines if the stop button is shown.
  ///
  /// The [showRestartButton] parameter determines if the restart button is shown.
  ///
  /// The [showEmergencyStop] parameter determines if the emergency stop button is shown.
  ///
  /// The [mainButtonSize] parameter is the size of the play/pause button.
  ///
  /// The [secondaryButtonSize] parameter is the size of stop and restart buttons.
  ///
  /// The [color] parameter is the color for the controls.
  ///
  /// The [applyFocusMode] parameter determines if buttons should scale in focus mode.
  ///
  /// The [orientation] parameter is used to adjust the layout based on device orientation.
  const BasicControls({
    Key? key,
    required this.isPlaying,
    required this.onPlay,
    required this.onPause,
    required this.onStop,
    required this.onRestart,
    required this.onEmergencyStop,
    this.isEnabled = true,
    this.showStopButton = true,
    this.showRestartButton = true,
    this.showEmergencyStop = true,
    this.mainButtonSize = AppTheme.iconSizeLarge,
    this.secondaryButtonSize = AppTheme.iconSizeMedium,
    this.color = AppTheme.gentleTeal,
    this.applyFocusMode = false,
    this.orientation = Orientation.portrait,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // NEW: Check orientation
    final isLandscape = orientation == Orientation.landscape;

    return LayoutBuilder(
        builder: (context, constraints) {
          // Adjust spacing based on available width
          final isSmallScreen = constraints.maxWidth < 300;
          final spacing = isSmallScreen ? AppTheme.spacingMedium : AppTheme.spacingLarge;

          // NEW: For landscape mode with emergency button, use a different layout
          if (isLandscape && showEmergencyStop) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Main row with primary controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Restart button
                    if (showRestartButton)
                      AccessibleButton(
                        onPressed: onRestart,
                        icon: Icons.replay,
                        semanticLabel: 'Restart',
                        size: isSmallScreen ? secondaryButtonSize * 0.7 : secondaryButtonSize * 0.8,
                        color: color,
                        isEnabled: isEnabled,
                        applyFocusMode: applyFocusMode,
                        focusModeScale: 1.2,
                        tooltip: 'Restart from beginning',
                      ),

                    if (showRestartButton)
                      SizedBox(width: spacing * 0.7),

                    // Play/Pause button (larger)
                    AccessibleButton(
                      onPressed: isPlaying ? onPause : onPlay,
                      icon: isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      semanticLabel: isPlaying ? 'Pause' : 'Play',
                      size: isSmallScreen ? mainButtonSize * 0.7 : mainButtonSize * 0.8,
                      color: color,
                      isEnabled: isEnabled,
                      applyFocusMode: applyFocusMode,
                      focusModeScale: 1.3,
                      tooltip: isPlaying ? 'Pause playback' : 'Start playback',
                    ),

                    if (showStopButton)
                      SizedBox(width: spacing * 0.7),

                    // Stop button
                    if (showStopButton)
                      AccessibleButton(
                        onPressed: onStop,
                        icon: Icons.stop_circle,
                        semanticLabel: 'Stop',
                        size: isSmallScreen ? secondaryButtonSize * 0.7 : secondaryButtonSize * 0.8,
                        color: color,
                        isEnabled: isEnabled,
                        applyFocusMode: applyFocusMode,
                        focusModeScale: 1.2,
                        tooltip: 'Stop and reset',
                      ),
                  ],
                ),

                // Emergency stop button in separate row with emphasis
                if (showEmergencyStop)
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: AccessibleButton(
                      onPressed: onEmergencyStop,
                      icon: Icons.pan_tool, // Hand icon for "stop"
                      semanticLabel: 'Emergency Stop',
                      size: isSmallScreen ? mainButtonSize * 0.7 : mainButtonSize * 0.8,
                      color: AppTheme.errorColor,
                      isEnabled: isEnabled,
                      applyFocusMode: true, // Always use focus for emergency button
                      focusModeScale: 1.3,
                      tooltip: 'Emergency stop playback',
                      isEmergencyButton: true,
                      onLongPress: onEmergencyStop, // Same action for long press
                    ),
                  ),
              ],
            );
          }

          // Original portrait layout with emergency button (if shown)
          final controlButtons = <Widget>[];

          // Restart button
          if (showRestartButton) {
            controlButtons.add(
              AccessibleButton(
                onPressed: onRestart,
                icon: Icons.replay,
                semanticLabel: 'Restart',
                size: isSmallScreen ? secondaryButtonSize * 0.8 : secondaryButtonSize,
                color: color,
                isEnabled: isEnabled,
                applyFocusMode: applyFocusMode,
                focusModeScale: 1.2,
                tooltip: 'Restart from beginning',
              ),
            );
            controlButtons.add(SizedBox(width: spacing));
          }

          // Emergency stop button (if shown)
          if (showEmergencyStop) {
            controlButtons.add(
              AccessibleButton(
                onPressed: onEmergencyStop,
                icon: Icons.pan_tool, // Hand icon for "stop"
                semanticLabel: 'Emergency Stop',
                size: isSmallScreen ? secondaryButtonSize * 0.9 : secondaryButtonSize * 1.1,
                color: AppTheme.errorColor,
                isEnabled: isEnabled,
                applyFocusMode: true, // Always use focus for emergency button
                focusModeScale: 1.3,
                tooltip: 'Emergency stop playback',
                isEmergencyButton: true,
                onLongPress: onEmergencyStop, // Same action for long press
              ),
            );
            controlButtons.add(SizedBox(width: spacing));
          }

          // Play/Pause button (larger)
          controlButtons.add(
            AccessibleButton(
              onPressed: isPlaying ? onPause : onPlay,
              icon: isPlaying
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled,
              semanticLabel: isPlaying ? 'Pause' : 'Play',
              size: isSmallScreen ? mainButtonSize * 0.8 : mainButtonSize,
              color: color,
              isEnabled: isEnabled,
              applyFocusMode: applyFocusMode,
              focusModeScale: 1.3,
              tooltip: isPlaying ? 'Pause playback' : 'Start playback',
            ),
          );

          if (showStopButton) {
            controlButtons.add(SizedBox(width: spacing));

            // Stop button
            controlButtons.add(
              AccessibleButton(
                onPressed: onStop,
                icon: Icons.stop_circle,
                semanticLabel: 'Stop',
                size: isSmallScreen ? secondaryButtonSize * 0.8 : secondaryButtonSize,
                color: color,
                isEnabled: isEnabled,
                applyFocusMode: applyFocusMode,
                focusModeScale: 1.2,
                tooltip: 'Stop and reset',
              ),
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: controlButtons,
          );
        }
    );
  }
}

/// A component that displays playback status message with visual indicators
class StatusDisplay extends StatelessWidget {
  /// Current playback state
  final AudioPlayerState state;

  /// Custom message to display (if null, uses state-based message)
  final String? customMessage;

  /// Color scheme for different states
  final Map<AudioPlayerState, Color> stateColors;

  /// Whether to show icon indicator
  final bool showIcon;

  /// Text style for the message
  final TextStyle? textStyle;

  /// NEW: Error recovery support
  final bool isInErrorRecoveryMode;

  /// NEW: Error recovery attempts
  final int errorRecoveryAttempts;

  /// NEW: Retry callback
  final VoidCallback? onRetry;

  /// Creates a playback status display.
  ///
  /// The [state] parameter is the current audio player state.
  ///
  /// The [customMessage] parameter overrides the default state-based message.
  ///
  /// The [stateColors] parameter maps states to colors for visual indication.
  ///
  /// The [showIcon] parameter determines if an icon is shown alongside the message.
  ///
  /// The [textStyle] parameter customizes the text appearance.
  ///
  /// The [isInErrorRecoveryMode] parameter indicates if error recovery is active.
  ///
  /// The [errorRecoveryAttempts] parameter shows how many retry attempts have been made.
  ///
  /// The [onRetry] parameter is called when the user manually retries after an error.
  const StatusDisplay({
    Key? key,
    required this.state,
    this.customMessage,
    this.stateColors = const {
      AudioPlayerState.playing: AppTheme.calmGreen,
      AudioPlayerState.paused: AppTheme.gentleTeal,
      AudioPlayerState.loading: AppTheme.calmBlue,
      AudioPlayerState.buffering: AppTheme.calmBlue,
      AudioPlayerState.error: AppTheme.errorColor,
    },
    this.showIcon = true,
    this.textStyle,
    this.isInErrorRecoveryMode = false,
    this.errorRecoveryAttempts = 0,
    this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = stateColors[state] ?? AppTheme.textSecondaryColor;

    // NEW: Determine message based on error recovery status
    String message;
    if (isInErrorRecoveryMode) {
      message = 'Attempting to recover... (Try ${errorRecoveryAttempts}/5)';
    } else {
      message = customMessage ?? _getStateMessage(state);
    }

    final baseTextStyle = textStyle ?? TextStyle(
      fontFamily: AppTheme.primaryFontFamily,
      fontSize: AppTheme.fontSizeSmall,
      fontWeight: FontWeight.w500,
      color: AppTheme.textSecondaryColor,
    );

    // NEW: Determine if retry button should be shown
    final showRetryButton = state == AudioPlayerState.error &&
        onRetry != null &&
        !isInErrorRecoveryMode;

    if (showIcon) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _getStateIcon(state),
                color: color,
                size: AppTheme.iconSizeSmall,
              ),
              const SizedBox(width: 8),
              Text(
                message,
                style: baseTextStyle,
              ),
            ],
          ),

          // NEW: Show retry button if in error state
          if (showRetryButton)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.calmBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          style: baseTextStyle,
          textAlign: TextAlign.center,
        ),

        // NEW: Show retry button if in error state
        if (showRetryButton)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.calmBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Get icon based on player state
  IconData _getStateIcon(AudioPlayerState state) {
    switch (state) {
      case AudioPlayerState.playing:
        return Icons.play_arrow;
      case AudioPlayerState.paused:
        return Icons.pause;
      case AudioPlayerState.loading:
      case AudioPlayerState.buffering:
        return Icons.hourglass_top;
      case AudioPlayerState.completed:
        return Icons.done;
      case AudioPlayerState.error:
        return Icons.error_outline;
      case AudioPlayerState.stopped:
        return Icons.stop;
      default:
        return Icons.music_note;
    }
  }

  /// Get human-readable message based on player state
  String _getStateMessage(AudioPlayerState state) {
    switch (state) {
      case AudioPlayerState.initializing:
        return 'Getting ready';
      case AudioPlayerState.idle:
        return 'Ready to play';
      case AudioPlayerState.loading:
        return 'Loading audio...';
      case AudioPlayerState.ready:
        return 'Ready to play';
      case AudioPlayerState.playing:
        return 'Playing';
      case AudioPlayerState.paused:
        return 'Paused';
      case AudioPlayerState.completed:
        return 'Playback completed';
      case AudioPlayerState.stopped:
        return 'Playback stopped';
      case AudioPlayerState.error:
        return 'Error occurred';
    }
  }
}

/// A floating mini player that can be expanded
class MiniPlayer extends StatefulWidget {
  /// Current playback status
  final PlaybackStatus status;

  /// Function called when play button is pressed
  final VoidCallback onPlay;

  /// Function called when pause button is pressed
  final VoidCallback onPause;

  /// Function called when stop button is pressed
  final VoidCallback onStop;

  /// NEW: Function called for emergency stop
  final VoidCallback onEmergencyStop;

  /// Function called when position is changed
  final ValueChanged<int> onPositionChanged;

  /// Function called to expand the player
  final VoidCallback onExpand;

  /// Title text to display
  final String title;

  /// Subtitle text to display
  final String? subtitle;

  /// Color for the player
  final Color color;

  /// Whether the player can be expanded
  final bool isExpandable;

  /// NEW: Show emergency stop button
  final bool showEmergencyStop;

  /// NEW: Current orientation for layout adjustment
  final Orientation orientation;

  /// Creates a mini floating player.
  ///
  /// The [status] parameter is the current playback status.
  ///
  /// The [onPlay], [onPause], and [onStop] parameters are callbacks for
  /// the respective actions.
  ///
  /// The [onEmergencyStop] parameter is called for immediate stop with higher priority.
  ///
  /// The [onPositionChanged] parameter is called when the position is changed.
  ///
  /// The [onExpand] parameter is called when the user wants to expand the player.
  ///
  /// The [title] parameter is the main text to display.
  ///
  /// The [subtitle] parameter is optional secondary text to display.
  ///
  /// The [color] parameter is the accent color for the player.
  ///
  /// The [isExpandable] parameter determines if the player can be expanded.
  ///
  /// The [showEmergencyStop] parameter determines if the emergency stop button is shown.
  ///
  /// The [orientation] parameter is used to adjust the layout based on device orientation.
  const MiniPlayer({
    Key? key,
    required this.status,
    required this.onPlay,
    required this.onPause,
    required this.onStop,
    required this.onEmergencyStop,
    required this.onPositionChanged,
    required this.onExpand,
    required this.title,
    this.subtitle,
    this.color = AppTheme.gentleTeal,
    this.isExpandable = true,
    this.showEmergencyStop = false,
    this.orientation = Orientation.portrait,
  }) : super(key: key);

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_animationController);
    _updateProgressAnimation();
  }

  @override
  void didUpdateWidget(MiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateProgressAnimation();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _updateProgressAnimation() {
    // If playing, animate progress smoothly
    if (widget.status.state == AudioPlayerState.playing) {
      final progress = widget.status.durationMs > 0
          ? widget.status.positionMs / widget.status.durationMs
          : 0.0;

      // Set current progress
      _animationController.value = progress;

      // If not at the end, animate to the end
      if (progress < 1.0) {
        // Calculate how long until the end at current rate
        final remaining = widget.status.durationMs - widget.status.positionMs;
        final duration = Duration(milliseconds: remaining);

        // Animate to the end over the remaining time
        _animationController.animateTo(
          1.0,
          duration: duration,
          curve: Curves.linear,
        );
      }
    } else {
      // Not playing, stop animation
      _animationController.stop();

      // Update to current position
      final progress = widget.status.durationMs > 0
          ? widget.status.positionMs / widget.status.durationMs
          : 0.0;
      _animationController.value = progress;
    }
  }

  @override
  Widget build(BuildContext context) {
    // NEW: Different layouts based on orientation
    final isLandscape = widget.orientation == Orientation.landscape;

    return Card(
      elevation: 8,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
      ),
      color: AppTheme.elevationColors[8],
      child: InkWell(
        onTap: widget.isExpandable ? widget.onExpand : null,
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress bar at top
            AnimatedBuilder(
              animation: _progressAnimation,
              builder: (context, child) {
                return LinearProgressIndicator(
                  value: _progressAnimation.value,
                  backgroundColor: AppTheme.dividerColor,
                  valueColor: AlwaysStoppedAnimation<Color>(widget.color),
                  minHeight: 4,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppTheme.borderRadiusMedium),
                    topRight: Radius.circular(AppTheme.borderRadiusMedium),
                  ),
                );
              },
            ),

            // Content
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: isLandscape ? 4.0 : 8.0
              ),
              child: isLandscape
                  ? _buildLandscapeContent()
                  : _buildPortraitContent(),
            ),
          ],
        ),
      ),
    );
  }

  // NEW: Portrait layout (original)
  Widget _buildPortraitContent() {
    return Row(
      children: [
        // Title and subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  fontSize: AppTheme.fontSizeMedium,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.subtitle != null)
                Text(
                  widget.subtitle!,
                  style: TextStyle(
                    fontFamily: AppTheme.primaryFontFamily,
                    fontSize: AppTheme.fontSizeSmall,
                    color: AppTheme.textSecondaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),

        // Controls
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Emergency stop button if enabled
            if (widget.showEmergencyStop)
              AccessibleButton(
                onPressed: widget.onEmergencyStop,
                icon: Icons.pan_tool,
                semanticLabel: 'Emergency Stop',
                size: AppTheme.iconSizeMedium * 0.9,
                color: AppTheme.errorColor,
                isEmergencyButton: true,
              ),

            // Play/Pause button
            AccessibleButton(
              onPressed: widget.status.state == AudioPlayerState.playing
                  ? widget.onPause
                  : widget.onPlay,
              icon: widget.status.state == AudioPlayerState.playing
                  ? Icons.pause
                  : Icons.play_arrow,
              semanticLabel: widget.status.state == AudioPlayerState.playing
                  ? 'Pause'
                  : 'Play',
              size: AppTheme.iconSizeMedium,
              color: widget.color,
            ),

            // Stop button
            AccessibleButton(
              onPressed: widget.onStop,
              icon: Icons.stop,
              semanticLabel: 'Stop',
              size: AppTheme.iconSizeMedium,
              color: widget.color,
            ),

            // Expand button
            if (widget.isExpandable)
              AccessibleButton(
                onPressed: widget.onExpand,
                icon: Icons.expand_less,
                semanticLabel: 'Expand player',
                size: AppTheme.iconSizeMedium,
                color: widget.color,
              ),
          ],
        ),
      ],
    );
  }

  // NEW: Landscape layout (more compact)
  Widget _buildLandscapeContent() {
    return Row(
      children: [
        // Emergency stop button if enabled
        if (widget.showEmergencyStop)
          AccessibleButton(
            onPressed: widget.onEmergencyStop,
            icon: Icons.pan_tool,
            semanticLabel: 'Emergency Stop',
            size: AppTheme.iconSizeSmall,
            color: AppTheme.errorColor,
            isEmergencyButton: true,
          ),

        // Title - only show title in landscape, no subtitle
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              widget.title,
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: AppTheme.fontSizeSmall,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),

        // Compact controls
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Play/Pause button
            AccessibleButton(
              onPressed: widget.status.state == AudioPlayerState.playing
                  ? widget.onPause
                  : widget.onPlay,
              icon: widget.status.state == AudioPlayerState.playing
                  ? Icons.pause
                  : Icons.play_arrow,
              semanticLabel: widget.status.state == AudioPlayerState.playing
                  ? 'Pause'
                  : 'Play',
              size: AppTheme.iconSizeSmall,
              color: widget.color,
            ),

            // Stop button
            AccessibleButton(
              onPressed: widget.onStop,
              icon: Icons.stop,
              semanticLabel: 'Stop',
              size: AppTheme.iconSizeSmall,
              color: widget.color,
            ),

            // Expand button
            if (widget.isExpandable)
              AccessibleButton(
                onPressed: widget.onExpand,
                icon: Icons.expand_less,
                semanticLabel: 'Expand player',
                size: AppTheme.iconSizeSmall,
                color: widget.color,
              ),
          ],
        ),
      ],
    );
  }
}

/// A complete set of advanced audio controls
class AudioControlsPanel extends StatefulWidget {
  /// Audio player service instance
  final AudioPlayerService audioService;

  /// Whether to show volume controls
  final bool showVolumeControl;

  /// Whether to show speed controls
  final bool showSpeedControl;

  /// Whether to show waveform visualization
  final bool showWaveform;

  /// Whether to enable focus mode
  final bool enableFocusMode;

  /// Whether to enable speed ramping
  final bool enableSpeedRamp;

  /// Whether to enable progress haptics
  final bool enableProgressHaptics;

  /// NEW: Whether to show emergency stop button
  final bool showEmergencyStop;

  /// Accent color for controls
  final Color accentColor;

  /// Feedback callback when control is used
  final VoidCallback? onControlUsed;

  /// List of waveform data points (optional)
  final List<double>? waveformData;

  /// NEW: Retry callback for error recovery
  final VoidCallback? onRetry;

  /// Creates a complete audio control panel.
  ///
  /// The [audioService] parameter is the audio player service instance.
  ///
  /// The [showVolumeControl] parameter determines if volume controls are shown.
  ///
  /// The [showLabels] parameter determines if text labels are shown on buttons.
  ///
  /// The [showEmergencyStop] parameter determines if the emergency stop button is shown.
  ///
  /// The [orientation] parameter is used to adjust the layout based on device orientation.
  ///
  /// The [onRetry] parameter is called when manual retry is requested after an error. determines if volume controls are displayed.
  ///
  /// The [showSpeedControl] parameter determines if speed controls are displayed.
  ///
  /// The [showWaveform] parameter determines if waveform visualization is shown.
  ///
  /// The [enableFocusMode] parameter enables temporary enlargement of controls
  /// when user attention is needed.
  ///
  /// The [enableSpeedRamp] parameter enables progressive speed ramping.
  ///
  /// The [enableProgressHaptics] parameter enables haptic feedback at key
  /// playback milestones.
  ///
  /// The [showEmergencyStop] parameter determines if the emergency stop button is shown.
  ///
  /// The [accentColor] parameter is the color for the controls.
  ///
  /// The [onControlUsed] parameter is called when any control is interacted with.
  ///
  /// The [waveformData] parameter provides optional waveform visualization data.
  ///
  /// The [onRetry] parameter is called when manual retry is requested after an error.
  const AudioControlsPanel({
    Key? key,
    required this.audioService,
    this.showVolumeControl = true,
    this.showSpeedControl = true,
    this.showWaveform = true,
    this.enableFocusMode = false,
    this.enableSpeedRamp = false,
    this.enableProgressHaptics = false,
    this.showEmergencyStop = false,
    this.accentColor = AppTheme.gentleTeal,
    this.onControlUsed,
    this.waveformData,
    this.onRetry,
  }) : super(key: key);

  @override
  State<AudioControlsPanel> createState() => _AudioControlsPanelState();
}

class _AudioControlsPanelState extends State<AudioControlsPanel> {
  final _controlsState = AudioControlsState();
  late final StreamSubscription<PlaybackStatus> _statusSubscription;
  Timer? _hapticTimer;
  double? _lastHapticProgress;

  // NEW: Monitor orientation changes
  Orientation _currentOrientation = Orientation.portrait;

  @override
  void initState() {
    super.initState();

    // Initialize preferences
    _controlsState.initializePreferences();

    _initHaptics();
    _statusSubscription = widget.audioService.status.listen(_updateStatus);

    // NEW: Register with system media controls
    if (_controlsState.isBackgroundControlEnabled) {
      _registerWithSystemMediaControls();
    }
  }

  @override
  void dispose() {
    _statusSubscription.cancel();
    _hapticTimer?.cancel();
    super.dispose();
  }

  // NEW: Handle orientation changes
  void _handleOrientationChange(Orientation newOrientation) {
    if (_currentOrientation != newOrientation) {
      _currentOrientation = newOrientation;
      _controlsState.currentOrientation = newOrientation;
    }
  }

  // NEW: Register with system media controls
  Future<void> _registerWithSystemMediaControls() async {
    try {
      await _controlsState.registerWithSystemMediaControls(
        _onPlayPause,
        _onPlayPause,
        _onStop,
        _onSeek,
      );

      // Update metadata initially
      _updateSystemMediaMetadata();
    } catch (e, stackTrace) {
      AdvancedLogger.e(_logTag, 'Failed to register with system media controls: $e', stackTrace);
      ErrorReporter.reportError('AudioControlsPanel._registerWithSystemMediaControls', e, stackTrace);
    }
  }

  // NEW: Update system media controls metadata
  void _updateSystemMediaMetadata() {
    if (!_controlsState.isBackgroundControlEnabled) return;

    final status = widget.audioService.currentStatus;
    final metadata = _controlsState.mediaMetadata;

    if (metadata != null) {
      _controlsState.updateSystemMediaControlsMetadata(
        title: metadata['title'] as String? ?? 'Milo Nudge',
        artist: metadata['category'] as String?,
        duration: status.durationMs,
        position: status.positionMs,
        isPlaying: status.state == AudioPlayerState.playing,
      );
    } else {
      _controlsState.updateSystemMediaControlsMetadata(
        title: status.nudge?.title ?? 'Milo Nudge',
        artist: status.nudge?.category,
        duration: status.durationMs,
        position: status.positionMs,
        isPlaying: status.state == AudioPlayerState.playing,
      );
    }
  }

  void _updateStatus(PlaybackStatus status) {
    _controlsState.updateFromStatus(status);

    // If we're playing and haptics are enabled, check for progress
    if (widget.enableProgressHaptics &&
        status.state == AudioPlayerState.playing) {
      _checkProgressHaptics(status);
    }

    // NEW: Update system media controls metadata
    if (_controlsState.isBackgroundControlEnabled) {
      _updateSystemMediaMetadata();
    }

    // NEW: Announce position changes for accessibility
    if (status.state == AudioPlayerState.playing) {
      _controlsState.announcePosition(status.positionMs, status.durationMs);
    }
  }

  void _initHaptics() {
    if (widget.enableProgressHaptics) {
      _hapticTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final status = widget.audioService.currentStatus;
        if (status.state == AudioPlayerState.playing) {
          _checkProgressHaptics(status);
        }
      });
    }
  }

  void _checkProgressHaptics(PlaybackStatus status) {
    if (status.durationMs <= 0) return;

    // Calculate progress
    final progress = status.positionMs / status.durationMs;

    // Check for key points
    if (progress >= 0.25 && (_lastHapticProgress == null || _lastHapticProgress! < 0.25)) {
      HapticFeedback.lightImpact();
      _lastHapticProgress = 0.25;
    } else if (progress >= 0.5 && (_lastHapticProgress == null || _lastHapticProgress! < 0.5)) {
      HapticFeedback.mediumImpact();
      _lastHapticProgress = 0.5;
    } else if (progress >= 0.75 && (_lastHapticProgress == null || _lastHapticProgress! < 0.75)) {
      HapticFeedback.heavyImpact();
      _lastHapticProgress = 0.75;
    } else if (progress >= 0.99 && (_lastHapticProgress == null || _lastHapticProgress! < 0.99)) {
      HapticFeedback.vibrate();
      _lastHapticProgress = 0.99;
    }
  }

  void _onPlayPause() {
    if (_controlsState.isPlaying) {
      widget.audioService.pause();
    } else {
      widget.audioService.play();
    }

    if (widget.enableFocusMode) {
      _controlsState.activateFocusMode();
    }

    if (widget.onControlUsed != null) {
      widget.onControlUsed!();
    }
  }

  void _onStop() {
    widget.audioService.stop();

    if (widget.enableFocusMode) {
      _controlsState.activateFocusMode();
    }

    if (widget.onControlUsed != null) {
      widget.onControlUsed!();
    }
  }

  // NEW: Emergency stop with feedback
  void _onEmergencyStop() {
    // Play haptic feedback for confirmation
    HapticFeedback.heavyImpact();

    // Stop playback
    widget.audioService.stop();

    // Make announcement for accessibility
    if (_controlsState.accessibilityAnnouncementsEnabled) {
      SemanticsService.announce(
        'Emergency stop activated. Playback has been stopped.',
        TextDirection.ltr,
      );
    }

    // Use more prominent visual indication
    _controlsState.activateFocusMode();

    if (widget.onControlUsed != null) {
      widget.onControlUsed!();
    }

    // Log emergency stop event
    AdvancedLogger.w(_logTag, 'Emergency stop activated by user');
  }

  void _onRestart() {
    widget.audioService.seekTo(0);
    widget.audioService.play();

    if (widget.enableFocusMode) {
      _controlsState.activateFocusMode();
    }

    if (widget.onControlUsed != null) {
      widget.onControlUsed!();
    }
  }

  void _onSeek(int positionMs) {
    widget.audioService.seekTo(positionMs);

    if (widget.enableFocusMode) {
      _controlsState.activateFocusMode();
    }

    if (widget.onControlUsed != null) {
      widget.onControlUsed!();
    }
  }

  void _onReplay(int durationMs) {
    final newPosition = max(0, _controlsState.positionMs - durationMs);
    widget.audioService.seekTo(newPosition);

    if (widget.enableFocusMode) {
      _controlsState.activateFocusMode();
    }

    if (widget.onControlUsed != null) {
      widget.onControlUsed!();
    }
  }

  void _onVolumeChange(double volume) {
    widget.audioService.setVolume(volume);

    if (widget.enableFocusMode) {
      _controlsState.activateFocusMode();
    }

    if (widget.onControlUsed != null) {
      widget.onControlUsed!();
    }
  }

  void _onSpeedChange(double speed) {
    widget.audioService.setSpeed(speed);

    if (widget.enableFocusMode) {
      _controlsState.activateFocusMode();
    }

    if (widget.onControlUsed != null) {
      widget.onControlUsed!();
    }
  }

  void _onSpeedRampRequested(double targetSpeed) {
    if (!widget.enableSpeedRamp) return;

    _controlsState.startSpeedRamp(targetSpeed);

    // Start at half speed
    widget.audioService.setSpeed(0.5);

    // Set up a timer to gradually increase speed
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_controlsState.isRampingSpeed) {
        timer.cancel();
        return;
      }

      // Increase by 0.1 up to target
      final currentSpeed = _controlsState.currentSpeed;
      final newSpeed = min(currentSpeed + 0.1, targetSpeed);

      // Update control state and player
      _controlsState.updateRampSpeed(newSpeed);
      widget.audioService.setSpeed(newSpeed);

      // If we've reached the target, stop ramping
      if (newSpeed >= targetSpeed) {
        _controlsState.stopSpeedRamp();
        timer.cancel();
      }
    });

    if (widget.enableFocusMode) {
      _controlsState.activateFocusMode();
    }

    if (widget.onControlUsed != null) {
      widget.onControlUsed!();
    }
  }

  // NEW: Start error recovery process
  void _onRetry() {
    // Start error recovery process
    _controlsState.startErrorRecovery();

    // Try to replay the current media
    final mediaId = _controlsState.mediaId;
    if (mediaId != null) {
      // Schedule first recovery attempt
      Future.delayed(const Duration(milliseconds: 500), () {
        try {
          widget.audioService.playUrl(mediaId);
        } catch (e, stackTrace) {
          AdvancedLogger.e(_logTag, 'Error recovery attempt failed: $e', stackTrace);

          // Schedule next attempt from state
          if (_controlsState.isInErrorRecoveryMode) {
            _controlsState._scheduleErrorRecoveryAttempt();
          }
        }
      });
    } else {
      // Can't recover without media ID
      _controlsState.stopErrorRecovery();

      AdvancedLogger.w(
          _logTag,
          'Could not start error recovery - no media ID available'
      );
    }

    if (widget.onControlUsed != null) {
      widget.onControlUsed!();
    }
  }

  // NEW: Handle drag start/end for accessibility
  void _onDragStart() {
    if (_controlsState.accessibilityAnnouncementsEnabled) {
      SemanticsService.announce(
        'Moving position slider, release to set new position',
        TextDirection.ltr,
      );
    }
  }

  void _onDragEnd() {
    if (_controlsState.accessibilityAnnouncementsEnabled) {
      final position = Duration(milliseconds: _controlsState.positionMs);
      final minutes = position.inMinutes;
      final seconds = position.inSeconds % 60;

      SemanticsService.announce(
        'Position set to $minutes minutes, $seconds seconds',
        TextDirection.ltr,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Detect orientation
    final currentOrientation = MediaQuery.of(context).orientation;
    _handleOrientationChange(currentOrientation);

    return ChangeNotifierProvider.value(
      value: _controlsState,
      child: Consumer<AudioControlsState>(
        builder: (context, state, child) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final isSmallScreen = constraints.maxWidth < 300;

              // NEW: Different layouts for portrait and landscape
              if (currentOrientation == Orientation.landscape) {
                return _buildLandscapeLayout(state, constraints, isSmallScreen);
              } else {
                return _buildPortraitLayout(state, constraints, isSmallScreen);
              }
            },
          );
        },
      ),
    );
  }

  // NEW: Portrait layout (similar to original)
  Widget _buildPortraitLayout(
      AudioControlsState state,
      BoxConstraints constraints,
      bool isSmallScreen
      ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Progress bar
        ProgressBar(
          positionMs: state.positionMs,
          durationMs: state.durationMs,
          isBuffering: state.isBuffering,
          onPositionChanged: _onSeek,
          onReplay: _onReplay,
          isEnabled: state.state != AudioPlayerState.loading &&
              state.state != AudioPlayerState.error,
          waveformData: widget.waveformData,
          showWaveform: widget.showWaveform,
          accentColor: widget.accentColor,
          orientation: Orientation.portrait,
          onDragStart: _onDragStart,
          onDragEnd: _onDragEnd,
        ),

        const SizedBox(height: AppTheme.spacingMedium),

        // Basic controls
        BasicControls(
          isPlaying: state.isPlaying,
          onPlay: _onPlayPause,
          onPause: _onPlayPause,
          onStop: _onStop,
          onRestart: _onRestart,
          onEmergencyStop: _onEmergencyStop,
          isEnabled: state.state != AudioPlayerState.loading,
          showStopButton: true,
          showRestartButton: true,
          showEmergencyStop: widget.showEmergencyStop,
          mainButtonSize: isSmallScreen ? AppTheme.iconSizeLarge * 0.8 : AppTheme.iconSizeLarge,
          secondaryButtonSize: isSmallScreen ? AppTheme.iconSizeMedium * 0.8 : AppTheme.iconSizeMedium,
          color: widget.accentColor,
          applyFocusMode: widget.enableFocusMode,
          orientation: Orientation.portrait,
        ),

        const SizedBox(height: AppTheme.spacingMedium),

        // Volume and speed controls
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.showVolumeControl)
              VolumeButton(
                currentVolume: state.volume,
                onVolumeChanged: _onVolumeChange,
                isEnabled: state.state != AudioPlayerState.loading &&
                    state.state != AudioPlayerState.error,
                color: widget.accentColor,
                orientation: Orientation.portrait,
              ),

            if (widget.showVolumeControl && widget.showSpeedControl)
              const SizedBox(width: AppTheme.spacingLarge),

            if (widget.showSpeedControl)
              SpeedButton(
                currentSpeed: state.currentSpeed,
                onSpeedChanged: _onSpeedChange,
                onSpeedRampRequested: _onSpeedRampRequested,
                isRampingSpeed: state.isRampingSpeed,
                isEnabled: state.state != AudioPlayerState.loading &&
                    state.state != AudioPlayerState.error,
                color: widget.accentColor,
                orientation: Orientation.portrait,
              ),
          ],
        ),

        const SizedBox(height: AppTheme.spacingSmall),

        // Status message
        StatusDisplay(
          state: state.state,
          showIcon: true,
          stateColors: {
            AudioPlayerState.playing: widget.accentColor,
            AudioPlayerState.paused: widget.accentColor.withOpacity(0.7),
            AudioPlayerState.loading: widget.accentColor.withOpacity(0.7),
            AudioPlayerState.error: AppTheme.errorColor,
          },
          isInErrorRecoveryMode: state.isInErrorRecoveryMode,
          errorRecoveryAttempts: state.errorRecoveryAttempts,
          onRetry: widget.onRetry ?? _onRetry,
        ),
      ],
    );
  }

  // NEW: Landscape layout (optimized for horizontal)
  Widget _buildLandscapeLayout(
      AudioControlsState state,
      BoxConstraints constraints,
      bool isSmallScreen
      ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // More compact layout for landscape
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            children: [
              // Left column - controls and status
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Basic controls
                    BasicControls(
                      isPlaying: state.isPlaying,
                      onPlay: _onPlayPause,
                      onPause: _onPlayPause,
                      onStop: _onStop,
                      onRestart: _onRestart,
                      onEmergencyStop: _onEmergencyStop,
                      isEnabled: state.state != AudioPlayerState.loading,
                      showStopButton: true,
                      showRestartButton: true,
                      showEmergencyStop: widget.showEmergencyStop,
                      mainButtonSize: AppTheme.iconSizeLarge * 0.7,
                      secondaryButtonSize: AppTheme.iconSizeMedium * 0.7,
                      color: widget.accentColor,
                      applyFocusMode: widget.enableFocusMode,
                      orientation: Orientation.landscape,
                    ),

                    const SizedBox(height: AppTheme.spacingSmall),

                    // Volume and speed controls in compact row
                    if (widget.showVolumeControl || widget.showSpeedControl)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.showVolumeControl)
                            VolumeButton(
                              currentVolume: state.volume,
                              onVolumeChanged: _onVolumeChange,
                              isEnabled: state.state != AudioPlayerState.loading &&
                                  state.state != AudioPlayerState.error,
                              color: widget.accentColor,
                              orientation: Orientation.landscape,
                            ),

                          if (widget.showVolumeControl && widget.showSpeedControl)
                            const SizedBox(width: AppTheme.spacingMedium),

                          if (widget.showSpeedControl)
                            SpeedButton(
                              currentSpeed: state.currentSpeed,
                              onSpeedChanged: _onSpeedChange,
                              onSpeedRampRequested: _onSpeedRampRequested,
                              isRampingSpeed: state.isRampingSpeed,
                              isEnabled: state.state != AudioPlayerState.loading &&
                                  state.state != AudioPlayerState.error,
                              color: widget.accentColor,
                              orientation: Orientation.landscape,
                            ),
                        ],
                      ),
                  ],
                ),
              ),

              // Progress display
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Progress bar
                    ProgressBar(
                      positionMs: state.positionMs,
                      durationMs: state.durationMs,
                      isBuffering: state.isBuffering,
                      onPositionChanged: _onSeek,
                      onReplay: _onReplay,
                      isEnabled: state.state != AudioPlayerState.loading &&
                          state.state != AudioPlayerState.error,
                      waveformData: widget.waveformData,
                      showWaveform: widget.showWaveform,
                      accentColor: widget.accentColor,
                      orientation: Orientation.landscape,
                      onDragStart: _onDragStart,
                      onDragEnd: _onDragEnd,
                    ),

                    const SizedBox(height: 4),

                    // Status display
                    StatusDisplay(
                      state: state.state,
                      showIcon: true,
                      stateColors: {
                        AudioPlayerState.playing: widget.accentColor,
                        AudioPlayerState.paused: widget.accentColor.withOpacity(0.7),
                        AudioPlayerState.loading: widget.accentColor.withOpacity(0.7),
                        AudioPlayerState.error: AppTheme.errorColor,
                      },
                      isInErrorRecoveryMode: state.isInErrorRecoveryMode,
                      errorRecoveryAttempts: state.errorRecoveryAttempts,
                      onRetry: widget.onRetry ?? _onRetry,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Creates waveform data from audio samples or a placeholder pattern
///
/// This is a utility class that can generate waveform visualizations
/// for audio files or create placeholder patterns for testing
class WaveformGenerator {
  /// Generate a placeholder waveform for testing or when real data isn't available
  ///
  /// [length] is the number of data points to generate
  /// [pattern] is the type of pattern to generate (sine, triangle, random)
  /// [minAmplitude] is the minimum amplitude value (0.0-1.0)
  /// [maxAmplitude] is the maximum amplitude value (0.0-1.0)
  static List<double> generatePlaceholder({
    int length = 100,
    String pattern = 'sine',
    double minAmplitude = 0.2,
    double maxAmplitude = 0.8,
  }) {
    final random = Random();
    final amplitudeRange = maxAmplitude - minAmplitude;

    switch (pattern) {
      case 'sine':
        return List<double>.generate(
            length,
                (i) => minAmplitude + amplitudeRange *
                (0.5 + 0.5 * sin(i / length * 6 * pi))
        );

      case 'triangle':
        return List<double>.generate(
            length,
                (i) {
              // Triangle wave pattern
              final phase = (i % (length / 2)) / (length / 2);
              final value = i < length / 2 ? phase : 1 - phase;
              return minAmplitude + amplitudeRange * value;
            }
        );

      case 'random':
        return List<double>.generate(
            length,
                (i) => minAmplitude + amplitudeRange * random.nextDouble()
        );

      case 'smooth_random':
      // Generate completely random values
        final rawValues = List<double>.generate(
            length,
                (i) => random.nextDouble()
        );

        // Apply smoothing (moving average)
        final smoothedValues = List<double>.filled(length, 0.0);
        const windowSize = 5;

        for (int i = 0; i < length; i++) {
          double sum = 0.0;
          int count = 0;

          for (int j = max(0, i - windowSize ~/ 2);
          j < min(length, i + windowSize ~/ 2 + 1);
          j++) {
            sum += rawValues[j];
            count++;
          }

          smoothedValues[i] = sum / count;
        }

        // Scale to desired amplitude range
        return smoothedValues.map(
                (v) => minAmplitude + amplitudeRange * v
        ).toList();

      default:
      // Default to sine pattern
        return List<double>.generate(
            length,
                (i) => minAmplitude + amplitudeRange *
                (0.5 + 0.5 * sin(i / length * 6 * pi))
        );
    }
  }

  /// Generate waveform data from an audio file (placeholder implementation)
  ///
  /// In a real implementation, this would analyze the audio file's amplitude data
  ///
  /// [filePath] is the path to the audio file
  /// [sampleCount] is the number of data points to generate
  static Future<List<double>> generateFromAudioFile(
      String filePath, {
        int sampleCount = 100,
      }) async {
    // This is a placeholder that would be replaced with actual audio analysis
    // In a real implementation, you would:
    // 1. Read the audio file and extract amplitude data
    // 2. Normalize the amplitude data
    // 3. Downsample to the requested number of points

    // For now, return a sine pattern with some randomness
    final random = Random();
    final seedValue = filePath.hashCode; // Use filename hash for consistent pattern
    random.nextInt(seedValue); // Seed the generator

    return List<double>.generate(
        sampleCount,
            (i) {
          // Base sine wave
          final baseSine = 0.5 + 0.4 * sin(i / sampleCount * 8 * pi);

          // Add some randomness
          final randomFactor = 0.05 + 0.1 * random.nextDouble();

          return 0.2 + 0.6 * (baseSine + randomFactor);
        }
    );
  }

  /// Generate waveform data based on the frequency spectrum of speech
  ///
  /// This creates a more realistic pattern for spoken word audio
  ///
  /// [sampleCount] is the number of data points to generate
  /// [speechRate] simulates different speech rates (0.5-2.0)
  static List<double> generateSpeechPattern({
    int sampleCount = 100,
    double speechRate = 1.0,
  }) {
    final random = Random();
    final result = List<double>.filled(sampleCount, 0.0);

    // Parameters to simulate speech patterns
    final double baseSilenceProb = 0.2 / speechRate; // Probability of silence
    final int minWordLength = (2 / speechRate).round();
    final int maxWordLength = (8 / speechRate).round();
    final int minSilenceLength = (1 / speechRate).round();
    final int maxSilenceLength = (3 / speechRate).round();

    int i = 0;
    bool isSilence = true; // Start with silence

    while (i < sampleCount) {
      if (isSilence) {
        // Generate silence (low amplitude)
        final silenceLength = minSilenceLength +
            random.nextInt(maxSilenceLength - minSilenceLength);

        for (int j = 0; j < silenceLength && i < sampleCount; j++, i++) {
          result[i] = 0.1 + 0.1 * random.nextDouble();
        }

        isSilence = false;
      } else {
        // Generate "word" (higher amplitude with variation)
        final wordLength = minWordLength +
            random.nextInt(maxWordLength - minWordLength);

        for (int j = 0; j < wordLength && i < sampleCount; j++, i++) {
          // Base amplitude with some randomness for natural speech
          result[i] = 0.3 + 0.5 * random.nextDouble();

          // Add some peaks for emphasized syllables
          if (random.nextDouble() > 0.7) {
            result[i] = 0.7 + 0.3 * random.nextDouble();
          }
        }

        // Determine if next segment is silence
        isSilence = random.nextDouble() < baseSilenceProb;
      }
    }

    // Apply smoothing to make it look more natural
    for (int i = 1; i < sampleCount - 1; i++) {
      result[i] = (result[i - 1] + result[i] * 2 + result[i + 1]) / 4;
    }

    return result;
  }
}

/// A specialized control set for elderly users with simplified interface
class ElderlyFriendlyControls extends StatelessWidget {
  /// Current playback status
  final PlaybackStatus status;

  /// Function called when play/pause button is pressed
  final VoidCallback onPlayPause;

  /// Function called when stop button is pressed
  final VoidCallback onStop;

  /// Function called when restart button is pressed
  final VoidCallback onRestart;

  /// NEW: Function called for emergency stop
  final VoidCallback onEmergencyStop;

  /// Function called when position is changed
  final ValueChanged<int> onPositionChanged;

  /// Function called to request volume change
  final ValueChanged<double> onVolumeChanged;

  /// Color for the controls
  final Color accentColor;

  /// Whether to show progress bar
  final bool showProgress;

  /// Whether to show volume control
  final bool showVolumeControl;

  /// Whether to show text labels on buttons
  final bool showLabels;

  /// NEW: Whether to show emergency stop button
  final bool showEmergencyStop;

  /// NEW: Current orientation
  final Orientation orientation;

  /// NEW: Retry callback for error recovery
  final VoidCallback? onRetry;

/// Creates an elderly-friendly control panel.
///
/// The [status] parameter is the current playback status.
///
/// The [onPlayPause] parameter is called when the play/pause button is pressed.
///
/// The [onStop] parameter is called when the stop button is pressed.
///
/// The [onRestart] parameter is called when the restart button is pressed.
///
/// The [onEmergencyStop] parameter is called for immediate stop with higher priority.
///
/// The [onPositionChanged] parameter is called when the position is changed.
///
/// The [onVolumeChanged] parameter is called when volume change is requested.
///
/// The [accentColor] parameter is the color for the controls.
///
/// The [showProgress] parameter determines if the progress bar is shown.
///
/// /// The [showVolumeControl] parameter determines if volume controls are shown.
///
/// The [showLabels] parameter determines if text labels are shown on buttons.
///
/// The [showEmergencyStop] parameter determines if the emergency stop button is shown.
///
/// The [orientation] parameter is used to adjust the layout based on device orientation.
///
/// The [onRetry] parameter is called when manual retry is requested after an error.
  const ElderlyFriendlyControls({
    Key? key,
    required this.status,
    required this.onPlayPause,
    required this.onStop,
    required this.onRestart,
    required this.onEmergencyStop,
    required this.onPositionChanged,
    required this.onVolumeChanged,
    this.accentColor = AppTheme.gentleTeal,
    this.showProgress = true,
    this.showVolumeControl = true,
    this.showLabels = true,
    this.showEmergencyStop = false,
    this.orientation = Orientation.portrait,
    this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // NEW: Check orientation and screen size
    final isLandscape = orientation == Orientation.landscape;
    final isSmallScreen = MediaQuery.of(context).size.width < 320;

    // Determine icon size based on orientation and screen size
    final double iconSize = isLandscape
        ? (isSmallScreen ? AppTheme.iconSizeMedium * 0.7 : AppTheme.iconSizeMedium * 0.8)
        : (isSmallScreen ? AppTheme.iconSizeLarge * 0.7 : AppTheme.iconSizeLarge);

    // Determine text size based on orientation and screen size
    final double textSize = isLandscape
        ? AppTheme.fontSizeXSmall
        : (isSmallScreen ? AppTheme.fontSizeSmall : AppTheme.fontSizeMedium);

    // Create appropriate layout based on orientation
    if (isLandscape) {
      return _buildLandscapeLayout(iconSize, textSize, isSmallScreen);
    } else {
      return _buildPortraitLayout(iconSize, textSize, isSmallScreen);
    }
  }

  /// Build portrait layout with vertical arrangement
  Widget _buildPortraitLayout(double iconSize, double textSize, bool isSmallScreen) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Progress bar (if enabled)
        if (showProgress)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: _buildProgressBar(),
          ),

        const SizedBox(height: 8),

        // Main controls row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Restart button
            _buildControlButton(
              icon: Icons.replay,
              label: 'Restart',
              onPressed: onRestart,
              size: iconSize * 0.8,
              textSize: textSize,
            ),

            const SizedBox(width: 16),

            // Play/Pause button (larger)
            _buildControlButton(
              icon: status.state == AudioPlayerState.playing
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled,
              label: status.state == AudioPlayerState.playing ? 'Pause' : 'Play',
              onPressed: onPlayPause,
              size: iconSize,
              textSize: textSize,
              isHighlighted: true,
            ),

            const SizedBox(width: 16),

            // Stop button
            _buildControlButton(
              icon: Icons.stop_circle,
              label: 'Stop',
              onPressed: onStop,
              size: iconSize * 0.8,
              textSize: textSize,
            ),
          ],
        ),

        // Add space before emergency stop if shown
        if (showEmergencyStop)
          const SizedBox(height: 16),

        // Emergency stop button (if enabled)
        if (showEmergencyStop)
          _buildControlButton(
            icon: Icons.pan_tool,
            label: 'STOP NOW',
            onPressed: onEmergencyStop,
            size: iconSize * 0.9,
            textSize: textSize,
            color: AppTheme.errorColor,
            isEmergency: true,
          ),

        // Volume control (if enabled)
        if (showVolumeControl)
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: _buildVolumeControl(textSize),
          ),

        // Status message
        Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: StatusDisplay(
            state: status.state,
            showIcon: true,
            isInErrorRecoveryMode: false, // We don't track this in this component
            errorRecoveryAttempts: 0,
            onRetry: onRetry,
            stateColors: {
              AudioPlayerState.playing: accentColor,
              AudioPlayerState.paused: accentColor.withOpacity(0.7),
              AudioPlayerState.loading: accentColor.withOpacity(0.7),
              AudioPlayerState.error: AppTheme.errorColor,
            },
          ),
        ),
      ],
    );
  }

  /// Build landscape layout with horizontal arrangement
  Widget _buildLandscapeLayout(double iconSize, double textSize, bool isSmallScreen) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Controls column
        Expanded(
          flex: 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main controls row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Restart button
                  _buildControlButton(
                    icon: Icons.replay,
                    label: 'Restart',
                    onPressed: onRestart,
                    size: iconSize * 0.9,
                    textSize: textSize,
                    showLabel: false, // Hide labels in landscape
                  ),

                  const SizedBox(width: 12),

                  // Play/Pause button
                  _buildControlButton(
                    icon: status.state == AudioPlayerState.playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    label: status.state == AudioPlayerState.playing ? 'Pause' : 'Play',
                    onPressed: onPlayPause,
                    size: iconSize,
                    textSize: textSize,
                    isHighlighted: true,
                    showLabel: false, // Hide labels in landscape
                  ),

                  const SizedBox(width: 12),

                  // Stop button
                  _buildControlButton(
                    icon: Icons.stop_circle,
                    label: 'Stop',
                    onPressed: onStop,
                    size: iconSize * 0.9,
                    textSize: textSize,
                    showLabel: false, // Hide labels in landscape
                  ),
                ],
              ),

              // Emergency stop button in landscape
              if (showEmergencyStop)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: _buildControlButton(
                    icon: Icons.pan_tool,
                    label: 'STOP',
                    onPressed: onEmergencyStop,
                    size: iconSize * 0.8,
                    textSize: textSize * 0.9,
                    color: AppTheme.errorColor,
                    isEmergency: true,
                    showLabel: true, // Always show label for emergency
                  ),
                ),
            ],
          ),
        ),

        // Progress and volume column
        Expanded(
          flex: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress bar (if enabled)
              if (showProgress)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: _buildProgressBar(),
                ),

              // Volume in landscape
              if (showVolumeControl)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: _buildVolumeControl(textSize * 0.8),
                ),

              // Status message
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: StatusDisplay(
                  state: status.state,
                  showIcon: true,
                  isInErrorRecoveryMode: false,
                  errorRecoveryAttempts: 0,
                  onRetry: onRetry,
                  stateColors: {
                    AudioPlayerState.playing: accentColor,
                    AudioPlayerState.paused: accentColor.withOpacity(0.7),
                    AudioPlayerState.loading: accentColor.withOpacity(0.7),
                    AudioPlayerState.error: AppTheme.errorColor,
                  },
                  textStyle: TextStyle(
                    fontFamily: AppTheme.primaryFontFamily,
                    fontSize: textSize * 0.8,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build a simplified progress bar
  Widget _buildProgressBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Time display
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(Duration(milliseconds: status.positionMs)),
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: AppTheme.fontSizeSmall,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondaryColor,
              ),
            ),
            Text(
              _formatDuration(Duration(milliseconds: status.durationMs)),
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: AppTheme.fontSizeSmall,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondaryColor,
              ),
            ),
          ],
        ),

        const SizedBox(height: 4),

        // Progress slider
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 8.0,
            activeTrackColor: accentColor,
            inactiveTrackColor: AppTheme.dividerColor,
            thumbColor: accentColor,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 12.0,
              elevation: 4.0,
              pressedElevation: 8.0,
            ),
            overlayShape: const RoundSliderOverlayShape(
              overlayRadius: 24.0,
            ),
          ),
          child: Slider(
            value: (status.durationMs > 0 ? status.positionMs / status.durationMs : 0.0)
                .clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            onChanged: (value) {
              final newPositionMs = (value * status.durationMs).round();
              onPositionChanged(newPositionMs);
            },
          ),
        ),
      ],
    );
  }

  /// Build a control button with optional label
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required double size,
    required double textSize,
    bool isHighlighted = false,
    bool isEmergency = false,
    Color? color,
    bool showLabel = true,
  }) {
    final buttonColor = color ?? accentColor;

    // Determine if we should show the label
    final shouldShowLabel = showLabel && showLabels;

    // Button with optional label
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Button with larger tap target
        Container(
          decoration: isEmergency
              ? BoxDecoration(
            color: AppTheme.errorColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusCircular),
            border: Border.all(
              color: AppTheme.errorColor,
              width: 2.0,
            ),
          )
              : null,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.mediumImpact();
                onPressed();
              },
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusCircular),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Icon(
                  icon,
                  size: size,
                  color: buttonColor,
                ),
              ),
            ),
          ),
        ),

        // Optional label
        if (shouldShowLabel)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: textSize,
                fontWeight: isHighlighted || isEmergency ? FontWeight.bold : FontWeight.normal,
                color: isEmergency ? AppTheme.errorColor : AppTheme.textColor,
              ),
            ),
          ),
      ],
    );
  }

  /// Build a simplified volume control
  Widget _buildVolumeControl(double textSize) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Volume label
        Text(
          'Volume',
          style: TextStyle(
            fontFamily: AppTheme.primaryFontFamily,
            fontSize: textSize,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondaryColor,
          ),
        ),

        const SizedBox(height: 4),

        // Volume slider
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.volume_down,
              size: AppTheme.iconSizeSmall,
              color: accentColor,
            ),

            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 8.0,
                  activeTrackColor: accentColor,
                  inactiveTrackColor: AppTheme.dividerColor,
                  thumbColor: accentColor,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 12.0,
                    elevation: 4.0,
                    pressedElevation: 8.0,
                  ),
                ),
                child: Slider(
                  value: status.volume.clamp(0.0, 1.0),
                  min: 0.0,
                  max: 1.0,
                  onChanged: (value) {
                    HapticFeedback.lightImpact();
                    onVolumeChanged(value);
                  },
                ),
              ),
            ),

            Icon(
              Icons.volume_up,
              size: AppTheme.iconSizeSmall,
              color: accentColor,
            ),
          ],
        ),
      ],
    );
  }

  /// Format a duration as mm:ss
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// A specialized player for therapeutic nudges designed for elderly users
class NudgeAudioPlayer extends StatefulWidget {
  /// Audio URL to play
  final String audioUrl;

  /// Title of the nudge
  final String title;

  /// Category of the nudge
  final String? category;

  /// When this nudge was delivered
  final DateTime? deliveryTime;

  /// Function called when playback completes
  final VoidCallback? onPlaybackComplete;

  /// Function called when user marks as helpful
  final VoidCallback? onMarkHelpful;

  /// Function called when user marks as not helpful
  final VoidCallback? onMarkNotHelpful;

  /// Function called when user saves as memory
  final VoidCallback? onSaveAsMemory;

  /// Function called when player is closed
  final VoidCallback? onClose;

  /// Main color scheme
  final Color accentColor;

  /// Whether to use simplified controls for elderly users
  final bool useSimplifiedControls;

  /// NEW: Whether to show emergency stop button
  final bool showEmergencyStop;

  /// Whether to start playback automatically
  final bool autoPlay;

  /// Creates a specialized player for therapeutic nudges.
  ///
  /// The [audioUrl] parameter is the URL of the audio to play.
  ///
  /// The [title] parameter is the title of the nudge.
  ///
  /// The [category] parameter is the optional category of the nudge.
  ///
  /// The [deliveryTime] parameter is when the nudge was delivered.
  ///
  /// The [onPlaybackComplete] parameter is called when playback completes.
  ///
  /// The [onMarkHelpful] parameter is called when the user marks the nudge as helpful.
  ///
  /// The [onMarkNotHelpful] parameter is called when the user marks the nudge as not helpful.
  ///
  /// The [onSaveAsMemory] parameter is called when the user wants to save as a memory.
  ///
  /// The [onClose] parameter is called when the player is closed.
  ///
  /// The [accentColor] parameter is the main color scheme.
  ///
  /// The [useSimplifiedControls] parameter determines if simplified controls are used.
  ///
  /// The [showEmergencyStop] parameter determines if the emergency stop button is shown.
  ///
  /// The [autoPlay] parameter determines if playback starts automatically.
  const NudgeAudioPlayer({
    Key? key,
    required this.audioUrl,
    required this.title,
    this.category,
    this.deliveryTime,
    this.onPlaybackComplete,
    this.onMarkHelpful,
    this.onMarkNotHelpful,
    this.onSaveAsMemory,
    this.onClose,
    this.accentColor = AppTheme.gentleTeal,
    this.useSimplifiedControls = true,
    this.showEmergencyStop = false,
    this.autoPlay = false,
  }) : super(key: key);

  @override
  State<NudgeAudioPlayer> createState() => _NudgeAudioPlayerState();
}

class _NudgeAudioPlayerState extends State<NudgeAudioPlayer> {
  late final AudioPlayerService _audioService;
  bool _isExpanded = true;
  bool _feedbackSubmitted = false;
  List<double>? _waveformData;

  // NEW: Track orientation
  Orientation _currentOrientation = Orientation.portrait;

  @override
  void initState() {
    super.initState();

    // Initialize audio service
    _audioService = AudioPlayerService();

    // Generate waveform data
    _generateWaveform();

    // Prepare the audio player
    _initializePlayer();
  }

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    try {
      await _audioService.initialize();

      // Set up the audio
      await _audioService.loadFromUrl(widget.audioUrl, metadata: {
        'title': widget.title,
        'category': widget.category,
        'deliveryTime': widget.deliveryTime?.toIso8601String(),
      });

      // Start playback if auto-play is enabled
      if (widget.autoPlay && mounted) {
        await _audioService.play();
      }

      // Listen for playback completion
      _audioService.status.listen((status) {
        if (status.state == AudioPlayerState.completed && widget.onPlaybackComplete != null) {
          widget.onPlaybackComplete!();
        }
      });

    } catch (e, stackTrace) {
      AdvancedLogger.e(_logTag, 'Error initializing player: $e', stackTrace);
      ErrorReporter.reportError('NudgeAudioPlayer._initializePlayer', e, stackTrace);
    }
  }

  void _generateWaveform() {
    // Generate a speech-like waveform pattern
    _waveformData = WaveformGenerator.generateSpeechPattern(
      sampleCount: 120,
      speechRate: 1.0,
    );
  }

  // NEW: Track orientation changes
  void _handleOrientationChange(Orientation newOrientation) {
    if (_currentOrientation != newOrientation) {
      setState(() {
        _currentOrientation = newOrientation;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // NEW: Detect orientation
    final currentOrientation = MediaQuery.of(context).orientation;
    _handleOrientationChange(currentOrientation);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isExpanded)
          _buildExpandedPlayer(context)
        else
          _buildMiniPlayer(context),
      ],
    );
  }

  Widget _buildExpandedPlayer(BuildContext context) {
    return StreamBuilder<PlaybackStatus>(
      stream: _audioService.status,
      builder: (context, snapshot) {
        final status = snapshot.data ?? PlaybackStatus.initial();

        return Card(
          margin: const EdgeInsets.all(0),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
          ),
          child: Padding(
            padding: EdgeInsets.all(_currentOrientation == Orientation.portrait ? 16.0 : 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with title and close button
                _buildHeader(context),

                SizedBox(height: _currentOrientation == Orientation.portrait ? 16.0 : 8.0),

                // Controls
                widget.useSimplifiedControls
                    ? ElderlyFriendlyControls(
                  status: status,
                  onPlayPause: () {
                    if (status.state == AudioPlayerState.playing) {
                      _audioService.pause();
                    } else {
                      _audioService.play();
                    }
                  },
                  onStop: () => _audioService.stop(),
                  onRestart: () {
                    _audioService.seekTo(0);
                    _audioService.play();
                  },
                  onEmergencyStop: () {
                    _audioService.stop();

                    // Provide haptic feedback
                    HapticFeedback.heavyImpact();

                    // Show a brief message
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Playback stopped immediately',
                          style: TextStyle(
                            fontSize: AppTheme.fontSizeMedium,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        backgroundColor: AppTheme.errorColor,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  onPositionChanged: (positionMs) => _audioService.seekTo(positionMs),
                  onVolumeChanged: (volume) => _audioService.setVolume(volume),
                  accentColor: widget.accentColor,
                  showEmergencyStop: widget.showEmergencyStop,
                  orientation: _currentOrientation,
                )
                    : AudioControlsPanel(
                  audioService: _audioService,
                  showVolumeControl: true,
                  showSpeedControl: true,
                  showWaveform: true,
                  enableFocusMode: true,
                  enableProgressHaptics: true,
                  showEmergencyStop: widget.showEmergencyStop,
                  accentColor: widget.accentColor,
                  waveformData: _waveformData,
                ),

                // Feedback buttons (if not in landscape)
                if (_currentOrientation == Orientation.portrait)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: _buildFeedbackButtons(context),
                  ),

                // Action buttons
                Padding(
                  padding: EdgeInsets.only(
                      top: _currentOrientation == Orientation.portrait ? 16.0 : 8.0
                  ),
                  child: _buildActionButtons(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniPlayer(BuildContext context) {
    return StreamBuilder<PlaybackStatus>(
      stream: _audioService.status,
      builder: (context, snapshot) {
        final status = snapshot.data ?? PlaybackStatus.initial();

        return MiniPlayer(
          status: status,
          onPlay: () => _audioService.play(),
          onPause: () => _audioService.pause(),
          onStop: () => _audioService.stop(),
          onEmergencyStop: () {
            _audioService.stop();
            HapticFeedback.heavyImpact();
          },
          onPositionChanged: (positionMs) => _audioService.seekTo(positionMs),
          onExpand: () => setState(() => _isExpanded = true),
          title: widget.title,
          subtitle: widget.category,
          color: widget.accentColor,
          isExpandable: true,
          showEmergencyStop: widget.showEmergencyStop,
          orientation: _currentOrientation,
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final subtitleText = widget.category != null && widget.deliveryTime != null
        ? '${widget.category} • ${_formatDeliveryTime(widget.deliveryTime!)}'
        : widget.category ?? (widget.deliveryTime != null
        ? _formatDeliveryTime(widget.deliveryTime!)
        : 'Therapeutic Nudge');

    return Row(
      children: [
        // Title and subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  fontSize: _currentOrientation == Orientation.portrait
                      ? AppTheme.fontSizeLarge
                      : AppTheme.fontSizeMedium,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textColor,
                ),
              ),
              if (subtitleText.isNotEmpty)
                Text(
                  subtitleText,
                  style: TextStyle(
                    fontFamily: AppTheme.primaryFontFamily,
                    fontSize: _currentOrientation == Orientation.portrait
                        ? AppTheme.fontSizeSmall
                        : AppTheme.fontSizeXSmall,
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
            ],
          ),
        ),

        // Close and minimize buttons
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Minimize button
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              tooltip: 'Minimize player',
              onPressed: () => setState(() => _isExpanded = false),
              iconSize: AppTheme.iconSizeMedium,
              color: AppTheme.textSecondaryColor,
            ),

            // Close button
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close player',
              onPressed: () {
                // Stop playback
                _audioService.stop();

                // Notify parent
                if (widget.onClose != null) {
                  widget.onClose!();
                }
              },
              iconSize: AppTheme.iconSizeMedium,
              color: AppTheme.textSecondaryColor,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeedbackButtons(BuildContext context) {
    // If feedback already submitted, show thank you message
    if (_feedbackSubmitted) {
      return Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: AppTheme.gentleTeal.withOpacity(0.2),
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle,
              color: AppTheme.gentleTeal,
            ),
            SizedBox(width: 8),
            Text(
              'Thank you for your feedback!',
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: AppTheme.fontSizeMedium,
                color: AppTheme.textColor,
              ),
            ),
          ],
        ),
      );
    }

    // Show feedback buttons
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Was this helpful?',
          style: TextStyle(
            fontFamily: AppTheme.primaryFontFamily,
            fontSize: _currentOrientation == Orientation.portrait
                ? AppTheme.fontSizeMedium
                : AppTheme.fontSizeSmall,
            fontWeight: FontWeight.w500,
            color: AppTheme.textColor,
          ),
        ),

        const SizedBox(height: 8),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Yes button
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _feedbackSubmitted = true);

                if (widget.onMarkHelpful != null) {
                  widget.onMarkHelpful!();
                }

                // Show haptic feedback
                HapticFeedback.lightImpact();
              },
              icon: const Icon(Icons.thumb_up),
              label: const Text('Yes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gentleTeal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                textStyle: TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  fontSize: AppTheme.fontSizeMedium,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(width: 16),

            // No button
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _feedbackSubmitted = true);

                if (widget.onMarkNotHelpful != null) {
                  widget.onMarkNotHelpful!();
                }

                // Show haptic feedback
                HapticFeedback.lightImpact();
              },
              icon: const Icon(Icons.thumb_down),
              label: const Text('No'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade200,
                foregroundColor: AppTheme.textSecondaryColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                textStyle: TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  fontSize: AppTheme.fontSizeMedium,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    // In landscape, show a row with both feedback and save
    if (_currentOrientation == Orientation.landscape) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Feedback in landscape (more compact)
          if (!_feedbackSubmitted)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Helpful? ',
                  style: TextStyle(
                    fontFamily: AppTheme.primaryFontFamily,
                    fontSize: AppTheme.fontSizeSmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.thumb_up),
                  onPressed: () {
                    setState(() => _feedbackSubmitted = true);
                    if (widget.onMarkHelpful != null) {
                      widget.onMarkHelpful!();
                    }
                  },
                  color: AppTheme.gentleTeal,
                ),
                IconButton(
                  icon: const Icon(Icons.thumb_down),
                  onPressed: () {
                    setState(() => _feedbackSubmitted = true);
                    if (widget.onMarkNotHelpful != null) {
                      widget.onMarkNotHelpful!();
                    }
                  },
                  color: AppTheme.textSecondaryColor,
                ),
              ],
            )
          else
            const Text(
              'Thanks for your feedback!',
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: AppTheme.fontSizeXSmall,
                fontStyle: FontStyle.italic,
              ),
            ),

          // Save as memory button
          TextButton.icon(
            onPressed: widget.onSaveAsMemory,
            icon: const Icon(Icons.bookmark_add),
            label: const Text('Save as Memory'),
            style: TextButton.styleFrom(
              foregroundColor: widget.accentColor,
              textStyle: const TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: AppTheme.fontSizeSmall,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      );
    }

    // Portrait mode - just save button
    return Center(
      child: ElevatedButton.icon(
        onPressed: widget.onSaveAsMemory,
        icon: const Icon(Icons.bookmark_add),
        label: const Text('Save as a Memory'),
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.accentColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 16,
          ),
          textStyle: TextStyle(
            fontFamily: AppTheme.primaryFontFamily,
            fontSize: AppTheme.fontSizeMedium,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _formatDeliveryTime(DateTime time) {
    // For today, show time only
    final now = DateTime.now();
    if (now.year == time.year && now.month == time.month && now.day == time.day) {
      return 'Today at ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    }

    // For yesterday
    final yesterday = now.subtract(const Duration(days: 1));
    if (yesterday.year == time.year && yesterday.month == time.month && yesterday.day == time.day) {
      return 'Yesterday at ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    }

    // For other days
    return '${time.month}/${time.day} at ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }
}

/// Utility class for simulating audio-based haptic feedback
///
/// This class is designed to provide haptic feedback at key moments
/// during audio playback, enhancing the experience for elderly users.
class AudioHapticFeedback {
  /// The last time feedback was provided
  DateTime _lastFeedbackTime = DateTime.now();

  /// Minimum time between feedback events (to prevent excessive vibrations)
  final Duration _minInterval = const Duration(milliseconds: 500);

  /// Provide haptic feedback at a certain progress percentage
  ///
  /// [progress] is the current playback progress (0.0-1.0)
  /// [milestones] is a list of progress points to provide feedback at
  /// [intensities] is a list of feedback intensities matching the milestones
  void provideProgressFeedback(
      double progress, {
        List<double> milestones = const [0.25, 0.5, 0.75, 0.95],
        List<HapticFeedbackType> intensities = const [
          HapticFeedbackType.light,
          HapticFeedbackType.medium,
          HapticFeedbackType.medium,
          HapticFeedbackType.heavy,
        ],
      }) {
    // Check if we're allowed to give feedback yet
    final now = DateTime.now();
    if (now.difference(_lastFeedbackTime) < _minInterval) {
      return;
    }

    // Find the closest milestone that we've just passed
    for (int i = 0; i < milestones.length; i++) {
      final milestone = milestones[i];
      // If we're within 2% of a milestone, provide feedback
      if (progress >= milestone && progress <= milestone + 0.02) {
        _provideFeedback(intensities[i]);
        _lastFeedbackTime = now;
        break;
      }
    }
  }

  /// Provide haptic feedback for button interactions
  ///
  /// [type] determines the intensity of the feedback
  void provideButtonFeedback(HapticFeedbackType type) {
    // Check if we're allowed to give feedback yet
    final now = DateTime.now();
    if (now.difference(_lastFeedbackTime) < _minInterval) {
      return;
    }

    _provideFeedback(type);
    _lastFeedbackTime = now;
  }

  /// Provide emergency stop feedback - more intense
  void provideEmergencyFeedback() {
    // For emergency stop, we always provide feedback regardless of interval
    _provideFeedback(HapticFeedbackType.heavy);

    // Double tap for emphasis
    Future.delayed(const Duration(milliseconds: 200), () {
      _provideFeedback(HapticFeedbackType.heavy);
    });

    _lastFeedbackTime = DateTime.now();
  }

  /// Provide the actual haptic feedback
  void _provideFeedback(HapticFeedbackType type) {
    switch (type) {
      case HapticFeedbackType.light:
        HapticFeedback.lightImpact();
        break;
      case HapticFeedbackType.medium:
        HapticFeedback.mediumImpact();
        break;
      case HapticFeedbackType.heavy:
        HapticFeedback.heavyImpact();
        break;
      case HapticFeedbackType.selection:
        HapticFeedback.selectionClick();
        break;
      case HapticFeedbackType.vibrate:
        HapticFeedback.vibrate();
        break;
    }
  }
}

/// Types of haptic feedback available
enum HapticFeedbackType {
  light,
  medium,
  heavy,
  selection,
  vibrate,
}

/// Calculate the power of a number
double pow(num x, num exponent) => x.pow(exponent).toDouble();