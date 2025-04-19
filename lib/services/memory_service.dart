// lib/services/memory_service.dart - bkend ops for memories
import 'dart:io';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/openai_service.dart';
import '../utils/logger.dart';
import '../models/memory.dart';
import '../models/ai_story.dart';

class MemoryService {
  static const String _tag = 'MemoryService';

  final FirebaseFirestore firestore;
  final FirebaseStorage storage;
  final OpenAIService openAIService;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<Memory> _memories = [];
  bool _isLoading = false;

  MemoryService({
    required this.firestore,
    required this.storage,
    required this.openAIService,
  });

  // Getters
  List<Memory> get memories => _memories;
  bool get isLoading => _isLoading;

  // Load all memories for the current user
  Future<List<Memory>> loadMemories() async {
    Logger.info(_tag, 'Loading memories');

    try {
      _isLoading = true;

      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        Logger.warning(_tag, 'No authenticated user');
        _isLoading = false;
        return [];
      }

      final String userId = currentUser.uid;

      final snapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection('memories')
          .orderBy('createdAt', descending: true)
          .get();

      _memories = snapshot.docs
          .map((doc) => Memory.fromFirestore(doc))
          .toList();

      Logger.info(_tag, 'Loaded ${_memories.length} memories');

      _isLoading = false;
      return _memories;
    } catch (e) {
      Logger.error(_tag, 'Error loading memories: $e');
      _isLoading = false;
      rethrow;
    }
  }

  // Get a specific memory by ID
  Future<Memory> getMemoryById(String memoryId) async {
    Logger.info(_tag, 'Getting memory by ID: $memoryId');

    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('No authenticated user');
      }

      final String userId = currentUser.uid;

      final doc = await firestore
          .collection('users')
          .doc(userId)
          .collection('memories')
          .doc(memoryId)
          .get();

      if (!doc.exists) {
        throw Exception('Memory not found: $memoryId');
      }

      return Memory.fromFirestore(doc);
    } catch (e) {
      Logger.error(_tag, 'Error getting memory by ID: $e');
      rethrow;
    }
  }

  // Process an existing memory with AI
  Future<Memory> processExistingMemory(Memory memory) async {
    Logger.info(_tag, 'Processing memory with AI: ${memory.id}');

    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('No authenticated user');
      }

      final String userId = currentUser.uid;

      // Update memory status to processing
      await firestore
          .collection('users')
          .doc(userId)
          .collection('memories')
          .doc(memory.id)
          .update({
        'isProcessing': true,
      });

      // Simulate getting transcription from OpenAI
      String transcription = memory.transcription ?? "Transcription for memory: ${memory.title}";

      // Simulate generating summary
      String summary = memory.summary ?? "Summary of ${memory.title}";

      // Update memory in Firestore
      final Map<String, dynamic> updateData = {
        'transcription': transcription,
        'summary': summary,
        'isProcessing': false,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await firestore
          .collection('users')
          .doc(userId)
          .collection('memories')
          .doc(memory.id)
          .update(updateData);

      Logger.info(_tag, 'Memory processing completed: ${memory.id}');

      // Fetch updated memory
      final updatedDoc = await firestore
          .collection('users')
          .doc(userId)
          .collection('memories')
          .doc(memory.id)
          .get();

      return Memory.fromFirestore(updatedDoc);
    } catch (e) {
      Logger.error(_tag, 'Error processing memory: $e');

      // Update memory status to not processing
      try {
        final String userId = _auth.currentUser?.uid ?? '';
        if (userId.isNotEmpty) {
          await firestore
              .collection('users')
              .doc(userId)
              .collection('memories')
              .doc(memory.id)
              .update({
            'isProcessing': false,
          });
        }
      } catch (updateError) {
        Logger.error(_tag, 'Error updating memory processing status: $updateError');
      }

      rethrow;
    }
  }

  // Delete a memory
  Future<void> deleteMemory(String memoryId) async {
    Logger.info(_tag, 'Deleting memory: $memoryId');

    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('No authenticated user');
      }

      final String userId = currentUser.uid;

      // Get the memory first to get its audio URL
      final memoryDoc = await firestore
          .collection('users')
          .doc(userId)
          .collection('memories')
          .doc(memoryId)
          .get();

      if (!memoryDoc.exists) {
        throw Exception('Memory not found: $memoryId');
      }

      final memory = Memory.fromFirestore(memoryDoc);

      // Delete the memory document
      await firestore
          .collection('users')
          .doc(userId)
          .collection('memories')
          .doc(memoryId)
          .delete();

      // Delete the audio file if URL exists
      if (memory.audioUrl.isNotEmpty) {
        final fileRef = storage.refFromURL(memory.audioUrl);
        await fileRef.delete();
      }

      Logger.info(_tag, 'Memory deleted: $memoryId');
    } catch (e) {
      Logger.error(_tag, 'Error deleting memory: $e');
      rethrow;
    }
  }

  // Update an AI story
  Future<AiStory> updateAiStory(AiStory story) async {
    Logger.info(_tag, 'Updating AI story: ${story.id}');

    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('No authenticated user');
      }

      final String userId = currentUser.uid;

      // Convert story to map
      final Map<String, dynamic> storyData = {
        'title': story.title,
        'content': story.content,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Any metadata updates
      if (story.metadata != null) {
        storyData['metadata'] = story.metadata;
      }

      // Update the story document
      await firestore
          .collection('users')
          .doc(userId)
          .collection('ai_stories')
          .doc(story.id)
          .update(storyData);

      Logger.info(_tag, 'AI story updated: ${story.id}');

      // Fetch the updated story to return
      final updatedDoc = await firestore
          .collection('users')
          .doc(userId)
          .collection('ai_stories')
          .doc(story.id)
          .get();

      if (!updatedDoc.exists) {
        throw Exception('Updated story not found: ${story.id}');
      }

      // Convert to AiStory object and return
      return AiStory(
        id: story.id,
        memoryId: story.memoryId,
        userId: story.userId,
        title: story.title,
        content: story.content,
        sentiment: story.sentiment,
        createdAt: story.createdAt,
        metadata: story.metadata,
      );
    } catch (e) {
      Logger.error(_tag, 'Error updating AI story: $e');
      rethrow;
    }
  }

  // Delete an AI story
  Future<void> deleteAiStory(String storyId) async {
    Logger.info(_tag, 'Deleting AI story: $storyId');

    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('No authenticated user');
      }

      final String userId = currentUser.uid;

      // Delete the story document
      await firestore
          .collection('users')
          .doc(userId)
          .collection('ai_stories')
          .doc(storyId)
          .delete();

      Logger.info(_tag, 'AI story deleted: $storyId');
    } catch (e) {
      Logger.error(_tag, 'Error deleting AI story: $e');
      rethrow;
    }
  }
}