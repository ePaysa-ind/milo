// Copyright © 2025 Milo App. All rights reserved.
// Author: Milo Development Team
// File: test/utils/audio_quality_monitor_test.dart
// Version: 1.0.0
// Last Updated: April 21, 2025
// Description: Test suite for AudioQualityMonitor utility

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:milo/utils/audio_quality_monitor.dart';
import 'package:milo/services/audio/audio_accessibility_service.dart';
import 'package:milo/utils/advanced_logger.dart';
import 'package:milo/services/localization/app_localizations.dart';
import 'package:milo/services/auth/auth_service.dart';
import 'package:milo/services/storage/secure_storage_service.dart';
import 'package:milo/services/firebase/firebase_service.dart';

// Generate mocks for our dependencies
@GenerateMocks([
  AudioAnalyzer,
  PerformanceMonitor,
  DeviceInfoProvider,
  AudioQualityRepository,
  AppLocalizations,
  SecureStorageService,
  AuthService,
  FirebaseService,
  AudioAccessibilityService,
])
import 'audio_quality_monitor_test.mocks.dart';

/// Test setup helper class
class TestSetup {
  late MockAudioAnalyzer audioAnalyzer;
  late MockPerformanceMonitor performanceMonitor;
  late MockDeviceInfoProvider deviceInfoProvider;
  late MockAudioQualityRepository repository;
  late MockAppLocalizations localizations;
  late MockSecureStorageService secureStorage;
  late MockAuthService authService;
  late AudioQualityMonitorConfig config;
  late AudioQualityMonitor monitor;

  TestSetup() {
    _setupMocks();
    _createMonitor();
  }

  void _setupMocks() {
    audioAnalyzer = MockAudioAnalyzer();
    performanceMonitor = MockPerformanceMonitor();
    deviceInfoProvider = MockDeviceInfoProvider();
    repository = MockAudioQualityRepository();
    localizations = MockAppLocalizations();
    secureStorage = MockSecureStorageService();
    authService = MockAuthService();

    // Default mock implementation of translate method
    when(localizations.translate(any, any)).thenReturn('translated_text');
    when(localizations.translate(any)).thenReturn('translated_text');

    // Auth service mock setup
    when(authService.getCurrentUserId()).thenAnswer((_) async => 'test_user_id');
    when(authService.canRequestDataCollectionConsent()).thenAnswer((_) async => true);

    // Device info mock setup
    when(deviceInfoProvider.getDeviceModel()).thenAnswer((_) async => 'Test Device');
    when(deviceInfoProvider.getDeviceId()).thenReturn('test_device_id');
    when(deviceInfoProvider.getBasicDeviceInfo()).thenReturn({
      'platform': 'test_platform',
      'deviceModel': 'Test Device',
    });

    // Performance monitor mock setup
    when(performanceMonitor.initialize()).thenAnswer((_) async {});
    when(performanceMonitor.getCurrentCpuUsage()).thenAnswer((_) async => 15.0);
    when(performanceMonitor.getBatteryLevel()).thenAnswer((_) async => 80.0);
    when(performanceMonitor.getBatteryDrainRate()).thenAnswer((_) async => 0.5);
    when(performanceMonitor.dispose()).thenAnswer((_) async {});

    // Audio analyzer mock setup
    when(audioAnalyzer.initialize()).thenAnswer((_) async {});
    when(audioAnalyzer.dispose()).thenAnswer((_) async {});

    // Repository mock setup
    when(repository.initialize()).thenAnswer((_) async {});
    when(repository.saveMetricsBatch(any)).thenAnswer((_) async => true);

    // Secure storage mock setup
    when(secureStorage.read(any)).thenAnswer((_) async => null);
    when(secureStorage.write(any, any)).thenAnswer((_) async {});
  }

  void _createMonitor() {
    config = const AudioQualityMonitorConfig.defaults();

    // Create monitor instance with mocked dependencies
    monitor = AudioQualityMonitor(
      audioAnalyzer: audioAnalyzer,
      performanceMonitor: performanceMonitor,
      deviceInfoProvider: deviceInfoProvider,
      repository: repository,
      localizations: localizations,
      secureStorage: secureStorage,
      authService: authService,
      config: config,
    );
  }

  /// Setup temporary test audio file
  Future<String> setupTestAudioFile() async {
    final directory = await Directory.systemTemp.createTemp('test_audio');
    final file = File('${directory.path}/test_audio.mp3');
    await file.writeAsBytes(List.generate(1024, (index) => index % 256));

    // Setup format info for the test file
    final formatInfo = AudioFormatInfo(
      codec: 'MP3',
      sampleRate: 44100,
      bitRate: 128,
      channels: 2,
      duration: 10.0,
      fileSize: 1024,
    );

    when(audioAnalyzer.getAudioFormatInfo(file.path))
        .thenAnswer((_) async => formatInfo);

    when(audioAnalyzer.analyzeAudio(file.path))
        .thenAnswer((_) async => AudioAnalysisMetrics(
      peakAmplitude: 0.8,
      rmsLevel: -18.0,
      clippingPercentage: 2.0,
      signalToNoiseRatio: 40.0,
      frequencyBalance: null,
    ));

    when(audioAnalyzer.analyzeAudioSimple(file.path))
        .thenAnswer((_) async => AudioAnalysisMetrics(
      peakAmplitude: 0.7,
      rmsLevel: -20.0,
      clippingPercentage: 1.0,
      signalToNoiseRatio: null,
      frequencyBalance: null,
    ));

    when(audioAnalyzer.detectOutputDevice())
        .thenAnswer((_) async => AudioOutputDevice.speaker);

    when(audioAnalyzer.processAudioForElderly(any, any))
        .thenAnswer((_) async => true);

    when(audioAnalyzer.processAudioSimple(any, any))
        .thenAnswer((_) async => true);

    return file.path;
  }

  /// Clean up temporary files created during tests
  Future<void> cleanupTestFiles() async {
    try {
      final tempDir = await Directory.systemTemp.createTemp('test_audio');
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (e) {
      // Ignore cleanup errors in tests
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestSetup testSetup;

  setUp(() {
    testSetup = TestSetup();
  });

  tearDown(() async {
    await testSetup.cleanupTestFiles();
    AudioQualityMonitor.resetInstance();
  });

  // Unit Tests

  group('AudioQualityMonitor Initialization Tests', () {
    test('Should initialize properly with default config', () async {
      // Arrange - done in setUp

      // Act
      await testSetup.monitor.initialize();

      // Assert
      expect(testSetup.monitor.getDiagnosticInfo()['isInitialized'], true);
      verify(testSetup.audioAnalyzer.initialize()).called(1);
      verify(testSetup.performanceMonitor.initialize()).called(1);
      verify(testSetup.repository.initialize()).called(1);
    });

    test('Should handle initialization errors gracefully', () async {
      // Arrange
      when(testSetup.audioAnalyzer.initialize()).thenThrow(Exception('Test error'));

      // Act & Assert
      expect(() => testSetup.monitor.initialize(), throwsException);
    });

    test('Should not re-initialize if already initialized', () async {
      // Arrange
      await testSetup.monitor.initialize();
      clearInteractions(testSetup.audioAnalyzer);

      // Act
      await testSetup.monitor.initialize();

      // Assert
      verifyNever(testSetup.audioAnalyzer.initialize());
    });
  });

  group('AudioQualityMonitor Session Management Tests', () {
    test('Should start monitoring session properly', () async {
      // Arrange
      await testSetup.monitor.initialize();
      final audioPath = await testSetup.setupTestAudioFile();

      // Act
      final sessionId = await testSetup.monitor.startMonitoringSession(audioPath);

      // Assert
      expect(sessionId, isNotEmpty);
      verify(testSetup.audioAnalyzer.getAudioFormatInfo(audioPath)).called(1);
      verify(testSetup.deviceInfoProvider.getDeviceModel()).called(1);
    });

    test('Should stop monitoring session properly', () async {
      // Arrange
      await testSetup.monitor.initialize();
      final audioPath = await testSetup.setupTestAudioFile();
      final sessionId = await testSetup.monitor.startMonitoringSession(audioPath);

      // Act
      final metrics = await testSetup.monitor.stopMonitoringSession(
        sessionId,
        completionPercentage: 80.0,
        userEngagement: 0.7,
      );

      // Assert
      expect(metrics, isNotNull);
      expect(metrics!.playbackCompletionRate, 80.0);
      expect(metrics.userEngagementScore, 0.7);
    });

    test('Should handle non-existent audio file', () async {
      // Arrange
      await testSetup.monitor.initialize();
      const nonExistentPath = '/path/to/non_existent_file.mp3';

      // Mock file exists check to return false
      when(testSetup.audioAnalyzer.getAudioFormatInfo(nonExistentPath))
          .thenThrow(FileSystemException('File not found'));

      // Act & Assert
      expect(
            () => testSetup.monitor.startMonitoringSession(nonExistentPath),
        throwsException,
      );
    });

    test('Should handle empty audio path', () async {
      // Arrange
      await testSetup.monitor.initialize();

      // Act & Assert
      expect(
            () => testSetup.monitor.startMonitoringSession(''),
        throwsArgumentError,
      );
    });

    test('Should handle stopping non-existent session', () async {
      // Arrange
      await testSetup.monitor.initialize();

      // Act
      final metrics = await testSetup.monitor.stopMonitoringSession('non_existent_session');

      // Assert
      expect(metrics, isNull);
    });
  });

  group('AudioQualityMonitor Metrics Collection Tests', () {
    test('Should collect metrics properly', () async {
      // Arrange
      await testSetup.monitor.initialize();
      final audioPath = await testSetup.setupTestAudioFile();
      final sessionId = await testSetup.monitor.startMonitoringSession(audioPath);

      // Act
      // Monitor will collect metrics internally
      await Future.delayed(const Duration(milliseconds: 100)); // Allow time for collection

      // Assert
      final currentMetrics = testSetup.monitor.getCurrentMetrics();
      expect(currentMetrics, isNull); // Initially null until first check completes

      // Force metrics collection by stopping the session
      final metrics = await testSetup.monitor.stopMonitoringSession(sessionId);

      // Validate metrics
      expect(metrics, isNotNull);
      expect(metrics!.peakAmplitude, 0.8);
      expect(metrics.rmsLevel, -18.0);
      expect(metrics.clippingPercentage, 2.0);
      expect(metrics.signalToNoiseRatio, 40.0);
      expect(metrics.playbackCompletionRate, 100.0);
    });

    test('Should upload metrics batch when threshold reached', () async {
      // Arrange
      await testSetup.monitor.initialize();
      final audioPath = await testSetup.setupTestAudioFile();
      final sessions = <String>[];

      // Start multiple sessions to reach batch threshold
      for (int i = 0; i < 20; i++) {
        final sessionId = await testSetup.monitor.startMonitoringSession(audioPath);
        sessions.add(sessionId);
        await testSetup.monitor.stopMonitoringSession(sessionId);
      }

      // Act & Assert
      verify(testSetup.repository.saveMetricsBatch(any)).called(greaterThanOrEqualTo(1));
    });
  });

  group('AudioQualityMonitor Configuration Tests', () {
    test('Should update configuration properly', () async {
      // Arrange
      await testSetup.monitor.initialize();

      final newConfig = AudioQualityMonitorConfig(
        enableRealTimeMonitoring: false,
        samplingIntervalMs: 10000,
        enableAutoCorrections: false,
        enableBatteryMonitoring: false,
        enableCpuMonitoring: false,
        enableEngagementTracking: false,
        maxCachedMetrics: 50,
        uploadMetricsToFirebase: false,
        analyticsBatchSize: 10,
        clippingThreshold: 10.0,
        lowVolumeThreshold: -35.0,
        highVolumeThreshold: -5.0,
        cpuUsageThreshold: 60.0,
        batteryDrainThreshold: 3.0,
        privacyModeEnabled: false,
        analyticsEnabled: false,
        debugModeEnabled: true,
        debugModeSamplingIntervalMs: 500,
        lowBatteryThreshold: 20,
        criticalBatteryThreshold: 10,
        lowBatterySamplingIntervalMs: 20000,
        networkRetryBaseDelayMs: 2000,
        maxNetworkRetryAttempts: 3,
        securityLevel: SecurityLevel.maximum,
        offlineDataRetentionDays: 14,
      );

      // Act
      final result = await testSetup.monitor.updateConfiguration(newConfig);

      // Assert
      expect(result, true);
      final diagnosticInfo = testSetup.monitor.getDiagnosticInfo();
      expect(diagnosticInfo['configSettings']['enableRealTimeMonitoring'], false);
      expect(diagnosticInfo['configSettings']['samplingIntervalMs'], 10000);
      expect(diagnosticInfo['configSettings']['enableAutoCorrections'], false);
      expect(diagnosticInfo['thresholds']['clippingThreshold'], 10.0);
    });
  });

  group('AudioQualityMonitor Consent Management Tests', () {
    test('Should request and store user consent', () async {
      // Arrange
      await testSetup.monitor.initialize();

      // Act
      final consentStatus = await testSetup.monitor.getUserConsent();

      // Assert
      expect(consentStatus, ConsentStatus.granted);
      verify(testSetup.secureStorage.write('audio_monitor_consent', 'granted')).called(1);
      verify(testSetup.secureStorage.write('audio_monitor_consent_timestamp', any)).called(1);
    });

    test('Should revoke user consent', () async {
      // Arrange
      await testSetup.monitor.initialize();
      await testSetup.monitor.getUserConsent();

      // Act
      final result = await testSetup.monitor.revokeConsent();

      // Assert
      expect(result, true);
      verify(testSetup.secureStorage.write('audio_monitor_consent', 'revoked')).called(1);
    });

    test('Should respect existing consent status', () async {
      // Arrange
      when(testSetup.secureStorage.read('audio_monitor_consent'))
          .thenAnswer((_) async => 'granted');
      when(testSetup.secureStorage.read('audio_monitor_consent_timestamp'))
          .thenAnswer((_) async => DateTime.now().toIso8601String());

      await testSetup.monitor.initialize();

      // Act
      final consentStatus = await testSetup.monitor.getUserConsent();

      // Assert
      expect(consentStatus, ConsentStatus.granted);
      verifyNever(testSetup.secureStorage.write('audio_monitor_consent', any));
    });
  });

  group('AudioQualityMonitor Audio Processing Tests', () {
    test('Should validate audio for accessibility', () async {
      // Arrange
      await testSetup.monitor.initialize();
      final audioPath = await testSetup.setupTestAudioFile();

      // Act
      final result = await testSetup.monitor.validateAudioForAccessibility(audioPath);

      // Assert
      expect(result.isValid, isTrue);
      expect(result.format, isNotNull);
      expect(result.metrics, isNotNull);
      expect(result.correlationId, isNotEmpty);
    });

    test('Should optimize audio for elderly', () async {
      // Arrange
      await testSetup.monitor.initialize();
      final audioPath = await testSetup.setupTestAudioFile();

      // Act
      final optimizedPath = await testSetup.monitor.optimizeAudioForElderly(audioPath);

      // Assert
      expect(optimizedPath, isNotEmpty);
      expect(optimizedPath, isNot(equals(audioPath)));
      verify(testSetup.audioAnalyzer.processAudioForElderly(audioPath, optimizedPath)).called(1);
    });

    test('Should fallback to simple processing when full processing fails', () async {
      // Arrange
      await testSetup.monitor.initialize();
      final audioPath = await testSetup.setupTestAudioFile();

      // Mock full processing to fail
      when(testSetup.audioAnalyzer.processAudioForElderly(any, any))
          .thenAnswer((_) async => false);

      // Act
      final optimizedPath = await testSetup.monitor.optimizeAudioForElderly(audioPath);

      // Assert
      expect(optimizedPath, isNotEmpty);
      verify(testSetup.audioAnalyzer.processAudioForElderly(audioPath, optimizedPath)).called(1);
      verify(testSetup.audioAnalyzer.processAudioSimple(audioPath, optimizedPath)).called(1);
    });

    test('Should fallback to file copy when all processing fails', () async {
      // Arrange
      await testSetup.monitor.initialize();
      final audioPath = await testSetup.setupTestAudioFile();

      // Mock both processing methods to fail
      when(testSetup.audioAnalyzer.processAudioForElderly(any, any))
          .thenAnswer((_) async => false);
      when(testSetup.audioAnalyzer.processAudioSimple(any, any))
          .thenAnswer((_) async => false);

      // Act
      final optimizedPath = await testSetup.monitor.optimizeAudioForElderly(audioPath);

      // Assert
      expect(optimizedPath, isNotEmpty);
      verify(testSetup.audioAnalyzer.processAudioForElderly(any, any)).called(1);
      verify(testSetup.audioAnalyzer.processAudioSimple(any, any)).called(1);
    });
  });

  group('AudioQualityMonitor Performance Report Tests', () {
    test('Should generate performance report', () async {
      // Arrange
      await testSetup.monitor.initialize();

      // Setup mock metrics for retrieval
      final mockMetrics = [
        AudioQualityMetrics(
          peakAmplitude: 0.8,
          rmsLevel: -18.0,
          clippingPercentage: 2.0,
          signalToNoiseRatio: 40.0,
          cpuUsage: 15.0,
          batteryDrainRate: 0.5,
          playbackCompletionRate: 95.0,
          userEngagementScore: 0.8,
          outputDevice: AudioOutputDevice.speaker,
          format: AudioFormatInfo(
            codec: 'MP3',
            sampleRate: 44100,
            bitRate: 128,
            channels: 2,
            duration: 30.0,
            fileSize: 3840000,
          ),
          deviceModel: 'Test Device',
          timestamp: DateTime.now(),
          nudgeId: 'test_nudge_1',
          userId: 'test_user_id',
          sessionId: 'test_session_1',
          appVersion: '1.0.0',
          correlationId: 'test_correlation_1',
          sessionContext: null,
        ),
        AudioQualityMetrics(
          peakAmplitude: 0.7,
          rmsLevel: -20.0,
          clippingPercentage: 1.5,
          signalToNoiseRatio: 42.0,
          cpuUsage: 14.0,
          batteryDrainRate: 0.4,
          playbackCompletionRate: 100.0,
          userEngagementScore: 0.9,
          outputDevice: AudioOutputDevice.bluetoothHeadphones,
          format: AudioFormatInfo(
            codec: 'AAC',
            sampleRate: 48000,
            bitRate: 192,
            channels: 2,
            duration: 45.0,
            fileSize: 10800000,
          ),
          deviceModel: 'Test Device',
          timestamp: DateTime.now(),
          nudgeId: 'test_nudge_2',
          userId: 'test_user_id',
          sessionId: 'test_session_2',
          appVersion: '1.0.0',
          correlationId: 'test_correlation_2',
          sessionContext: null,
        ),
      ];

      when(testSetup.repository.getMetrics(
        startDate: anyNamed('startDate'),
        endDate: anyNamed('endDate'),
        limit: anyNamed('limit'),
        userId: anyNamed('userId'),
      )).thenAnswer((_) async => mockMetrics);

      // Act
      final report = await testSetup.monitor.getPerformanceReport();

      // Assert
      expect(report.totalPlaybackSessions, 2);
      expect(report.averageCompletionRate, 97.5);
      expect(report.devicePerformance.keys, contains('Test Device'));
      expect(report.nudgeEffectiveness.keys, contains('test_nudge_1'));
      expect(report.nudgeEffectiveness.keys, contains('test_nudge_2'));
    });

    test('Should handle empty metrics for performance report', () async {
      // Arrange
      await testSetup.monitor.initialize();

      // Setup mock to return empty metrics
      when(testSetup.repository.getMetrics(
        startDate: anyNamed('startDate'),
        endDate: anyNamed('endDate'),
        limit: anyNamed('limit'),
        userId: anyNamed('userId'),
      )).thenAnswer((_) async => []);

      // Act
      final report = await testSetup.monitor.getPerformanceReport();

      // Assert
      expect(report.totalPlaybackSessions, 0);
      expect(report.devicePerformance, isEmpty);
      expect(report.nudgeEffectiveness, isEmpty);
    });
  });

  group('AudioQualityMonitor Resource Management Tests', () {
    test('Should dispose resources properly', () async {
      // Arrange
      await testSetup.monitor.initialize();

      // Act
      await AudioQualityMonitor.resetInstance();

      // Assert
      verify(testSetup.audioAnalyzer.dispose()).called(1);
      verify(testSetup.performanceMonitor.dispose()).called(1);
    });
  });

  // Integration Tests

  group('AudioQualityMonitor Integration Tests', () {
    test('Should complete full workflow successfully', () async {
      // Arrange
      await testSetup.monitor.initialize();
      final audioPath = await testSetup.setupTestAudioFile();

      // Act - Validate audio
      final validationResult = await testSetup.monitor.validateAudioForAccessibility(audioPath);
      expect(validationResult.isValid, isTrue);

      // Act - Optimize audio
      final optimizedPath = await testSetup.monitor.optimizeAudioForElderly(audioPath);
      expect(optimizedPath, isNotEmpty);

      // Act - Start monitoring session
      final sessionId = await testSetup.monitor.startMonitoringSession(optimizedPath);
      expect(sessionId, isNotEmpty);

      // Act - Get recommendations
      final recommendations = testSetup.monitor.getQualityRecommendations();
      expect(recommendations, isNotEmpty);

      // Act - Stop monitoring session
      final metrics = await testSetup.monitor.stopMonitoringSession(
        sessionId,
        completionPercentage: 90.0,
        userEngagement: 0.8,
      );
      expect(metrics, isNotNull);

      // Act - Generate performance report
      final report = await testSetup.monitor.getPerformanceReport();

      // Assert - Should complete entire flow without errors
      expect(report, isNotNull);
    });
  });

  // Security Tests

  group('AudioQualityMonitor Security Tests', () {
    test('Should anonymize sensitive data', () async {
      // Arrange
      await testSetup.monitor.initialize();
      final audioPath = await testSetup.setupTestAudioFile();

      // Create session with context containing PII
      final sessionContext = {
        'timestamp': DateTime.now().toIso8601String(),
        'email': 'test@example.com',
        'phone': '123-456-7890',
        'preference': 'high_quality',
        'nested': {
          'address': '123 Main St',
          'preference': 'high_volume',
        }
      };

      // Act
      final sessionId = await testSetup.monitor.startMonitoringSession(
        audioPath,
        sessionContext: sessionContext,
      );

      final metrics = await testSetup.monitor.stopMonitoringSession(sessionId);

      // Assert
      expect(metrics, isNotNull);
      expect(metrics!.sessionContext, isNotNull);

      // Verify PII is not present
      final context = metrics.sessionContext!;
      expect(context.containsKey('email'), isTrue);
      expect(context['email'], isNot(equals('test@example.com')));
      expect(context['email'], startsWith('hashed_'));

      expect(context.containsKey('phone'), isTrue);
      expect(context['phone'], isNot(equals('123-456-7890')));
      expect(context['phone'], startsWith('hashed_'));

      expect(context.containsKey('preference'), isTrue);
      expect(context['preference'], equals('high_quality'));

      expect(context.containsKey('nested'), isTrue);
      expect(context['nested']['address'], startsWith('hashed_'));
      expect(context['nested']['preference'], equals('high_volume'));
    });

    test('Should validate metrics for compliance', () async {
      // Arrange
      await testSetup.monitor.initialize();

      // Create metrics with invalid values
      final invalidMetrics = AudioQualityMetrics(
        peakAmplitude: 1.5, // Invalid: > 1.0
        rmsLevel: -18.0,
        clippingPercentage: 2.0,
        signalToNoiseRatio: 40.0,
        cpuUsage: 15.0,
        batteryDrainRate: 0.5,
        playbackCompletionRate: 95.0,
        userEngagementScore: 0.8,
        outputDevice: AudioOutputDevice.speaker,
        format: AudioFormatInfo(
          codec: 'MP3',
          sampleRate: 44100,
          bitRate: 128,
          channels: 2,
          duration: 30.0,
          fileSize: 3840000,
        ),
        deviceModel: 'Test Device',
        timestamp: DateTime.now(),
        nudgeId: 'test_nudge_1',
        userId: 'test_user_id',
        sessionId: 'test_session_1',
        appVersion: '1.0.0',
        correlationId: 'test_correlation_1',
        sessionContext: {'email': 'test@example.com'},
      );

      // Check compliance directly
      expect(invalidMetrics.validateForCompliance(), isFalse);

      // Create anonymized version
      final anonymized = invalidMetrics.anonymized();

      // Verify anonymized version has no PII
      expect(anonymized.userId, isNull);
      expect(anonymized.nudgeId, isNull);
      expect(anonymized.sessionContext, isNull);
      expect(anonymized.deviceModel, 'Test');
    });
  });

  // Performance Tests

  group('AudioQualityMonitor Performance Tests', () {
    test('Should adjust monitoring based on battery level', () async {
      // Arrange
      await testSetup.monitor.initialize();

      // Mock low battery
      when(testSetup.performanceMonitor.getBatteryLevel())
          .thenAnswer((_) async => 20.0);

      final audioPath = await testSetup.setupTestAudioFile();

      // Act - Start monitoring with low battery
      final sessionId = await testSetup.monitor.startMonitoringSession(audioPath);

      // Verify it uses simplified analysis for low battery
      verify(testSetup.audioAnalyzer.analyzeAudioSimple(audioPath)).called(greaterThanOrEqualTo(1));
    });

    test('Should optimize audio processing based on file size', () async {
      // Arrange
      await testSetup.monitor.initialize();
      final smallAudioPath = await testSetup.setupTestAudioFile();

      // Create a larger test file
      final directory = await Directory.systemTemp.createTemp('test_audio');
      final largeFile = File('${directory.path}/large_test_audio.mp3');
      await largeFile.writeAsBytes(List.generate(1024 * 1024, (index) => index % 256));

      // Setup format info for the large file
      final formatInfo = AudioFormatInfo(
        codec: 'MP3',
        sampleRate: 44100,
        bitRate: 128,
        channels: 2,
        duration: 240.0,
        fileSize: 1024 * 1024,
      );

      when(testSetup.audioAnalyzer.getAudioFormatInfo(largeFile.path))
          .thenAnswer((_) async => formatInfo);

      // We need to be able to measure time, so use real timing for processing
      // Restore original implementations
      when(testSetup.audioAnalyzer.processAudioForElderly(any, any))
          .thenAnswer((invocation) async {
        final inputPath = invocation.positionalArguments[0] as String;
        final outputPath = invocation.positionalArguments[1] as String;

        // Processing time proportional to file size
        final file = File(inputPath);
        final fileSize = await file.length();

        // Simulate processing time
        final processingTime = fileSize ~/ 10000;
        await Future.delayed(Duration(milliseconds: processingTime));

        // Copy the file
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          await outputFile.delete();
        }
        await file.copy(outputPath);

        return true;
      });

      // Act and measure time for small file
      final smallStartTime = DateTime.now();
      final smallOptimizedPath = await testSetup.monitor.optimizeAudioForElderly(smallAudioPath);
      final smallDuration = DateTime.now().difference(smallStartTime);

      // Act and measure time for large file
      final largeStartTime = DateTime.now();
      final largeOptimizedPath = await testSetup.monitor.optimizeAudioForElderly(largeFile.path);
      final largeDuration = DateTime.now().difference(largeStartTime);

      // Assert
      expect(smallOptimizedPath, isNotEmpty);
      expect(largeOptimizedPath, isNotEmpty);

      // Processing time should be longer for larger file
      expect(largeDuration, greaterThan(smallDuration));
    });
  });
}