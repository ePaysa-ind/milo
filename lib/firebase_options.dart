// File: lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

/// Default Firebase configuration options for the app
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDEUGWcBIJwsZahiJignkpt-qAh2V_DI_I',
    appId: '1:925078103220:android:38beefe44fb436f5f723e1',  // Use the value from your google-services.json
    messagingSenderId: '925078103220',  // Use the project_number from google-services.json
    projectId: 'milo-9bb6e',  // Use your Firebase project ID
    storageBucket: 'milo-9bb6e.firebasestorage.app',  // Your Firebase storage bucket
  );

  //google service info plist
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBlBCcd7A40vet8E32RmQwpDwXnVF05v3c',
    appId: '1:925078103220:ios:77039b5af45e160ef723e1',
    messagingSenderId: '925078103220',  // Same as Android
    projectId: 'milo-9bb6e',  // Same as Android
    storageBucket: 'milo-9bb6e.firebasestorage.app',  // Same as Android
  );
}