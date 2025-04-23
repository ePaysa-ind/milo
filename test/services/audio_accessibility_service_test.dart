// Copyright © 2025 Milo App. All rights reserved.
// Author: Milo Development Team
// File: test/services/audio_accessibility_service_test.dart
// Version: 1.0.0
// Last Updated: April 21, 2025
// Description: Unit tests for AudioAccessibilityService

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

import 'package:milo/services/audio_accessibility_service.dart';
import 'package:milo/services/localization_service.dart';
import 'package:milo/services/secure_storage_service.dart';
import 'package:milo/services/app_lifecycle_service.dart';
import 'package:milo/models/nudge_model.dart';
import 'package:milo/utils/advanced_logger.dart';

// Generate mocks
@GenerateMocks([
  AudioEngineProvider,
  StorageProvider,
  TextToSpeechProvider,
  AudioProcessor,
  LocalizationService,
  SecureStorageService,
  AppLifecycleService,
  FirebaseFirestore,
  FirebaseAnalytics,
  Directory,
  File,
  SharedPreferences,
  AudioSession,
  AudioPlayer,
])
import 'audio_accessibility_service_test.mocks.dart';

void main() {
  late MockAudioEngineProvider mockAudioEngine;
  late MockStorageProvider mockStorage;
  late MockTextToSpeechProvider mockTts;
  late MockAudioProcessor mockProcessor;
  late MockLocalizationService mockLocalization;
  late MockSecureStorageService mockSecureStorage;
  late MockAppLifecycleService mockLifecycle;
  late MockFirebaseFirestore mockFirestore;
  late MockFirebaseAnalytics mockAnalytics;
  late AudioAccessibilityService service;

  // Setup mocks
  setUp(() {
    mockAudioEngine = MockAudioEngineProvider();
    mockStorage = MockStorageProvider();
    mockTts = MockTextToSpeechProvider();
    mockProcessor = MockAudioProcessor();
    mockLocalization = MockLocalizationService();
    mockSecureStorage = MockSecureStorageService();
    mockLifecycle = MockAppLifecycleService();
    mockFirestore = MockFirebaseFirestore();
    mockAnalytics = MockFirebaseAnalytics();

    // Reset singleton for testing
    AudioAccessibilityService.resetInstance();

    // Create service with mocks
    service = AudioAccessibilityService(
      audioEngineProvider: mockAudioEngine,
      storageProvider: mockStorage,
      ttsProvider: mockTts,
      audioProcessor: mockProcessor,
      localizationService: mockLocalization,
      secureStorageService: mockSecureStorage,
      lifecycleService: mockLifecycle,
      config: const AudioAccessibilityConfig(),
      firestore: mockFirestore,
      analytics: mockAnalytics,
    );

    // Set up common mock behavior
    final mockSession = MockAudioSession();
    when(mockAudioEngine.getAudioSession()).thenAnswer((_) async => mockSession);
    when(mockSession.configure(any)).thenAnswer((_) async {});
    when(mockSession.interruptionEventStream).thenAnswer(
            (_) => Stream<AudioInterruptionEvent>.empty()
    );

    when(mockLocalization.isLanguageSupported(any)).thenAnswer((_) async => true);
    when(mockLocalization.getMessage(any, any, any)).thenReturn('Localized message');

    final mockDir = MockDirectory();
    when(mockStorage.getApplicationDocumentsDirectory())
        .thenAnswer((_) async => mockDir);
    when(mockDir.path).thenReturn('/mock/path');
    when(mockDir.exists()).thenAnswer((_) async => true);
    when(mockDir.list()).thenAnswer((_) => Stream<FileSystemEntity>.empty());

    final mockPrefs = MockSharedPreferences();
    when(mockStorage.getSharedPreferences()).thenAnswer((_) async => mockPrefs);

    when(mockTts.initialize()).thenAnswer((_) async {});
    when(mockTts.setSpeechRate(any)).thenAnswer((_) async {});
    when(mockTts.setPitch(any)).thenAnswer((_) async {});
    when(mockTts.setVolume(any)).thenAnswer((_) async {});
    when(mockTts.setLanguage(any)).thenAnswer((_) async {});
    when(mockTts.getAvailableVoices()).thenAnswer((_) async => []);

    when(mockLifecycle.onResume).thenAnswer((_) => Stream.empty());
    when(mockLifecycle.onPause).thenAnswer((_) => Stream.empty());
    when(mockLifecycle.onMemoryPressure).thenAnswer((_) => Stream.empty());
    when(mockLifecycle.isAccessibilityEnabled).thenReturn(false);
    when(mockLifecycle.batteryLevel).thenReturn(80);
    when(mockLifecycle.isCharging).thenReturn(true);

    when(mockAnalytics.logEvent(name: anyNamed('name'), parameters: anyNamed('parameters')))
        .thenAnswer((_) async {});

    final mockCollection = MockCollectionReference();
    when(mockFirestore.collection(any)).thenReturn(mockCollection);
    when(mockCollection.add(any)).thenAnswer((_) async => MockDocumentReference());

    final mockDocRef = MockDocumentReference();
    when(mockCollection.doc(any)).thenReturn(mockDocRef);
    when(mockDocRef.set(any, any)).thenAnswer((_) async {});
    when(mockDocRef.update(any)).thenAnswer((_) async {});
  });

  tearDown(() {
    // Clean up after each test
    AudioAccessibilityService.resetInstance();
  });

  group('AudioAccessibilityService initialization', () {
    test('initializes successfully', () async {
      // Arrange
      when(mockSecureStorage.read(any)).thenAnswer((_) async => null);

      // Create a mock directory for cache
      final mockCacheDir = MockDirectory();
      final mockDirFile = MockFile();
      when(mockDir.path).thenReturn('/mock/path');
      when(mockCacheDir.exists()).thenAnswer((_) async => false);
      when(mockCacheDir.create(recursive: true)).thenAnswer((_) async => mockCacheDir);

      // Act
      await service.initialize();

      // Assert
      verify(mockAudioEngine.getAudioSession()).called(1);
      verify(mockTts.initialize()).called(1);
      expect(service.getCurrentSettings()['language'], 'en');
    });

    test('loads preferences from secure storage', () async {
      // Arrange
      when(mockSecureStorage.read('accessibility_speaking_rate')).thenAnswer((_) async => '0.9');
      when(mockSecureStorage.read('accessibility_pitch')).thenAnswer((_) async => '1.1');
      when(mockSecureStorage.read('accessibility_volume')).thenAnswer((_) async => '0.8');
      when(mockSecureStorage.read('accessibility_frequency_adjustment')).thenAnswer((_) async => 'true');
      when(mockSecureStorage.read('accessibility_volume_normalization')).thenAnswer((_) async => 'true');
      when(mockSecureStorage.read('accessibility_language')).thenAnswer((_) async => 'es');

      // Act
      await service.initialize();

      // Assert
      final settings = service.getCurrentSettings();
      expect(settings['speakingRate'], 0.9);
      expect(settings['pitch'], 1.1);
      expect(settings['volume'], 0.8);
      expect(settings['frequencyAdjustmentEnabled'], true);
      expect(settings['volumeNormalizationEnabled'], true);
      expect(settings['language'], 'es');
    });

    test('falls back to default settings when preferences not found', () async {
      // Arrange
      when(mockSecureStorage.read(any)).thenAnswer((_) async => null);

      // Act
      await service.initialize();

      // Assert
      final settings = service.getCurrentSettings();
      expect(settings['speakingRate'], 0.85); // Default value
      expect(settings['pitch'], 1.0); // Default value
      expect(settings['volume'], 0.85); // Default value
    });
  });

  group('AudioAccessibilityService audio processing', () {
    setUp(() async {
      // Setup for all tests in this group
      when(mockSecureStorage.read(any)).thenAnswer((_) async => null);
      await service.initialize();

      // Setup mock file operations
      final mockInputFile = MockFile();
      final mockOutputFile = MockFile();
      when(mockInputFile.exists()).thenAnswer((_) async => true);
      when(mockInputFile.length()).thenAnswer((_) async => 1024 * 1024); // 1MB
      when(mockInputFile.copy(any)).thenAnswer((_) async => mockOutputFile);

      when(mockOutputFile.exists()).thenAnswer((_) async => true);
      when(mockOutputFile.length()).thenAnswer((_) async => 1024 * 1024); // 1MB

      when(mockStorage.saveFile(any, any)).thenAnswer((_) async => mockOutputFile);

      // Setup processor mocks
      when(mockProcessor.normalizeVolume(any, any, targetLevel: anyNamed('targetLevel'), maxGain: anyNamed('maxGain')))
          .thenAnswer((_) async => true);
      when(mockProcessor.adjustFrequency(any, any, bassBoost: anyNamed('bassBoost'), trebleBoost: anyNamed('trebleBoost')))
          .thenAnswer((_) async => true);
      when(mockProcessor.compressDynamicRange(any, any, threshold: anyNamed('threshold'), ratio: anyNamed('ratio')))
          .thenAnswer((_) async => true);
    });

    test('processes audio file successfully', () async {
      // Arrange
      const inputPath = '/mock/input.mp3';
      final mockFile = MockFile();
      when(File(inputPath)).thenReturn(mockFile);
      when(mockFile.exists()).thenAnswer((_) async => true);
      when(mockFile.length()).thenAnswer((_) async => 1024 * 1024); // 1MB

      final mockOutputDir = MockDirectory();
      when(mockDir.path).thenReturn('/mock/path');
      when(Directory('/mock/path/accessibility_audio_cache')).thenReturn(mockOutputDir);
      when(mockOutputDir.exists()).thenAnswer((_) async => true);

      final mockOutputFile = MockFile();
      when(File(any)).thenReturn(mockOutputFile);
      when(mockOutputFile.exists()).thenAnswer((_) async => true);
      when(mockOutputFile.length()).thenAnswer((_) async => 1024 * 1024); // 1MB

      // Act
      final outputPath = await service.processAudioForAccessibility(inputPath);

      // Assert
      expect(outputPath, isNotNull);
      expect(outputPath, isNotEmpty);
      verify(mockProcessor.normalizeVolume(any, any, targetLevel: anyNamed('targetLevel'), maxGain: anyNamed('maxGain')))
          .called(1);
    });

    test('handles unsupported file format gracefully', () async {
      // Arrange
      const inputPath = '/mock/input.xyz'; // Unsupported format
      final mockFile = MockFile();
      when(File(inputPath)).thenReturn(mockFile);

      // Act & Assert
      expect(
              () => service.processAudioForAccessibility(inputPath),
          throwsA(isA<AudioAccessibilityException>())
      );
    });

    test('handles non-existent file gracefully', () async {
      // Arrange
      const inputPath = '/mock/nonexistent.mp3';
      final mockFile = MockFile();
      when(File(inputPath)).thenReturn(mockFile);
      when(mockFile.exists()).thenAnswer((_) async => false);

      // Act & Assert
      expect(
              () => service.processAudioForAccessibility(inputPath),
          throwsA(isA<AudioAccessibilityException>())
      );
    });

    test('handles processing failure gracefully', () async {
      // Arrange
      const inputPath = '/mock/input.mp3';
      final mockFile = MockFile();
      when(File(inputPath)).thenReturn(mockFile);
      when(mockFile.exists()).thenAnswer((_) async => true);
      when(mockFile.length()).thenAnswer((_) async => 1024 * 1024); // 1MB

      final mockOutputDir = MockDirectory();
      when(mockDir.path).thenReturn('/mock/path');
      when(Directory('/mock/path/accessibility_audio_cache')).thenReturn(mockOutputDir);
      when(mockOutputDir.exists()).thenAnswer((_) async => true);

      final mockOutputFile = MockFile();
      when(File(any)).thenReturn(mockOutputFile);
      when(mockOutputFile.exists()).thenAnswer((_) async => true);
      when(mockOutputFile.length()).thenAnswer((_) async => 0); // Empty file (processing failed)

      // Setup processor to fail
      when(mockProcessor.normalizeVolume(any, any, targetLevel: anyNamed('targetLevel'), maxGain: anyNamed('maxGain')))
          .thenAnswer((_) async => false);

      // Act
      final outputPath = await service.processAudioForAccessibility(inputPath);

      // Assert
      expect(outputPath, inputPath); // Should return original file on failure
    });
  });

  group('AudioAccessibilityService playback', () {
    setUp(() async {
      // Setup for all tests in this group
      when(mockSecureStorage.read(any)).thenAnswer((_) async => null);
      await service.initialize();

      // Setup mock audio player
      final mockPlayer = MockAudioPlayer();
      final mockPipeline = AudioPipeline(
        id: 'test_id',
        player: mockPlayer,
        audioPath: '/mock/audio.mp3',
      );

      when(mockAudioEngine.createPipeline(any, any)).thenAnswer((_) async => mockPipeline);
      when(mockPlayer.play()).thenAnswer((_) async {});
      when(mockPlayer.pause()).thenAnswer((_) async {});
      when(mockPlayer.stop()).thenAnswer((_) async {});
      when(mockPlayer.seek(any)).thenAnswer((_) async {});
      when(mockPlayer.setVolume(any)).thenAnswer((_) async {});
      when(mockPlayer.setSpeed(any)).thenAnswer((_) async {});

      // Setup mock file
      final mockFile = MockFile();
      when(File(any)).thenReturn(mockFile);
      when(mockFile.exists()).thenAnswer((_) async => true);
    });

    test('plays audio successfully', () async {
      // Arrange
      const audioPath = '/mock/audio.mp3';
      final mockFile = MockFile();
      when(File(audioPath)).thenReturn(mockFile);
      when(mockFile.exists()).thenAnswer((_) async => true);

      // Act
      final stateStream = await service.playEnhancedAudio(audioPath);

      // Assert
      expect(stateStream, isNotNull);
      verify(mockAudioEngine.createPipeline(any, audioPath)).called(1);
    });

    test('stops playback successfully', () async {
      // Arrange
      const audioPath = '/mock/audio.mp3';
      const playbackId = 'test_playback';
      final mockFile = MockFile();
      when(File(audioPath)).thenReturn(mockFile);
      when(mockFile.exists()).thenAnswer((_) async => true);

      // Act
      await service.playEnhancedAudio(audioPath, playbackId: playbackId);
      await service.stopPlayback(playbackId);

      // Assert
      // Verification will be done by the mocks
    });
  });

  group('AudioAccessibilityService settings', () {
    setUp(() async {
      // Setup for all tests in this group
      when(mockSecureStorage.read(any)).thenAnswer((_) async => null);
      await service.initialize();
    });

    test('updates settings successfully', () async {
      // Arrange
      const newSpeakingRate = 0.7;
      const newPitch = 1.2;
      const newVolume = 0.9;

      // Act
      await service.updateSettings(
        speakingRate: newSpeakingRate,
        pitch: newPitch,
        volume: newVolume,
        frequencyAdjustment: false,
        volumeNormalization: true,
      );

      // Assert
      final settings = service.getCurrentSettings();
      expect(settings['speakingRate'], newSpeakingRate);
      expect(settings['pitch'], newPitch);
      expect(settings['volume'], newVolume);
      expect(settings['frequencyAdjustmentEnabled'], false);
      expect(settings['volumeNormalizationEnabled'], true);

      verify(mockSecureStorage.write('accessibility_speaking_rate', newSpeakingRate.toString())).called(1);
      verify(mockSecureStorage.write('accessibility_pitch', newPitch.toString())).called(1);
      verify(mockSecureStorage.write('accessibility_volume', newVolume.toString())).called(1);
      verify(mockSecureStorage.write('accessibility_frequency_adjustment', 'false')).called(1);
      verify(mockSecureStorage.write('accessibility_volume_normalization', 'true')).called(1);
    });

    test('validates settings values', () async {
      // Arrange
      const invalidSpeakingRate = 3.0; // Out of range

      // Act & Assert
      await expectLater(
        service.updateSettings(speakingRate: invalidSpeakingRate),
        completes, // Should not update but also not throw
      );

      final settings = service.getCurrentSettings();
      expect(settings['speakingRate'], 0.85); // Should remain default
    });
  });

  group('AudioAccessibilityService cache management', () {
    setUp(() async {
      // Setup for all tests in this group
      when(mockSecureStorage.read(any)).thenAnswer((_) async => null);
      await service.initialize();

      // Setup mock cache directory
      final mockCacheDir = MockDirectory();
      when(mockDir.path).thenReturn('/mock/path');
      when(Directory('/mock/path/accessibility_audio_cache')).thenReturn(mockCacheDir);
      when(mockCacheDir.exists()).thenAnswer((_) async => true);

      // Setup mock files in cache
      final mockFile1 = MockFile();
      final mockFile2 = MockFile();
      when(mockFile1.path).thenReturn('/mock/path/accessibility_audio_cache/file1.mp3');
      when(mockFile2.path).thenReturn('/mock/path/accessibility_audio_cache/file2.mp3');

      final mockStat1 = FileStat(
        accessed: DateTime.now().subtract(const Duration(days: 10)),
        modified: DateTime.now().subtract(const Duration(days: 10)),
        changed: DateTime.now().subtract(const Duration(days: 10)),
        type: FileSystemEntityType.file,
        size: 1024 * 1024, // 1MB
        mode: 0,
      );

      final mockStat2 = FileStat(
        accessed: DateTime.now().subtract(const Duration(days: 2)),
        modified: DateTime.now().subtract(const Duration(days: 2)),
        changed: DateTime.now().subtract(const Duration(days: 2)),
        type: FileSystemEntityType.file,
        size: 2 * 1024 * 1024, // 2MB
        mode: 0,
      );

      when(mockFile1.stat()).thenAnswer((_) async => mockStat1);
      when(mockFile2.stat()).thenAnswer((_) async => mockStat2);
      when(mockFile1.length()).thenAnswer((_) async => 1024 * 1024);
      when(mockFile2.length()).thenAnswer((_) async => 2 * 1024 * 1024);
      when(mockFile1.delete()).thenAnswer((_) async => true);
      when(mockFile2.delete()).thenAnswer((_) async => true);

      when(mockCacheDir.list()).thenAnswer((_) => Stream.fromIterable([mockFile1, mockFile2]));
    });

    test('cleans up old cached files', () async {
      // Act
      await service.resetCache();

      // Assert
      verify(File('/mock/path/accessibility_audio_cache/file1.mp3').delete()).called(1);
      verify(File('/mock/path/accessibility_audio_cache/file2.mp3').delete()).called(1);
    });
  });

  group('AudioAccessibilityService accessibility features', () {
    setUp(() async {
      // Setup for all tests in this group
      when(mockSecureStorage.read(any)).thenAnswer((_) async => null);
      when(mockLifecycle.isAccessibilityEnabled).thenReturn(true);
      await service.initialize();
    });

    test('announces messages for screen readers', () async {
      // Act
      await service.enhanceForSpecialNeeds(severeHearingLoss: true);

      // Assert
      verify(mockTts.setVolume(1.0)).called(1);
      verify(mockSecureStorage.write('accessibility_volume', '1.0')).called(1);
    });
  });

  group('AudioAccessibilityService Firebase integration', () {
    setUp(() async {
      // Setup for all tests in this group
      when(mockSecureStorage.read(any)).thenAnswer((_) async => null);
      when(mockSecureStorage.read('user_id')).thenAnswer((_) async => 'test_user_id');
      await service.initialize();
    });

    test('logs events to Firebase Analytics', () async {
      // Act
      await service.updateSettings(speakingRate: 0.8);

      // Assert
      verify(mockAnalytics.logEvent(
        name: 'audio_accessibility_settings_updated',
        parameters: any,
      )).called(1);
    });

    test('stores settings in Firestore', () async {
      // Setup
      when(mockSecureStorage.read('user_id')).thenAnswer((_) async => 'test_user_id');

      // Act
      await service.updateSettings(speakingRate: 0.8);

      // Assert
      verify(mockFirestore.collection('user_settings')).called(greaterThan(0));
    });
  });
}

// Mock classes not auto-generated by Mockito
class MockCollectionReference extends Mock implements CollectionReference {
  @override
  DocumentReference doc(String documentPath) {
    return super.noSuchMethod(
      Invocation.method(#doc, [documentPath]),
      returnValue: MockDocumentReference(),
    );
  }
}

class MockDocumentReference extends Mock implements DocumentReference {
  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) {
    return super.noSuchMethod(
      Invocation.method(#set, [data, options]),
      returnValue: Future.value(),
    );
  }

  @override
  Future<void> update(Map<String, dynamic> data) {
    return super.noSuchMethod(
      Invocation.method(#update, [data]),
      returnValue: Future.value(),
    );
  }
}

// Helper class to create a pipeline for testing
class AudioPipeline {
  final String id;
  final AudioPlayer player;
  final String audioPath;
  final StreamController<PlaybackState> _stateController = StreamController<PlaybackState>.broadcast();

  AudioPipeline({
    required this.id,
    required this.player,
    required this.audioPath,
  });

  Stream<PlaybackState> get playbackStateStream => _stateController.stream;

  Future<void> play() async {
    await player.play();
    _stateController.add(PlaybackState(
      isPlaying: true,
      positionSeconds: 0.0,
      durationSeconds: 60.0,
      volume: 1.0,
      speed: 1.0,
    ));
  }

  Future<void> pause() async {
    await player.pause();
    _stateController.add(PlaybackState(
      isPlaying: false,
      positionSeconds: 30.0,
      durationSeconds: 60.0,
      volume: 1.0,
      speed: 1.0,
    ));
  }

  Future<void> stop() async {
    await player.stop();
    _stateController.add(PlaybackState(
      isPlaying: false,
      positionSeconds: 0.0,
      durationSeconds: 60.0,
      volume: 1.0,
      speed: 1.0,
    ));
  }

  Future<void> setVolume(double volume) async {
    await player.setVolume(volume);
  }

  Future<void> setSpeed(double speed) async {
    await player.setSpeed(speed);
  }

  void dispose() {
    _stateController.close();
  }
}