import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'dart:convert';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user ID
  String? get userId => _auth.currentUser?.uid;

  // Retry configuration
  final int _maxRetries = 3;
  final Duration _retryDelay = Duration(seconds: 2);

  // Upload audio file and return download URL - updated to use auth
  Future<String> uploadAudio(File audioFile, String memoryTitle) async {
    final currentUserId = userId;
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    int retryCount = 0;

    while (retryCount < _maxRetries) {
      try {
        print("⭐ Starting upload to Firebase Storage (attempt ${retryCount + 1})");

        // Verify file exists and is accessible
        if (!audioFile.existsSync()) {
          throw FileSystemException('File does not exist or is inaccessible', audioFile.path);
        }

        print("⭐ File exists: ${audioFile.existsSync()}");
        print("⭐ File path: ${audioFile.path}");
        print("⭐ File size: ${audioFile.lengthSync()} bytes");

        // Create reference to the file location in Firebase Storage
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.aac';
        final storageRef = _storage.ref().child('users/$currentUserId/audio/$fileName');
        print("⭐ Storage reference created: users/$currentUserId/audio/$fileName");

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
        print("⭐ Starting file upload...");
        final uploadTask = storageRef.putFile(audioFile, metadata);

        // Log progress
        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          print("⭐ Upload progress: ${(progress * 100).toStringAsFixed(2)}%");
        });

        // Wait for completion
        final snapshot = await uploadTask;
        print("⭐ File uploaded successfully (${snapshot.bytesTransferred} bytes)");

        // Get the download URL
        final downloadUrl = await storageRef.getDownloadURL();
        print("⭐ Download URL obtained: $downloadUrl");

        // Store metadata in Firestore
        print("⭐ Saving metadata to Firestore...");
        final docRef = await _firestore.collection('users').doc(currentUserId).collection('memories').add({
          'title': memoryTitle,
          'audioUrl': downloadUrl,
          'timestamp': FieldValue.serverTimestamp(),
          'type': 'audio',
          'fileName': fileName,
          'fileSize': audioFile.lengthSync(),
        });
        print("⭐ Metadata saved to Firestore with ID: ${docRef.id}");

        // Delete the local temporary file after successful upload
        try {
          if (audioFile.existsSync()) {
            await audioFile.delete();
            print("⭐ Temporary local file deleted");
          }
        } catch (e) {
          print("⚠️ Error deleting temporary file: $e");
          // Continue even if deletion fails
        }

        return downloadUrl;
      } catch (e) {
        print('❌ Error uploading audio (attempt ${retryCount + 1}): $e');
        retryCount++;

        if (retryCount < _maxRetries) {
          print('⏳ Retrying in ${_retryDelay.inSeconds} seconds...');
          await Future.delayed(_retryDelay);
        } else {
          print('❌ Max retries reached. Upload failed.');
          throw Exception('Failed to upload audio after $_maxRetries attempts: $e');
        }
      }
    }

    // This should never be reached due to the exception in the loop
    throw Exception('Unexpected error in upload retry loop');
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

      print("📝 Test file created at: ${testFile.path}");
      print("📝 Test file size: ${await testFile.length()} bytes");
      print("📝 Test file exists: ${await testFile.exists()}");

      // Upload to Firebase Storage
      final storageRef = _storage.ref().child('users/$currentUserId/test/test_${DateTime.now().millisecondsSinceEpoch}.txt');
      print("📝 Starting test upload to: ${storageRef.fullPath}");

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
        print("📝 Test upload progress: ${(progress * 100).toStringAsFixed(2)}%");
      });

      // Wait for completion
      final snapshot = await uploadTask;
      print("📝 Test file uploaded successfully (${snapshot.bytesTransferred} bytes)");

      // Get download URL to verify accessibility
      final downloadUrl = await storageRef.getDownloadURL();
      print("📝 Test file download URL: $downloadUrl");

      // Clean up - delete the test file
      await storageRef.delete();
      print("📝 Test file deleted from Storage");

      // Delete local test file
      if (await testFile.exists()) {
        await testFile.delete();
        print("📝 Local test file deleted");
      }

      return true;
    } catch (e) {
      print('❌ Test upload error: $e');
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
      print('Error getting memories: $e');
      throw e;
    }
  }

  // Delete a memory
  Future<void> deleteMemory(String memoryId) async {
    final currentUserId = userId;
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    try {
      print("🗑️ Attempting to delete memory: $memoryId for user: $currentUserId");

      // Get the memory document
      final memoryDoc = await _firestore
          .collection('users')
          .doc(currentUserId)
          .collection('memories')
          .doc(memoryId)
          .get();

      if (!memoryDoc.exists) {
        print("⚠️ Memory document not found");
        throw Exception('Memory not found');
      }

      final data = memoryDoc.data();
      final audioUrl = data?['audioUrl'] as String?;
      final fileName = data?['fileName'] as String?;

      // Delete from Storage if URL exists
      if (audioUrl != null) {
        try {
          print("🗑️ Deleting file from Storage: $audioUrl");
          final ref = _storage.refFromURL(audioUrl);
          await ref.delete();
          print("✅ File deleted from Storage");
        } catch (e) {
          print("⚠️ Error deleting from Storage: $e");
          // Continue with Firestore deletion even if Storage deletion fails
        }
      } else if (fileName != null) {
        // Try using the fileName if URL is not available
        try {
          print("🗑️ Deleting file from Storage using fileName: $fileName");
          final ref = _storage.ref().child('users/$currentUserId/audio/$fileName');
          await ref.delete();
          print("✅ File deleted from Storage");
        } catch (e) {
          print("⚠️ Error deleting from Storage using fileName: $e");
          // Continue with Firestore deletion even if Storage deletion fails
        }
      }

      // Delete from Firestore
      await _firestore
          .collection('users')
          .doc(currentUserId)
          .collection('memories')
          .doc(memoryId)
          .delete();

      print("✅ Memory document deleted from Firestore");
    } catch (e) {
      print('❌ Error deleting memory: $e');
      throw e;
    }
  }

  // Check Firebase Storage connectivity
  Future<bool> checkStorageConnectivity() async {
    final currentUserId = userId;
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    try {
      print("🔍 Testing Firebase Storage connectivity...");

      // Create a small in-memory file (text content)
      final List<int> bytes = utf8.encode('Connectivity test ${DateTime.now().toIso8601String()}');
      final testData = Uint8List.fromList(bytes);

      // Upload to a test location
      final testRef = _storage.ref().child('users/$currentUserId/_connectivity_test/test_${DateTime.now().millisecondsSinceEpoch}.txt');

      // Upload the data
      final uploadTask = testRef.putData(testData);
      final snapshot = await uploadTask;
      print("✅ Test data uploaded: ${snapshot.bytesTransferred} bytes");

      // Get download URL
      final downloadUrl = await testRef.getDownloadURL();
      print("✅ Storage connectivity test passed. URL: $downloadUrl");

      // Clean up - delete the test file
      await testRef.delete();
      print("✅ Test file deleted");

      return true;
    } catch (e) {
      print("❌ Storage connectivity test failed: $e");
      return false;
    }
  }
}