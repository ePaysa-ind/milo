// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Monitor authentication state - call this in main.dart
  void monitorAuthState() {
    _auth.authStateChanges().listen((User? user) {
      if (user == null) {
        print('🔴 User is currently signed out!');
      } else {
        print('🟢 User is signed in! UID: ${user.uid}, Email: ${user.email}');
      }
    });
  }

  // Sign up with email and password
  Future<UserCredential> signUpWithEmailAndPassword(
      String email, String password, String name, int age) async {
    try {
      print("📝 Attempting to create user with email: $email");

      // Create user with email and password
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Add user details to Firestore after successful account creation
      if (userCredential.user != null) {
        print("✅ User created with ID: ${userCredential.user!.uid}");

        await _firestore.collection('users').doc(userCredential.user!.uid).set({
          'name': name,
          'email': email,
          'age': age,
          'createdAt': FieldValue.serverTimestamp(),
        });
        print("✅ User profile saved to Firestore");

        // Update display name
        await userCredential.user!.updateDisplayName(name);
        print("✅ Display name updated: $name");
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      print('❌ Firebase Auth Error during sign up: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      print('❌ Error during sign up: $e');
      rethrow;
    }
  }

  // Sign in with email and password
  Future<UserCredential> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      print("🔑 Attempting to sign in user with email: $email");
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      print("✅ User signed in successfully: ${credential.user?.uid}");
      return credential;
    } on FirebaseAuthException catch (e) {
      print('❌ Firebase Auth Error during sign in: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      print('❌ Error during sign in: $e');
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      print("👋 User signed out successfully");
    } catch (e) {
      print('❌ Error during sign out: $e');
      rethrow;
    }
  }

  // Password reset
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      print("📧 Sending password reset email to: $email");
      await _auth.sendPasswordResetEmail(email: email);
      print("✅ Password reset email sent successfully");
    } on FirebaseAuthException catch (e) {
      print('❌ Firebase Auth Error sending reset email: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      print('❌ Error sending password reset email: $e');
      rethrow;
    }
  }

  // Get user profile
  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      if (currentUser != null) {
        final doc = await _firestore.collection('users').doc(currentUser!.uid).get();
        return doc.data();
      }
      return null;
    } catch (e) {
      print('❌ Error getting user profile: $e');
      rethrow;
    }
  }

  // Update user profile
  Future<void> updateUserProfile(Map<String, dynamic> data) async {
    try {
      if (currentUser != null) {
        await _firestore.collection('users').doc(currentUser!.uid).update(data);
        print("✅ User profile updated in Firestore");

        // Update display name if provided
        if (data.containsKey('name')) {
          await currentUser!.updateDisplayName(data['name']);
          print("✅ Display name updated to: ${data['name']}");
        }
      }
    } catch (e) {
      print('❌ Error updating user profile: $e');
      rethrow;
    }
  }
}