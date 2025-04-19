// lib/utils/config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/logger.dart';

class AppConfig {
  static const String _tag = 'AppConfig';
  static final AppConfig _instance = AppConfig._internal();

  // Singleton instance
  factory AppConfig() => _instance;

  AppConfig._internal();

  String? _openAIApiKey;

  // Initialize the config (call this at app startup)
  Future<void> initialize() async {
    Logger.info(_tag, 'Initializing app configuration');

    try {
      // Load API key from .env file
      final envKey = dotenv.env['OPENAI_API_KEY'];

      if (envKey != null && envKey.isNotEmpty) {
        Logger.info(_tag, 'OpenAI API key loaded from .env file');
        _openAIApiKey = envKey;
      } else {
        Logger.warning(_tag, 'OpenAI API key not found in .env file');
      }
    } catch (e) {
      Logger.error(_tag, 'Error initializing app config: $e');
    }
  }

  // Get the OpenAI API key
  String? get openAIApiKey => _openAIApiKey;

  // Check if the OpenAI API key is configured
  bool get isOpenAIConfigured => _openAIApiKey != null && _openAIApiKey!.isNotEmpty;
}