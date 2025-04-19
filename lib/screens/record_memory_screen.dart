// lib/screens/record_memory_screen.dart -create new memories
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

import '../services/memory_service.dart';
import '../services/openai_service.dart';
import '../services/auth_service.dart';
import '../utils/advanced_logger.dart';
import '../models/memory.dart';
import '../models/ai_story.dart';
import '../theme/app_theme.dart';
import 'ai_story_screen.dart';
import 'ai_story_processing_screen.dart';

class RecordMemoryScreen extends StatefulWidget {
  const RecordMemoryScreen({Key? key}) : super(key: key);

  @override
  State<RecordMemoryScreen> createState() => _RecordMemoryScreenState();
}

class _RecordMemoryScreenState extends State<RecordMemoryScreen> {
  static const String _tag = 'RecordMemoryScreen';

  // Recording state
  final _audioRecorder = Record();
  final _audioPlayer = AudioPlayer();
  String? _recordingPath;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isPlaying = false;

  // For counting down recording time
  Timer? _timer;
  int _recordingSeconds = 0;
  final int _maxRecordingSeconds = 30;

  // UI state
  bool _isLoading = false;
  bool _showRecordingControls = false;
  bool _recordingComplete = false;

  // For memory saving
  final _titleController = TextEditingController();
  String? _autoTitle;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    AdvancedLogger.info(_tag, 'Record Memory Screen initialized');
  }

  @override
  void dispose() {
    _stopRecording();
    _stopPlayback();
    _timer?.cancel();
    _titleController.dispose();
    _audioRecorder.dispose();
    AdvancedLogger.info(_tag, 'Record Memory Screen disposed');
    super.dispose();
  }

  // Check and request microphone permissions
  Future<void> _checkPermissions() async {
    try {
      final micStatus = await Permission.microphone.status;
      final storageStatus = await Permission.storage.status;

      AdvancedLogger.info(_tag, 'Checking permissions', data: {
        'microphone': micStatus.toString(),
        'storage': storageStatus.toString()
      });

      if (micStatus.isDenied) {
        AdvancedLogger.info(_tag, 'Requesting microphone permission');
        final result = await Permission.microphone.request();

        if (result.isDenied) {
          AdvancedLogger.warning(_tag, 'Microphone permission denied by user');
          _showPermissionError('microphone');
        }
      }

      if (storageStatus.isDenied) {
        AdvancedLogger.info(_tag, 'Requesting storage permission');
        final result = await Permission.storage.request();

        // Also request MANAGE_EXTERNAL_STORAGE for Android 11+
        if (Platform.isAndroid) {
          AdvancedLogger.info(_tag, 'Requesting MANAGE_EXTERNAL_STORAGE permission');
          await Permission.manageExternalStorage.request();
          final manageStatus = await Permission.manageExternalStorage.status;
          AdvancedLogger.info(_tag, 'MANAGE_EXTERNAL_STORAGE status',
              data: {'status': manageStatus.toString()});
        }

        if (result.isDenied) {
          AdvancedLogger.warning(_tag, 'Storage permission denied by user');
          _showPermissionError('storage');
        }
      }
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error checking permissions', error: e, stackTrace: stackTrace);
      _showPermissionError('unknown');
    }
  }

  // Start recording audio
  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        // Check storage permission explicitly
        if (await Permission.storage.isGranted ||
            await Permission.manageExternalStorage.isGranted) {

          AdvancedLogger.info(_tag, 'Storage permission: granted');

          // Create a unique filename
          final appDir = await getApplicationDocumentsDirectory();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final currentUser = Provider.of<AuthService>(context, listen: false).currentUser;
          final userId = currentUser?.uid ?? 'unknown_user';

          _recordingPath = '${appDir.path}/memory_${userId}_$timestamp.m4a';

          AdvancedLogger.info(_tag, 'Starting recording', data: {'path': _recordingPath});

          // Configure recording
          await _audioRecorder.start(
            path: _recordingPath,
            encoder: AudioEncoder.aacLc, // This creates m4a files which are supported by the api
            bitRate: 128000,
            samplingRate: 44100,
          );

          // Start timer
          _recordingSeconds = 0;
          _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
            setState(() {
              _recordingSeconds++;

              if (_recordingSeconds >= _maxRecordingSeconds) {
                _stopRecording();
              }
            });
          });

          setState(() {
            _isRecording = true;
            _showRecordingControls = true;
          });
        } else {
          AdvancedLogger.warning(_tag, 'No storage permission');
          _showPermissionError('storage');
        }
      } else {
        AdvancedLogger.warning(_tag, 'No microphone permission');
        _showPermissionError('microphone');
      }
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error starting recording', error: e, stackTrace: stackTrace);
      _showErrorSnackbar('Could not start recording: $e');
    }
  }

  // Pause the current recording
  Future<void> _pauseRecording() async {
    try {
      if (_isRecording && !_isPaused) {
        AdvancedLogger.info(_tag, 'Pausing recording');
        await _audioRecorder.pause();
        _timer?.cancel();

        setState(() {
          _isPaused = true;
        });
      }
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error pausing recording', error: e, stackTrace: stackTrace);
      _showErrorSnackbar('Could not pause recording: $e');
    }
  }

  // Resume a paused recording
  Future<void> _resumeRecording() async {
    try {
      if (_isPaused) {
        AdvancedLogger.info(_tag, 'Resuming recording');
        await _audioRecorder.resume();

        // Restart timer
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _recordingSeconds++;

            if (_recordingSeconds >= _maxRecordingSeconds) {
              _stopRecording();
            }
          });
        });

        setState(() {
          _isPaused = false;
        });
      }
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error resuming recording', error: e, stackTrace: stackTrace);
      _showErrorSnackbar('Could not resume recording: $e');
    }
  }

  // Stop and save the recording
  Future<void> _stopRecording() async {
    try {
      if (_isRecording) {
        AdvancedLogger.info(_tag, 'Stopping recording');
        _timer?.cancel();
        await _audioRecorder.stop();

        // Generate automatic title based on date/time
        final now = DateTime.now();
        final formatter = DateFormat('MMM d, h:mm a');
        _autoTitle = 'Memory ${formatter.format(now)}';

        setState(() {
          _isRecording = false;
          _isPaused = false;
          _recordingComplete = true;
        });
      }
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error stopping recording', error: e, stackTrace: stackTrace);
      _showErrorSnackbar('Could not stop recording: $e');
    }
  }

  // Play back the recorded audio
  Future<void> _playRecording() async {
    try {
      if (_recordingPath != null && !_isPlaying) {
        AdvancedLogger.info(_tag, 'Playing recording', data: {'path': _recordingPath});

        setState(() {
          _isPlaying = true;
        });

        await _audioPlayer.play(DeviceFileSource(_recordingPath!));

        // Listen for playback completion
        _audioPlayer.onPlayerComplete.listen((event) {
          setState(() {
            _isPlaying = false;
          });
        });
      }
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error playing recording', error: e, stackTrace: stackTrace);
      _showErrorSnackbar('Could not play recording: $e');
      setState(() {
        _isPlaying = false;
      });
    }
  }

  // Stop playback
  Future<void> _stopPlayback() async {
    try {
      if (_isPlaying) {
        AdvancedLogger.info(_tag, 'Stopping playback');
        await _audioPlayer.stop();

        setState(() {
          _isPlaying = false;
        });
      }
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error stopping playback', error: e, stackTrace: stackTrace);
    }
  }

  // Save the memory to storage
  Future<Memory?> _saveMemory() async {
    try {
      setState(() {
        _isLoading = true;
      });

      if (_recordingPath == null) {
        AdvancedLogger.warning(_tag, 'No recording to save');
        _showErrorSnackbar('No recording to save');
        return null;
      }

      AdvancedLogger.info(_tag, 'Saving memory recording');

      // Determine title (use user provided or auto-generated)
      String title = _titleController.text.trim();
      if (title.isEmpty) {
        title = _autoTitle ?? 'Memory ${DateTime.now().millisecondsSinceEpoch}';
      }

      // Get the user ID
      final userId = Provider.of<AuthService>(context, listen: false).currentUser?.uid;
      if (userId == null) {
        AdvancedLogger.warning(_tag, 'No user ID found, cannot save memory');
        _showErrorSnackbar('You need to be logged in to save memories');
        return null;
      }

      // Create memory object
      final memory = Memory(
        id: const Uuid().v4(),
        userId: userId,
        title: title,
        audioPath: _recordingPath!,  // Use local path for now
        createdAt: DateTime.now(),
        transcription: "",  // Will be populated by the service
      );

      // Since MemoryService doesn't have a direct saveMemory method,
      // we'll save the memory directly to the file system
      final savedMemoryPath = await _saveMemoryToLocalStorage(memory);

      // Update the memory object with the saved path
      final savedMemory = Memory(
        id: memory.id,
        userId: memory.userId,
        title: memory.title,
        audioPath: savedMemoryPath,
        createdAt: memory.createdAt,
        transcription: memory.transcription,
      );

      AdvancedLogger.info(_tag, 'Memory saved successfully',
          data: {
            'memoryId': savedMemory.id,
            'title': savedMemory.title,
            'audioPath': savedMemory.audioPath
          });

      setState(() {
        _isLoading = false;
      });

      // Show success message with file location info
      _showFileLocationInfo(savedMemory);

      return savedMemory;
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error saving memory', error: e, stackTrace: stackTrace);
      _showErrorSnackbar('Failed to save memory: $e');

      setState(() {
        _isLoading = false;
      });

      return null;
    }
  }

  // Helper method to save memory to local storage
  Future<String> _saveMemoryToLocalStorage(Memory memory) async {
    try {
      // Create app documents directory for memories
      final appDocDir = await getApplicationDocumentsDirectory();
      final memoriesDir = Directory('${appDocDir.path}/memories');
      if (!await memoriesDir.exists()) {
        await memoriesDir.create(recursive: true);
      }

      // Copy the recording to the memories directory
      final File sourceFile = File(memory.audioPath);
      final String safeTitle = memory.title.replaceAll(RegExp(r'[^\w\s.-]'), '_');
      final String fileName = '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final String destinationPath = '${memoriesDir.path}/$fileName';
      final File destinationFile = await sourceFile.copy(destinationPath);

      AdvancedLogger.info(_tag, 'Memory audio saved to local storage',
          data: {'path': destinationPath});

      return destinationPath;
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error saving memory to local storage',
          error: e, stackTrace: stackTrace);
      throw e;
    }
  }

  // Show a dialog with file location information
  void _showFileLocationInfo(Memory memory) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Memory Saved'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your memory "${memory.title}" has been saved.'),
            const SizedBox(height: 16),
            const Text('Location:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('App Documents > Memories > ${memory.title}'),
            const SizedBox(height: 16),
            const Text('You can access your memories from the Memories tab.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    ).then((_) {
      // After showing the file info, ask if user wants to create AI story
      if (mounted) {
        _showCreateStoryOptions(memory);
      }
    });
  }

  // Show options to create AI story or not
  void _showCreateStoryOptions(Memory memory) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create AI Story?'),
        content: const Text(
            'Would you like to create an AI story from your recorded memory?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToAiStoryProcessing(memory);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.gentleTeal,
              foregroundColor: Colors.white,
            ),
            child: const Text('Create Story'),
          ),
        ],
      ),
    );
  }

  // Navigate directly to AI Story Processing Screen
  void _navigateToAiStoryProcessing(Memory memory) {
    try {
      if (!mounted) {
        AdvancedLogger.warning(_tag, 'Widget not mounted when attempting to navigate');
        return;
      }

      AdvancedLogger.info(_tag, 'Navigating to AI story processing screen',
          data: {'memoryId': memory.id, 'title': memory.title, 'audioPath': memory.audioPath});

      // Direct navigation to processing screen avoids widget lifecycle issues
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AiStoryProcessingScreen(
            memoryId: memory.id,
            memoryTitle: memory.title,
            audioUrl: memory.audioPath,
            memory: memory,
          ),
        ),
      );
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error navigating to AI story processing',
          error: e, stackTrace: stackTrace);

      if (!mounted) return;

      _showErrorSnackbar('Unable to create AI story: $e');
    }
  }

  // Reset the recording state to start over
  void _resetRecording() {
    setState(() {
      _recordingPath = null;
      _isRecording = false;
      _isPaused = false;
      _isPlaying = false;
      _recordingSeconds = 0;
      _recordingComplete = false;
      _showRecordingControls = false;
      _titleController.clear();
      _autoTitle = null;
    });
  }

  // Show a dialog for title and saving
  Future<void> _showSaveDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Memory?'),
        content: TextField(
          controller: _titleController,
          decoration: InputDecoration(
            labelText: 'Enter memory title',
            hintText: 'Leave blank for auto-naming',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (result == true) {
      final savedMemory = await _saveMemory();
      if (savedMemory != null) {
        _resetRecording();
      }
    }
  }

  // Show error for missing permissions
  void _showPermissionError(String permissionType) {
    String message;
    if (permissionType == 'microphone') {
      message = 'Milo needs access to your microphone to record memories. Please grant microphone permission in your device settings.';
    } else if (permissionType == 'storage') {
      message = 'Milo needs access to your device storage to save memories. Please grant storage permission in your device settings.';
    } else {
      message = 'Milo needs certain permissions to function properly. Please check your device settings.';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${permissionType.substring(0, 1).toUpperCase()}${permissionType.substring(1)} Permission Required'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // Show error snackbar
  void _showErrorSnackbar(String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Memory'),
        backgroundColor: AppTheme.gentleTeal,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // Main content
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Recording indicator
                Container(
                  height: 200,
                  width: 200,
                  decoration: BoxDecoration(
                    color: _isRecording
                        ? Colors.red.withOpacity(0.2)
                        : AppTheme.gentleTeal.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isRecording ? Icons.mic : Icons.mic_none,
                    size: 80,
                    color: _isRecording ? Colors.red : AppTheme.gentleTeal,
                  ),
                ),
                const SizedBox(height: 24),

                // Recording status text
                Text(
                  _isRecording
                      ? 'Recording... ${_maxRecordingSeconds - _recordingSeconds}s left'
                      : _recordingComplete
                      ? 'Recording complete'
                      : 'Tap to Record',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeLarge,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Instructions
                Text(
                  'Share your memory (max ${_maxRecordingSeconds} seconds)',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
                const SizedBox(height: 24),

                // Recording controls
                if (!_showRecordingControls)
                // Initial record button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _startRecording,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.gentleTeal,
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(24),
                    ),
                    child: const Icon(Icons.mic, size: 32),
                  )
                else
                // Recording controls row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Reset button
                      IconButton(
                        onPressed: _isLoading ? null : _resetRecording,
                        icon: const Icon(Icons.refresh),
                        color: Colors.grey,
                        tooltip: 'Reset',
                      ),
                      const SizedBox(width: 16),

                      // Record/pause button
                      if (_isRecording)
                      // Recording in progress - show pause/resume
                        IconButton(
                          onPressed: _isLoading
                              ? null
                              : (_isPaused ? _resumeRecording : _pauseRecording),
                          icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                          color: Colors.red,
                          iconSize: 32,
                          tooltip: _isPaused ? 'Resume' : 'Pause',
                        )
                      else
                      // Recording complete - show play/stop
                        IconButton(
                          onPressed: _isLoading
                              ? null
                              : (_isPlaying ? _stopPlayback : _playRecording),
                          icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                          color: AppTheme.gentleTeal,
                          iconSize: 32,
                          tooltip: _isPlaying ? 'Stop' : 'Play',
                        ),
                      const SizedBox(width: 16),

                      // Stop/save button
                      IconButton(
                        onPressed: _isLoading
                            ? null
                            : (_isRecording ? _stopRecording : _showSaveDialog),
                        icon: Icon(_isRecording ? Icons.stop : Icons.save),
                        color:
                        _isRecording ? Colors.red : AppTheme.gentleTeal,
                        iconSize: 32,
                        tooltip: _isRecording ? 'Stop' : 'Save',
                      ),
                    ],
                  ),
                const SizedBox(height: 32),

                // AI Stories info box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.gentleTeal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.auto_stories,
                            color: AppTheme.gentleTeal,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'AI Memory Stories',
                            style: TextStyle(
                              fontSize: AppTheme.fontSizeMedium,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'After recording, you can generate personalized stories from your memories using our AI assistant.',
                        style: TextStyle(
                          fontSize: AppTheme.fontSizeSmall,
                          color: AppTheme.textSecondaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your privacy is important: audio is processed securely and is not used to train AI models.',
                        style: TextStyle(
                          fontSize: AppTheme.fontSizeSmall,
                          color: AppTheme.textSecondaryColor,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(
                  color: AppTheme.gentleTeal,
                ),
              ),
            ),
        ],
      ),
    );
  }
}