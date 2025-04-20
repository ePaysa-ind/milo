// lib/services/tts_service.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../services/openai_service.dart';
import '../utils/advanced_logger.dart';

enum TTSStatus {
  idle,
  loading,
  playing,
  error,
  stopped,
  completed,
}

// Available TTS voices
enum TTSVoice {
  alloy,
  echo,
  fable,
  onyx,
  nova,
  shimmer,
}

// Extension to get string value for OpenAI API
extension TTSVoiceValue on TTSVoice {
  String get value {
    switch (this) {
      case TTSVoice.alloy:
        return 'alloy';
      case TTSVoice.echo:
        return 'echo';
      case TTSVoice.fable:
        return 'fable';
      case TTSVoice.onyx:
        return 'onyx';
      case TTSVoice.nova:
        return 'nova';
      case TTSVoice.shimmer:
        return 'shimmer';
    }
  }
}

// Custom exception for TTS service
class TTSException implements Exception {
  final String message;
  final String code;
  final Object? originalError;

  TTSException({
    required this.message,
    this.code = 'unknown_error',
    this.originalError,
  });

  @override
  String toString() => 'TTSException: $message (Code: $code)';
}

// TTS service with fallback mechanisms
class TTSService {
  static const String _tag = 'TTSService';

  // External services
  final OpenAIService _openAIService;

  // Internal state
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  TTSStatus _status = TTSStatus.idle;
  File? _lastAudioFile;
  String? _lastText;
  bool _preferDeviceTTS = false;
  bool _isFlutterTTSInitialized = false;

  // Track failed attempts
  int _failedCloudTTSAttempts = 0;
  static const int _maxFailedAttempts = 3;

  // Public properties
  TTSStatus get status => _status;
  bool get isPlaying => _status == TTSStatus.playing;
  bool get isLoading => _status == TTSStatus.loading;
  String? get lastText => _lastText;
  bool get cloudTTSAvailable => _openAIService.isTTSEnabled;

  // Event listeners
  final ValueNotifier<TTSStatus> statusNotifier = ValueNotifier(TTSStatus.idle);

  // Constructor
  TTSService({required OpenAIService openAIService}) : _openAIService = openAIService {
    _initializeFlutterTTS();
    _listenToAudioPlayerEvents();
    AdvancedLogger.info(_tag, 'TTS Service initialized');
  }

  // Initialize device TTS
  Future<void> _initializeFlutterTTS() async {
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5); // Slightly slower for elderly users
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _flutterTts.setCompletionHandler(() {
        _setStatus(TTSStatus.completed);
        AdvancedLogger.info(_tag, 'Flutter TTS playback completed');
      });

      _flutterTts.setErrorHandler((error) {
        AdvancedLogger.error(_tag, 'Flutter TTS error', error: error);
        _setStatus(TTSStatus.error);
      });

      // Check available engines
      try {
        final engines = await _flutterTts.getEngines;
        if (engines.isEmpty) {
          AdvancedLogger.warning(_tag, 'No TTS engines available on device');
        } else {
          AdvancedLogger.info(_tag, 'Flutter TTS engines available', data: {'engines': engines});
        }
      } catch (e) {
        AdvancedLogger.warning(_tag, 'Unable to query TTS engines', error: e);
      }

      // Check available voices
      try {
        final voices = await _flutterTts.getVoices;
        AdvancedLogger.info(_tag, 'Flutter TTS voices available', data: {'voicesCount': voices.length});
      } catch (e) {
        AdvancedLogger.warning(_tag, 'Unable to query TTS voices', error: e);
      }

      _isFlutterTTSInitialized = true;
      AdvancedLogger.info(_tag, 'Flutter TTS initialized successfully');
    } catch (e, stackTrace) {
      _isFlutterTTSInitialized = false;
      AdvancedLogger.error(_tag, 'Error initializing Flutter TTS',
          error: e, stackTrace: stackTrace);
    }
  }

  // Set up audio player event listeners
  void _listenToAudioPlayerEvents() {
    try {
      _audioPlayer.onPlayerComplete.listen((_) {
        _setStatus(TTSStatus.completed);
        AdvancedLogger.info(_tag, 'Audio player playback completed');
      });

      _audioPlayer.onPlayerStateChanged.listen((state) {
        AdvancedLogger.info(_tag, 'Audio player state changed', data: {'state': state.toString()});

        if (state == PlayerState.playing) {
          _setStatus(TTSStatus.playing);
        } else if (state == PlayerState.stopped) {
          _setStatus(TTSStatus.stopped);
        }
      });

      // Listen for play exceptions by setting up error handling during play operations
      // Note: We're not using direct event listener for errors since it's not available in this version
      AdvancedLogger.info(_tag, 'Audio player listeners set up successfully');
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error setting up audio player listeners',
          error: e, stackTrace: stackTrace);
    }
  }

  // Update status and notify listeners
  void _setStatus(TTSStatus status) {
    _status = status;
    statusNotifier.value = status;
    AdvancedLogger.info(_tag, 'TTS status changed', data: {'status': status.toString()});
  }

  // Speak text using OpenAI TTS or device fallback
  Future<void> speakText(String text, {
    TTSVoice voice = TTSVoice.alloy,
    double? speed,
    bool forceDeviceTTS = false,
    bool useCache = true,
  }) async {
    if (text.isEmpty) {
      AdvancedLogger.warning(_tag, 'Attempted to speak empty text');
      return;
    }

    // Stop any ongoing speech
    await stop();

    _lastText = text;
    _setStatus(TTSStatus.loading);

    try {
      // Check if OpenAI TTS is globally disabled
      final isOpenAITTSAvailable = _openAIService.isTTSEnabled;

      // Determine whether to use device TTS or OpenAI TTS
      if (forceDeviceTTS || _preferDeviceTTS || !isOpenAITTSAvailable || _failedCloudTTSAttempts >= _maxFailedAttempts) {
        AdvancedLogger.info(_tag, 'Using device TTS',
            data: {
              'reason': forceDeviceTTS ? 'forced' :
              _preferDeviceTTS ? 'preferred' :
              !isOpenAITTSAvailable ? 'cloud unavailable' :
              'too many failures',
              'failedAttempts': _failedCloudTTSAttempts,
            });
        await _speakWithDeviceTTS(text, speed: speed);
      } else {
        // Try OpenAI TTS first, fall back to device TTS if needed
        final success = await _speakWithOpenAITTS(text, voice: voice, speed: speed, useCache: useCache);

        if (!success) {
          AdvancedLogger.info(_tag, 'Falling back to device TTS after OpenAI TTS failure');

          // Increment failed attempts counter
          _failedCloudTTSAttempts++;
          AdvancedLogger.warning(_tag, 'Cloud TTS failure count increased',
              data: {'count': _failedCloudTTSAttempts, 'max': _maxFailedAttempts});

          // If we've reached max failed attempts, log a more severe warning
          if (_failedCloudTTSAttempts >= _maxFailedAttempts) {
            AdvancedLogger.warning(_tag, 'Cloud TTS temporarily disabled due to repeated failures');
          }

          await _speakWithDeviceTTS(text, speed: speed);
        } else {
          // Reset failed attempts counter on success
          if (_failedCloudTTSAttempts > 0) {
            _failedCloudTTSAttempts = 0;
            AdvancedLogger.info(_tag, 'Cloud TTS failure count reset after successful request');
          }
        }
      }
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error speaking text',
          error: e, stackTrace: stackTrace);
      _setStatus(TTSStatus.error);

      // Try device TTS as last resort
      try {
        AdvancedLogger.info(_tag, 'Attempting last-resort device TTS after error');
        await _speakWithDeviceTTS(text, speed: speed);
      } catch (e, stackTrace) {
        AdvancedLogger.error(_tag, 'Failed to speak text with any method',
            error: e, stackTrace: stackTrace);
        _setStatus(TTSStatus.error);

        // Provide haptic feedback as error indication
        try {
          HapticFeedback.vibrate();
        } catch (hapticError) {
          AdvancedLogger.warning(_tag, 'Failed to provide haptic feedback', error: hapticError);
        }
      }
    }
  }

  // Speak with OpenAI TTS
  Future<bool> _speakWithOpenAITTS(String text, {
    TTSVoice voice = TTSVoice.alloy,
    double? speed,
    bool useCache = true,
  }) async {
    try {
      AdvancedLogger.info(_tag, 'Speaking with OpenAI TTS',
          data: {'textLength': text.length, 'voice': voice.value});

      // Check if we have a cached file for this text
      if (useCache && _lastAudioFile != null && _lastText == text) {
        AdvancedLogger.info(_tag, 'Using cached audio file');

        if (!await _lastAudioFile!.exists()) {
          AdvancedLogger.warning(_tag, 'Cached audio file no longer exists',
              data: {'path': _lastAudioFile!.path});
          return false;
        }

        try {
          await _audioPlayer.play(DeviceFileSource(_lastAudioFile!.path));
          return true;
        } catch (e, stackTrace) {
          AdvancedLogger.error(_tag, 'Error playing cached audio file',
              error: e, stackTrace: stackTrace);
          return false;
        }
      }

      // Generate new TTS audio - UPDATED PARAMETER NAME
      final audioFile = await _openAIService.textToSpeech(
        text,
        voice: voice,
        speed: speed,
        useHighQuality: true,  // Updated parameter name
      );

      if (audioFile == null) {
        AdvancedLogger.warning(_tag, 'OpenAI TTS returned null file');
        return false;
      }

      _lastAudioFile = audioFile;

      // Log file info
      AdvancedLogger.info(_tag, 'OpenAI TTS audio file generated',
          data: {'path': audioFile.path, 'size': await audioFile.length()});

      // Play the audio file with error handling
      try {
        await _audioPlayer.play(DeviceFileSource(audioFile.path));
        return true;
      } catch (e, stackTrace) {
        AdvancedLogger.error(_tag, 'Error playing generated audio file',
            error: e, stackTrace: stackTrace);
        _setStatus(TTSStatus.error);
        return false;
      }
    } on OpenAIServiceException catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'OpenAI Service Exception',
          error: e, stackTrace: stackTrace,
          data: {'code': e.code, 'recoverable': e.isRecoverable});

      // Special handling for TTS not available exception
      if (e.code == 'tts_not_available') {
        AdvancedLogger.error(_tag, 'TTS feature not available with current API key configuration');
        // Permanently set preference to device TTS
        _preferDeviceTTS = true;
      }

      return false;
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error with OpenAI TTS',
          error: e, stackTrace: stackTrace);
      return false;
    }
  }

  // Speak with device TTS
  Future<void> _speakWithDeviceTTS(String text, {double? speed}) async {
    try {
      AdvancedLogger.info(_tag, 'Speaking with device TTS',
          data: {'textLength': text.length, 'speed': speed});

      // Check if Flutter TTS is initialized
      if (!_isFlutterTTSInitialized) {
        AdvancedLogger.warning(_tag, 'Flutter TTS not initialized, attempting to initialize');
        await _initializeFlutterTTS();

        if (!_isFlutterTTSInitialized) {
          throw TTSException(
              message: 'Device TTS is not available or initialized',
              code: 'device_tts_init_error'
          );
        }
      }

      if (speed != null) {
        await _flutterTts.setSpeechRate(speed);
      }

      final result = await _flutterTts.speak(text);

      if (result != 1) {
        AdvancedLogger.error(_tag, 'Device TTS failed to start', data: {'result': result});
        throw TTSException(message: 'Device TTS failed to start', code: 'device_tts_error');
      }

      _setStatus(TTSStatus.playing);
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error with device TTS',
          error: e, stackTrace: stackTrace);
      _setStatus(TTSStatus.error);
      throw TTSException(
          message: 'Failed to use device TTS: ${e.toString()}',
          code: 'device_tts_error',
          originalError: e
      );
    }
  }

  // Stop any ongoing speech
  Future<void> stop() async {
    if (_status == TTSStatus.playing || _status == TTSStatus.loading) {
      AdvancedLogger.info(_tag, 'Stopping TTS playback');

      try {
        // Stop both TTS engines
        await _audioPlayer.stop();
        await _flutterTts.stop();

        _setStatus(TTSStatus.stopped);
      } catch (e, stackTrace) {
        AdvancedLogger.error(_tag, 'Error stopping TTS playback',
            error: e, stackTrace: stackTrace);
        // Still set status to stopped since we attempted to stop
        _setStatus(TTSStatus.stopped);
      }
    }
  }

  // Pause speech
  Future<void> pause() async {
    if (_status == TTSStatus.playing) {
      AdvancedLogger.info(_tag, 'Pausing TTS playback');

      try {
        await _audioPlayer.pause();
        if (_isFlutterTTSInitialized) {
          await _flutterTts.pause();
        }

        _setStatus(TTSStatus.stopped);
      } catch (e, stackTrace) {
        AdvancedLogger.error(_tag, 'Error pausing TTS playback',
            error: e, stackTrace: stackTrace);
      }
    }
  }

  // Resume speech
  Future<void> resume() async {
    if (_status == TTSStatus.stopped) {
      AdvancedLogger.info(_tag, 'Resuming TTS playback');

      try {
        // Try to resume the appropriate player
        if (_lastAudioFile != null && await _lastAudioFile!.exists()) {
          await _audioPlayer.resume();
          _setStatus(TTSStatus.playing);
        } else if (_isFlutterTTSInitialized && _lastText != null && _lastText!.isNotEmpty) {
          // Flutter TTS doesn't have a resume method, so we need to re-speak the text
          // This is a workaround for the missing 'resume' method
          AdvancedLogger.info(_tag, 'Flutter TTS does not support resume, re-speaking from start');
          await _flutterTts.speak(_lastText!);
          _setStatus(TTSStatus.playing);
        } else {
          AdvancedLogger.warning(_tag, 'Cannot resume TTS, no audio source available');
        }
      } catch (e, stackTrace) {
        AdvancedLogger.error(_tag, 'Error resuming TTS playback',
            error: e, stackTrace: stackTrace);
        _setStatus(TTSStatus.error);
      }
    }
  }

  // Set preference for device TTS
  void setPreferDeviceTTS(bool prefer) {
    _preferDeviceTTS = prefer;
    AdvancedLogger.info(_tag, 'TTS preference updated', data: {'preferDeviceTTS': prefer});
  }

  // Reset failed attempts counter - useful if you want to retry cloud TTS after errors
  void resetFailedAttemptsCounter() {
    _failedCloudTTSAttempts = 0;
    AdvancedLogger.info(_tag, 'Cloud TTS failed attempts counter reset manually');
  }

  // Check if device TTS is available
  Future<bool> isDeviceTTSAvailable() async {
    try {
      if (!_isFlutterTTSInitialized) {
        await _initializeFlutterTTS();
      }

      final engines = await _flutterTts.getEngines;
      return engines.isNotEmpty;
    } catch (e) {
      AdvancedLogger.error(_tag, 'Error checking device TTS availability', error: e);
      return false;
    }
  }

  // Clean up resources
  Future<void> dispose() async {
    AdvancedLogger.info(_tag, 'Disposing TTS service');

    try {
      await stop();
      await _audioPlayer.dispose();
      if (_isFlutterTTSInitialized) {
        await _flutterTts.stop();
      }

      statusNotifier.dispose();
    } catch (e, stackTrace) {
      AdvancedLogger.error(_tag, 'Error disposing TTS service',
          error: e, stackTrace: stackTrace);
    }
  }

  // Create an error message for users
  String createUserFriendlyErrorMessage(dynamic error) {
    if (error is OpenAIServiceException) {
      switch (error.code) {
        case 'tts_not_available':
          return 'The cloud voice service is not available with your current API settings. Using your device\'s built-in voice instead.';
        case 'model_not_found':
          return 'The text-to-speech service is temporarily unavailable. Using your device\'s built-in voice instead.';
        case 'network_error':
          return 'Unable to connect to the text-to-speech service. Please check your internet connection.';
        case 'timeout':
          return 'The text-to-speech request timed out. Please try again.';
        case 'rate_limit_exceeded':
          return 'The text-to-speech service is currently busy. Please try again in a few moments.';
        case 'invalid_request':
          return 'There was an issue with the text-to-speech request. Using your device\'s built-in voice instead.';
        case 'all_models_failed':
          return 'All available voice models failed. Using your device\'s built-in voice instead.';
        default:
          return 'There was a problem with the text-to-speech service. Using your device\'s voice instead.';
      }
    } else if (error is TTSException) {
      switch (error.code) {
        case 'device_tts_init_error':
          return 'Your device\'s text-to-speech capability couldn\'t be initialized. Please check your device settings.';
        case 'device_tts_error':
          return 'There was a problem with your device\'s text-to-speech feature. Please check your device settings.';
        default:
          return 'There was a problem with the text-to-speech service. Please try again later.';
      }
    } else if (error is Exception) {
      return 'An unexpected error occurred with the text-to-speech feature. Please try again later.';
    }

    return 'An unexpected error occurred with the text-to-speech feature.';
  }
}