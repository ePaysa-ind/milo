// lib/utils/logger.dart
import 'package:flutter/foundation.dart';

class Logger {
  static void info(String tag, String message) {
    if (kDebugMode) {
      print('I/$tag (${DateTime.now().millisecondsSinceEpoch}): ✅ $message');
    }
  }

  static void error(String tag, String message) {
    if (kDebugMode) {
      print('E/$tag (${DateTime.now().millisecondsSinceEpoch}): ❌ $message');
    }
  }

  static void warning(String tag, String message) {
    if (kDebugMode) {
      print('W/$tag (${DateTime.now().millisecondsSinceEpoch}): ⚠️ $message');
    }
  }

  static void debug(String tag, String message) {
    if (kDebugMode) {
      print('D/$tag (${DateTime.now().millisecondsSinceEpoch}): 🔍 $message');
    }
  }
}