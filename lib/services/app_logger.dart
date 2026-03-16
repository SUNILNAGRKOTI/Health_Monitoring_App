import 'package:flutter/foundation.dart';

/// Secure logger that only prints in debug mode.
/// In release builds, ALL logs are silenced — no data leakage.
class AppLogger {
  static void log(String message) {
    if (kDebugMode) {
      print(message);
    }
  }

  static void error(String message) {
    if (kDebugMode) {
      print('❌ $message');
    }
  }

  static void warning(String message) {
    if (kDebugMode) {
      print('⚠️ $message');
    }
  }

  static void success(String message) {
    if (kDebugMode) {
      print('✅ $message');
    }
  }

  static void info(String message) {
    if (kDebugMode) {
      print('ℹ️ $message');
    }
  }
}
