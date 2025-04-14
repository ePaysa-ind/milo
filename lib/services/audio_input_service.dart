import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

class AudioInputService {
  // For recording
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecorderInitialized = false;

  // For speech recognition
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechInitialized = false;

  // Initialize
  Future<void> init() async {
    // Request permissions
    await [Permission.microphone, Permission.storage].request();

    // Initialize recorder
    await _recorder.openRecorder();
    _isRecorderInitialized = true;

    // Initialize speech recognition
    _speechInitialized = await _speech.initialize();
  }

  // Start recording audio
  Future<String> startRecording() async {
    if (!_isRecorderInitialized) {
      await init();
    }

    final directory = await getTemporaryDirectory();
    final filePath = '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.startRecorder(
      toFile: filePath,
      codec: Codec.aacMP4,
    );

    return filePath;
  }

  // Stop recording and return file path
  Future<String> stopRecording() async {
    final filePath = await _recorder.stopRecorder();
    return filePath ?? '';
  }

  // Dispose resources
  void dispose() {
    _recorder.closeRecorder();
    _isRecorderInitialized = false;
  }

  // Speech to text function (alternative to direct recording)
  Future<void> startListening(Function(String) onResult) async {
    if (!_speechInitialized) {
      await init();
    }

    await _speech.listen(
      onResult: (result) {
        onResult(result.recognizedWords);
      },
      listenFor: Duration(seconds: 30),
      pauseFor: Duration(seconds: 5),
      partialResults: true,
      localeId: 'en_US',
      onSoundLevelChange: (level) {
        // You can use this to provide visual feedback
      },
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }
}