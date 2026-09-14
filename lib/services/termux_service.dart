import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Talks to the native Android side (MainActivity.kt), which fires Termux's
/// RUN_COMMAND intent to run Garage_backend/deploy/start-garage.sh — the same
/// script Termux:Boot runs automatically on power-on. This is the manual
/// fallback for when the server didn't come up on its own (Termux got killed,
/// boot didn't fire, etc.).
///
/// One-time setup this depends on (see Garage_backend/TERMUX_SETUP.md):
///   - `allow-external-apps=true` in ~/.termux/termux.properties
///   - The app is granted the com.termux.permission.RUN_COMMAND permission
///     (requested automatically the first time this is used)
class TermuxService {
  static const MethodChannel _channel = MethodChannel('garage_manager/termux');

  /// Fires the RUN_COMMAND intent. Throws a [TermuxException] with a
  /// human-readable message on failure (permission denied, Termux missing, …).
  static Future<void> startBackendServer() async {
    if (!Platform.isAndroid) {
      throw TermuxException(
        'Starting the server from the app only works on the Android phone that runs it.',
      );
    }
    try {
      await _channel.invokeMethod('startServer');
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'PERMISSION_DENIED':
          throw TermuxException(
            'Permission to control Termux was denied. Grant "Run commands" for '
            'Garage Manager in Android Settings → Apps, then try again.',
          );
        case 'TERMUX_ERROR':
          throw TermuxException(
            'Could not reach Termux (${e.message}). Make sure Termux is installed '
            'and allow-external-apps=true is set in ~/.termux/termux.properties.',
          );
        default:
          throw TermuxException(e.message ?? 'Failed to start the server.');
      }
    }
  }
}

class TermuxException implements Exception {
  final String message;
  TermuxException(this.message);

  @override
  String toString() => message;
}
