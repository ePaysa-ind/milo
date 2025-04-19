// lib/services/openai_service.dart
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../utils/advanced_logger.dart';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

// Import the TTSVoice enum from tts_service instead of defining it here
import 'tts_service.dart';

// Define custom error types for better error handling
class OpenAIServiceException implements Exception {
  final String message;
  final String code;
  final int? statusCode;
  final bool isRecoverable;

  OpenAIServiceException({
    required this.message,
    this.code = 'unknown_error',
    this.statusCode,
    this.isRecoverable = true,
  });

  @override
  String toString() => 'OpenAIServiceException: $message (Code: $code, Status: $statusCode)';
}

class OpenAIService {
  static const String _tag = 'OpenAIService';
  final String _apiKey;
  final String _baseUrl = 'https://api.openai.com/v1';
  final int _maxRetries = 3;
  final Duration _initialBackoff = Duration(seconds: 1);
  final Dio _dio = Dio(); // Initialize the Dio object

  // Create a unique session ID for tracking API calls
  final String _sessionId = _generateSessionId();

  static String _generateSessionId() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return base64Url.encode(values).substring(0, 10);
  }

  OpenAIService({required String apiKey}) : _apiKey = apiKey {
    // Set global timeout settings for Dio
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 60);
    _dio.options.sendTimeout = const Duration(seconds: 30);

    AdvancedLogger.info(_tag, 'OpenAI service initialized',
        data: {'hasApiKey': apiKey.isNotEmpty, 'sessionId': _sessionId});

    if (_apiKey.isEmpty) {
      AdvancedLogger.error(_tag, 'API key is empty! API calls will fail');
    }
  }

  // Sanitize and secure sensitive content for logging
  String _sanitizeContent(String content) {
    if (content.isEmpty) return '';

    // Limit content length for logging
    if (content.length > 150) {
      return '${content.substring(0, 75)}...${content.substring(content.length - 75)}';
    }

    // Remove potential PII
    var sanitized = content;

    // Email pattern
    final emailRegex = RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b');
    sanitized = sanitized.replaceAll(emailRegex, '[EMAIL]');

    // Phone pattern
    final phoneRegex = RegExp(r'\b(\+\d{1,2}\s?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b');
    sanitized = sanitized.replaceAll(phoneRegex, '[PHONE]');

    // Address pattern (simple)
    final addressRegex = RegExp(r'\b\d+\s+[A-Za-z]+\s+(?:Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Drive|Dr|Court|Ct|Lane|Ln|Way|Parkway|Pkwy|Place|Pl)\b', caseSensitive: false);
    sanitized = sanitized.replaceAll(addressRegex, '[ADDRESS]');

    // SSN pattern
    final ssnRegex = RegExp(r'\b\d{3}-\d{2}-\d{4}\b');
    sanitized = sanitized.replaceAll(ssnRegex, '[SSN]');

    return sanitized;
  }

  // Generic method to handle API requests with retries and error handling
  Future<dynamic> _makeApiRequest({
    required String endpoint,
    required String method,
    dynamic body,
    Map<String, String>? additionalHeaders,
    bool isMultipart = false,
    http.MultipartRequest? multipartRequest,
    bool returnRawResponse = false,
  }) async {
    int attempts = 0;
    Duration backoff = _initialBackoff;

    while (attempts < _maxRetries) {
      attempts++;
      final requestId = '${_sessionId}-${DateTime.now().millisecondsSinceEpoch}';

      try {
        AdvancedLogger.info(_tag, 'Making API request',
            data: {
              'endpoint': endpoint,
              'method': method,
              'attempt': attempts,
              'requestId': requestId,
            });

        if (isMultipart && multipartRequest != null) {
          final response = await multipartRequest.send()
              .timeout(const Duration(seconds: 30), onTimeout: () {
            throw TimeoutException('Request timed out after 30 seconds');
          });

          final responseBody = await response.stream.bytesToString();

          if (response.statusCode >= 200 && response.statusCode < 300) {
            AdvancedLogger.info(_tag, 'API request successful',
                data: {'requestId': requestId, 'statusCode': response.statusCode});
            return jsonDecode(responseBody);
          } else {
            AdvancedLogger.error(_tag, 'API request failed',
                data: {
                  'requestId': requestId,
                  'statusCode': response.statusCode,
                  'response': _sanitizeContent(responseBody),
                });

            final errorJson = _tryParseJson(responseBody);
            final errorMessage = errorJson?['error']?['message'] ?? 'Unknown error';
            final errorCode = errorJson?['error']?['code'] ?? 'unknown_error';

            // Check if we should retry based on status code
            if (_shouldRetry(response.statusCode) && attempts < _maxRetries) {
              AdvancedLogger.warning(_tag, 'Retrying request after backoff',
                  data: {'backoff': backoff.inMilliseconds, 'attempt': attempts});
              await Future.delayed(backoff);
              backoff *= 2; // Exponential backoff
              continue;
            }

            throw OpenAIServiceException(
              message: errorMessage,
              code: errorCode,
              statusCode: response.statusCode,
              isRecoverable: _isRecoverableError(response.statusCode, errorCode),
            );
          }
        } else {
          // Standard REST API request
          final url = Uri.parse('$_baseUrl/$endpoint');
          final headers = {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiKey',
            'X-Request-ID': requestId,
            ...?additionalHeaders,
          };

          http.Response response;

          switch (method.toUpperCase()) {
            case 'GET':
              response = await http.get(url, headers: headers)
                  .timeout(const Duration(seconds: 30));
              break;
            case 'POST':
              response = await http.post(url, headers: headers, body: jsonEncode(body))
                  .timeout(const Duration(seconds: 60));
              break;
            case 'PUT':
              response = await http.put(url, headers: headers, body: jsonEncode(body))
                  .timeout(const Duration(seconds: 30));
              break;
            case 'DELETE':
              response = await http.delete(url, headers: headers)
                  .timeout(const Duration(seconds: 30));
              break;
            default:
              throw OpenAIServiceException(message: 'Unsupported HTTP method: $method');
          }

          if (returnRawResponse && response.statusCode >= 200 && response.statusCode < 300) {
            return response;
          }

          if (response.statusCode >= 200 && response.statusCode < 300) {
            AdvancedLogger.info(_tag, 'API request successful',
                data: {'requestId': requestId, 'statusCode': response.statusCode});

            // Content-Type could be application/json or something else
            final contentType = response.headers['content-type'] ?? '';
            if (contentType.contains('application/json')) {
              return jsonDecode(response.body);
            } else {
              return response.body;
            }
          } else {
            AdvancedLogger.error(_tag, 'API request failed',
                data: {
                  'requestId': requestId,
                  'statusCode': response.statusCode,
                  'response': _sanitizeContent(response.body),
                });

            final errorJson = _tryParseJson(response.body);
            final errorMessage = errorJson?['error']?['message'] ?? 'Unknown error';
            final errorCode = errorJson?['error']?['code'] ?? 'unknown_error';

            // Check if we should retry based on status code
            if (_shouldRetry(response.statusCode) && attempts < _maxRetries) {
              AdvancedLogger.warning(_tag, 'Retrying request after backoff',
                  data: {'backoff': backoff.inMilliseconds, 'attempt': attempts});
              await Future.delayed(backoff);
              backoff *= 2; // Exponential backoff
              continue;
            }

            throw OpenAIServiceException(
              message: errorMessage,
              code: errorCode,
              statusCode: response.statusCode,
              isRecoverable: _isRecoverableError(response.statusCode, errorCode),
            );
          }
        }
      } on SocketException catch (e, stackTrace) {
        AdvancedLogger.error(_tag, 'Network error making API request',
            error: e,
            stackTrace: stackTrace,
            data: {
              'requestId': requestId,
              'attempt': attempts,
            });

        if (attempts < _maxRetries) {
          AdvancedLogger.warning(_tag, 'Retrying request after backoff',
              data: {'backoff': backoff.inMilliseconds, 'attempt': attempts});
          await Future.delayed(backoff);
          backoff *= 2; // Exponential backoff
          continue;
        }

        throw OpenAIServiceException(
          message: 'Network connection error: ${e.message}',
          code: 'network_error',
          isRecoverable: true,
        );
      } on TimeoutException catch (e, stackTrace) {
        AdvancedLogger.error(_tag, 'Timeout making API request',
            error: e,
            stackTrace: stackTrace,
            data: {
              'requestId': requestId,
              'attempt': attempts,
            });

        if (attempts < _maxRetries) {
          AdvancedLogger.warning(_tag, 'Retrying request after backoff',
              data: {'backoff': backoff.inMilliseconds, 'attempt': attempts});
          await Future.delayed(backoff);
          backoff *= 2; // Exponential backoff
          continue;
        }

        throw OpenAIServiceException(
          message: 'Request timed out',
          code: 'timeout',
          isRecoverable: true,
        );
      } catch (e, stackTrace) {
        final isOpenAIException = e is OpenAIServiceException;

        AdvancedLogger.error(_tag, 'Error making API request',
            error: e,
            stackTrace: stackTrace,
            data: {
              'requestId': requestId,
              'attempt': attempts,
              'isOpenAIException': isOpenAIException,
            });

        if (!isOpenAIException && attempts < _maxRetries) {
          AdvancedLogger.warning(_tag, 'Retrying request after backoff',
              data: {'backoff': backoff.inMilliseconds, 'attempt': attempts});
          await Future.delayed(backoff);
          backoff *= 2; // Exponential backoff
          continue;
        }

        if (isOpenAIException) rethrow;

        throw OpenAIServiceException(
          message: 'Unexpected error: ${e.toString()}',
          code: 'unexpected_error',
          isRecoverable: false,
        );
      }
    }

    throw OpenAIServiceException(
      message: 'API request failed after $attempts attempts',
      code: 'max_retries_exceeded',
      isRecoverable: false,
    );
  }

  // Try to parse JSON, return null if failed
  Map<String, dynamic>? _tryParseJson(String text) {
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // Determine if we should retry based on HTTP status code
  bool _shouldRetry(int statusCode) {
    // Retry on rate limiting, server errors, or certain 4xx errors
    return statusCode == 429 ||
        (statusCode >= 500 && statusCode < 600) ||
        statusCode == 408; // Request timeout
  }

  // Determine if an error is potentially recoverable
  bool _isRecoverableError(int? statusCode, String errorCode) {
    if (statusCode == null) return true;

    // Most 4xx errors are client errors and won't be fixed by retrying
    if (statusCode >= 400 && statusCode < 500) {
      // But some are recoverable
      return statusCode == 408 || statusCode == 429;
    }

    // Server errors are potentially recoverable
    if (statusCode >= 500 && statusCode < 600) {
      return true;
    }

    // Check error codes for specific cases
    final nonRecoverableCodes = [
      'invalid_api_key',
      'model_not_found',
      'content_policy_violation',
      'insufficient_quota',
    ];

    return !nonRecoverableCodes.contains(errorCode);
  }

  // Transcribe audio file from a local path
  Future<String> transcribeAudio(String filePath) async {
    AdvancedLogger.info(_tag, 'Starting audio transcription',
        data: {'filePath': filePath});

    try {
      final url = Uri.parse('$_baseUrl/audio/transcriptions');
      final request = http.MultipartRequest('POST', url);

      request.headers.addAll({
        'Authorization': 'Bearer $_apiKey',
        'X-Request-ID': '${_sessionId}-${DateTime.now().millisecondsSinceEpoch}',
      });

      request.fields['model'] = 'whisper-1';
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      final response = await _makeApiRequest(
        endpoint: 'audio/transcriptions',
        method: 'POST',
        isMultipart: true,
        multipartRequest: request,
      );

      final transcription = response['text'] as String;

      // Check for potential background noise issues
      if (_isLikelyBackgroundNoise(transcription)) {
        AdvancedLogger.warning(_tag, 'Possible background noise detected in transcription',
            data: {'transcription': _sanitizeContent(transcription)});
      }

      AdvancedLogger.info(_tag, 'Transcription completed successfully',
          data: {'contentLength': transcription.length});

      return transcription;
    } catch (e) {
      if (e is OpenAIServiceException) {
        rethrow;
      }

      AdvancedLogger.error(_tag, 'Error transcribing audio', error: e);
      throw OpenAIServiceException(
          message: 'Failed to transcribe audio: ${e.toString()}',
          code: 'transcription_error'
      );
    }
  }

  // NEW METHOD: Transcribe audio from a File object
  Future<String> transcribeAudioFromFile(File audioFile) async {
    AdvancedLogger.info(_tag, 'Starting audio transcription from File object',
        data: {'filePath': audioFile.path});

    try {
      // Verify the file exists
      if (!(await audioFile.exists())) {
        AdvancedLogger.error(_tag, 'Audio file does not exist',
            data: {'filePath': audioFile.path});

        throw OpenAIServiceException(
          message: 'Audio file does not exist',
          code: 'file_not_found',
          isRecoverable: false,
        );
      }

      // Check file extension to ensure it's a supported format
      final String fileExtension = audioFile.path.split('.').last.toLowerCase();
      final List<String> supportedFormats = ['flac', 'm4a', 'mp3', 'mp4', 'mpeg', 'mpga', 'oga', 'ogg', 'wav', 'webm', 'aac'];

      if (!supportedFormats.contains(fileExtension)) {
        AdvancedLogger.error(_tag, 'Invalid file format',
            data: {'format': fileExtension, 'supportedFormats': supportedFormats.join(', ')});

        throw OpenAIServiceException(
          message: 'Invalid file format. Supported formats: ${supportedFormats.join(", ")}',
          code: 'invalid_file_format',
          isRecoverable: false,
        );
      }

      // Check file size
      final fileSize = await audioFile.length();
      if (fileSize > 25 * 1024 * 1024) { // OpenAI has a 25MB limit
        AdvancedLogger.error(_tag, 'File size exceeds OpenAI limit',
            data: {'fileSize': fileSize, 'maxSize': 25 * 1024 * 1024});

        throw OpenAIServiceException(
          message: 'File size exceeds the 25MB limit',
          code: 'file_too_large',
          isRecoverable: false,
        );
      }

      // Use the existing transcribeAudio method as it already handles the rest of the logic
      return await transcribeAudio(audioFile.path);
    } catch (e) {
      if (e is OpenAIServiceException) {
        rethrow;
      }

      AdvancedLogger.error(_tag, 'Error transcribing audio from File', error: e);
      throw OpenAIServiceException(
        message: 'Failed to transcribe audio file: ${e.toString()}',
        code: 'file_transcription_error',
      );
    }
  }

  // Check if transcription likely contains background noise
  bool _isLikelyBackgroundNoise(String transcription) {
    if (transcription.isEmpty) return false;

    // Check for typical background noise patterns
    final noisePatterns = [
      RegExp(r'\b(um+|uh+|hmm+|aah+|uhh+)\b', caseSensitive: false),
      RegExp(r'\b(background noise|static|silence|inaudible)\b', caseSensitive: false),
      RegExp(r'\.{3,}'),  // Ellipses indicating pauses or unclear speech
    ];

    int noiseMatches = 0;
    for (final pattern in noisePatterns) {
      if (pattern.hasMatch(transcription)) {
        noiseMatches++;
      }
    }

    // Check for very short transcriptions
    if (transcription.length < 10 && noiseMatches > 0) {
      return true;
    }

    // Check for high ratio of noise indicators to content
    final words = transcription.split(' ').length;
    if (words > 0 && noiseMatches / words > 0.3) {
      return true;
    }

    return false;
  }

  // Transcribe audio file from a URL
  Future<String> transcribeAudioFromUrl(String url) async {
    AdvancedLogger.info(_tag, 'Starting transcription from URL',
        data: {'urlLength': url.length});

    try {
      // Download the file to a temporary location
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Audio download timed out');
        },
      );

      if (response.statusCode != 200) {
        AdvancedLogger.error(_tag, 'Failed to download audio file',
            data: {'statusCode': response.statusCode});

        throw OpenAIServiceException(
          message: 'Failed to download audio file: ${response.statusCode}',
          code: 'download_error',
          statusCode: response.statusCode,
        );
      }

      final tempDir = await getTemporaryDirectory();
      final tempFilePath = '${tempDir.path}/temp_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

      AdvancedLogger.info(_tag, 'Saving temporary file',
          data: {'tempFilePath': tempFilePath});

      await File(tempFilePath).writeAsBytes(response.bodyBytes);

      // Transcribe the downloaded file
      final transcription = await transcribeAudio(tempFilePath);

      // Clean up the temporary file
      AdvancedLogger.info(_tag, 'Cleaning up temporary file');
      await File(tempFilePath).delete();

      return transcription;
    } catch (e) {
      if (e is OpenAIServiceException) {
        rethrow;
      }

      AdvancedLogger.error(_tag, 'Error transcribing audio from URL', error: e);
      throw OpenAIServiceException(
        message: 'Failed to transcribe audio from URL: ${e.toString()}',
        code: 'url_transcription_error',
      );
    }
  }

  // Summarize text using GPT-4
  Future<String> summarizeText(String text) async {
    AdvancedLogger.info(_tag, 'Starting text summarization',
        data: {'textLength': text.length, 'contentPreview': _sanitizeContent(text)});

    try {
      final sanitizedText = _sanitizeContent(text);
      final payload = {
        'model': 'gpt-4',
        'messages': [
          {
            'role': 'system',
            'content': 'You are a helpful assistant that summarizes content. Create a concise summary of the following text.'
          },
          {
            'role': 'user',
            'content': sanitizedText,
          },
        ],
        'temperature': 0.7,
        'max_tokens': 500,
      };

      final response = await _makeApiRequest(
        endpoint: 'chat/completions',
        method: 'POST',
        body: payload,
      );

      final summary = response['choices'][0]['message']['content'];
      AdvancedLogger.info(_tag, 'Summarization completed successfully',
          data: {'summaryLength': summary.length});

      return summary;
    } catch (e) {
      if (e is OpenAIServiceException) {
        rethrow;
      }

      AdvancedLogger.error(_tag, 'Error summarizing text', error: e);
      throw OpenAIServiceException(
        message: 'Failed to summarize text: ${e.toString()}',
        code: 'summarization_error',
      );
    }
  }

  // Get a conversational response from GPT-4
  Future<String> chatWithGPT({
    required String prompt,
    required List<Map<String, String>> conversation,
  }) async {
    AdvancedLogger.info(_tag, 'Starting chat with GPT',
        data: {
          'promptLength': prompt.length,
          'conversationCount': conversation.length,
          'promptPreview': _sanitizeContent(prompt),
        });

    try {
      final messages = [
        {
          'role': 'system',
          'content': 'You are Milo, a helpful assistant for elderly users who helps them recall and explore their memories. '
              'Respond in a friendly, concise manner that is easy to understand. '
              'Prioritize user privacy and never retain or share personal information. '
              'If you detect potentially harmful or sensitive content, acknowledge it respectfully and offer support. '
              'Format your responses with clear paragraphs and use simple language.'
        },
      ];

      // Add conversation history
      for (final message in conversation) {
        messages.add({
          'role': message['role']!,
          'content': message['content']!,
        });
      }

      final payload = {
        'model': 'gpt-4',
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 800,
      };

      final response = await _makeApiRequest(
        endpoint: 'chat/completions',
        method: 'POST',
        body: payload,
      );

      final reply = response['choices'][0]['message']['content'];
      AdvancedLogger.info(_tag, 'Chat response received successfully',
          data: {'replyLength': reply.length});

      return reply;
    } catch (e) {
      if (e is OpenAIServiceException) {
        rethrow;
      }

      AdvancedLogger.error(_tag, 'Error chatting with GPT', error: e);
      throw OpenAIServiceException(
        message: 'Failed to get response from GPT: ${e.toString()}',
        code: 'chat_error',
      );
    }
  }

  // Enhanced story generation with better prompts and customization
  Future<String> generateStoryFromMemory({
    required String transcription,
    String sentiment = 'neutral',
    String? tone,
    String? theme,
    String? style,
    int? minLength,
    int? maxLength,
  }) async {
    AdvancedLogger.info(_tag, 'Generating story from memory',
        data: {
          'transcriptionLength': transcription.length,
          'sentiment': sentiment,
          'tone': tone,
          'theme': theme,
          'style': style,
        });

    try {
      final sanitizedTranscription = _sanitizeContent(transcription);

      // Determine story prompt based on sentiment and customization
      String systemPrompt = 'You are a skilled storyteller creating personalized stories from memories. ';

      // Add specific tone instructions
      if (tone != null && tone.isNotEmpty) {
        systemPrompt += 'Your story should have a $tone tone. ';
      } else {
        // Default tone based on sentiment
        switch (sentiment.toLowerCase()) {
          case 'positive':
            systemPrompt += 'Your story should have a warm, uplifting tone. ';
            break;
          case 'negative':
            systemPrompt += 'Your story should have a reflective, hopeful tone. ';
            break;
          default:
            systemPrompt += 'Your story should have a thoughtful, engaging tone. ';
        }
      }

      // Add theme instructions
      if (theme != null && theme.isNotEmpty) {
        systemPrompt += 'The theme should focus on $theme. ';
      }

      // Add style instructions
      if (style != null && style.isNotEmpty) {
        systemPrompt += 'Write in the style of $style. ';
      }

      // Add length instructions
      if (minLength != null && maxLength != null) {
        systemPrompt += 'The story should be between $minLength and $maxLength words. ';
      } else if (maxLength != null) {
        systemPrompt += 'The story should be at most $maxLength words. ';
      } else if (minLength != null) {
        systemPrompt += 'The story should be at least $minLength words. ';
      } else {
        // Default length guidance
        systemPrompt += 'The story should be 300-500 words. ';
      }

      // Format guidelines
      systemPrompt += 'Use clear paragraphs, simple language, and engaging narrative. '
          'For elderly users, prioritize readability with good spacing between paragraphs.';

      // Craft the user prompt based on sentiment
      String userPrompt;
      if (sentiment.toLowerCase() == 'positive') {
        userPrompt = 'Create a heartwarming, uplifting story based on this memory. Enhance and celebrate the joyful aspects: $sanitizedTranscription';
      } else if (sentiment.toLowerCase() == 'negative') {
        userPrompt = 'Create a thoughtful, gently uplifting story based on this memory. While acknowledging any difficult emotions, help find meaning, hope, or wisdom in the experience: $sanitizedTranscription';
      } else {
        userPrompt = 'Create an engaging, reflective story based on this memory, highlighting its significance and personal meaning: $sanitizedTranscription';
      }

      final messages = [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ];

      final payload = {
        'model': 'gpt-4',
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 1000,
      };

      final response = await _makeApiRequest(
        endpoint: 'chat/completions',
        method: 'POST',
        body: payload,
      );

      final story = response['choices'][0]['message']['content'];

      AdvancedLogger.info(_tag, 'Story generation completed successfully',
          data: {'storyLength': story.length});

      return story;
    } catch (e) {
      if (e is OpenAIServiceException) {
        rethrow;
      }

      AdvancedLogger.error(_tag, 'Error generating story from memory', error: e);
      throw OpenAIServiceException(
        message: 'Failed to generate story: ${e.toString()}',
        code: 'story_generation_error',
      );
    }
  }

  // Analyze sentiment of text
  Future<String> analyzeSentiment(String text) async {
    AdvancedLogger.info(_tag, 'Analyzing sentiment',
        data: {'textLength': text.length});

    try {
      final sanitizedText = _sanitizeContent(text);
      final promptText = 'Analyze the emotional tone of this text and respond with exactly one word: "positive", "negative", or "neutral". Text: $sanitizedText';

      final payload = {
        'model': 'gpt-4',
        'messages': [
          {'role': 'system', 'content': 'You are a sentiment analysis assistant that responds with only a single word.'},
          {'role': 'user', 'content': promptText},
        ],
        'temperature': 0.1,
        'max_tokens': 20,
      };

      final response = await _makeApiRequest(
        endpoint: 'chat/completions',
        method: 'POST',
        body: payload,
      );

      final sentiment = response['choices'][0]['message']['content'].toLowerCase().trim();

      // Normalize the response
      String normalizedSentiment;
      if (sentiment.contains('positive')) {
        normalizedSentiment = 'positive';
      } else if (sentiment.contains('negative')) {
        normalizedSentiment = 'negative';
      } else {
        normalizedSentiment = 'neutral';
      }

      AdvancedLogger.info(_tag, 'Sentiment analysis completed',
          data: {'sentiment': normalizedSentiment});

      return normalizedSentiment;
    } catch (e) {
      if (e is OpenAIServiceException) {
        rethrow;
      }

      AdvancedLogger.error(_tag, 'Error analyzing sentiment', error: e);
      throw OpenAIServiceException(
        message: 'Failed to analyze sentiment: ${e.toString()}',
        code: 'sentiment_analysis_error',
      );
    }
  }

  // Improved TTS with better error handling and fallbacks
  Future<File?> textToSpeech(String text, {
    TTSVoice voice = TTSVoice.alloy,
    double? speed,
    bool useAdvancedModel = true,
  }) async {
    try {
      AdvancedLogger.info(_tag, 'Starting text-to-speech conversion',
          data: {'textLength': text.length, 'voice': voice.value});

      // Create a temporary file to save the audio
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${directory.path}/tts_${timestamp}.mp3';

      // Create payload for the API request
      final Map<String, dynamic> payload = {
        'model': useAdvancedModel ? 'tts-1' : 'tts-1-hd',
        'input': text,
        'voice': voice.value,
      };

      // Fix: Convert double to String for the speed parameter
      if (speed != null) {
        // Convert the double to a string to ensure proper typing
        payload['speed'] = speed.toString();
        AdvancedLogger.info(_tag, 'Setting TTS speed', data: {'speed': speed});
      }

      // Make API request to OpenAI TTS endpoint
      final response = await _dio.post(
        '$_baseUrl/audio/speech',
        options: Options(
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.bytes,
        ),
        data: payload,
      );

      // Save the audio data to a file
      if (response.statusCode == 200 && response.data != null) {
        final file = File(filePath);
        await file.writeAsBytes(response.data);

        AdvancedLogger.info(_tag, 'Text-to-speech conversion successful',
            data: {'filePath': filePath, 'fileSize': response.data.length});

        return file;
      } else {
        AdvancedLogger.error(_tag, 'Error in TTS API response',
            data: {'statusCode': response.statusCode});
        return null;
      }
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error in text-to-speech conversion',
          error: e, stackTrace: stackTrace);

      if (e is DioException) {
        final dioError = e;
        AdvancedLogger.error(_tag, 'Dio error details',
            data: {
              'type': dioError.type.toString(),
              'statusCode': dioError.response?.statusCode,
              'responseMessage': dioError.response?.statusMessage,
            });
      }

      throw OpenAIServiceException(
        message: 'Failed to convert text to speech: ${e.toString()}',
        code: e is DioException && e.type == DioExceptionType.connectionTimeout
            ? 'timeout'
            : 'api_error',
      );
    }
  }
}