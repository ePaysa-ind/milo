// lib/screens/memories_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:milo/services/storage_service.dart';
import 'package:milo/theme/app_theme.dart';
import 'package:milo/utils/logger.dart';
import 'package:milo/widgets/milo_bottom_navigation.dart';
import 'package:milo/widgets/privacy_disclaimer_dialog.dart';
import 'package:milo/screens/ai_story_processing_screen.dart';

class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({Key? key}) : super(key: key);

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  static const String _tag = 'MemoriesScreen';

  List<Map<String, dynamic>> _memories = [];
  bool _isLoading = true;
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  final StorageService _storageService = StorageService();
  String? _currentlyPlayingUrl;
  bool _isPlaying = false;

  // For bottom navigation
  int _currentIndex = 2; // Set to 2 for Memories tab

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _initPlayer();
    await _loadMemories();
  }

  Future<void> _initPlayer() async {
    await _player.openPlayer();
    Logger.info(_tag, 'Audio player initialized');

    // Handle playback progress
    _player.onProgress?.listen((event) {
      // Update progress indicator if needed
      if (mounted) {
        setState(() {
          _isPlaying = _player.isPlaying;
        });
      }
    });
  }

  Future<void> _loadMemories() async {
    Logger.info(_tag, 'Loading memories');

    setState(() {
      _isLoading = true;
    });

    try {
      // Use our StorageService to get memories from Firestore - no userId parameter
      final memories = await _storageService.getMemories();

      // Format timestamps
      final formattedMemories = memories.map((data) {
        // Format timestamp if it exists
        if (data['timestamp'] != null) {
          Timestamp timestamp = data['timestamp'] as Timestamp;
          data['formattedDate'] = DateFormat('MMMM d, yyyy • hh:mm a')
              .format(timestamp.toDate());
        } else {
          data['formattedDate'] = 'Unknown date';
        }
        return data;
      }).toList();

      if (mounted) {
        setState(() {
          _memories = formattedMemories;
          _isLoading = false;
        });
      }

      Logger.info(_tag, 'Loaded ${_memories.length} memories');
    } catch (e) {
      Logger.error(_tag, 'Error loading memories: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error loading memories: $e'),
              backgroundColor: AppTheme.errorColor,
            )
        );
      }
    }
  }

  Future<void> _playMemory(Map<String, dynamic> memory) async {
    if (_player.isPlaying) {
      await _player.stopPlayer();
      if (_currentlyPlayingUrl == memory['audioUrl']) {
        setState(() {
          _currentlyPlayingUrl = null;
        });
        return; // Stop if tapping the currently playing memory
      }
    }

    final audioUrl = memory['audioUrl'] as String?;
    if (audioUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Audio URL not found'),
            backgroundColor: AppTheme.warningColor,
          )
      );
      return;
    }

    setState(() {
      _currentlyPlayingUrl = audioUrl;
    });

    try {
      Logger.info(_tag, 'Playing memory: ${memory['title']}');
      await _player.startPlayer(
          fromURI: audioUrl,
          codec: Codec.aacADTS,
          whenFinished: () {
            if (mounted) {
              setState(() {
                _currentlyPlayingUrl = null;
              });
            }
          }
      );
    } catch (e) {
      Logger.error(_tag, 'Error playing memory: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error playing memory: $e'),
              backgroundColor: AppTheme.errorColor,
            )
        );

        setState(() {
          _currentlyPlayingUrl = null;
        });
      }
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> memory) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Memory?'),
        content: const Text('Are you sure you want to delete this memory? It will be permanently removed from the cloud.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: AppTheme.mutedRed)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        final memoryId = memory['id'] as String;
        Logger.info(_tag, 'Deleting memory: $memoryId');

        // Use our StorageService to delete the memory - removed userId parameter
        await _storageService.deleteMemory(memoryId);

        // Reload memories after deletion
        await _loadMemories();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Memory deleted successfully'),
                backgroundColor: AppTheme.successColor,
              )
          );
        }
      } catch (e) {
        Logger.error(_tag, 'Error deleting memory: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error deleting memory: $e'),
                backgroundColor: AppTheme.errorColor,
              )
          );
        }
      }
    }
  }

  // New method for showing memory options
  void _showMemoryOptions(Map<String, dynamic> memory) {
    Logger.info(_tag, 'Showing options for memory: ${memory['id']}');

    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.borderRadiusMedium),
        ),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.auto_stories, color: AppTheme.gentleTeal),
            title: Text(
              'Generate AI Story',
              style: TextStyle(
                fontSize: AppTheme.fontSizeMedium,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            subtitle: Text(
              'Create a personalized story from this memory',
              style: TextStyle(
                fontSize: AppTheme.fontSizeSmall,
                color: AppTheme.textSecondaryColor,
              ),
            ),
            onTap: () async {
              Navigator.pop(context); // Close the bottom sheet

              Logger.info(_tag, '🤖 User requested AI story generation for memory: ${memory['id']}');

              // Show privacy disclaimer
              final consentGiven = await PrivacyDisclaimerDialog.show(context);
              Logger.info(_tag, '🔒 User consent for AI processing: $consentGiven');

              if (consentGiven && mounted) {
                final memoryId = memory['id'] as String;
                final memoryTitle = memory['title'] as String? ?? 'Memory';
                final audioUrl = memory['audioUrl'] as String? ?? '';

                if (audioUrl.isNotEmpty && mounted) {
                  Logger.info(_tag, '⏳ Starting AI story processing for memory: $memoryId');

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
                  Logger.warning(_tag, '⚠️ Cannot process memory: Audio URL is empty');

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Cannot process this memory: Audio not found'),
                        backgroundColor: AppTheme.warningColor,
                      ),
                    );
                  }
                }
              } else {
                Logger.info(_tag, '🚫 User declined AI story generation');
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.play_arrow, color: AppTheme.gentleTeal),
            title: Text(
              'Play Memory',
              style: TextStyle(
                fontSize: AppTheme.fontSizeMedium,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            onTap: () {
              Navigator.pop(context); // Close the bottom sheet
              _playMemory(memory);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete, color: AppTheme.mutedRed),
            title: Text(
              'Delete Memory',
              style: TextStyle(
                fontSize: AppTheme.fontSizeMedium,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            onTap: () {
              Navigator.pop(context); // Close the bottom sheet
              _confirmDelete(memory);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _checkConnectivity() async {
    try {
      final isConnected = await _storageService.checkStorageConnectivity();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isConnected
                  ? 'Connected to Firebase Storage'
                  : 'Not connected to Firebase Storage'
              ),
              backgroundColor: isConnected ? AppTheme.successColor : AppTheme.errorColor,
            )
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error checking connectivity: $e'),
              backgroundColor: AppTheme.errorColor,
            )
        );
      }
    }
  }

  // Handle navigation between tabs
  void _onTabTapped(int index) {
    if (index == _currentIndex) return;

    Logger.info(_tag, 'Tab changed to $index');

    // Do not allow navigation while playing
    if (_isPlaying) {
      Logger.warning(_tag, 'Cannot navigate away while audio is playing');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please stop playback before navigating away'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      _player.stopPlayer();
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
      // Already on memories screen
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/conversation');
        break;
      case 4:
      // Sign out functionality handled in other screens
        break;
    }
  }

  @override
  void dispose() {
    // Clean up resources
    if (_player.isPlaying) {
      _player.stopPlayer();
    }
    _player.closePlayer();
    Logger.info(_tag, 'Audio player disposed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('My Memories'),
        backgroundColor: AppTheme.gentleTeal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.wifi),
            onPressed: _checkConnectivity,
            tooltip: 'Check connectivity',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMemories,
            tooltip: 'Refresh memories',
          ),
        ],
      ),
      body: _isLoading
          ? Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.gentleTeal),
        ),
      )
          : _memories.isEmpty
          ? _buildEmptyMemoriesView()
          : _buildMemoriesList(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/record').then((_) => _loadMemories());
        },
        backgroundColor: AppTheme.gentleTeal,
        child: const Icon(Icons.mic),
        tooltip: 'Record a new memory',
      ),
      bottomNavigationBar: MiloBottomNavigation(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
      ),
    );
  }

  Widget _buildEmptyMemoriesView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/images/empty_memories.png', width: 200),
          const SizedBox(height: 20),
          Text(
            'No memories yet!',
            style: TextStyle(
              fontSize: AppTheme.fontSizeLarge,
              color: AppTheme.gentleTeal,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Record your first memory to get started',
            style: TextStyle(
              fontSize: AppTheme.fontSizeMedium,
              color: AppTheme.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pushNamed(context, '/record').then((_) => _loadMemories());
            },
            icon: const Icon(Icons.mic),
            label: const Text('Record My First Memory'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.gentleTeal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoriesList() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80), // Extra padding for FAB
      itemCount: _memories.length,
      itemBuilder: (context, index) {
        final memory = _memories[index];
        final title = memory['title'] as String? ?? 'Memory';
        final formattedDate = memory['formattedDate'] as String;
        final audioUrl = memory['audioUrl'] as String?;
        final isPlaying = _currentlyPlayingUrl == audioUrl && _isPlaying;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
            onTap: () => _playMemory(memory),
            onLongPress: () => _showMemoryOptions(memory), // Add long press handler
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.gentleTeal.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_circle_filled : Icons.music_note,
                    color: AppTheme.gentleTeal,
                    size: 28,
                  ),
                ),
                title: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTheme.fontSizeMedium,
                    color: AppTheme.textColor,
                  ),
                ),
                subtitle: Text(
                  formattedDate,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeSmall,
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPlaying)
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.gentleTeal,
                          ),
                        ),
                      ),
                    // Add menu icon to make it more obvious there are options
                    IconButton(
                      icon: Icon(Icons.more_vert, color: AppTheme.textSecondaryColor),
                      onPressed: () => _showMemoryOptions(memory),
                      tooltip: 'More options',
                    ),
                    IconButton(
                      icon: Icon(Icons.delete, color: AppTheme.mutedRed),
                      onPressed: () => _confirmDelete(memory),
                      tooltip: 'Delete memory',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}