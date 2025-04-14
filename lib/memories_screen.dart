// lib/memories_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:milo/services/storage_service.dart';

class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({Key? key}) : super(key: key);

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  List<Map<String, dynamic>> _memories = [];
  bool _isLoading = true;
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  final StorageService _storageService = StorageService();
  String? _currentlyPlayingUrl;
  bool _isPlaying = false;

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
    } catch (e) {
      print('Error loading memories: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading memories: $e'))
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
          const SnackBar(content: Text('Audio URL not found'))
      );
      return;
    }

    setState(() {
      _currentlyPlayingUrl = audioUrl;
    });

    try {
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
      print('Error playing memory: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error playing memory: $e'))
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
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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

        // Use our StorageService to delete the memory - removed userId parameter
        await _storageService.deleteMemory(memoryId);

        // Reload memories after deletion
        await _loadMemories();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Memory deleted successfully'))
          );
        }
      } catch (e) {
        print('Error deleting memory: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error deleting memory: $e'))
          );
        }
      }
    }
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
              backgroundColor: isConnected ? Colors.green : Colors.red,
            )
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error checking connectivity: $e'))
        );
      }
    }
  }

  @override
  void dispose() {
    // Clean up resources
    if (_player.isPlaying) {
      _player.stopPlayer();
    }
    _player.closePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Memories'),
        backgroundColor: Colors.teal,
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
          ? const Center(child: CircularProgressIndicator())
          : _memories.isEmpty
          ? _buildEmptyMemoriesView()
          : _buildMemoriesList(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/record').then((_) => _loadMemories());
        },
        backgroundColor: Colors.teal,
        child: const Icon(Icons.mic),
        tooltip: 'Record a new memory',
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
          const Text(
            'No memories yet!',
            style: TextStyle(fontSize: 18, color: Colors.teal),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pushNamed(context, '/record').then((_) => _loadMemories());
            },
            icon: const Icon(Icons.mic),
            label: const Text('Record My First Memory'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoriesList() {
    return ListView.builder(
      itemCount: _memories.length,
      itemBuilder: (context, index) {
        final memory = _memories[index];
        final title = memory['title'] as String? ?? 'Memory';
        final formattedDate = memory['formattedDate'] as String;
        final audioUrl = memory['audioUrl'] as String?;
        final isPlaying = _currentlyPlayingUrl == audioUrl && _isPlaying;

        return GestureDetector(
          onTap: () => _playMemory(memory),
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            elevation: 4,
            child: ListTile(
              leading: Icon(
                isPlaying ? Icons.pause_circle_filled : Icons.music_note,
                color: Colors.teal,
                size: 30,
              ),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(formattedDate),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isPlaying)
                    const Padding(
                      padding: EdgeInsets.only(right: 16),
                      child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.teal,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _confirmDelete(memory),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}