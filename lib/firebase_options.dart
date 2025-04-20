// File: lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:milo/services/env_service.dart';

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

  // Remove 'const' and make it a getter
  static FirebaseOptions get android => FirebaseOptions(
    apiKey: EnvService.firebaseAndroidApiKey,
    appId: '1:925078103220:android:38beefe44fb436f5f723e1',
    messagingSenderId: '925078103220',
    projectId: 'milo-9bb6e',
    storageBucket: 'milo-9bb6e.firebasestorage.app',
  );

  // Remove 'const' and make it a getter
  static FirebaseOptions get ios => FirebaseOptions(
    apiKey: EnvService.firebaseIosApiKey,
    appId: '1:925078103220:ios:77039b5af45e160ef723e1',
    messagingSenderId: '925078103220',
    projectId: 'milo-9bb6e',
    storageBucket: 'milo-9bb6e.firebasestorage.app',
  );
}