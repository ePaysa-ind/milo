import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:milo/services/storage_service.dart';
import 'package:milo/theme/app_theme.dart';
import 'package:milo/utils/advanced_logger.dart'; // Changed to advanced_logger
import 'package:firebase_auth/firebase_auth.dart';
import 'package:milo/widgets/milo_bottom_navigation.dart';
import 'package:milo/widgets/privacy_disclaimer_dialog.dart';
import 'package:milo/screens/ai_story_processing_screen.dart';
import 'package:record/record.dart'; // Replaced flutter_sound with record package

class RecordMemoryScreen extends StatefulWidget {
  const RecordMemoryScreen({super.key});

  @override
  State<RecordMemoryScreen> createState() => _RecordMemoryScreenState();
}

class _RecordMemoryScreenState extends State<RecordMemoryScreen> {
  static const String _tag = 'RecordMemoryScreen';

  // Replace FlutterSoundRecorder with Record
  final Record _recorder = Record();
  final StorageService _storageService = StorageService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isRecording = false;
  bool _isRecorderInitialized = false;
  String? _filePath;
  Timer? _timer;
  int _recordDuration = 0;
  int _memoryCount = 1; // For naming memories
  bool _isUploading = false;

  // For bottom navigation
  int _currentIndex = 1; // Set to 1 for Record tab

  // Supported audio formats by OpenAI
  static const List<String> _supportedFormats = [
    'flac', 'm4a', 'mp3', 'mp4', 'mpeg', 'mpga', 'oga', 'ogg', 'wav', 'webm'
  ];

  @override
  void initState() {
    super.initState();
    _initRecorder();

    // Check authentication status
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      AdvancedLogger.warning(_tag, 'User not authenticated!');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Please log in to record memories'),
              backgroundColor: AppTheme.warningColor,
            ),
          );
        }
      });
    } else {
      AdvancedLogger.info(_tag, 'User authenticated', data: {'uid': currentUser.uid});
    }
  }

  Future<void> _initRecorder() async {
    try {
      // Check if recorder is already initialized
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }

      // Request permissions
      final micPermission = await Permission.microphone.request();
      final storagePermission = await Permission.storage.request();

      AdvancedLogger.info(_tag, 'Permissions requested', data: {
        'microphone': micPermission.toString(),
        'storage': storagePermission.toString()
      });

      if (micPermission != PermissionStatus.granted) {
        AdvancedLogger.warning(_tag, 'Microphone permission not granted',
            data: {'status': micPermission.toString()});
        throw Exception('Microphone permission not granted');
      }

      if (storagePermission != PermissionStatus.granted) {
        AdvancedLogger.warning(_tag, 'Storage permission not granted',
            data: {'status': storagePermission.toString()});
        throw Exception('Storage permission not granted');
      }

      // Check if recorder is available
      bool isAvailable = await _recorder.hasPermission();
      if (!isAvailable) {
        throw Exception('Recorder is not available');
      }

      _isRecorderInitialized = true;
      AdvancedLogger.info(_tag, 'Recorder initialized successfully');
    } catch (e, stackTrace) {
      _isRecorderInitialized = false;
      AdvancedLogger.error(_tag, 'Error initializing recorder',
          error: e, stackTrace: stackTrace);

      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initializing recorder: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    AdvancedLogger.info(_tag, 'Recorder disposed');
    super.dispose();
  }

  Future<String> _getFilePath(String title) async {
    final dir = await getTemporaryDirectory();
    String timestamp = DateFormat('MMMM_d_yyyy').format(DateTime.now());
    // Use mp3 format which is well-supported by OpenAI
    return '${dir.path}/${title}_$timestamp.mp3';
  }

  void _startRecording() async {
    // Check if user is authenticated
    if (_auth.currentUser == null) {
      AdvancedLogger.warning(_tag, 'Cannot start recording - user not authenticated');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please log in to record memories'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = dir.listSync().where((f) =>
          _supportedFormats.any((format) => f.path.endsWith('.$format'))).toList();
      _memoryCount = files.length + 1;

      String defaultTitle = "Memory $_memoryCount";
      _filePath = await _getFilePath(defaultTitle);

      AdvancedLogger.info(_tag, 'Starting recording', data: {'path': _filePath});

      // Check if recorder is initialized
      if (!_isRecorderInitialized) {
        AdvancedLogger.warning(_tag, 'Recorder not initialized');
        await _initRecorder();

        // If still not initialized, show error and return
        if (!_isRecorderInitialized) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Could not initialize audio recorder'),
                backgroundColor: AppTheme.errorColor,
              ),
            );
          }
          return;
        }
      }

      // Configure recorder with settings compatible with OpenAI
      await _recorder.start(
        path: _filePath,
        encoder: AudioEncoder.aacLc,  // AAC is compatible with OpenAI as .m4a
        bitRate: 128000,
        samplingRate: 44100,
      );

      if (mounted) {
        setState(() {
          _isRecording = true;
          _recordDuration = 0;
        });
      }

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
        if (mounted) {
          setState(() {
            _recordDuration++;
          });
        }

        if (_recordDuration >= 30) {
          AdvancedLogger.info(_tag, 'Reached maximum recording duration (30s)');
          _stopRecording();
        }
      });

      AdvancedLogger.info(_tag, 'Recording started successfully');
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error starting recording',
          error: e, stackTrace: stackTrace);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting recording: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  void _stopRecording() async {
    if (!_isRecording) {
      AdvancedLogger.warning(_tag, 'Attempted to stop recording when not recording');
      return;
    }

    try {
      AdvancedLogger.info(_tag, 'Stopping recording');
      String? filePath = await _recorder.stop();
      _timer?.cancel();

      if (mounted) {
        setState(() {
          _isRecording = false;
          // Update file path with the one returned by recorder.stop()
          if (filePath != null) {
            _filePath = filePath;
          }
        });
      }

      if (mounted) {
        _showSavePrompt();
      }
      AdvancedLogger.info(_tag, 'Recording stopped successfully', data: {'path': _filePath});
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error stopping recording',
          error: e, stackTrace: stackTrace);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error stopping recording: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  void _showSavePrompt() {
    // Initialize with an empty controller instead of a default value
    TextEditingController controller = TextEditingController();

    // Store a copy of the file path before showing dialog
    final String currentFilePath = _filePath ?? '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save Memory?'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Enter memory title',
            hintText: 'Leave blank for auto-naming',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                AdvancedLogger.info(_tag, 'User chose not to save the recording');
                final fileToDelete = File(currentFilePath);
                if (await fileToDelete.exists()) {
                  await fileToDelete.delete();
                  AdvancedLogger.info(_tag, 'Deleted temporary file', data: {'path': currentFilePath});
                }
              } catch (e, stackTrace) {
                AdvancedLogger.error(_tag, 'Error deleting file',
                    error: e, stackTrace: stackTrace);
              }

              // Use dialogContext to close dialog safely
              Navigator.pop(dialogContext);
            },
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              // Get values before closing dialog
              final String enteredTitle = controller.text.trim();

              // Use dialogContext to close dialog safely
              Navigator.pop(dialogContext);

              // Proceed with upload process after dialog is closed
              _processUpload(currentFilePath, enteredTitle);
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  // Separate method to handle upload process after dialog is closed
  void _processUpload(String filePath, String enteredTitle) async {
    if (!mounted) return;

    setState(() {
      _isUploading = true;
    });

    AdvancedLogger.info(_tag, 'Processing upload', data: {
      'title': enteredTitle.isEmpty ? "<auto>" : enteredTitle,
      'path': filePath
    });

    try {
      File audioFile = File(filePath);
      bool exists = await audioFile.exists();
      AdvancedLogger.info(_tag, 'File exists check', data: {'exists': exists});

      if (!exists) {
        throw Exception("Recording file not found");
      }

      // Verify the file extension is supported by OpenAI
      String fileExtension = filePath.split('.').last.toLowerCase();
      if (!_supportedFormats.contains(fileExtension)) {
        AdvancedLogger.warning(_tag, 'File format may not be supported by OpenAI',
            data: {'format': fileExtension, 'supportedFormats': _supportedFormats.join(', ')});
        // Continue anyway as Firebase will store it
      }

      AdvancedLogger.info(_tag, 'Uploading audio to Firebase');

      final downloadUrl = await _storageService.uploadAudio(
        audioFile,
        enteredTitle,
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          AdvancedLogger.warning(_tag, 'Upload timeout after 60 seconds');
          throw TimeoutException('Upload timed out after 60 seconds');
        },
      );

      AdvancedLogger.info(_tag, 'Upload completed successfully',
          data: {'downloadUrl': _getSafeUrlForLogging(downloadUrl)});

      // Get the memory ID that was just created
      final memories = await _storageService.getMemories();
      String? memoryId;
      String? memoryTitle;

      if (memories.isNotEmpty) {
        // Find the memory with matching download URL
        for (var memory in memories) {
          if (memory['audioUrl'] == downloadUrl) {
            memoryId = memory['id'];
            memoryTitle = memory['title'] as String? ?? 'Memory';
            break;
          }
        }
      }

      if (mounted) {
        setState(() {
          _isUploading = false;
        });

        // If we found the memory ID, offer to create AI story
        if (memoryId != null) {
          _showAiStoryPrompt(memoryId, memoryTitle ?? 'Memory', downloadUrl);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Memory saved successfully!'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error uploading memory',
          error: e, stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          _isUploading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving memory: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  // Helper method for safely logging URLs (to avoid PII in logs)
  String _getSafeUrlForLogging(String url) {
    if (url.length <= 20) return url;
    return '${url.substring(0, min(url.length, 20))}...';
  }

  // Helper method for min to avoid importing dart:math
  int min(int a, int b) {
    return a < b ? a : b;
  }

  void _showAiStoryPrompt(String memoryId, String memoryTitle, String audioUrl) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create AI Story?'),
        content: Text('Would you like to create an AI story from your memory "$memoryTitle"?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);

              // Show success message for memory saved
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Memory saved successfully!'),
                  backgroundColor: AppTheme.successColor,
                ),
              );
            },
            child: const Text('Not Now'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              // Show privacy disclaimer
              final consentGiven = await PrivacyDisclaimerDialog.show(context);

              if (consentGiven && mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AiStoryProcessingScreen(
                      memoryId: memoryId,
                      memoryTitle: memoryTitle,
                      audioUrl: audioUrl,
                    ),
                  ),
                );
              } else {
                // Show success message for memory saved
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Memory saved successfully!'),
                    backgroundColor: AppTheme.successColor,
                  ),
                );
              }
            },
            child: const Text('Create Story'),
          ),
        ],
      ),
    );
  }

  // Handle navigation between tabs
  void _onTabTapped(int index) {
    if (index == _currentIndex) return;

    AdvancedLogger.info(_tag, 'Tab changed', data: {'index': index});

    // Do not allow navigation while recording
    if (_isRecording) {
      AdvancedLogger.warning(_tag, 'Cannot navigate away while recording');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please stop recording before navigating away'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    setState(() {
      _currentIndex = index;
    });

    // Navigate based on the tab index
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/home');
        break;
      case 1:
      // Already on record screen
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/memories');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/conversation');
        break;
      case 4:
      // Sign out functionality
      // This could be implemented here or handled elsewhere
        break;
    }
  }

  String _getRecordDurationText() {
    final minutes = (_recordDuration ~/ 60).toString().padLeft(2, '0');
    final seconds = (_recordDuration % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Record Memory'),
        backgroundColor: AppTheme.gentleTeal,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Recording waveform or icon
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: _isRecording
                      ? AppTheme.gentleTeal.withOpacity(0.2)
                      : AppTheme.gentleTeal.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    _isRecording ? Icons.mic : Icons.mic_none,
                    size: 100,
                    color: _isRecording
                        ? AppTheme.gentleTeal
                        : AppTheme.gentleTeal.withOpacity(0.7),
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // Recording duration
              Text(
                _isRecording ? _getRecordDurationText() : 'Tap to Record',
                style: TextStyle(
                  fontSize: AppTheme.fontSizeLarge,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textColor,
                ),
              ),
              const SizedBox(height: 10),

              // Recording status message
              Text(
                _isRecording
                    ? 'Recording in progress...'
                    : 'Share your memory (max 30 seconds)',
                style: TextStyle(
                  fontSize: AppTheme.fontSizeMedium,
                  color: AppTheme.textSecondaryColor,
                ),
              ),
              const SizedBox(height: 40),

              // Record/Stop button
              if (_isUploading)
                Column(
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.gentleTeal),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Saving your memory...',
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeMedium,
                        color: AppTheme.textSecondaryColor,
                      ),
                    ),
                  ],
                )
              else
                GestureDetector(
                  onTap: _isRecording ? _stopRecording : _startRecording,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: _isRecording ? AppTheme.mutedRed : AppTheme.gentleTeal,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              // Instructions text
              Text(
                _isRecording
                    ? 'Tap to stop recording'
                    : 'Tap the button to start recording',
                style: TextStyle(
                  fontSize: AppTheme.fontSizeSmall,
                  color: AppTheme.textSecondaryColor,
                ),
              ),

              const Spacer(),

              // Feature description
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
                        Icon(Icons.auto_stories, color: AppTheme.gentleTeal),
                        const SizedBox(width: 12),
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: MiloBottomNavigation(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
      ),
    );
  }
}