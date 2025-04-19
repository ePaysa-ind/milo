// lib/screens/memory_detail_screen.dart - Fixed audioUrl references
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/memory.dart';
import '../services/memory_service.dart';
import '../utils/logger.dart';
import '../widgets/milo_bottom_navigation.dart';
import '../theme/app_theme.dart';
import 'conversation_screen.dart';

class MemoryDetailScreen extends StatefulWidget {
  final String memoryId;

  const MemoryDetailScreen({Key? key, required this.memoryId}) : super(key: key);

  @override
  _MemoryDetailScreenState createState() => _MemoryDetailScreenState();
}

class _MemoryDetailScreenState extends State<MemoryDetailScreen> {
  static const String _tag = 'MemoryDetailScreen';

  Memory? _memory;
  bool _isLoading = true;
  bool _isPlaying = false;
  bool _isProcessing = false;

  // For bottom navigation
  int _currentIndex = 2; // Set to 2 for Memories tab

  final AudioPlayer _audioPlayer = AudioPlayer();
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    Logger.info(_tag, 'Initializing memory detail screen for memory: ${widget.memoryId}');
    _loadMemory();
    _setupAudioPlayer();
  }

  void _setupAudioPlayer() {
    Logger.debug(_tag, 'Setting up audio player');

    _audioPlayer.onPlayerStateChanged.listen((state) {
      Logger.debug(_tag, 'Audio player state changed: $state');
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() {
          _duration = duration;
        });
      }
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      Logger.debug(_tag, 'Audio playback completed');
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    Logger.info(_tag, 'Memory detail screen disposed');
    super.dispose();
  }

  // Load memory details
  Future<void> _loadMemory() async {
    Logger.info(_tag, 'Loading memory: ${widget.memoryId}');

    setState(() {
      _isLoading = true;
    });

    try {
      final memoryService = Provider.of<MemoryService>(context, listen: false);
      final memory = await memoryService.getMemoryById(widget.memoryId);

      if (mounted) {
        setState(() {
          _memory = memory;
          _isLoading = false;
        });

        Logger.info(_tag, 'Memory loaded: ${memory?.title}');
      }
    } catch (e) {
      Logger.error(_tag, 'Failed to load memory details: $e');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load memory details: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  // Toggle audio playback
  Future<void> _togglePlay() async {
    Logger.info(_tag, 'Toggling audio playback');

    if (_memory == null) return;

    if (_isPlaying) {
      Logger.debug(_tag, 'Pausing audio');
      await _audioPlayer.pause();
    } else {
      // Fixed line: Using the getter through audioPath
      Logger.debug(_tag, 'Starting audio playback: ${_memory!.audioPath}');
      await _audioPlayer.play(UrlSource(_memory!.audioPath));
    }
  }

  // Process memory with AI if not already processed
  Future<void> _processMemoryWithAI() async {
    Logger.info(_tag, 'Processing memory with AI: ${_memory?.id}');

    if (_memory == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final memoryService = Provider.of<MemoryService>(context, listen: false);
      final updatedMemory = await memoryService.processExistingMemory(_memory!);

      if (mounted) {
        setState(() {
          _memory = updatedMemory;
          _isProcessing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Memory processed successfully'),
            backgroundColor: AppTheme.successColor,
          ),
        );

        Logger.info(_tag, 'Memory processed successfully: ${updatedMemory.id}');
      }
    } catch (e) {
      Logger.error(_tag, 'Failed to process memory: $e');

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process memory: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  // Start a conversation about this memory
  void _startConversation() {
    Logger.info(_tag, 'Starting conversation about memory: ${_memory?.id}');

    if (_memory == null) return;

    String initialPrompt;

    if (_memory!.summary != null && _memory!.summary!.isNotEmpty) {
      initialPrompt = 'I have a memory titled "${_memory!.title}" with this summary: ${_memory!.summary}. What would you like to know about it?';
    } else if (_memory!.transcription.isNotEmpty) {
      initialPrompt = 'I have a memory titled "${_memory!.title}" with this transcription: ${_memory!.transcription}. What would you like to know about it?';
    } else {
      initialPrompt = 'I have a memory titled "${_memory!.title}". What would you like to know about it?';
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ConversationScreen(
          memoryId: _memory!.id,
          initialPrompt: initialPrompt,
        ),
      ),
    );
  }

  // Handle navigation between tabs
  void _onTabTapped(int index) {
    if (index == _currentIndex) return;

    Logger.info(_tag, 'Tab changed to $index');

    // Do not allow navigation while processing
    if (_isProcessing) {
      Logger.warning(_tag, 'Cannot navigate away while processing');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please wait for processing to complete'),
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
        Navigator.pushReplacementNamed(context, '/record');
        break;
      case 2:
      // Already on memories screen, navigate to main memories list
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          Navigator.pushReplacementNamed(context, '/memories');
        }
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/conversation');
        break;
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_memory?.title ?? 'Memory Details'),
        backgroundColor: AppTheme.gentleTeal,
        foregroundColor: Colors.white,
        actions: [
          if (_memory != null && !_memory!.isFullyProcessed && !_isProcessing)
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              tooltip: 'Process with AI',
              onPressed: _processMemoryWithAI,
            ),
        ],
      ),
      body: _isLoading
          ? Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.gentleTeal),
        ),
      )
          : _memory == null
          ? Center(
        child: Text(
          'Memory not found',
          style: TextStyle(
            fontSize: AppTheme.fontSizeMedium,
            color: AppTheme.textColor,
          ),
        ),
      )
          : _buildMemoryDetails(),
      floatingActionButton: _memory != null
          ? FloatingActionButton(
        backgroundColor: AppTheme.calmBlue,
        child: const Icon(Icons.chat),
        tooltip: 'Ask about this memory',
        onPressed: _startConversation,
      )
          : null,
      bottomNavigationBar: MiloBottomNavigation(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
      ),
    );
  }

  Widget _buildMemoryDetails() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Audio player card
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _memory!.title,
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeLarge,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                        iconSize: 48,
                        color: AppTheme.gentleTeal,
                        onPressed: _togglePlay,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SliderTheme(
                              data: SliderThemeData(
                                thumbColor: AppTheme.gentleTeal,
                                activeTrackColor: AppTheme.gentleTeal,
                                inactiveTrackColor: AppTheme.gentleTeal.withOpacity(0.3),
                              ),
                              child: Slider(
                                value: _position.inSeconds.toDouble(),
                                max: _duration.inSeconds.toDouble() > 0
                                    ? _duration.inSeconds.toDouble()
                                    : (_memory!.audioDuration?.toDouble() ?? 100),
                                onChanged: (value) {
                                  final position = Duration(seconds: value.toInt());
                                  _audioPlayer.seek(position);
                                },
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(_position),
                                  style: TextStyle(
                                    fontSize: AppTheme.fontSizeSmall,
                                    color: AppTheme.textSecondaryColor,
                                  ),
                                ),
                                Text(
                                  _formatDuration(_duration),
                                  style: TextStyle(
                                    fontSize: AppTheme.fontSizeSmall,
                                    color: AppTheme.textSecondaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Processing status
          if (_memory!.isProcessing || _isProcessing)
            Card(
              color: Colors.blue.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.gentleTeal),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Processing with AI. This may take a moment...',
                        style: TextStyle(
                          color: AppTheme.calmBlue,
                          fontSize: AppTheme.fontSizeSmall,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Summary section
          if (_memory!.summary != null && _memory!.summary!.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Summary',
              style: TextStyle(
                fontSize: AppTheme.fontSizeLarge,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  _memory!.summary!,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    color: AppTheme.textColor,
                  ),
                ),
              ),
            ),
          ],

          // Transcription section
          if (_memory!.transcription.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Transcription',
              style: TextStyle(
                fontSize: AppTheme.fontSizeLarge,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  _memory!.transcription,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    color: AppTheme.textColor,
                  ),
                ),
              ),
            ),
          ],

          // If neither transcription nor summary is available
          if (_memory!.transcription.isEmpty &&
              (_memory!.summary == null || _memory!.summary!.isEmpty) &&
              !_memory!.isProcessing && !_isProcessing) ...[
            const SizedBox(height: 24),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'This memory has not been processed with AI yet.',
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeMedium,
                        color: AppTheme.textColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(
                        'Process Now',
                        style: TextStyle(
                          fontSize: AppTheme.fontSizeMedium,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.gentleTeal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                        ),
                      ),
                      onPressed: _processMemoryWithAI,
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Created/Updated date info
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Created: ${_memory!.createdAt.toLocal().toString().split('.')[0]}',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeSmall,
                    color: AppTheme.textLightColor,
                  ),
                ),
                if (_memory!.updatedAt != null)
                  Text(
                    'Updated: ${_memory!.updatedAt!.toLocal().toString().split('.')[0]}',
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeSmall,
                      color: AppTheme.textLightColor,
                    ),
                  ),
              ],
            ),
          ),

          // Bottom padding for floating action button
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}