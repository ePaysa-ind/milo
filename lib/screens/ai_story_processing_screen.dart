// lib/screens/ai_story_processing_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:milo/models/ai_story.dart';
import 'package:milo/models/memory.dart';
import 'package:milo/services/openai_service.dart';
import 'package:milo/services/storage_service.dart';
import 'package:milo/services/memory_service.dart';
import 'package:milo/services/env_service.dart';
import 'package:milo/services/auth_service.dart';
import 'package:milo/theme/app_theme.dart';
import 'package:milo/utils/advanced_logger.dart';
import 'package:milo/widgets/milo_bottom_navigation.dart';
import 'package:milo/screens/ai_story_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;

/// Enum to track specific processing stages with more granularity
enum ProcessingStage {
  init,
  downloadingAudio,
  validatingAudio,
  transcribing,
  analyzingSentiment,
  generatingStory,
  savingStory,
  complete,
  error
}

/// Custom error types for better error handling
class ProcessingError {
  final String message;
  final String details;
  final ProcessingStage stage;
  final bool isRecoverable;

  ProcessingError({
    required this.message,
    required this.details,
    required this.stage,
    this.isRecoverable = true
  });

  @override
  String toString() {
    return '$message: $details';
  }
}

/// The AI Story Processing Screen
/// This screen handles the complete workflow of converting an audio memory
/// into an AI-generated story, including:
/// - Audio processing and validation for OpenAI API compatibility
/// - Transcription using OpenAI's Whisper API
/// - Sentiment analysis
/// - Story generation
/// - Saving the story to user's collection
class AiStoryProcessingScreen extends StatefulWidget {
  final String memoryId;
  final String memoryTitle;
  final String audioUrl;
  final Memory? memory;  // Optional memory object if available

  const AiStoryProcessingScreen({
    Key? key,
    required this.memoryId,
    required this.memoryTitle,
    required this.audioUrl,
    this.memory,
  }) : super(key: key);

  @override
  State<AiStoryProcessingScreen> createState() => _AiStoryProcessingScreenState();
}

class _AiStoryProcessingScreenState extends State<AiStoryProcessingScreen> with WidgetsBindingObserver {
  static const String _tag = 'AiStoryProcessing';

  // Services (using Provider for dependency injection)
  OpenAIService get _openAIService => Provider.of<OpenAIService>(context, listen: false);
  StorageService get _storageService => Provider.of<StorageService>(context, listen: false);
  MemoryService get _memoryService => Provider.of<MemoryService>(context, listen: false);
  AuthService get _authService => Provider.of<AuthService>(context, listen: false);

  // State management
  ProcessingStage _stage = ProcessingStage.init;
  bool _isDisposed = false;
  bool _hasInternetConnection = true;
  double _progressPercentage = 0.0;
  ProcessingError? _error;
  Timer? _sessionTimeoutTimer;
  bool _allowedToLeave = false;

  // Processing results
  String _transcription = '';
  String _sentiment = '';
  String _generatedStory = '';
  AiStory? _savedStory;

  // Bottom navigation state
  int _currentIndex = 1; // Set to 1 for Record tab by default

  // Fixed: Connectivity instance and subscription
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  // Audio transcription state
  bool _isTranscribing = false;
  Timer? _countdownTimer;
  int _remainingSeconds = 30; // Limit to 30 seconds for OpenAI Whisper

  // List of supported formats by OpenAI Whisper API
  static const List<String> supportedFormats = [
    'flac', 'm4a', 'mp3', 'mp4', 'mpeg', 'mpga', 'oga', 'ogg', 'wav', 'webm'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Check storage permissions first
    _checkStoragePermissions();

    // Set up connectivity monitoring
    _initConnectivity();

    // Set up session timeout
    _resetSessionTimeout();

    AdvancedLogger.info(_tag, 'AI Story Processing Screen initialized', data: {
      'memoryId': widget.memoryId,
      'memoryTitle': widget.memoryTitle,
      'hasMemoryObject': widget.memory != null,
      'audioUrl': _getSafeUrlForLogging(widget.audioUrl),
    });

    // Start processing after initialization
    _startProcessing();
  }

  /// Check for storage permissions needed to save audio and stories
  Future<void> _checkStoragePermissions() async {
    try {
      final storageStatus = await Permission.storage.status;
      final manageExternalStorageStatus = await Permission.manageExternalStorage.status;

      AdvancedLogger.info(_tag, 'Checking storage permissions', data: {
        'storage': storageStatus.toString(),
        'manageExternalStorage': manageExternalStorageStatus.toString()
      });

      if (!storageStatus.isGranted && !manageExternalStorageStatus.isGranted) {
        AdvancedLogger.warning(_tag, 'Storage permissions not granted');

        // Request storage permissions
        final result = await Permission.storage.request();
        if (Platform.isAndroid) {
          await Permission.manageExternalStorage.request();
        }

        AdvancedLogger.info(_tag, 'Storage permission requested', data: {
          'result': result.toString(),
          'manageExternalStorage': (await Permission.manageExternalStorage.status).toString()
        });
      }
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error checking storage permissions',
          error: e, stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _sessionTimeoutTimer?.cancel();
    _countdownTimer?.cancel();
    AdvancedLogger.info(_tag, 'AI Story Processing Screen disposed');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    AdvancedLogger.info(_tag, 'App lifecycle state changed', data: {'state': state.toString()});

    if (state == AppLifecycleState.resumed) {
      // Check connectivity when app is resumed
      _checkConnectivity();
      _resetSessionTimeout();
    } else if (state == AppLifecycleState.paused) {
      // App is paused, update state if needed
    }
  }

  /// Safe setState that checks if component is still mounted
  void _safeSetState(VoidCallback fn) {
    if (!mounted || _isDisposed) return;
    setState(fn);
  }

  /// Initialize connectivity monitoring
  void _initConnectivity() {
    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);

    // Check initial connectivity
    _checkConnectivity();
  }

  /// Check initial connectivity
  Future<void> _checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _updateConnectionStatus(result);
      AdvancedLogger.info(_tag, 'Initial connectivity check',
          data: {'result': result.toString()});
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error checking connectivity',
          error: e, stackTrace: stackTrace);
    }
  }

  /// Handle connectivity changes
  void _updateConnectionStatus(ConnectivityResult result) {
    final hasConnection = result != ConnectivityResult.none;

    AdvancedLogger.info(_tag, 'Connectivity status updated',
        data: {'connected': hasConnection, 'type': result.toString()});

    if (hasConnection != _hasInternetConnection) {
      _safeSetState(() {
        _hasInternetConnection = hasConnection;
      });

      if (!hasConnection) {
        _showConnectionError();
      } else if (_stage == ProcessingStage.error &&
          _error?.message.contains('connection') == true) {
        // Auto-retry if we regained connection after a connection error
        _startProcessing();
      }
    }
  }

  /// Reset session timeout
  /// Prevents processing from running indefinitely if something gets stuck
  void _resetSessionTimeout() {
    _sessionTimeoutTimer?.cancel();
    _sessionTimeoutTimer = Timer(const Duration(minutes: 10), () {
      if (_stage != ProcessingStage.complete && _stage != ProcessingStage.error) {
        AdvancedLogger.warning(_tag, 'Session timeout occurred',
            data: {'currentStage': _stage.toString()});

        _handleError(ProcessingError(
          message: 'Session timeout',
          details: 'The processing session timed out after 10 minutes of inactivity.',
          stage: _stage,
        ));
      }
    });
  }

  /// Start the countdown timer for transcription process (limited to 30 seconds)
  void _startCountdown(StateSetter setStateCallback) {
    _remainingSeconds = 30;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setStateCallback(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  /// Download and prepare audio file for processing
  /// This method ensures the file has a supported extension for OpenAI
  Future<File> _downloadAudioFile(String url) async {
    try {
      AdvancedLogger.info(_tag, 'Downloading audio',
          data: {'url': _getSafeUrlForLogging(url)});

      // Download the file
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Audio download timed out after 30 seconds');
        },
      );

      if (response.statusCode != 200) {
        throw ProcessingError(
          message: 'Download failed',
          details: 'Failed to download audio: HTTP ${response.statusCode}',
          stage: ProcessingStage.downloadingAudio,
        );
      }

      // Get file extension from URL
      String fileExtension = '';
      final Uri audioUri = Uri.parse(url);
      final String path = audioUri.path;

      if (path.contains('.')) {
        fileExtension = path.split('.').last.split('?').first.toLowerCase();
      }

      // Check if the extension is supported by OpenAI
      if (fileExtension.isEmpty || !supportedFormats.contains(fileExtension)) {
        AdvancedLogger.warning(_tag, 'Unsupported or missing file format',
            data: {
              'originalFormat': fileExtension,
              'supportedFormats': supportedFormats.join(', ')
            });

        // Try to detect format from file headers
        final format = _detectAudioFormat(response.bodyBytes);

        if (format != null && supportedFormats.contains(format)) {
          fileExtension = format;
          AdvancedLogger.info(_tag, 'Audio format detected from content',
              data: {'detectedFormat': format});
        } else {
          // Default to mp3 if format not detected or supported
          fileExtension = 'mp3';
          AdvancedLogger.warning(_tag, 'Could not detect format, using default',
              data: {'defaultFormat': fileExtension});
        }
      }

      // Create a temp file with appropriate extension
      final tempDir = await getTemporaryDirectory();
      final tempFilePath = '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final file = File(tempFilePath);

      // Write downloaded audio to file
      await file.writeAsBytes(response.bodyBytes);

      AdvancedLogger.info(_tag, 'Audio downloaded successfully',
          data: {'filePath': tempFilePath, 'fileSize': response.bodyBytes.length, 'format': fileExtension});

      return file;
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Failed to download audio',
          error: e, stackTrace: stackTrace);

      if (e is ProcessingError) {
        rethrow;
      }

      throw ProcessingError(
        message: 'Audio download failed',
        details: e.toString(),
        stage: ProcessingStage.downloadingAudio,
      );
    }
  }

  /// Detect audio format from file content by examining file signatures
  String? _detectAudioFormat(Uint8List bytes) {
    if (bytes.length < 12) return null;

    // MP3 files typically start with ID3 or with 0xFF 0xFB
    if ((bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) ||
        (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0)) {
      return 'mp3';
    }

    // WAV files start with RIFF....WAVE
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45) {
      return 'wav';
    }

    // FLAC files start with "fLaC"
    if (bytes[0] == 0x66 && bytes[1] == 0x4C && bytes[2] == 0x61 && bytes[3] == 0x43) {
      return 'flac';
    }

    // M4A/AAC files often have "ftyp" at position 4
    if (bytes.length > 11 && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) {
      return 'm4a';
    }

    // OGG files start with "OggS"
    if (bytes[0] == 0x4F && bytes[1] == 0x67 && bytes[2] == 0x67 && bytes[3] == 0x53) {
      return 'ogg';
    }

    // Could not identify the format
    return null;
  }

  /// Verify the audio file is compatible with OpenAI's API
  Future<void> _validateAudioFile(File file) async {
    try {
      _safeSetState(() {
        _stage = ProcessingStage.validatingAudio;
        _progressPercentage = 15.0;
      });

      AdvancedLogger.info(_tag, 'Validating audio file',
          data: {'filePath': file.path});

      // Check if file exists
      if (!(await file.exists())) {
        throw ProcessingError(
            message: 'File not found',
            details: 'The audio file does not exist at the specified path.',
            stage: ProcessingStage.validatingAudio,
            isRecoverable: false
        );
      }

      // Check file size - OpenAI has a 25MB limit
      final fileSize = await file.length();
      if (fileSize > 25 * 1024 * 1024) {
        throw ProcessingError(
            message: 'File too large',
            details: 'The audio file exceeds the 25MB limit for OpenAI\'s API.',
            stage: ProcessingStage.validatingAudio,
            isRecoverable: false
        );
      }

      // Extract file extension and verify it's supported
      final fileExtension = file.path.split('.').last.toLowerCase();
      if (!supportedFormats.contains(fileExtension)) {
        throw ProcessingError(
            message: 'Unsupported format',
            details: 'The audio format ".$fileExtension" is not supported. Supported formats are: ${supportedFormats.join(", ")}',
            stage: ProcessingStage.validatingAudio,
            isRecoverable: false
        );
      }

      // Additional validation - check file header
      final fileBytes = await file.openRead(0, 12).fold<List<int>>(
          [], (previous, element) => previous..addAll(element));

      // Verify file signature matches its extension
      final detectedFormat = _detectAudioFormat(Uint8List.fromList(fileBytes));

      if (detectedFormat != null && detectedFormat != fileExtension) {
        AdvancedLogger.warning(_tag, 'File extension mismatch',
            data: {'extension': fileExtension, 'detectedFormat': detectedFormat});

        // We'll proceed anyway, but log the mismatch
      }

      AdvancedLogger.info(_tag, 'Audio file validated successfully',
          data: {'format': fileExtension, 'size': fileSize});

    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Audio validation failed',
          error: e, stackTrace: stackTrace);

      if (e is ProcessingError) {
        rethrow;
      }

      throw ProcessingError(
          message: 'Audio validation failed',
          details: e.toString(),
          stage: ProcessingStage.validatingAudio,
          isRecoverable: false
      );
    }
  }

  /// Helper method for safely logging URLs (to avoid PII in logs)
  String _getSafeUrlForLogging(String url) {
    if (url.length <= 20) return url;
    return '${url.substring(0, min(url.length, 20))}...';
  }

  /// Main processing workflow
  Future<void> _startProcessing() async {
    if (!_hasInternetConnection) {
      _showConnectionError();
      return;
    }

    _safeSetState(() {
      _stage = ProcessingStage.init;
      _progressPercentage = 0.0;
      _error = null;
    });

    try {
      AdvancedLogger.info(_tag, 'Starting AI story processing workflow',
          data: {'memoryId': widget.memoryId, 'audioUrl': _getSafeUrlForLogging(widget.audioUrl)});

      await _transcribeAudio();
      if (_isDisposed) return;

      await _analyzeSentiment();
      if (_isDisposed) return;

      await _generateStory();
      if (_isDisposed) return;

      await _saveStory();
      if (_isDisposed) return;

      _safeSetState(() {
        _stage = ProcessingStage.complete;
        _progressPercentage = 100.0;
        _allowedToLeave = true;
      });

      AdvancedLogger.info(_tag, 'AI story processing completed successfully',
          data: {'storyId': _savedStory?.id});

    } catch (e, stackTrace) {
      // This catch-all ensures that unexpected errors are also properly handled
      AdvancedLogger.error(_tag, 'Unexpected error during story processing',
          error: e, stackTrace: stackTrace);

      _handleError(ProcessingError(
        message: 'Unexpected error',
        details: e.toString(),
        stage: _stage,
      ));
    }
  }

  /// Transcribe the audio
  Future<void> _transcribeAudio() async {
    _safeSetState(() {
      _stage = ProcessingStage.downloadingAudio;
      _progressPercentage = 10.0;
      _isTranscribing = true;
    });

    File? audioFile;

    try {
      AdvancedLogger.info(_tag, 'Starting audio transcription process',
          data: {'audioUrl': _getSafeUrlForLogging(widget.audioUrl)});

      // Step 1: Download the audio file
      audioFile = await _downloadAudioFile(widget.audioUrl);

      // Step 2: Validate the audio file
      await _validateAudioFile(audioFile);

      _safeSetState(() {
        _stage = ProcessingStage.transcribing;
        _progressPercentage = 30.0;
      });

      // Step 3: Use existing transcription if memory object has it
      if (widget.memory?.transcription != null && widget.memory!.transcription.isNotEmpty) {
        _transcription = widget.memory!.transcription;
        AdvancedLogger.info(_tag, 'Using existing transcription from memory object',
            data: {'transcriptionLength': _transcription.length});
      } else {
        // Step 4: Transcribe the audio using our OpenAIService
        _transcription = await _openAIService.transcribeAudioFromFile(audioFile);
      }

      if (_transcription.isEmpty) {
        throw ProcessingError(
          message: 'Transcription failed',
          details: 'No text was recognized in the audio recording.',
          stage: ProcessingStage.transcribing,
        );
      }

      AdvancedLogger.info(_tag, 'Transcription completed successfully',
          data: {'length': _transcription.length});

      _resetSessionTimeout();
    } catch (e, stackTrace) {
      final isProcessingError = e is ProcessingError;

      if (e.toString().contains('Invalid file format') || e.toString().contains('Unsupported format')) {
        AdvancedLogger.error(_tag, 'Audio format error during transcription',
            error: e, stackTrace: stackTrace);

        _handleError(ProcessingError(
            message: 'Unsupported audio format',
            details: 'The audio format is not supported for transcription. Supported formats are: ${supportedFormats.join(", ")}.',
            stage: isProcessingError ? (e as ProcessingError).stage : ProcessingStage.transcribing,
            isRecoverable: false
        ));
      } else {
        AdvancedLogger.error(_tag, 'Error during audio transcription',
            error: e, stackTrace: stackTrace);

        _handleError(isProcessingError ? e as ProcessingError : ProcessingError(
          message: 'Transcription error',
          details: e.toString(),
          stage: ProcessingStage.transcribing,
        ));
      }

      rethrow;
    } finally {
      // Clean up temporary files
      _safeSetState(() => _isTranscribing = false);
      _countdownTimer?.cancel();

      try {
        if (audioFile != null && await audioFile.exists()) {
          await audioFile.delete();
          AdvancedLogger.info(_tag, 'Temporary audio file cleaned up');
        }
      } catch (e) {
        AdvancedLogger.warning(_tag, 'Temp file cleanup error', error: e);
      }
    }
  }

  /// Step 2: Analyze sentiment
  Future<void> _analyzeSentiment() async {
    _safeSetState(() {
      _stage = ProcessingStage.analyzingSentiment;
      _progressPercentage = 50.0;
    });

    try {
      AdvancedLogger.info(_tag, 'Starting sentiment analysis of transcription');

      final sanitizedTranscription = _sanitizeContent(_transcription);
      final sentimentPrompt = 'Analyze the emotional tone of this text and return only one word: "positive", "negative", or "neutral". Text: $sanitizedTranscription';
      final conversation = [{'role': 'user', 'content': sentimentPrompt}];

      _sentiment = await _openAIService.chatWithGPT(
        prompt: sentimentPrompt,
        conversation: conversation,
      );

      // Extract just the sentiment word
      _sentiment = _sentiment.toLowerCase();
      if (_sentiment.contains('positive')) {
        _sentiment = 'positive';
      } else if (_sentiment.contains('negative')) {
        _sentiment = 'negative';
      } else {
        _sentiment = 'neutral';
      }

      AdvancedLogger.info(_tag, 'Sentiment analysis completed',
          data: {'sentiment': _sentiment});

      _resetSessionTimeout();
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error during sentiment analysis',
          error: e, stackTrace: stackTrace);

      _handleError(ProcessingError(
        message: 'Sentiment analysis error',
        details: e.toString(),
        stage: ProcessingStage.analyzingSentiment,
      ));

      rethrow;
    }
  }

  /// Step 3: Generate story
  Future<void> _generateStory() async {
    _safeSetState(() {
      _stage = ProcessingStage.generatingStory;
      _progressPercentage = 75.0;
    });

    try {
      AdvancedLogger.info(_tag, 'Starting story generation',
          data: {'sentiment': _sentiment});

      final sanitizedTranscription = _sanitizeContent(_transcription);
      String storyPrompt;

      // Customize prompt based on sentiment
      if (_sentiment == 'positive') {
        storyPrompt = 'Create a heartwarming, uplifting story based on this memory. Enhance and celebrate the joyful aspects. Memory: $sanitizedTranscription';
      } else if (_sentiment == 'negative') {
        storyPrompt = 'Create a thoughtful, gently uplifting story based on this memory. While acknowledging any difficult emotions, help find meaning, hope, or wisdom in the experience. Memory: $sanitizedTranscription';
      } else {
        storyPrompt = 'Create an engaging, reflective story based on this memory, highlighting its significance and personal meaning. Memory: $sanitizedTranscription';
      }

      final storyConversation = [{'role': 'user', 'content': storyPrompt}];

      _generatedStory = await _openAIService.chatWithGPT(
        prompt: storyPrompt,
        conversation: storyConversation,
      );

      if (_generatedStory.isEmpty) {
        throw ProcessingError(
          message: 'Story generation failed',
          details: 'The AI was unable to generate a story from your memory.',
          stage: ProcessingStage.generatingStory,
        );
      }

      AdvancedLogger.info(_tag, 'Story generation completed successfully',
          data: {'length': _generatedStory.length});

      _resetSessionTimeout();
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error during story generation',
          error: e, stackTrace: stackTrace);

      _handleError(ProcessingError(
        message: 'Story generation error',
        details: e.toString(),
        stage: ProcessingStage.generatingStory,
      ));

      rethrow;
    }
  }

  /// Step 4: Save the story
  Future<void> _saveStory() async {
    _safeSetState(() {
      _stage = ProcessingStage.savingStory;
      _progressPercentage = 90.0;
    });

    try {
      AdvancedLogger.info(_tag, 'Saving AI story to storage');

      // Verify storage permissions
      bool hasStorageAccess = await Permission.storage.isGranted ||
          await Permission.manageExternalStorage.isGranted;

      if (!hasStorageAccess) {
        AdvancedLogger.warning(_tag, 'Storage permission not granted for saving story');
        throw ProcessingError(
            message: 'Storage permission denied',
            details: 'We need storage permission to save your story. Please grant storage permission in your device settings.',
            stage: ProcessingStage.savingStory,
            isRecoverable: true
        );
      }

      // Get current user ID
      final userId = _authService.currentUser?.uid;
      if (userId == null) {
        throw ProcessingError(
            message: 'Authentication error',
            details: 'User ID not found. Please log in again.',
            stage: ProcessingStage.savingStory,
            isRecoverable: false
        );
      }

      // Create metadata map with null safety
      final Map<String, dynamic> metadata = {
        'transcription': _transcription,
        'originalMemoryTitle': widget.memoryTitle,
        'processingDate': DateTime.now().toIso8601String(),
        'sentiment': _sentiment,
        'sourceAudioPath': widget.audioUrl,
      };

      final storyTitle = '${widget.memoryTitle}_aiStory';

      // Create the AiStory object with a generated ID
      final aiStory = AiStory(
        id: const Uuid().v4(), // Generate a new ID
        memoryId: widget.memoryId,
        userId: userId,
        title: storyTitle,
        content: _generatedStory,
        sentiment: _sentiment,
        createdAt: DateTime.now(),
        metadata: metadata,
      );

      // If StorageService.saveAiStory is not available or has issues,
      // we'll use our direct method to save to device
      try {
        final savedStoryId = await _storageService.saveAiStory(aiStory);
        _savedStory = aiStory.copyWith(id: savedStoryId);
      } catch (e) {
        // Fallback to direct file saving if StorageService fails
        await _directlySaveStoryToDevice(aiStory);
        _savedStory = aiStory;
      }

      AdvancedLogger.info(_tag, 'AI story saved successfully',
          data: {
            'storyId': _savedStory?.id ?? 'unknown',
            'title': storyTitle,
            'savedToLocation': 'local device storage/stories/${storyTitle}.txt'
          });

      _resetSessionTimeout();
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error saving AI story',
          error: e, stackTrace: stackTrace);

      _handleError(ProcessingError(
        message: 'Saving error',
        details: e.toString(),
        stage: ProcessingStage.savingStory,
      ));

      rethrow;
    }
  }

  /// Helper method to save the story to device storage if StorageService fails
  Future<void> _directlySaveStoryToDevice(AiStory story) async {
    try {
      // Create app documents directory for stories
      final appDocDir = await getApplicationDocumentsDirectory();
      final storiesDir = Directory('${appDocDir.path}/stories');
      if (!await storiesDir.exists()) {
        await storiesDir.create(recursive: true);
      }

      // Create a file for the story
      final String safeTitle = story.title.replaceAll(RegExp(r'[^\w\s.-]'), '_');
      final String filePath = '${storiesDir.path}/$safeTitle.txt';
      final File storyFile = File(filePath);

      // Prepare story content with metadata
      final String content =
          'Title: ${story.title}\n'
          'Created: ${story.createdAt.toString()}\n'
          'Sentiment: ${story.sentiment}\n'
          'Memory ID: ${story.memoryId}\n\n'
          '${story.content}';

      // Write to file
      await storyFile.writeAsString(content);

      AdvancedLogger.info(_tag, 'Story saved to device storage',
          data: {'path': filePath});

      // Update the metadata with the file path
      story.metadata?['localFilePath'] = filePath;
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error saving story to device',
          error: e, stackTrace: stackTrace);
      throw ProcessingError(
        message: 'File save error',
        details: 'Could not save story to device storage: $e',
        stage: ProcessingStage.savingStory,
      );
    }
  }

  /// Handle encountered errors
  void _handleError(ProcessingError error) {
    AdvancedLogger.error(_tag, 'Handling processing error',
        data: {
          'stage': error.stage.toString(),
          'message': error.message,
          'details': error.details,
        });

    _safeSetState(() {
      _stage = ProcessingStage.error;
      _error = error;
      _allowedToLeave = true;
    });

    // Vibrate to notify user of error
    HapticFeedback.vibrate();
  }

  /// Show connection error
  void _showConnectionError() {
    _handleError(ProcessingError(
        message: 'No internet connection',
        details: 'Please check your internet connection and try again.',
        stage: _stage,
        isRecoverable: true
    ));
  }

  /// Retry the current operation
  void _retry() {
    _safeSetState(() {
      _stage = ProcessingStage.init;
      _progressPercentage = 0.0;
      _error = null;
      _allowedToLeave = false;
    });

    _startProcessing();
  }

  /// Sanitize content for security
  /// Removes potential PII before sending to external APIs
  String _sanitizeContent(String content) {
    // Remove potential PII or sensitive content before sending to API
    // This is a simple implementation - consider more advanced PII detection
    final emailRegex = RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b');
    final phoneRegex = RegExp(r'\b(\+\d{1,2}\s?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b');
    final ssnRegex = RegExp(r'\b\d{3}[-]?\d{2}[-]?\d{4}\b');
    final creditCardRegex = RegExp(r'\b(?:\d{4}[-\s]?){3}\d{4}\b');
    final addressRegex = RegExp(r'\b\d+\s+[A-Za-z]+\s+(?:Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Drive|Dr|Court|Ct|Lane|Ln|Way|Parkway|Pkwy|Place|Pl)\b', caseSensitive: false);

    var sanitized = content.replaceAll(emailRegex, '[EMAIL]');
    sanitized = sanitized.replaceAll(phoneRegex, '[PHONE]');
    sanitized = sanitized.replaceAll(ssnRegex, '[SSN]');
    sanitized = sanitized.replaceAll(creditCardRegex, '[CREDIT_CARD]');
    sanitized = sanitized.replaceAll(addressRegex, '[ADDRESS]');

    return sanitized;
  }

  /// Show confirmation dialog when user tries to leave
  Future<bool> _onWillPop() async {
    if (_allowedToLeave) return true;

    if (_stage != ProcessingStage.complete && _stage != ProcessingStage.error) {
      final shouldLeave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cancel Story Creation?'),
          content: const Text(
            'If you leave now, your story creation progress will be lost. Are you sure you want to cancel?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay'),
            ),
            TextButton(
              onPressed: () {
                _allowedToLeave = true;
                Navigator.pop(context, true);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      return shouldLeave ?? false;
    }

    return true;
  }

  /// Handle navigation
  void _onTabTapped(int index) {
    if (index == _currentIndex) return;

    AdvancedLogger.info(_tag, 'Tab tapped', data: {'index': index});

    // Prevent navigation during processing
    if (!_allowedToLeave && _stage != ProcessingStage.complete && _stage != ProcessingStage.error) {
      _showCannotLeaveMessage();
      return;
    }

    setState(() {
      _currentIndex = index;
    });

    // Navigate based on tab
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/home');
        break;
      case 1:
        Navigator.pushReplacementNamed(context, '/record');
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/memories');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/conversation');
        break;
    }
  }

  /// Show message when user can't leave during processing
  void _showCannotLeaveMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Please wait for processing to complete or cancel it first'),
        backgroundColor: AppTheme.warningColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'Cancel',
          onPressed: () {
            _onWillPop().then((canLeave) {
              if (canLeave) {
                Navigator.of(context).pop();
              }
            });
          },
          textColor: Colors.white,
        ),
      ),
    );
  }

  /// Navigate to the completed story method
  void _viewCompletedStory() {
    if (_savedStory == null) return;

    AdvancedLogger.info(_tag, 'Navigating to completed story view',
        data: {'storyId': _savedStory!.id});

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AiStoryScreen(
          story: _savedStory!,
          memory: widget.memory ?? Memory(
            id: widget.memoryId,
            userId: _savedStory!.userId,
            title: widget.memoryTitle,
            audioPath: widget.audioUrl,
            transcription: _transcription,
            createdAt: DateTime.now(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: Text(_getAppBarTitle()),
          backgroundColor: AppTheme.gentleTeal,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: _allowedToLeave,
          leading: _allowedToLeave
              ? IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          )
              : null,
        ),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(AppTheme.spacingMedium),
            child: _buildBody(),
          ),
        ),
        bottomNavigationBar: MiloBottomNavigation(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
        ),
      ),
    );
  }

  /// Get the appropriate app bar title based on current state
  String _getAppBarTitle() {
    switch (_stage) {
      case ProcessingStage.error:
        return 'Story Creation Error';
      case ProcessingStage.complete:
        return 'Story Created';
      case ProcessingStage.downloadingAudio:
        return 'Downloading Audio';
      case ProcessingStage.validatingAudio:
        return 'Checking Audio Format';
      case ProcessingStage.transcribing:
        return 'Transcribing Memory';
      case ProcessingStage.analyzingSentiment:
        return 'Analyzing Memory';
      case ProcessingStage.generatingStory:
        return 'Creating Your Story';
      case ProcessingStage.savingStory:
        return 'Saving Your Story';
      default:
        return 'Creating Memory Story';
    }
  }

  /// Build the appropriate body based on current state
  Widget _buildBody() {
    if (!_hasInternetConnection && _stage != ProcessingStage.complete) {
      return _buildConnectionErrorView();
    }

    switch (_stage) {
      case ProcessingStage.error:
        return _buildErrorView();
      case ProcessingStage.complete:
        return _buildCompletedView();
      default:
        return _buildProcessingView();
    }
  }

  /// Build the processing view with progress indicators
  Widget _buildProcessingView() {
    return StatefulBuilder(
      builder: (context, setState) {
        // Start the countdown timer if we're transcribing
        if (_isTranscribing) _startCountdown(setState);

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Show countdown spinner during transcription
              if (_isTranscribing) ...[
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      strokeWidth: 6,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.gentleTeal),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Processing audio... ($_remainingSeconds s)',
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeMedium,
                        color: AppTheme.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Main status card
              _buildStatusCard(),
              const SizedBox(height: 24),

              // Progress bar
              _buildProgressBar(),
              const SizedBox(height: 30),

              // Processing steps
              _buildProcessingSteps(),
              const SizedBox(height: 40),

              // Privacy notice
              _buildPrivacyNotice(),
              const SizedBox(height: 24),

              // Cancel button
              TextButton.icon(
                icon: const Icon(Icons.cancel),
                label: const Text('Cancel Processing'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textSecondaryColor,
                ),
                onPressed: () => _onWillPop(),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Build the error view
  Widget _buildErrorView() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Error card
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(AppTheme.spacingMedium),
            margin: EdgeInsets.only(bottom: AppTheme.spacingLarge),
            decoration: BoxDecoration(
              color: AppTheme.errorColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
              border: Border.all(color: AppTheme.errorColor.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.error_outline,
                  color: AppTheme.errorColor,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  _error?.message ?? 'An unknown error occurred',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeLarge,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.errorColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'We encountered a problem while creating your story.',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    color: AppTheme.textColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (_error != null) Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(AppTheme.spacingMedium),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  ),
                  child: Text(
                    _error!.details.isNotEmpty ? _error!.details : _error!.message,
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeSmall,
                      color: AppTheme.textColor,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_error?.isRecoverable == true) ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.gentleTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                  ),
                ),
                onPressed: _retry,
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go Back'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.gentleTeal,
                  side: BorderSide(color: AppTheme.gentleTeal),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Help text for audio format errors
          if (_error != null && (_error!.message.contains('format') || _error!.message.contains('Format')))
            Container(
              padding: EdgeInsets.all(AppTheme.spacingMedium),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
              ),
              child: Column(
                children: [
                  Text(
                    'Audio Format Tip',
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeMedium,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'When recording, please use MP3, WAV, or M4A formats for best compatibility with our AI service.',
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeSmall,
                      color: AppTheme.textColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // General help text
          Container(
            padding: EdgeInsets.all(AppTheme.spacingMedium),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
            ),
            child: Column(
              children: [
                Text(
                  'Need Help?',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'If the problem persists, try checking your internet connection, updating the app, or contacting support.',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeSmall,
                    color: AppTheme.textSecondaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build the completed view
  Widget _buildCompletedView() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Success card
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(AppTheme.spacingMedium),
            margin: EdgeInsets.only(bottom: AppTheme.spacingLarge),
            decoration: BoxDecoration(
              color: AppTheme.successColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
              border: Border.all(color: AppTheme.successColor.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: AppTheme.successColor,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  'Your Memory Story is Ready!',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeLarge,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.successColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'We\'ve successfully created a personalized story based on your memory.',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    color: AppTheme.textColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // Story preview
          if (_savedStory != null) Container(
            width: double.infinity,
            padding: EdgeInsets.all(AppTheme.spacingMedium),
            margin: EdgeInsets.only(bottom: AppTheme.spacingMedium),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _savedStory!.title,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeLarge,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Created on ${_savedStory!.createdAt.toLocal().toString().split(' ')[0]}',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeSmall,
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Saved to: Device Storage > Milo > Stories',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeSmall,
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  // Show truncated preview
                  _savedStory!.content.length > 150
                      ? '${_savedStory!.content.substring(0, 150)}...'
                      : _savedStory!.content,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    color: AppTheme.textColor,
                  ),
                ),
              ],
            ),
          ),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.book),
                label: const Text('View Full Story'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.gentleTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                  ),
                ),
                onPressed: _viewCompletedStory,
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.folder),
                label: const Text('All Memories'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.gentleTeal,
                  side: BorderSide(color: AppTheme.gentleTeal),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                  ),
                ),
                onPressed: () => Navigator.pushReplacementNamed(context, '/memories'),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Create another prompt
          Container(
            padding: EdgeInsets.all(AppTheme.spacingMedium),
            decoration: BoxDecoration(
              color: AppTheme.calmBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
              border: Border.all(color: AppTheme.calmBlue.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      color: AppTheme.calmBlue,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Create More Memories',
                        style: TextStyle(
                          fontSize: AppTheme.fontSizeMedium,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.calmBlue,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Record more memories to create your personalized memory collection. Each memory helps build a richer story.',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeSmall,
                    color: AppTheme.textColor,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/record'),
                  child: const Text('Record Another Memory'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build connection error view
  Widget _buildConnectionErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wifi_off,
            size: 64,
            color: AppTheme.errorColor,
          ),
          const SizedBox(height: 16),
          Text(
            'No Internet Connection',
            style: TextStyle(
              fontSize: AppTheme.fontSizeLarge,
              fontWeight: FontWeight.bold,
              color: AppTheme.textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please check your connection and try again.',
            style: TextStyle(
              fontSize: AppTheme.fontSizeMedium,
              color: AppTheme.textSecondaryColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.gentleTeal,
              foregroundColor: Colors.white,
            ),
            onPressed: _checkConnectivity,
          ),
        ],
      ),
    );
  }

  /// Build the status card
  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppTheme.spacingMedium),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            _getStatusTitle(),
            style: TextStyle(
              fontSize: AppTheme.fontSizeLarge,
              fontWeight: FontWeight.bold,
              color: AppTheme.textColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            _getStatusDescription(),
            style: TextStyle(
              fontSize: AppTheme.fontSizeMedium,
              color: AppTheme.textColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Build progress bar
  Widget _buildProgressBar() {
    return Column(
      children: [
        LinearProgressIndicator(
          value: _progressPercentage / 100,
          backgroundColor: Colors.grey.withOpacity(0.2),
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.gentleTeal),
          minHeight: 10,
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
        ),
        const SizedBox(height: 8),
        Text(
          '${_progressPercentage.toInt()}% Complete',
          style: TextStyle(
            fontSize: AppTheme.fontSizeSmall,
            color: AppTheme.textSecondaryColor,
          ),
        ),
      ],
    );
  }

  /// Build processing steps indicators
  Widget _buildProcessingSteps() {
    return Column(
      children: [
        _buildProcessingStep(
          title: 'Preparing audio',
          isActive: _stage == ProcessingStage.downloadingAudio || _stage == ProcessingStage.validatingAudio,
          isCompleted: _stage.index > ProcessingStage.validatingAudio.index && _stage != ProcessingStage.error,
          icon: Icons.music_note,
        ),
        _buildStepConnector(),
        _buildProcessingStep(
          title: 'Transcribing your memory',
          isActive: _stage == ProcessingStage.transcribing,
          isCompleted: _stage.index > ProcessingStage.transcribing.index && _stage != ProcessingStage.error,
          icon: Icons.record_voice_over,
        ),
        _buildStepConnector(),
        _buildProcessingStep(
          title: 'Analyzing emotional tone',
          isActive: _stage == ProcessingStage.analyzingSentiment,
          isCompleted: _stage.index > ProcessingStage.analyzingSentiment.index && _stage != ProcessingStage.error,
          icon: Icons.psychology,
        ),
        _buildStepConnector(),
        _buildProcessingStep(
          title: 'Creating your story',
          isActive: _stage == ProcessingStage.generatingStory,
          isCompleted: _stage.index > ProcessingStage.generatingStory.index && _stage != ProcessingStage.error,
          icon: Icons.auto_stories,
        ),
        _buildStepConnector(),
        _buildProcessingStep(
          title: 'Saving your story',
          isActive: _stage == ProcessingStage.savingStory,
          isCompleted: _stage == ProcessingStage.complete,
          icon: Icons.save,
        ),
      ],
    );
  }

  /// Build single processing step
  Widget _buildProcessingStep({
    required String title,
    required bool isActive,
    required bool isCompleted,
    required IconData icon,
  }) {
    return Row(
      children: [
        // Step indicator circle
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isCompleted
                ? AppTheme.successColor
                : isActive
                ? AppTheme.gentleTeal
                : Colors.grey.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : isActive
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 2,
              ),
            )
                : Icon(
              icon,
              color: Colors.grey.withOpacity(0.7),
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 16),

        // Step text
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: AppTheme.fontSizeMedium,
              fontWeight: isActive || isCompleted ? FontWeight.bold : FontWeight.normal,
              color: isActive
                  ? AppTheme.gentleTeal
                  : isCompleted
                  ? AppTheme.textColor
                  : AppTheme.textSecondaryColor,
            ),
          ),
        ),
      ],
    );
  }

  /// Build step connector line
  Widget _buildStepConnector() {
    return Padding(
      padding: const EdgeInsets.only(left: 20),
      child: Container(
        width: 2,
        height: 24,
        color: Colors.grey.withOpacity(0.2),
      ),
    );
  }

  /// Build privacy notice section
  Widget _buildPrivacyNotice() {
    return Container(
      padding: EdgeInsets.all(AppTheme.spacingMedium),
      decoration: BoxDecoration(
        color: AppTheme.calmBlue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        border: Border.all(color: AppTheme.calmBlue.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.privacy_tip,
                color: AppTheme.calmBlue,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Privacy Information',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.calmBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your audio is being processed by OpenAI to create your personalized story. '
                'All content is encrypted during transmission and your data is not used to train AI models.',
            style: TextStyle(
              fontSize: AppTheme.fontSizeSmall,
              color: AppTheme.textColor,
            ),
          ),
        ],
      ),
    );
  }

  /// Get status title based on current processing stage
  String _getStatusTitle() {
    switch (_stage) {
      case ProcessingStage.downloadingAudio:
        return 'Preparing Your Audio';
      case ProcessingStage.validatingAudio:
        return 'Verifying Audio Format';
      case ProcessingStage.transcribing:
        return 'Transcribing Your Memory';
      case ProcessingStage.analyzingSentiment:
        return 'Understanding Your Memory';
      case ProcessingStage.generatingStory:
        return 'Creating Your Memory Story';
      case ProcessingStage.savingStory:
        return 'Saving Your Story';
      default:
        return 'Creating Your Memory Story';
    }
  }

  /// Get status description based on current processing stage
  String _getStatusDescription() {
    switch (_stage) {
      case ProcessingStage.downloadingAudio:
        return 'We\'re downloading and preparing your audio recording for processing.';
      case ProcessingStage.validatingAudio:
        return 'We\'re ensuring your audio is in a format that our AI can process correctly.';
      case ProcessingStage.transcribing:
        return 'We\'re converting your voice recording into text so our AI can understand your memory.';
      case ProcessingStage.analyzingSentiment:
        return 'Our AI is analyzing the emotional tone of your memory to create a personalized story.';
      case ProcessingStage.generatingStory:
        return 'Based on your memory, our AI is crafting a unique and personalized story.';
      case ProcessingStage.savingStory:
        return 'Your story is being saved securely to your collection.';
      default:
        return 'Our AI assistant is crafting a personalized story from your memory. This may take a minute or two.';
    }
  }

  /// Helper method for min to avoid importing dart:math
  int min(int a, int b) {
    return a < b ? a : b;
  }
}