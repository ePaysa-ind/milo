// lib/services/security_provider_initializer.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../utils/advanced_logger.dart';

class SecurityProviderInitializer {
  static const MethodChannel _channel = MethodChannel('com.milo.memorykeeper.milo/security');
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    AdvancedLogger.info('SecurityProvider', 'Starting security provider initialization');

    try {
      // First attempt: Make an HTTPS request to trigger provider installation
      await _makeSecureRequest();

      // Second attempt: Try to invoke native security methods via platform channel
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _invokeNativeSecurityInit();
      }

      _initialized = true;
      AdvancedLogger.info('SecurityProvider', 'Security provider initialization completed');
    } catch (e) {
      AdvancedLogger.warning('SecurityProvider', 'Security provider initialization failed',
          data: {'error': e.toString()});

      // The app can still function without this, so we'll just log and continue
    }
  }

  static Future<void> _makeSecureRequest() async {
    try {
      // This will trigger the security provider update
      await http.get(Uri.parse('https://www.googleapis.com')).timeout(
        const Duration(seconds: 3),
        onTimeout: () => http.Response('Timeout', 408),
      );
      AdvancedLogger.info('SecurityProvider', 'Security provider check completed via HTTPS');
    } catch (e) {
      AdvancedLogger.warning('SecurityProvider', 'HTTPS request failed', data: {'error': e.toString()});
      // Continue to the next method
    }
  }

  static Future<void> _invokeNativeSecurityInit() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('initializeSecurityProvider');
      AdvancedLogger.info('SecurityProvider', 'Native security initialization result',
          data: {'success': result ?? false});
    } catch (e) {
      AdvancedLogger.warning('SecurityProvider', 'Native security initialization failed',
          data: {'error': e.toString()});
      // This is expected to fail if the method isn't implemented on the native side
    }
  }
}