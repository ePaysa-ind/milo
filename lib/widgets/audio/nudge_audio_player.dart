// Copyright © 2025 Milo App. All rights reserved.
// Author: Milo Development Team
// File: lib/widgets/audio/nudge_audio_player.dart
// Version: 1.1.0
// Last Updated: April 22, 2025
// Description: Accessible audio player widget specifically designed for playing nudge audio for elderly users (55+)
// Change History:
// - 1.0.0: Initial implementation with elderly-focused optimizations
// - 1.1.0: Enhanced with improved memory management, performance optimizations,
//          better documentation, layout resilience, parameter validation,
//          and additional accessibility features

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';

import '../../models/nudge_model.dart';
import '../../services/audio_player_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/advanced_logger.dart';

// -----------------
// STATE MANAGEMENT
// -----------------

/// State provider for the audio player to optimize rebuilds
class _AudioPlayerState extends ChangeNotifier {
  // Player state
  PlaybackStatus _status = PlaybackStatus(
    state: AudioPlayerState.initializing,
    volume: 0.8,
    speed: 1.0,
  );

  // UI state
  bool _isInitializing = true;
  bool _isError = false;
  String _errorMessage = '';
  bool _isFocusMode = false;
  bool _isWaveformLoaded = false;
  List<double> _waveformData = [];
  Timer? _focusModeTimer;
  Timer? _progressHapticTimer;
  double? _lastProgressHapticValue;
  Timer? _speedRampTimer;
  double _targetSpeed = 1.0;
  double _currentRampSpeed = 0.5;
  bool _isRampingSpeed = false;

  // Getters
  PlaybackStatus get status => _status;
  bool get isInitializing => _isInitializing;
  bool get isError => _isError;
  String get errorMessage => _errorMessage;
  bool get isFocusMode => _isFocusMode;
  bool get isWaveformLoaded => _isWaveformLoaded;
  List<double> get waveformData => _waveformData;
  bool get isRampingSpeed => _isRampingSpeed;

  // Setters that trigger notification
  set status(PlaybackStatus newStatus) {
    if (_status.state != newStatus.state ||
        _status.positionMs != newStatus.positionMs ||
        _status.buffering != newStatus.buffering) {
      _status = newStatus;
      notifyListeners();
    } else if (_status.volume != newStatus.volume ||
        _status.speed != newStatus.speed ||
        _status.durationMs != newStatus.durationMs) {
      _status = newStatus;
      notifyListeners();
    }
  }

  set isInitializing(bool value) {
    if (_isInitializing != value) {
      _isInitializing = value;
      notifyListeners();
    }
  }

  set isError(bool value) {
    if (_isError != value) {
      _isError = value;
      notifyListeners();
    }
  }

  set errorMessage(String value) {
    if (_errorMessage != value) {
      _errorMessage = value;
      notifyListeners();
    }
  }

  // Focus mode management
  void activateFocusMode() {
    _cancelFocusModeTimer();
    _isFocusMode = true;
    _focusModeTimer = Timer(const Duration(seconds: 5), () {
      _isFocusMode = false;
      notifyListeners();
    });
    notifyListeners();
  }

  void _cancelFocusModeTimer() {
    _focusModeTimer?.cancel();
    _focusModeTimer = null;
  }

  // Waveform data management
  void setWaveformData(List<double> data) {
    _waveformData = data;
    _isWaveformLoaded = true;
    notifyListeners();
  }

  // Speed ramping management
  void startSpeedRamp(double targetSpeed) {
    _cancelSpeedRampTimer();
    _targetSpeed = targetSpeed;
    _currentRampSpeed = 0.5; // Start slower
    _isRampingSpeed = true;

    // Update speed every 2 seconds
    _speedRampTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_currentRampSpeed >= _targetSpeed) {
        _cancelSpeedRampTimer();
        return;
      }

      // Gradually increase speed
      _currentRampSpeed = min(_currentRampSpeed + 0.1, _targetSpeed);
      notifyListeners();
    });

    notifyListeners();
  }

  void _cancelSpeedRampTimer() {
    _isRampingSpeed = false;
    _speedRampTimer?.cancel();
    _speedRampTimer = null;
  }

  // Progress haptics management
  void setupProgressHaptics(int durationMs) {
    _cancelProgressHapticTimer();
    _lastProgressHapticValue = null;

    // Only set up if duration is known and reasonable
    if (durationMs <= 0) return;

    // Check progress every second
    _progressHapticTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_status.durationMs <= 0) return;

      // Calculate progress percentage
      final progress = _status.positionMs / _status.durationMs;

      // Trigger at 25%, 50%, 75%
      if (progress >= 0.25 && (_lastProgressHapticValue == null || _lastProgressHapticValue! < 0.25)) {
        HapticFeedback.lightImpact();
        _lastProgressHapticValue = 0.25;
      } else if (progress >= 0.5 && (_lastProgressHapticValue == null || _lastProgressHapticValue! < 0.5)) {
        HapticFeedback.mediumImpact();
        _lastProgressHapticValue = 0.5;
      } else if (progress >= 0.75 && (_lastProgressHapticValue == null || _lastProgressHapticValue! < 0.75)) {
        HapticFeedback.heavyImpact();
        _lastProgressHapticValue = 0.75;
      }
    });
  }

  void _cancelProgressHapticTimer() {
    _progressHapticTimer?.cancel();
    _progressHapticTimer = null;
  }

  // Cleanup resources
  @override
  void dispose() {
    _cancelFocusModeTimer();
    _cancelProgressHapticTimer();
    _cancelSpeedRampTimer();
    super.dispose();
  }

  // Handle current speed considering ramping
  double get currentSpeed {
    if (_isRampingSpeed) {
      return _currentRampSpeed;
    } else {
      return _status.speed;
    }
  }
}

/// Widget for displaying loading state
class _LoadingIndicator extends StatelessWidget {
  /// Message to display under the loading indicator
  final String message;

  /// Color for the loading indicator
  final Color color;

  const _LoadingIndicator({
    required this.message,
    required this.color,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: AppTheme.iconSizeLarge,
          height: AppTheme.iconSizeLarge,
          child: CircularProgressIndicator(
            strokeWidth: 4.0,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: AppTheme.spacingSmall),
        Text(
          message,
          style: TextStyle(
            fontFamily: AppTheme.primaryFontFamily,
            fontSize: AppTheme.fontSizeMedium,
            fontWeight: FontWeight.w500,
            color: AppTheme.textColor,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Widget for displaying errors with retry option
class _ErrorDisplay extends StatelessWidget {
  /// Error message to display
  final String message;

  /// Function to call when retry button is pressed
  final VoidCallback onRetry;

  const _ErrorDisplay({
    required this.message,
    required this.onRetry,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
        builder: (context, constraints) {
          final isSmallScreen = constraints.maxWidth < 300;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: isSmallScreen ? AppTheme.iconSizeMedium : AppTheme.iconSizeLarge,
                color: AppTheme.errorColor,
              ),
              const SizedBox(height: AppTheme.spacingSmall),
              Text(
                message,
                style: TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  fontSize: isSmallScreen ? AppTheme.fontSizeSmall : AppTheme.fontSizeMedium,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacingMedium),
              SizedBox(
                width: isSmallScreen ? 140 : 200,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size(
                        AppTheme.buttonMinWidth,
                        isSmallScreen ? AppTheme.buttonMinHeight * 0.8 : AppTheme.buttonMinHeight
                    ),
                    padding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 16 : 24,
                        vertical: isSmallScreen ? 12 : 16
                    ),
                  ),
                ),
              ),
            ],
          );
        }
    );
  }
}

/// A button with haptic feedback and larger touch area for improved accessibility
class _AccessibleButton extends StatefulWidget {
  /// Function to call when button is pressed
  final VoidCallback onPressed;

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
  const _AccessibleButton({
    required this.onPressed,
    required this.icon,
    required this.semanticLabel,
    this.size = AppTheme.iconSizeMedium,
    this.color = AppTheme.gentleTeal,
    this.isEnabled = true,
    this.applyFocusMode = false,
    this.focusModeScale = 1.2,
    Key? key,
  }) : super(key: key);

  @override
  State<_AccessibleButton> createState() => _AccessibleButtonState();
}

class _AccessibleButtonState extends State<_AccessibleButton> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

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
    super.dispose();
  }

  @override
  void didUpdateWidget(_AccessibleButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    final playerState = Provider.of<_AudioPlayerState>(context, listen: false);

    // Handle focus mode animation
    if (widget.applyFocusMode && playerState.isFocusMode) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<_AudioPlayerState>(
      builder: (context, playerState, child) {
        if (widget.applyFocusMode && playerState.isFocusMode) {
          _animationController.forward();
        } else {
          _animationController.reverse();
        }

        return KeyboardListener(
          focusNode: FocusNode(),
          onKeyEvent: (keyEvent) {
            // Handle keyboard shortcuts if this button is in focus
            if (widget.isEnabled && keyEvent is KeyDownEvent) {
              if (keyEvent.logicalKey == LogicalKeyboardKey.space ||
                  keyEvent.logicalKey == LogicalKeyboardKey.enter) {
                widget.onPressed();
              }
            }
          },
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Semantics(
              button: true,
              enabled: widget.isEnabled,
              label: widget.semanticLabel,
              child: InkWell(
                onTap: widget.isEnabled ? () {
                  HapticFeedback.mediumImpact();
                  widget.onPressed();
                } : null,
                borderRadius: BorderRadius.circular(AppTheme.borderRadiusCircular),
                splashColor: widget.color.withOpacity(0.3),
                highlightColor: widget.color.withOpacity(0.2),
                child: Container(
                  constraints: BoxConstraints(
                    minWidth: AppTheme.touchTargetMinSize,
                    minHeight: AppTheme.touchTargetMinSize,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    widget.icon,
                    size: widget.size,
                    color: widget.isEnabled ? widget.color : widget.color.withOpacity(0.4),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Enhanced slider with larger touch area and better visual feedback
class _AccessibleSlider extends StatelessWidget {
  /// Current value of the slider
  final double value;

  /// Minimum value of the slider
  final double min;

  /// Maximum value of the slider
  final double max;

  /// Optional label text to display above the slider
  final String? label;

  /// Function called when slider value changes
  final ValueChanged<double> onChanged;

  /// Optional function called when slider adjustment ends
  final ValueChanged<double>? onChangeEnd;

  /// Color of the active portion of the slider
  final Color activeColor;

  /// Color of the inactive portion of the slider
  final Color inactiveColor;

  /// Creates an accessible slider.
  ///
  /// The [value], [min], [max], and [onChanged] parameters are required.
  ///
  /// The [label] parameter is an optional text label to display above the slider.
  ///
  /// The [onChangeEnd] parameter is an optional callback for when the user stops
  /// adjusting the slider.
  ///
  /// The [activeColor] parameter defaults to the teal color defined in AppTheme.
  ///
  /// The [inactiveColor] parameter defaults to the divider color defined in AppTheme.
  const _AccessibleSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.label,
    this.activeColor = AppTheme.gentleTeal,
    this.inactiveColor = AppTheme.dividerColor,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
        builder: (context, constraints) {
          final isSmallScreen = constraints.maxWidth < 300;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    label!,
                    style: TextStyle(
                      fontFamily: AppTheme.primaryFontFamily,
                      fontSize: isSmallScreen ? AppTheme.fontSizeXSmall : AppTheme.fontSizeSmall,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondaryColor,
                    ),
                  ),
                ),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: isSmallScreen ? 6.0 : 8.0,
                  activeTrackColor: activeColor,
                  inactiveTrackColor: inactiveColor,
                  thumbColor: activeColor,
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: isSmallScreen ? 12.0 : 16.0,
                    elevation: 4.0,
                    pressedElevation: 8.0,
                  ),
                  overlayShape: RoundSliderOverlayShape(
                    overlayRadius: isSmallScreen ? 24.0 : 28.0,
                  ),
                  valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
                  showValueIndicator: ShowValueIndicator.always,
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: (max - min > 10) ? 20 : 10,
                  label: value.toStringAsFixed(1),
                  onChanged: onChanged,
                  onChangeEnd: onChangeEnd,
                ),
              ),
            ],
          );
        }
    );
  }
}

/// A button for selecting playback speed with options for progressive speed ramping
class _SpeedButton extends StatelessWidget {
  /// Current playback speed
  final double currentSpeed;

  /// Function called when speed is changed
  final ValueChanged<double> onSpeedChanged;

  /// Function called when speed ramping is requested
  final ValueChanged<double> onSpeedRampRequested;

  /// Whether speed ramping is currently active
  final bool isRampingSpeed;

  /// Creates a speed selection button.
  ///
  /// The [currentSpeed] parameter is the current playback speed.
  ///
  /// The [onSpeedChanged] parameter is called when a new speed is selected.
  ///
  /// The [onSpeedRampRequested] parameter is called when speed ramping is requested.
  ///
  /// The [isRampingSpeed] parameter indicates if progressive speed ramping is active.
  const _SpeedButton({
    required this.currentSpeed,
    required this.onSpeedChanged,
    required this.onSpeedRampRequested,
    required this.isRampingSpeed,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Change playback speed',
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
        _buildSpeedMenuItem('0.5', 'Very Slow'),
        _buildSpeedMenuItem('0.75', 'Slow'),
        _buildSpeedMenuItem('1.0', 'Normal'),
        _buildSpeedMenuItem('1.25', 'Fast'),
        _buildSpeedMenuItem('1.5', 'Very Fast'),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'ramp',
          child: Row(
            children: [
              const Icon(
                Icons.trending_up,
                color: AppTheme.calmBlue,
                size: AppTheme.iconSizeSmall,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Progressive Speed (Start slow, gradually increase)',
                  style: TextStyle(
                    fontFamily: AppTheme.primaryFontFamily,
                    fontSize: AppTheme.fontSizeSmall,
                    fontWeight: isRampingSpeed ? FontWeight.bold : FontWeight.normal,
                    color: isRampingSpeed ? AppTheme.calmBlue : AppTheme.textColor,
                  ),
                ),
              ),
              if (isRampingSpeed)
                const Icon(
                  Icons.check,
                  color: AppTheme.calmBlue,
                  size: AppTheme.iconSizeSmall,
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
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isRampingSpeed ? Icons.trending_up : Icons.speed,
              color: AppTheme.gentleTeal,
              size: AppTheme.iconSizeSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${currentSpeed.toStringAsFixed(1)}x',
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: AppTheme.fontSizeSmall,
                fontWeight: FontWeight.w500,
                color: AppTheme.textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
              color: isSelected ? AppTheme.gentleTeal : AppTheme.textColor,
            ),
          ),
          const Spacer(),
          if (isSelected)
            const Icon(
              Icons.check,
              color: AppTheme.gentleTeal,
              size: AppTheme.iconSizeSmall,
            ),
        ],
      ),
    );
  }
}

/// A button for adjusting volume with presets
class _VolumeButton extends StatelessWidget {
  /// Current volume level
  final double currentVolume;

  /// Function called when volume is changed
  final ValueChanged<double> onVolumeChanged;

  /// Creates a volume adjustment button.
  ///
  /// The [currentVolume] parameter is the current volume level (0.0-1.0).
  ///
  /// The [onVolumeChanged] parameter is called when the volume is adjusted.
  const _VolumeButton({
    required this.currentVolume,
    required this.onVolumeChanged,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: 'Adjust volume',
      itemBuilder: (context) => [
        PopupMenuItem<double>(
          value: -1, // Special value for slider
          enabled: false,
          child: SizedBox(
            width: 200,
            child: _AccessibleSlider(
              value: currentVolume,
              min: 0.0,
              max: 1.0,
              label: 'Volume: ${(currentVolume * 100).toInt()}%',
              activeColor: AppTheme.gentleTeal,
              onChanged: (value) {
                // Update volume in real-time
                onVolumeChanged(value);
              },
            ),
          ),
        ),
        const PopupMenuDivider(),
        _buildVolumeMenuItem(0.25, 'Low'),
        _buildVolumeMenuItem(0.5, 'Medium'),
        _buildVolumeMenuItem(0.75, 'High'),
        _buildVolumeMenuItem(1.0, 'Maximum'),
      ],
      offset: const Offset(0, -250),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
      ),
      color: AppTheme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getVolumeIcon(currentVolume),
              color: AppTheme.gentleTeal,
              size: AppTheme.iconSizeSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${(currentVolume * 100).toInt()}%',
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: AppTheme.fontSizeSmall,
                fontWeight: FontWeight.w500,
                color: AppTheme.textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getVolumeIcon(double volume) {
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

  PopupMenuItem<double> _buildVolumeMenuItem(double volume, String label) {
    final volumePercent = (volume * 100).toInt();
    final isSelected = (currentVolume * 100).round() == volumePercent;

    return PopupMenuItem<double>(
      value: volume,
      onTap: () => onVolumeChanged(volume),
      child: Row(
        children: [
          Icon(
            _getVolumeIcon(volume),
            color: isSelected ? AppTheme.gentleTeal : AppTheme.textColor,
            size: AppTheme.iconSizeSmall,
          ),
          const SizedBox(width: 12),
          Text(
            '$label ($volumePercent%)',
            style: TextStyle(
              fontFamily: AppTheme.primaryFontFamily,
              fontSize: AppTheme.fontSizeMedium,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? AppTheme.gentleTeal : AppTheme.textColor,
            ),
          ),
          const Spacer(),
          if (isSelected)
            const Icon(
              Icons.check,
              color: AppTheme.gentleTeal,
              size: AppTheme.iconSizeSmall,
            ),
        ],
      ),
    );
  }
}

/// A widget that displays a position progress bar with time labels and waveform visualization
class _ProgressBar extends StatefulWidget {
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

  /// Function called to replay the last 10 seconds
  final VoidCallback onReplayLast10Seconds;

  /// Whether the progress bar is enabled
  final bool isEnabled;

  /// Waveform data for visualization (null if not available)
  final List<double>? waveformData;

  /// Whether to show waveform visualization
  final bool showWaveform;

  /// Creates a progress bar with waveform visualization.
  ///
  /// The [positionMs], [durationMs], [onPositionChanged], and [onReplayLast10Seconds]
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
  const _ProgressBar({
    required this.positionMs,
    required this.durationMs,
    required this.onPositionChanged,
    required this.onReplayLast10Seconds,
    this.isBuffering = false,
    this.bufferPositionMs = 0,
    this.isEnabled = true,
    this.waveformData,
    this.showWaveform = true,
    Key? key,
  }) : super(key: key);

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  // Used to track if user is currently dragging the slider
  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  Widget build(BuildContext context) {
    // Handle case where duration is unknown or zero
    final progress = widget.durationMs > 0 ? widget.positionMs / widget.durationMs : 0.0;
    final bufferProgress = widget.durationMs > 0 ? widget.bufferPositionMs / widget.durationMs : 0.0;

    // Use drag value if dragging, otherwise use actual progress
    final currentProgress = _isDragging ? _dragValue : progress;

    return LayoutBuilder(
        builder: (context, constraints) {
          final isSmallScreen = constraints.maxWidth < 300;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Time labels
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8.0 : 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Replay 10s button
                    TextButton.icon(
                      onPressed: widget.positionMs > 10000 ? widget.onReplayLast10Seconds : null,
                      icon: const Icon(Icons.replay_10, size: AppTheme.iconSizeSmall),
                      label: const Text('10s'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 4.0 : 8.0,
                          vertical: 0,
                        ),
                        minimumSize: Size.zero,
                        foregroundColor: AppTheme.gentleTeal,
                        textStyle: TextStyle(
                          fontFamily: AppTheme.primaryFontFamily,
                          fontSize: isSmallScreen ? AppTheme.fontSizeXSmall : AppTheme.fontSizeSmall,
                        ),
                      ),
                    ),

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
                            _formatDuration(Duration(milliseconds: widget.durationMs)),
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

                    // Buffering indicator
                    if (widget.isBuffering)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.gentleTeal),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Progress bar with waveform
              Stack(
                alignment: Alignment.center,
                children: [
                  // Waveform visualization (if available)
                  if (widget.showWaveform && widget.waveformData != null && widget.waveformData!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        height: 32,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
                          child: CustomPaint(
                            painter: _WaveformPainter(
                              waveformData: widget.waveformData!,
                              color: AppTheme.gentleTeal.withOpacity(0.3),
                              progressColor: AppTheme.gentleTeal,
                              progress: currentProgress.clamp(0.0, 1.0),
                            ),
                            size: Size(constraints.maxWidth - 32, 32),
                          ),
                        ),
                      ),
                    ),

                  // Main progress bar
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: isSmallScreen ? 6.0 : 8.0,
                      activeTrackColor: widget.showWaveform && widget.waveformData != null && widget.waveformData!.isNotEmpty
                          ? Colors.transparent
                          : AppTheme.gentleTeal,
                      inactiveTrackColor: widget.showWaveform && widget.waveformData != null && widget.waveformData!.isNotEmpty
                          ? Colors.transparent
                          : AppTheme.dividerColor,
                      thumbColor: AppTheme.gentleTeal,
                      thumbShape: RoundSliderThumbShape(
                        enabledThumbRadius: isSmallScreen ? 10.0 : 12.0,
                        elevation: 4.0,
                        pressedElevation: 8.0,
                      ),
                      overlayShape: RoundSliderOverlayShape(
                        overlayRadius: isSmallScreen ? 20.0 : 24.0,
                      ),
                    ),
                    child: SizedBox(
                      height: 40, // Extra height for larger touch area
                      child: Slider(
                        value: currentProgress.clamp(0.0, 1.0),
                        min: 0.0,
                        max: 1.0,
                        onChanged: widget.isEnabled ? (value) {
                          setState(() {
                            _isDragging = true;
                            _dragValue = value;
                          });
                        } : null,
                        onChangeEnd: widget.isEnabled ? (value) {
                          setState(() {
                            _isDragging = false;
                          });
                          final newPositionMs = (value * widget.durationMs).round();
                          widget.onPositionChanged(newPositionMs);
                        } : null,
                      ),
                    ),
                  ),

                  // Buffer indicator (positioned beneath the main slider)
                  if (bufferProgress > 0 && bufferProgress < 1.0)
                    Positioned(
                      left: 16 + (MediaQuery.of(context).size.width - 32) * bufferProgress,
                      child: Container(
                        width: 4,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppTheme.gentleTeal.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        }
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Custom painter for drawing waveform visualization
class _WaveformPainter extends CustomPainter {
  /// Waveform amplitude data (values between 0.0 and 1.0)
  final List<double> waveformData;

  /// Color for the inactive part of the waveform
  final Color color;

  /// Color for the active part of the waveform
  final Color progressColor;

  /// Current progress (0.0-1.0)
  final double progress;

  _WaveformPainter({
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
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.progressColor != progressColor;
  }
}

/// A widget that displays battery and connectivity status
class _StatusIndicators extends StatelessWidget {
  /// Whether the player is in offline mode
  final bool isOfflineMode;

  /// Battery level percentage
  final int batteryLevel;

  /// Whether the device is currently charging
  final bool isCharging;

  /// Creates status indicators for battery and connectivity.
  ///
  /// The [isOfflineMode] parameter indicates if the player is in offline mode.
  ///
  /// The [batteryLevel] parameter is the current battery level (0-100).
  ///
  /// The [isCharging] parameter indicates if the device is currently charging.
  const _StatusIndicators({
    required this.isOfflineMode,
    required this.batteryLevel,
    required this.isCharging,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
        builder: (context, constraints) {
          final isSmallScreen = constraints.maxWidth < 300;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Battery indicator
              Icon(
                _getBatteryIcon(),
                color: _getBatteryColor(),
                size: isSmallScreen ? AppTheme.iconSizeSmall * 0.8 : AppTheme.iconSizeSmall,
              ),
              const SizedBox(width: 4),
              Text(
                isCharging ? 'Charging' : '$batteryLevel%',
                style: TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  fontSize: isSmallScreen ? AppTheme.fontSizeXSmall * 0.9 : AppTheme.fontSizeXSmall,
                  fontWeight: FontWeight.w500,
                  color: _getBatteryColor(),
                ),
              ),

              const SizedBox(width: 16),

              // Offline mode indicator
              if (isOfflineMode) ...[
                Icon(
                  Icons.offline_bolt,
                  color: AppTheme.warningColor,
                  size: isSmallScreen ? AppTheme.iconSizeSmall * 0.8 : AppTheme.iconSizeSmall,
                ),
                const SizedBox(width: 4),
                Text(
                  'Offline',
                  style: TextStyle(
                    fontFamily: AppTheme.primaryFontFamily,
                    fontSize: isSmallScreen ? AppTheme.fontSizeXSmall * 0.9 : AppTheme.fontSizeXSmall,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.warningColor,
                  ),
                ),
              ],
            ],
          );
        }
    );
  }

  IconData _getBatteryIcon() {
    if (isCharging) {
      return Icons.battery_charging_full;
    } else if (batteryLevel <= 10) {
      return Icons.battery_alert;
    } else if (batteryLevel <= 30) {
      return Icons.battery_1_bar;
    } else if (batteryLevel <= 50) {
      return Icons.battery_3_bar;
    } else if (batteryLevel <= 80) {
      return Icons.battery_5_bar;
    } else {
      return Icons.battery_full;
    }
  }

  Color _getBatteryColor() {
    if (isCharging) {
      return AppTheme.calmGreen;
    } else if (batteryLevel <= 10) {
      return AppTheme.errorColor;
    } else if (batteryLevel <= 30) {
      return AppTheme.warningColor;
    } else {
      return AppTheme.textSecondaryColor;
    }
  }
}

/// A widget that displays feedback options for a nudge
class _NudgeFeedback extends StatelessWidget {
  /// Nudge metadata
  final NudgeDelivery nudge;

  /// Function called when feedback is given
  final Function(bool) onFeedbackGiven;

  /// Whether feedback controls are enabled
  final bool isFeedbackEnabled;

  /// Creates a feedback collection widget for nudges.
  ///
  /// The [nudge] parameter is the nudge metadata.
  ///
  /// The [onFeedbackGiven] parameter is called when the user provides feedback.
  ///
  /// The [isFeedbackEnabled] parameter determines if the feedback controls are enabled.
  const _NudgeFeedback({
    required this.nudge,
    required this.onFeedbackGiven,
    this.isFeedbackEnabled = true,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
        builder: (context, constraints) {
          final isSmallScreen = constraints.maxWidth < 300;

          // Already gave feedback
          if (nudge.userFeedback != null) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Was this helpful?',
                  style: TextStyle(
                    fontFamily: AppTheme.primaryFontFamily,
                    fontSize: isSmallScreen ? AppTheme.fontSizeSmall : AppTheme.fontSizeMedium,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textColor,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FeedbackButton(
                      icon: Icons.thumb_up,
                      label: 'Yes',
                      isSelected: nudge.userFeedback == true,
                      onPressed: null, // Already selected, disabled
                      isSmallScreen: isSmallScreen,
                    ),
                    SizedBox(width: isSmallScreen ? 16 : 32),
                    _FeedbackButton(
                      icon: Icons.thumb_down,
                      label: 'No',
                      isSelected: nudge.userFeedback == false,
                      onPressed: null, // Already selected, disabled
                      isSmallScreen: isSmallScreen,
                    ),
                  ],
                ),
              ],
            );
          }

          // Can give feedback
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Was this helpful?',
                style: TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  fontSize: isSmallScreen ? AppTheme.fontSizeSmall : AppTheme.fontSizeMedium,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textColor,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FeedbackButton(
                    icon: Icons.thumb_up,
                    label: 'Yes',
                    isEnabled: isFeedbackEnabled,
                    onPressed: () => onFeedbackGiven(true),
                    isSmallScreen: isSmallScreen,
                  ),
                  SizedBox(width: isSmallScreen ? 16 : 32),
                  _FeedbackButton(
                    icon: Icons.thumb_down,
                    label: 'No',
                    isEnabled: isFeedbackEnabled,
                    onPressed: () => onFeedbackGiven(false),
                    isSmallScreen: isSmallScreen,
                  ),
                ],
              ),
            ],
          );
        }
    );
  }
}

/// A button for nudge feedback
class _FeedbackButton extends StatelessWidget {
  /// Icon to display
  final IconData icon;

  /// Button label text
  final String label;

  /// Function called when button is pressed
  final VoidCallback? onPressed;

  /// Whether the button is selected
  final bool isSelected;

  /// Whether the button is enabled
  final bool isEnabled;

  /// Whether to use compact layout for small screens
  final bool isSmallScreen;

  /// Creates a feedback button.
  ///
  /// The [icon] parameter is the icon to display.
  ///
  /// The [label] parameter is the button label text.
  ///
  /// The [onPressed] parameter is called when the button is pressed.
  ///
  /// The [isSelected] parameter indicates if the button is selected.
  ///
  /// The [isEnabled] parameter determines if the button is enabled.
  ///
  /// The [isSmallScreen] parameter adjusts the layout for small screens.
  const _FeedbackButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.isSelected = false,
    this.isEnabled = true,
    this.isSmallScreen = false,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? AppTheme.gentleTeal
        : (isEnabled ? AppTheme.textSecondaryColor : AppTheme.textSecondaryColor.withOpacity(0.5));

    return InkWell(
      onTap: isEnabled ? onPressed : null,
      borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 8.0 : 12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: color,
              size: isSmallScreen ? AppTheme.iconSizeSmall : AppTheme.iconSizeMedium,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: isSmallScreen ? AppTheme.fontSizeXSmall : AppTheme.fontSizeSmall,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A widget for displaying "Save as Memory" button
class _SaveAsMemoryButton extends StatelessWidget {
  /// Nudge metadata
  final NudgeDelivery nudge;

  /// Function called when Save as Memory is requested
  final VoidCallback onSaveAsMemory;

  /// Whether the button is enabled
  final bool isEnabled;

  /// Creates a Save as Memory button.
  ///
  /// The [nudge] parameter is the nudge metadata.
  ///
  /// The [onSaveAsMemory] parameter is called when the user wants to save the nudge as a memory.
  ///
  /// The [isEnabled] parameter determines if the button is enabled.
  const _SaveAsMemoryButton({
    required this.nudge,
    required this.onSaveAsMemory,
    this.isEnabled = true,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
        builder: (context, constraints) {
          final isSmallScreen = constraints.maxWidth < 300;

          return SizedBox(
            width: isSmallScreen ? 160 : 200,
            child: ElevatedButton.icon(
              onPressed: isEnabled ? onSaveAsMemory : null,
              icon: const Icon(Icons.bookmark),
              label: const Text('Save as Memory'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.calmBlue,
                foregroundColor: Colors.black,
                minimumSize: Size(
                    isSmallScreen ? 160 : 200,
                    isSmallScreen ? AppTheme.buttonMinHeight * 0.8 : AppTheme.buttonMinHeight
                ),
                padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 16 : 24,
                    vertical: isSmallScreen ? 12 : 16
                ),
                textStyle: TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  fontSize: isSmallScreen ? AppTheme.fontSizeSmall : AppTheme.fontSizeMedium,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }
    );
  }
}

/// Function signature for generating random waveform data for testing
typedef WaveformDataGenerator = List<double> Function(int length);

/// Main widget for playing nudge audio with accessibility features
class NudgeAudioPlayer extends StatefulWidget {
  /// URL or file path to play
  final String audioUrl;

  /// Associated nudge metadata
  final NudgeDelivery? nudge;

  /// Whether to autoplay when loaded
  final bool autoPlay;

  /// Callback when user gives feedback
  final Function(NudgeDelivery, bool)? onFeedbackGiven;

  /// Callback when user wants to save as memory
  final Function(NudgeDelivery)? onSaveAsMemory;

  /// Callback when playback completes
  final VoidCallback? onPlaybackComplete;

  /// Callback when error occurs
  final Function(String)? onError;

  /// Whether to show volume and speed controls
  final bool showControls;

  /// Whether to show system status indicators
  final bool showStatusIndicators;

  /// Whether to show feedback options
  final bool showFeedback;

  /// Whether to show save as memory button
  final bool showSaveAsMemory;

  /// Whether to show waveform visualization
  final bool showWaveform;

  /// Whether to enable focus mode
  final bool enableFocusMode;

  /// Whether to enable speed ramping
  final bool enableSpeedRamp;

  /// Whether to enable progress haptics
  final bool enableProgressHaptics;

  /// Additional padding around the player
  final EdgeInsets padding;

  /// Background color for the player
  final Color? backgroundColor;

  /// Accent color for controls
  final Color accentColor;

  /// Function to generate waveform data if not loaded from audio
  final WaveformDataGenerator? waveformDataGenerator;

  /// Creates an accessible audio player for nudges.
  ///
  /// The [audioUrl] parameter is required and specifies the audio to play.
  ///
  /// The [nudge] parameter is optional metadata about the nudge.
  ///
  /// The [autoPlay] parameter determines if the audio should play automatically
  /// when loaded. Defaults to false.
  ///
  /// The [onFeedbackGiven] parameter is called when the user provides feedback
  /// about a nudge.
  ///
  /// The [onSaveAsMemory] parameter is called when the user wants to save a nudge
  /// as a memory.
  ///
  /// The [onPlaybackComplete] parameter is called when playback finishes.
  ///
  /// The [onError] parameter is called when an error occurs, with a user-friendly
  /// error message.
  ///
  /// The [showControls] parameter determines if volume and speed controls should
  /// be displayed. Defaults to true.
  ///
  /// The [showStatusIndicators] parameter determines if battery and connectivity
  /// indicators should be shown. Defaults to true.
  ///
  /// The [showFeedback] parameter determines if feedback options should be shown.
  /// Defaults to true.
  ///
  /// The [showSaveAsMemory] parameter determines if the "Save as Memory" button
  /// should be shown. Defaults to true.
  ///
  /// The [showWaveform] parameter determines if a waveform visualization should be
  /// displayed. Defaults to true.
  ///
  /// The [enableFocusMode] parameter enables a mode where controls temporarily enlarge
  /// when user attention is needed. Defaults to false.
  ///
  /// The [enableSpeedRamp] parameter enables progressive speed ramping, which starts
  /// playback slower and gradually increases to normal speed. Defaults to false.
  ///
  /// The [enableProgressHaptics] parameter enables haptic feedback at key points
  /// during playback (25%, 50%, 75%). Defaults to false.
  ///
  /// The [padding] parameter specifies additional padding around the player.
  /// Defaults to 16 pixels on all sides.
  ///
  /// The [backgroundColor] parameter specifies the background color for the player.
  /// If null, the card color from AppTheme is used.
  ///
  /// The [accentColor] parameter specifies the accent color for controls.
  /// Defaults to the teal color from AppTheme.
  ///
  /// The [waveformDataGenerator] parameter is an optional function to generate
  /// waveform data for testing or when not available from the audio file.
  const NudgeAudioPlayer({
    required this.audioUrl,
    this.nudge,
    this.autoPlay = false,
    this.onFeedbackGiven,
    this.onSaveAsMemory,
    this.onPlaybackComplete,
    this.onError,
    this.showControls = true,
    this.showStatusIndicators = true,
    this.showFeedback = true,
    this.showSaveAsMemory = true,
    this.showWaveform = true,
    this.enableFocusMode = false,
    this.enableSpeedRamp = false,
    this.enableProgressHaptics = false,
    this.padding = const EdgeInsets.all(16.0),
    this.backgroundColor,
    this.accentColor = AppTheme.gentleTeal,
    this.waveformDataGenerator,
    Key? key,
  }) : assert(
  audioUrl.isNotEmpty,
  'audioUrl must not be empty'
  ),
        assert(
        !showFeedback || nudge != null,
        'nudge must be provided when showFeedback is true'
        ),
        assert(
        !showSaveAsMemory || nudge != null,
        'nudge must be provided when showSaveAsMemory is true'
        ),
        super(key: key);

  @override
  State<NudgeAudioPlayer> createState() => _NudgeAudioPlayerState();
}

class _NudgeAudioPlayerState extends State<NudgeAudioPlayer> with SingleTickerProviderStateMixin {
  late final AudioPlayerService _audioPlayerService;
  final _audioPlayerState = _AudioPlayerState();
  StreamSubscription<PlaybackStatus>? _statusSubscription;
  FocusNode _keyboardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _audioPlayerService = AudioPlayerService();
    _initializePlayer();

    // Set up keyboard focus node
    _keyboardFocusNode = FocusNode(onKey: _handleKeyboardInput);

    // Generate waveform data if generator is provided
    if (widget.waveformDataGenerator != null) {
      final waveformData = widget.waveformDataGenerator!(100);
      _audioPlayerState.setWaveformData(waveformData);
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _audioPlayerState.dispose();
    _keyboardFocusNode.dispose();
    // Don't dispose the service as it's a singleton
    super.dispose();
  }

  @override
  void didUpdateWidget(NudgeAudioPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If the URL changed, reload the player
    if (widget.audioUrl != oldWidget.audioUrl) {
      _loadAudio();
    }
  }

  /// Handle keyboard input for controlling playback
  KeyEventResult _handleKeyboardInput(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.space:
          if (_audioPlayerState.status.state == AudioPlayerState.playing) {
            _audioPlayerService.pause();
          } else {
            _audioPlayerService.play();
          }
          return KeyEventResult.handled;

        case LogicalKeyboardKey.arrowRight:
        // Seek forward 5 seconds
          final newPosition = _audioPlayerState.status.positionMs + 5000;
          _audioPlayerService.seekTo(newPosition);
          return KeyEventResult.handled;

        case LogicalKeyboardKey.arrowLeft:
        // Seek backward 5 seconds
          final newPosition = max(_audioPlayerState.status.positionMs - 5000, 0);
          _audioPlayerService.seekTo(newPosition);
          return KeyEventResult.handled;

        case LogicalKeyboardKey.keyR:
          _restart();
          return KeyEventResult.handled;

        case LogicalKeyboardKey.escape:
          _stop();
          return KeyEventResult.handled;

        case LogicalKeyboardKey.keyM:
        // Mute/unmute
          if (_audioPlayerState.status.volume > 0.1) {
            _setVolume(0.0);
          } else {
            _setVolume(0.8);
          }
          return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  /// Initialize the player and subscribe to status updates
  Future<void> _initializePlayer() async {
    try {
      // Initialize the service if needed
      if (!_audioPlayerService.currentStatus.state.toString().contains('error')) {
        await _audioPlayerService.initialize();
      }

      // Subscribe to status updates
      _statusSubscription = _audioPlayerService.status.listen((status) {
        // Update player state
        _audioPlayerState.status = status;

        // Handle special states
        if (status.state == AudioPlayerState.error) {
          _audioPlayerState.isError = true;
          _audioPlayerState.errorMessage = status.friendlyErrorMessage;

          // Notify parent
          if (widget.onError != null) {
            widget.onError!(status.friendlyErrorMessage);
          }
        } else if (status.state == AudioPlayerState.completed) {
          // Notify parent
          if (widget.onPlaybackComplete != null) {
            widget.onPlaybackComplete!();
          }
        } else if (status.state == AudioPlayerState.playing) {
          // Set up progress haptics if enabled
          if (widget.enableProgressHaptics) {
            _audioPlayerState.setupProgressHaptics(status.durationMs);
          }

          // Activate focus mode if enabled
          if (widget.enableFocusMode) {
            _audioPlayerState.activateFocusMode();
          }
        }
      });

      // Load the audio
      await _loadAudio();

      // No longer initializing
      _audioPlayerState.isInitializing = false;
    } catch (e) {
      AdvancedLogger.logError('NudgeAudioPlayer', 'Failed to initialize player: $e');

      _audioPlayerState.isInitializing = false;
      _audioPlayerState.isError = true;
      _audioPlayerState.errorMessage = 'Failed to initialize audio player. Please try again.';

      // Notify parent
      if (widget.onError != null) {
        widget.onError!(_audioPlayerState.errorMessage);
      }
    }
  }

  /// Load the audio from the URL
  Future<void> _loadAudio() async {
    try {
      await _audioPlayerService.playUrl(
        widget.audioUrl,
        nudge: widget.nudge,
        autoPlay: widget.autoPlay,
      );

      // Reset error state
      _audioPlayerState.isError = false;

      // Generate waveform data if needed and not already available
      if (widget.showWaveform &&
          !_audioPlayerState.isWaveformLoaded &&
          widget.waveformDataGenerator == null) {
        // Either generate from audio file or use placeholder
        _generateWaveformFromAudio(widget.audioUrl);
      }
    } catch (e) {
      AdvancedLogger.logError('NudgeAudioPlayer', 'Failed to load audio: $e');

      _audioPlayerState.isError = true;
      _audioPlayerState.errorMessage = 'Failed to load audio. Please try again.';

      // Notify parent
      if (widget.onError != null) {
        widget.onError!(_audioPlayerState.errorMessage);
      }
    }
  }

  /// Generate waveform data from audio file
  Future<void> _generateWaveformFromAudio(String audioUrl) async {
    try {
      // For demonstration, generate random waveform data
      // In a real implementation, you would analyze the actual audio file
      final random = Random();
      final waveformData = List<double>.generate(
          100,
              (i) => 0.2 + 0.6 * random.nextDouble() * _smoothingFunction(i, 100)
      );

      _audioPlayerState.setWaveformData(waveformData);
    } catch (e) {
      // Non-critical, just log the error
      AdvancedLogger.logError('NudgeAudioPlayer', 'Failed to generate waveform: $e');
    }
  }

  /// Helper function to create smooth wave pattern
  double _smoothingFunction(int i, int total) {
    // Create a smoother pattern that rises and falls
    return 0.5 + 0.5 * sin(i / total * 6 * pi);
  }

  /// Toggle play/pause
  void _togglePlayPause() {
    if (_audioPlayerState.status.state == AudioPlayerState.playing) {
      _audioPlayerService.pause();
    } else {
      _audioPlayerService.play();
    }

    // Activate focus mode if enabled
    if (widget.enableFocusMode) {
      _audioPlayerState.activateFocusMode();
    }
  }

  /// Restart playback from beginning
  void _restart() {
    _audioPlayerService.seekTo(0);
    _audioPlayerService.play();

    // Activate focus mode if enabled
    if (widget.enableFocusMode) {
      _audioPlayerState.activateFocusMode();
    }
  }

  /// Stop playback
  void _stop() {
    _audioPlayerService.stop();
  }

  /// Seek to position
  void _seekTo(int positionMs) {
    _audioPlayerService.seekTo(positionMs);

    // Activate focus mode if enabled
    if (widget.enableFocusMode) {
      _audioPlayerState.activateFocusMode();
    }
  }

  /// Replay last 10 seconds
  void _replayLast10Seconds() {
    final newPosition = max(_audioPlayerState.status.positionMs - 10000, 0);
    _audioPlayerService.seekTo(newPosition);

    // Activate focus mode if enabled
    if (widget.enableFocusMode) {
      _audioPlayerState.activateFocusMode();
    }
  }

  /// Change volume
  void _setVolume(double volume) {
    _audioPlayerService.setVolume(volume);
  }

  /// Change playback speed directly
  void _setSpeed(double speed) {
    _audioPlayerService.setSpeed(speed);

    // Activate focus mode if enabled
    if (widget.enableFocusMode) {
      _audioPlayerState.activateFocusMode();
    }
  }

  /// Start speed ramping
  void _startSpeedRamp(double targetSpeed) {
    _audioPlayerState.startSpeedRamp(targetSpeed);

    // Start at half speed
    _audioPlayerService.setSpeed(0.5);

    // Setup a timer to progressively increase speed
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_audioPlayerState.isRampingSpeed) {
        timer.cancel();
        return;
      }

      // Get current ramp speed from state
      final currentSpeed = _audioPlayerState.currentSpeed;

      // Apply to player
      _audioPlayerService.setSpeed(currentSpeed);

      // Stop timer when reached target
      if (currentSpeed >= targetSpeed) {
        timer.cancel();
      }
    });
  }

  /// Handle user feedback
  void _handleFeedback(bool isPositive) {
    if (widget.nudge != null && widget.onFeedbackGiven != null) {
      widget.onFeedbackGiven!(widget.nudge!, isPositive);
    }
  }

  /// Handle save as memory
  void _handleSaveAsMemory() {
    if (widget.nudge != null && widget.onSaveAsMemory != null) {
      widget.onSaveAsMemory!(widget.nudge!);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Set up keyboard focus for the whole player
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true, // Allow immediate keyboard control
      child: Card(
        color: widget.backgroundColor ?? AppTheme.cardColor,
        elevation: 4.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
          side: BorderSide(
            color: AppTheme.dividerColor.withOpacity(0.3),
            width: 1.0,
          ),
        ),
        child: Padding(
          padding: widget.padding,
          child: ChangeNotifierProvider.value(
            value: _audioPlayerState,
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  /// Build the main content based on state
  Widget _buildContent() {
    return Consumer<_AudioPlayerState>(
      builder: (context, playerState, child) {
        // Show loading indicator during initialization
        if (playerState.isInitializing) {
          return _LoadingIndicator(
            message: 'Preparing audio player...',
            color: widget.accentColor,
          );
        }

        // Show error view if there's an error
        if (playerState.isError) {
          return _ErrorDisplay(
            message: playerState.errorMessage,
            onRetry: _loadAudio,
          );
        }

        // Show loading indicator while loading audio
        if (playerState.status.state == AudioPlayerState.loading) {
          return _LoadingIndicator(
            message: 'Loading audio...',
            color: widget.accentColor,
          );
        }

        // Show player content for all other states
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status indicators (optional)
            if (widget.showStatusIndicators) ...[
              _StatusIndicators(
                isOfflineMode: playerState.status.offlineMode,
                batteryLevel: playerState.status.batteryLevel,
                isCharging: playerState.status.isCharging,
              ),
              const SizedBox(height: AppTheme.spacingMedium),
            ],

            // Progress bar
            _ProgressBar(
              positionMs: playerState.status.positionMs,
              durationMs: playerState.status.durationMs,
              isBuffering: playerState.status.buffering,
              bufferPositionMs: playerState.status.bufferPositionMs,
              onPositionChanged: _seekTo,
              onReplayLast10Seconds: _replayLast10Seconds,
              isEnabled: playerState.status.state != AudioPlayerState.loading &&
                  playerState.status.state != AudioPlayerState.error,
              waveformData: playerState.isWaveformLoaded ? playerState.waveformData : null,
              showWaveform: widget.showWaveform,
            ),

            const SizedBox(height: AppTheme.spacingMedium),

            // Main playback controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Restart button
                _AccessibleButton(
                  onPressed: _restart,
                  icon: Icons.replay,
                  semanticLabel: 'Restart',
                  size: AppTheme.iconSizeMedium,
                  color: widget.accentColor,
                  isEnabled: playerState.status.state != AudioPlayerState.loading,
                  applyFocusMode: widget.enableFocusMode,
                  focusModeScale: 1.2,
                ),

                const SizedBox(width: AppTheme.spacingLarge),

                // Play/Pause button (larger)
                _AccessibleButton(
                  onPressed: _togglePlayPause,
                  icon: playerState.status.state == AudioPlayerState.playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  semanticLabel: playerState.status.state == AudioPlayerState.playing ? 'Pause' : 'Play',
                  size: AppTheme.iconSizeLarge,
                  color: widget.accentColor,
                  isEnabled: playerState.status.state != AudioPlayerState.loading,
                  applyFocusMode: widget.enableFocusMode,
                  focusModeScale: 1.3,
                ),

                const SizedBox(width: AppTheme.spacingLarge),

                // Stop button
                _AccessibleButton(
                  onPressed: _stop,
                  icon: Icons.stop_circle,
                  semanticLabel: 'Stop',
                  size: AppTheme.iconSizeMedium,
                  color: widget.accentColor,
                  isEnabled: playerState.status.state != AudioPlayerState.loading,
                  applyFocusMode: widget.enableFocusMode,
                  focusModeScale: 1.2,
                ),
              ],
            ),

            const SizedBox(height: AppTheme.spacingMedium),

            // Volume and speed controls (optional)
            if (widget.showControls) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Volume control
                  _VolumeButton(
                    currentVolume: playerState.status.volume,
                    onVolumeChanged: _setVolume,
                  ),

                  const SizedBox(width: AppTheme.spacingLarge),

                  // Speed control
                  _SpeedButton(
                    currentSpeed: playerState.currentSpeed,
                    onSpeedChanged: _setSpeed,
                    onSpeedRampRequested: widget.enableSpeedRamp ? _startSpeedRamp : (_) {},
                    isRampingSpeed: playerState.isRampingSpeed,
                  ),
                ],
              ),

              const SizedBox(height: AppTheme.spacingMedium),
            ],

            // Status message
            Text(
              playerState.status.statusMessage,
              style: TextStyle(
                fontFamily: AppTheme.primaryFontFamily,
                fontSize: AppTheme.fontSizeSmall,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondaryColor,
              ),
              textAlign: TextAlign.center,
            ),

            // Feedback section (optional)
            if (widget.showFeedback && widget.nudge != null) ...[
              const SizedBox(height: AppTheme.spacingLarge),
              _NudgeFeedback(
                nudge: widget.nudge!,
                onFeedbackGiven: _handleFeedback,
                isFeedbackEnabled: playerState.status.state != AudioPlayerState.loading,
              ),
            ],

            // Save as memory button (optional)
            if (widget.showSaveAsMemory && widget.nudge != null) ...[
              const SizedBox(height: AppTheme.spacingLarge),
              _SaveAsMemoryButton(
                nudge: widget.nudge!,
                onSaveAsMemory: _handleSaveAsMemory,
                isEnabled: playerState.status.state != AudioPlayerState.loading,
              ),
            ],
          ],
        );
      },
    );
  }
}