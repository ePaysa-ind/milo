// lib/services/env_service.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/advanced_logger.dart'; // Updated to advanced_logger

class EnvService {
  static const String _tag = 'EnvService'; // Fixed asterisk to underscore

  // Get the OpenAI API key from environment variables
  static String get openaiApiKey {
    final apiKey = dotenv.env['OPENAI_API_KEY'] ?? ''; // Fixed asterisk to underscore
    if (apiKey.isEmpty) {
      AdvancedLogger.error(_tag, 'OPENAI_API_KEY is not set in .env file');
    } else {
      AdvancedLogger.info(_tag, 'OPENAI_API_KEY loaded successfully');
    }
    return apiKey;
  }

  // Add Firebase API keys with logging
  static String get firebaseAndroidApiKey {
    final apiKey = dotenv.env['FIREBASE_ANDROID_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      AdvancedLogger.error(_tag, 'FIREBASE_ANDROID_API_KEY is not set in .env file');
    } else {
      AdvancedLogger.info(_tag, 'FIREBASE_ANDROID_API_KEY loaded successfully');
    }
    return apiKey;
  }

  static String get firebaseIosApiKey {
    final apiKey = dotenv.env['FIREBASE_IOS_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      AdvancedLogger.error(_tag, 'FIREBASE_IOS_API_KEY is not set in .env file');
    } else {
      AdvancedLogger.info(_tag, 'FIREBASE_IOS_API_KEY loaded successfully');
    }
    return apiKey;
  }
}