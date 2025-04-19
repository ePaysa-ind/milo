import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:milo/utils/logger.dart';
import 'package:milo/models/ai_story.dart'; // Import the AiStory model

class StorageService {
  static const String _tag = 'StorageService';
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user ID
  String? get userId => _auth.currentUser?.uid;

  // Retry configuration
  final int _maxRetries = 3;
  final Duration _retryDelay = Duration(seconds: 2);

  // Upload audio file and return download URL - updated to use auth and increment memory titles
  Future<String> uploadAudio(File audioFile, String memoryTitle) async {
    final currentUserId = userId;
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    // Handle auto-incrementing memory titles
    if (memoryTitle.isEmpty || memoryTitle.startsWith('Memory ')) {
      try {
        // Get existing memories to find highest number
        final memories = await getMemories();

        // Find the highest memory number
        int highestNumber = 0;
        for (var memory in memories) {
          final title = memory['title'] as String? ?? '';
          if (title.startsWith('Memory ')) {
            try {
              final number = int.parse(title.substring(7));
              if (number > highestNumber) {
                highestNumber = number;
              }
            } catch (_) {
              // Not a number, ignore
            }
          }
        }

        // Create new title with incremented number
        memoryTitle = "Memory ${highestNumber + 1}";
        Logger.info(_tag, 'Auto-generated incremental memory title: $memoryTitle');
      } catch (e) {
        // If we can't determine the next number, just use a timestamp
        memoryTitle = "Memory ${DateTime.now().millisecondsSinceEpoch}";
        Logger.warning(_tag, 'Failed to generate incremental title, using timestamp: $e');
      }
    }

    int retryCount = 0;

    while (retryCount < _maxRetries) {
      try {
        Logger.info(_tag, "Starting upload to Firebase Storage (attempt ${retryCount + 1})");

        // Verify file exists and is accessible
        if (!audioFile.existsSync()) {
          throw FileSystemException('File does not exist or is inaccessible', audioFile.path);
        }

        Logger.info(_tag, "File exists: ${audioFile.existsSync()}");
        Logger.info(_tag, "File path: ${audioFile.path}");
        Logger.info(_tag, "File size: ${audioFile.lengthSync()} bytes");

        // Create reference to the file location in Firebase Storage
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.aac';
        final storageRef = _storage.ref().child('users/$currentUserId/audio/$fileName');
        Logger.info(_tag, "Storage reference created: users/$currentUserId/audio/$fileName");

        // Set metadata
        final metadata = SettableMetadata(
          contentType: 'audio/aac',
          customMetadata: {
            'title': memoryTitle,
            'userId': currentUserId,
            'createdAt': DateTime.now().toIso8601String(),
          },
        );

        // Upload the file with progress tracking
        Logger.info(_tag, "Starting file upload...");
        final uploadTask = storageRef.putFile(audioFile, metadata);

        // Log progress
        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          Logger.info(_tag, "Upload progress: ${(progress * 100).toStringAsFixed(2)}%");
        });

        // Wait for completion
        final snapshot = await uploadTask;
        Logger.info(_tag, "File uploaded successfully (${snapshot.bytesTransferred} bytes)");

        // Get the download URL
        final downloadUrl = await storageRef.getDownloadURL();
        Logger.info(_tag, "Download URL obtained: $downloadUrl");

        // Store metadata in Firestore
        Logger.info(_tag, "Saving metadata to Firestore...");
        final docRef = await _firestore.collection('users').doc(currentUserId).collection('memories').add({
          'title': memoryTitle,
          'audioUrl': downloadUrl,
          'timestamp': FieldValue.serverTimestamp(),
          'type': 'audio',
          'fileName': fileName,
          'fileSize': audioFile.lengthSync(),
        });
        Logger.info(_tag, "Metadata saved to Firestore with ID: ${docRef.id}");

        // Delete the local temporary file after successful upload
        try {
          if (audioFile.existsSync()) {
            await audioFile.delete();
            Logger.info(_tag, "Temporary local file deleted");
          }
        } catch (e) {
          Logger.warning(_tag, "Error deleting temporary file: $e");
          // Continue even if deletion fails
        }

        return downloadUrl;
      } catch (e) {
        Logger.error(_tag, 'Error uploading audio (attempt ${retryCount + 1}): $e');
        retryCount++;

        if (retryCount < _maxRetries) {
          Logger.info(_tag, 'Retrying in ${_retryDelay.inSeconds} seconds...');
          await Future.delayed(_retryDelay);
        } else {
          Logger.error(_tag, 'Max retries reached. Upload failed.');
          throw Exception('Failed to upload audio after $_maxRetries attempts: $e');
        }
      }
    }

    // This should never be reached due to the exception in the loop
    throw Exception('Unexpected error in upload retry loop');
  }

  // Save AI-generated story for a memory
  Future<String> saveAiStory(AiStory aiStory) async {
    final currentUserId = userId;
    if (currentUserId == null) {
      Logger.error(_tag, 'Cannot save AI story: User not authenticated');
      throw Exception('User not authenticated');
    }

    // Extract data from the AiStory object
    final String memoryId = aiStory.memoryId;
    final String storyContent = aiStory.content;
    final String storyTitle = aiStory.title;
    final String sentiment = aiStory.sentiment;
    final DateTime createdAt = aiStory.createdAt;
    // Handle potentially nullable metadata with a default empty map
    final Map<String, dynamic> metadata = aiStory.metadata ?? {};

    Logger.info(_tag, 'Saving AI story for memory: $memoryId');
    Logger.info(_tag, 'Story title: $storyTitle');
    Logger.info(_tag, 'Story sentiment: $sentiment');
    Logger.info(_tag, 'Story length: ${storyContent.length} characters');

    int retryCount = 0;
    while (retryCount < _maxRetries) {
      try {
        // Reference to the stories subcollection for this memory
        final storiesCollection = _firestore
            .collection('users')
            .doc(currentUserId)
            .collection('memories')
            .doc(memoryId)
            .collection('stories');

        Logger.info(_tag, 'Creating reference to stories collection');

        // Verify the memory exists before saving the story
        final memoryDoc = await _firestore
            .collection('users')
            .doc(currentUserId)
            .collection('memories')
            .doc(memoryId)
            .get();

        if (!memoryDoc.exists) {
          Logger.error(_tag, 'Memory not found: $memoryId');
          throw Exception('Memory not found');
        }

        Logger.info(_tag, 'Memory exists, proceeding with story creation');

        // Create a new document with auto-generated ID
        final storyDoc = storiesCollection.doc();
        final storyId = storyDoc.id;
        Logger.info(_tag, 'Generated story ID: $storyId');

        // Prepare story data
        final storyData = {
          'id': storyId,
          'memoryId': memoryId,
          'title': storyTitle,
          'content': storyContent, // Note: using content field
          'sentiment': sentiment,
          'timestamp': FieldValue.serverTimestamp(),
          'createdAt': Timestamp.fromDate(createdAt),
          'createdBy': 'ai',
          'userId': currentUserId,
          'metadata': metadata,
          'version': '1.0',
        };

        // Save the story to Firestore
        Logger.info(_tag, 'Saving story data to Firestore...');
        await storyDoc.set(storyData);
        Logger.info(_tag, 'AI story saved successfully');

        // Update the memory document to indicate it has stories
        try {
          await _firestore
              .collection('users')
              .doc(currentUserId)
              .collection('memories')
              .doc(memoryId)
              .update({
            'hasStories': true,
            'lastStoryCreated': FieldValue.serverTimestamp(),
            'lastStorySentiment': sentiment,
          });
          Logger.info(_tag, 'Memory document updated with story flag');
        } catch (e) {
          // Log but don't fail if updating the memory fails
          Logger.warning(_tag, 'Failed to update memory with story flag: $e');
        }

        return storyId;
      } catch (e) {
        Logger.error(_tag, 'Error saving AI story (attempt ${retryCount + 1}): $e');
        retryCount++;

        if (retryCount < _maxRetries) {
          Logger.info(_tag, 'Retrying in ${_retryDelay.inSeconds} seconds...');
          await Future.delayed(_retryDelay);
        } else {
          Logger.error(_tag, 'Max retries reached. Save AI story failed.');
          throw Exception('Failed to save AI story after $_maxRetries attempts: $e');
        }
      }
    }

    // This should never be reached due to the exception in the loop
    throw Exception('Unexpected error in save AI story retry loop');
  }

  // Test method to verify basic upload functionality
  Future<bool> testUpload() async {
    final currentUserId = userId;
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    try {
      // Create a simple text file
      final tempDir = await getTemporaryDirectory();
      final testFile = File('${tempDir.path}/test_${DateTime.now().millisecondsSinceEpoch}.txt');
      await testFile.writeAsString('This is a test file created at ${DateTime.now().toIso8601String()}');

      Logger.info(_tag, "Test file created at: ${testFile.path}");
      Logger.info(_tag, "Test file size: ${await testFile.length()} bytes");
      Logger.info(_tag, "Test file exists: ${await testFile.exists()}");

      // Upload to Firebase Storage
      final storageRef = _storage.ref().child('users/$currentUserId/test/test_${DateTime.now().millisecondsSinceEpoch}.txt');
      Logger.info(_tag, "Starting test upload to: ${storageRef.fullPath}");

      // Set metadata
      final metadata = SettableMetadata(
        contentType: 'text/plain',
        customMetadata: {
          'purpose': 'testing',
          'timestamp': DateTime.now().toIso8601String(),
          'userId': currentUserId,
        },
      );

      final uploadTask = storageRef.putFile(testFile, metadata);

      // Track progress
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        Logger.info(_tag, "Test upload progress: ${(progress * 100).toStringAsFixed(2)}%");
      });

      // Wait for completion
      final snapshot = await uploadTask;
      Logger.info(_tag, "Test file uploaded successfully (${snapshot.bytesTransferred} bytes)");

      // Get download URL to verify accessibility
      final downloadUrl = await storageRef.getDownloadURL();
      Logger.info(_tag, "Test file download URL: $downloadUrl");

      // Clean up - delete the test file
      await storageRef.delete();
      Logger.info(_tag, "Test file deleted from Storage");

      // Delete local test file
      if (await testFile.exists()) {
        await testFile.delete();
        Logger.info(_tag, "Local test file deleted");
      }

      return true;
    } catch (e) {
      Logger.error(_tag, 'Test upload error: $e');
      return false;
    }
  }

  // Get all memories for current user
  Future<List<Map<String, dynamic>>> getMemories() async {
    final currentUserId = userId;
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(currentUserId)
          .collection('memories')
          .orderBy('timestamp', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      Logger.error(_tag, 'Error getting memories: $e');
      rethrow; // Use rethrow to preserve the original stack trace
    }
  }

  // Delete a memory
  Future<void> deleteMemory(String memoryId) async {
    final currentUserId = userId;
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    try {
      Logger.info(_tag, "Attempting to delete memory: $memoryId for user: $currentUserId");

      // Get the memory document
      final memoryDoc = await _firestore
          .collection('users')
          .doc(currentUserId)
          .collection('memories')
          .doc(memoryId)
          .get();

      if (!memoryDoc.exists) {
        Logger.warning(_tag, "Memory document not found");
        throw Exception('Memory not found');
      }

      final data = memoryDoc.data();
      final audioUrl = data?['audioUrl'] as String?;
      final fileName = data?['fileName'] as String?;

      // Delete from Storage if URL exists
      if (audioUrl != null) {
        try {
          Logger.info(_tag, "Deleting file from Storage: $audioUrl");
          final ref = _storage.refFromURL(audioUrl);
          await ref.delete();
          Logger.info(_tag, "File deleted from Storage");
        } catch (e) {
          Logger.warning(_tag, "Error deleting from Storage: $e");
          // Continue with Firestore deletion even if Storage deletion fails
        }
      } else if (fileName != null) {
        // Try using the fileName if URL is not available
        try {
          Logger.info(_tag, "Deleting file from Storage using fileName: $fileName");
          final ref = _storage.ref().child('users/$currentUserId/audio/$fileName');
          await ref.delete();
          Logger.info(_tag, "File deleted from Storage");
        } catch (e) {
          Logger.warning(_tag, "Error deleting from Storage using fileName: $e");
          // Continue with Firestore deletion even if Storage deletion fails
        }
      }

      // Check for and delete any AI stories associated with this memory
      try {
        Logger.info(_tag, "Checking for AI stories to delete...");
        final storiesSnapshot = await _firestore
            .collection('users')
            .doc(currentUserId)
            .collection('memories')
            .doc(memoryId)
            .collection('stories')
            .get();

        if (storiesSnapshot.docs.isNotEmpty) {
          Logger.info(_tag, "Found ${storiesSnapshot.docs.length} stories to delete");

          // Create a batch for efficient deletion of multiple stories
          final batch = _firestore.batch();

          for (var storyDoc in storiesSnapshot.docs) {
            batch.delete(storyDoc.reference);
          }

          await batch.commit();
          Logger.info(_tag, "Successfully deleted ${storiesSnapshot.docs.length} associated stories");
        } else {
          Logger.info(_tag, "No stories found for this memory");
        }
      } catch (e) {
        Logger.warning(_tag, "Error deleting associated stories: $e");
        // Continue with memory deletion even if story deletion fails
      }

      // Delete from Firestore
      await _firestore
          .collection('users')
          .doc(currentUserId)
          .collection('memories')
          .doc(memoryId)
          .delete();

      Logger.info(_tag, "Memory document deleted from Firestore");
    } catch (e) {
      Logger.error(_tag, 'Error deleting memory: $e');
      rethrow; // Use rethrow to preserve the original stack trace
    }
  }

  // Check Firebase Storage connectivity
  Future<bool> checkStorageConnectivity() async {
    final currentUserId = userId;
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    try {
      Logger.info(_tag, "Testing Firebase Storage connectivity...");

      // Create a small in-memory file (text content)
      final List<int> bytes = utf8.encode('Connectivity test ${DateTime.now().toIso8601String()}');
      final testData = Uint8List.fromList(bytes);

      // Upload to a test location
      final testRef = _storage.ref().child('users/$currentUserId/_connectivity_test/test_${DateTime.now().millisecondsSinceEpoch}.txt');

      // Upload the data
      final uploadTask = testRef.putData(testData);
      final snapshot = await uploadTask;
      Logger.info(_tag, "Test data uploaded: ${snapshot.bytesTransferred} bytes");

      // Get download URL
      final downloadUrl = await testRef.getDownloadURL();
      Logger.info(_tag, "Storage connectivity test passed. URL: $downloadUrl");

      // Clean up - delete the test file
      await testRef.delete();
      Logger.info(_tag, "Test file deleted");

      return true;
    } catch (e) {
      Logger.error(_tag, "Storage connectivity test failed: $e");
      return false;
    }
  }
}