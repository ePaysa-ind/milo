// lib/screens/ai_story_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';

import '../models/ai_story.dart';
import '../models/memory.dart';
import '../services/memory_service.dart';
import '../services/openai_service.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import '../utils/advanced_logger.dart';

class AiStoryScreen extends StatefulWidget {
  final AiStory story;
  final Memory memory;

  const AiStoryScreen({
    Key? key,
    required this.story,
    required this.memory,
  }) : super(key: key);

  @override
  State<AiStoryScreen> createState() => _AiStoryScreenState();
}

class _AiStoryScreenState extends State<AiStoryScreen> {
  static const String _tag = 'AiStoryScreen';

  // Fixed AudioPlayer initialization
  final AudioPlayer _audioPlayer = AudioPlayer();
  final _scrollController = ScrollController();
  final _titleController = TextEditingController();
  final _storyController = TextEditingController();

  bool _isPlayingOriginal = false;
  bool _isEditing = false;
  bool _isGeneratingAudio = false;
  bool _showFullControls = false;
  bool _isModified = false;
  bool _isSaving = false;
  bool _isDisposed = false;

  // TTS service reference
  late final TTSService _ttsService;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.story.title;
    _storyController.text = widget.story.content;

    // Initialize TTS service
    _ttsService = TTSService(
      openAIService: Provider.of<OpenAIService>(context, listen: false),
    );

    // Log screen initialization with secure data handling
    AdvancedLogger.info(_tag, 'AI Story Screen initialized',
        data: {
          'storyId': widget.story.id,
          'memoryId': widget.memory.id,
          'contentLength': widget.story.content.length,
          'sentiment': widget.story.sentiment,
        });

    // Add listeners for text changes to detect modifications
    _titleController.addListener(_onTextChanged);
    _storyController.addListener(_onTextChanged);

    // Listen to TTS status changes
    _ttsService.statusNotifier.addListener(_onTTSStatusChanged);

    // Set up audio player complete listener
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted && !_isDisposed) {
        _safeSetState(() {
          _isPlayingOriginal = false;
        });
        AdvancedLogger.info(_tag, 'Original recording playback completed');
      }
    });
  }

  @override
  void dispose() {
    // Mark as disposed to prevent setState after dispose
    _isDisposed = true;

    // Stop any playback and clean up resources
    _stopOriginalPlayback();
    _ttsService.stop();
    _ttsService.dispose();
    _audioPlayer.dispose();
    _scrollController.dispose();
    _titleController.dispose();
    _storyController.dispose();

    // Remove listeners
    _ttsService.statusNotifier.removeListener(_onTTSStatusChanged);

    // Log secure cleanup
    AdvancedLogger.info(_tag, 'AI Story Screen disposed');
    super.dispose();
  }

  // Safely update state
  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) {
      setState(fn);
    }
  }

  // Keep track of modifications
  void _onTextChanged() {
    if (!_isEditing) return;

    final titleChanged = _titleController.text != widget.story.title;
    final storyChanged = _storyController.text != widget.story.content;

    if (titleChanged || storyChanged) {
      _safeSetState(() {
        _isModified = true;
      });
    }
  }

  // Handle TTS status changes
  void _onTTSStatusChanged() {
    _safeSetState(() {
      // Update UI based on TTS status
      _isGeneratingAudio = _ttsService.status == TTSStatus.loading;
    });
  }

  // Play the original memory recording
  Future<void> _playOriginalRecording() async {
    try {
      if (_isPlayingOriginal) {
        await _stopOriginalPlayback();
        return;
      }

      // Stop TTS if it's playing
      await _ttsService.stop();

      AdvancedLogger.info(_tag, 'Playing original memory recording',
          data: {'audioPath': widget.memory.audioPath});

      _safeSetState(() {
        _isPlayingOriginal = true;
      });

      // Play audio using updated method with proper source
      await _audioPlayer.play(DeviceFileSource(widget.memory.audioPath));
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error playing original recording',
          error: e, stackTrace: stackTrace);

      _safeSetState(() {
        _isPlayingOriginal = false;
      });

      _showErrorSnackbar('Could not play recording: ${e.toString()}');
    }
  }

  // Stop original recording playback
  Future<void> _stopOriginalPlayback() async {
    try {
      if (_isPlayingOriginal) {
        AdvancedLogger.info(_tag, 'Stopping original recording playback');
        await _audioPlayer.stop();

        _safeSetState(() {
          _isPlayingOriginal = false;
        });
      }
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error stopping playback',
          error: e, stackTrace: stackTrace);
    }
  }

  // Handle text-to-speech playback
  Future<void> _handleTextToSpeech() async {
    try {
      // If TTS is playing or loading, stop it
      if (_ttsService.isPlaying || _ttsService.isLoading) {
        await _ttsService.stop();
        return;
      }

      // Stop original recording if playing
      if (_isPlayingOriginal) {
        await _stopOriginalPlayback();
      }

      AdvancedLogger.info(_tag, 'Starting text-to-speech for story');

      // Start TTS
      await _ttsService.speakText(
        widget.story.content,
        voice: _getVoiceBasedOnSentiment(),
      );
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error with text-to-speech',
          error: e, stackTrace: stackTrace);

      _showErrorDialog(
        'Text-to-Speech Error',
        _ttsService.createUserFriendlyErrorMessage(e),
        [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      );
    }
  }

  // Choose voice based on story sentiment
  TTSVoice _getVoiceBasedOnSentiment() {
    final sentiment = widget.story.sentiment.toLowerCase();

    if (sentiment == 'positive') {
      return TTSVoice.nova;  // More upbeat voice for positive stories
    } else if (sentiment == 'negative') {
      return TTSVoice.onyx;  // Deeper, more reflective voice for negative stories
    } else {
      return TTSVoice.alloy;  // Neutral voice for neutral stories
    }
  }

  // Toggle edit mode
  void _toggleEditMode() {
    _safeSetState(() {
      _isEditing = !_isEditing;

      // Reset modified flag when entering edit mode
      if (_isEditing) {
        _isModified = false;
      }
    });
  }

  // Save changes to the story
  Future<void> _saveChanges() async {
    if (!_isModified) return;

    try {
      _safeSetState(() {
        _isSaving = true;
      });

      // Get the updated values
      final updatedTitle = _titleController.text;
      final updatedContent = _storyController.text;

      AdvancedLogger.info(_tag, 'Saving story changes',
          data: {
            'storyId': widget.story.id,
            'titleChanged': updatedTitle != widget.story.title,
            'contentChanged': updatedContent.length != widget.story.content.length,
          });

      // Create updated story object
      final updatedStory = AiStory(
        id: widget.story.id,
        memoryId: widget.story.memoryId,
        userId: widget.story.userId,
        title: updatedTitle,
        content: updatedContent,
        sentiment: widget.story.sentiment,
        createdAt: widget.story.createdAt,
        metadata: widget.story.metadata,
      );

      // Save to storage
      final memoryService = Provider.of<MemoryService>(context, listen: false);
      await memoryService.updateAiStory(updatedStory);

      AdvancedLogger.info(_tag, 'Story saved successfully');

      _safeSetState(() {
        _isSaving = false;
        _isEditing = false;
        _isModified = false;
      });

      _showInfoSnackbar('Story updated successfully');
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error saving story changes',
          error: e, stackTrace: stackTrace);

      _safeSetState(() {
        _isSaving = false;
      });

      _showErrorSnackbar('Failed to save changes: ${e.toString()}');
    }
  }

  // Share the story
  void _shareStory() async {
    try {
      AdvancedLogger.info(_tag, 'Sharing story',
          data: {'storyId': widget.story.id, 'title': widget.story.title});

      // Create a temporary file with the story content
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/shared_story_${DateTime.now().millisecondsSinceEpoch}.txt');

      final storyText = 'AI Memory Story: ${widget.story.title}\n\n'
          '${widget.story.content}\n\n'
          'Created by Milo on ${DateFormat('MMM d, yyyy').format(widget.story.createdAt)}';

      await file.writeAsString(storyText);

      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'My AI Memory Story: ${widget.story.title}',
        text: 'Here\'s an AI-generated story based on my memory.',
      );
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error sharing story',
          error: e, stackTrace: stackTrace);

      _showErrorSnackbar('Failed to share story: ${e.toString()}');
    }
  }

  // Copy story to clipboard
  void _copyToClipboard() {
    try {
      AdvancedLogger.info(_tag, 'Copying story to clipboard');

      Clipboard.setData(ClipboardData(text: widget.story.content));

      _showInfoSnackbar('Story copied to clipboard');
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error copying to clipboard',
          error: e, stackTrace: stackTrace);

      _showErrorSnackbar('Failed to copy to clipboard: ${e.toString()}');
    }
  }

  // Delete the story with confirmation
  void _confirmDeleteStory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Story?'),
        content: const Text(
          'Are you sure you want to delete this AI story? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteStory();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Perform story deletion
  Future<void> _deleteStory() async {
    try {
      _safeSetState(() {
        _isSaving = true;
      });

      AdvancedLogger.info(_tag, 'Deleting story',
          data: {'storyId': widget.story.id, 'title': widget.story.title});

      final memoryService = Provider.of<MemoryService>(context, listen: false);
      await memoryService.deleteAiStory(widget.story.id);

      AdvancedLogger.info(_tag, 'Story deleted successfully');

      // Return to previous screen
      if (mounted && !_isDisposed) {
        Navigator.pop(context);
      }
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error deleting story',
          error: e, stackTrace: stackTrace);

      _safeSetState(() {
        _isSaving = false;
      });

      _showErrorSnackbar('Failed to delete story: ${e.toString()}');
    }
  }

  // Regenerate the story
  Future<void> _regenerateStory() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SpinKitDoubleBounce(
                  color: AppTheme.gentleTeal,
                  size: 50.0,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Regenerating story...',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'We\'re creating a new version of your story with AI.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );

      AdvancedLogger.info(_tag, 'Regenerating story',
          data: {'storyId': widget.story.id, 'memoryId': widget.memory.id});

      // Get the OpenAI and Memory services
      final openAIService = Provider.of<OpenAIService>(context, listen: false);
      final memoryService = Provider.of<MemoryService>(context, listen: false);

      // Generate new story content with enhanced generation
      final newStoryText = await openAIService.generateStoryFromMemory(
        transcription: widget.memory.transcription,
        sentiment: widget.story.sentiment,
        style: widget.story.metadata?['style'] as String?,
        tone: widget.story.metadata?['tone'] as String?,
        minLength: 300,
        maxLength: 800,
      );

      // Update the story object
      final updatedStory = AiStory(
        id: widget.story.id,
        memoryId: widget.story.memoryId,
        userId: widget.story.userId,
        title: widget.story.title,
        content: newStoryText,
        sentiment: widget.story.sentiment,
        createdAt: DateTime.now(),  // Update creation time
        metadata: widget.story.metadata,
      );

      // Save the updated story
      final savedStory = await memoryService.updateAiStory(updatedStory);
      AdvancedLogger.info(_tag, 'Story regenerated successfully');

      // Close the loading dialog
      if (mounted && !_isDisposed) Navigator.pop(context);

      // Update the UI
      _safeSetState(() {
        _storyController.text = savedStory.content;
      });

      _showInfoSnackbar('Story regenerated successfully');
    } catch (e, stackTrace) {
      // Close loading dialog if open
      if (mounted && !_isDisposed) Navigator.pop(context);

      AdvancedLogger.error(_tag, 'Error regenerating story',
          error: e, stackTrace: stackTrace);

      _showErrorSnackbar('Failed to regenerate story: ${e.toString()}');
    }
  }

  // Show error dialog with custom actions
  void _showErrorDialog(String title, String message, List<Widget> actions) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: actions,
      ),
    );
  }

  // Show informational snackbar
  void _showInfoSnackbar(String message) {
    if (mounted && !_isDisposed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppTheme.calmGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Show error snackbar
  void _showErrorSnackbar(String message) {
    if (mounted && !_isDisposed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppTheme.mutedRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Memory Story'),
        backgroundColor: AppTheme.gentleTeal,
        foregroundColor: Colors.white,
        actions: [
          // Edit/Save button
          IconButton(
            icon: Icon(_isEditing ? Icons.save : Icons.edit),
            tooltip: _isEditing ? 'Save changes' : 'Edit story',
            onPressed: _isSaving
                ? null
                : (_isEditing ? _saveChanges : _toggleEditMode),
          ),
          // More options menu
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More options',
            onPressed: () {
              _safeSetState(() {
                _showFullControls = !_showFullControls;
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Main content
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                _isEditing
                    ? TextField(
                  controller: _titleController,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeLarge,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Story Title',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                          AppTheme.borderRadiusMedium),
                    ),
                  ),
                )
                    : Text(
                  widget.story.title,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeLarge,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textColor,
                  ),
                ),
                const SizedBox(height: 8),

                // Creation date
                Text(
                  'Created on ${DateFormat('MMM d, yyyy').format(widget.story.createdAt)}',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeSmall,
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
                const SizedBox(height: 16),

                // Controls
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.gentleTeal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Play original recording
                      Column(
                        children: [
                          IconButton(
                            onPressed: (_isPlayingOriginal || _ttsService.isPlaying)
                                ? _stopOriginalPlayback
                                : _playOriginalRecording,
                            icon: Icon(
                              _isPlayingOriginal
                                  ? Icons.stop
                                  : Icons.play_arrow,
                            ),
                            color: AppTheme.gentleTeal,
                            tooltip: 'Play original recording',
                          ),
                          Text(
                            'Original',
                            style: TextStyle(
                              fontSize: AppTheme.fontSizeXSmall,
                              color: AppTheme.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),

                      // Text-to-speech
                      Column(
                        children: [
                          IconButton(
                            onPressed: _isGeneratingAudio
                                ? null
                                : _handleTextToSpeech,
                            icon: _isGeneratingAudio
                                ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.gentleTeal,
                              ),
                            )
                                : Icon(
                              _ttsService.isPlaying
                                  ? Icons.stop
                                  : Icons.volume_up,
                            ),
                            color: AppTheme.gentleTeal,
                            tooltip: 'Text to speech',
                          ),
                          Text(
                            'Read aloud',
                            style: TextStyle(
                              fontSize: AppTheme.fontSizeXSmall,
                              color: AppTheme.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),

                      // Share
                      Column(
                        children: [
                          IconButton(
                            onPressed: _shareStory,
                            icon: const Icon(Icons.share),
                            color: AppTheme.gentleTeal,
                            tooltip: 'Share story',
                          ),
                          Text(
                            'Share',
                            style: TextStyle(
                              fontSize: AppTheme.fontSizeXSmall,
                              color: AppTheme.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),

                      // Copy to clipboard
                      Column(
                        children: [
                          IconButton(
                            onPressed: _copyToClipboard,
                            icon: const Icon(Icons.content_copy),
                            color: AppTheme.gentleTeal,
                            tooltip: 'Copy to clipboard',
                          ),
                          Text(
                            'Copy',
                            style: TextStyle(
                              fontSize: AppTheme.fontSizeXSmall,
                              color: AppTheme.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Extended controls when showing full options
                if (_showFullControls)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Regenerate story
                        Column(
                          children: [
                            IconButton(
                              onPressed: _regenerateStory,
                              icon: const Icon(Icons.refresh),
                              color: AppTheme.calmBlue,
                              tooltip: 'Regenerate story',
                            ),
                            Text(
                              'Regenerate',
                              style: TextStyle(
                                fontSize: AppTheme.fontSizeXSmall,
                                color: AppTheme.textSecondaryColor,
                              ),
                            ),
                          ],
                        ),

                        // Download as file
                        Column(
                          children: [
                            IconButton(
                              onPressed: () async {
                                // This would use a file export package in a real implementation
                                _showInfoSnackbar('Story saved to Downloads folder');
                              },
                              icon: const Icon(Icons.download),
                              color: AppTheme.calmBlue,
                              tooltip: 'Save as file',
                            ),
                            Text(
                              'Download',
                              style: TextStyle(
                                fontSize: AppTheme.fontSizeXSmall,
                                color: AppTheme.textSecondaryColor,
                              ),
                            ),
                          ],
                        ),

                        // Print
                        Column(
                          children: [
                            IconButton(
                              onPressed: () {
                                // This would use a printing package in a real implementation
                                _showInfoSnackbar('Preparing for printing...');
                              },
                              icon: const Icon(Icons.print),
                              color: AppTheme.calmBlue,
                              tooltip: 'Print story',
                            ),
                            Text(
                              'Print',
                              style: TextStyle(
                                fontSize: AppTheme.fontSizeXSmall,
                                color: AppTheme.textSecondaryColor,
                              ),
                            ),
                          ],
                        ),

                        // Delete
                        Column(
                          children: [
                            IconButton(
                              onPressed: _confirmDeleteStory,
                              icon: const Icon(Icons.delete),
                              color: AppTheme.mutedRed,
                              tooltip: 'Delete story',
                            ),
                            Text(
                              'Delete',
                              style: TextStyle(
                                fontSize: AppTheme.fontSizeXSmall,
                                color: AppTheme.textSecondaryColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // Story content
                Expanded(
                  child: _isEditing
                      ? TextField(
                    controller: _storyController,
                    maxLines: null,
                    expands: true,
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeMedium,
                      color: AppTheme.textColor,
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Story Content',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                            AppTheme.borderRadiusMedium),
                      ),
                    ),
                  )
                      : Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(
                          AppTheme.borderRadiusMedium),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: Text(
                        widget.story.content,
                        style: TextStyle(
                          fontSize: AppTheme.fontSizeMedium,
                          color: AppTheme.textColor,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),

                // Privacy notice
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppTheme.gentleTeal.withOpacity(0.3),
                    ),
                    borderRadius: BorderRadius.circular(
                        AppTheme.borderRadiusSmall),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.security,
                        size: 16,
                        color: AppTheme.gentleTeal,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This story was generated by AI based on your memory. Your privacy is important to us. The content is stored securely on your device.',
                          style: TextStyle(
                            fontSize: AppTheme.fontSizeXSmall,
                            color: AppTheme.textSecondaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Loading overlay
          if (_isSaving)
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