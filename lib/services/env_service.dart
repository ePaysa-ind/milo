// lib/services/env_service.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/logger.dart';

class EnvService {
  static const String _tag = 'EnvService';

  // Get the OpenAI API key from environment variables
  static String get openaiApiKey {
    final apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      Logger.error(_tag, 'OPENAI_API_KEY is not set in .env file');
    } else {
      Logger.info(_tag, 'OPENAI_API_KEY loaded successfully');
    }
    return apiKey;
  }
}