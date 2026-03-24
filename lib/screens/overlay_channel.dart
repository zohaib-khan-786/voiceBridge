// lib/services/overlay_channel.dart
// Native ↔ Flutter bridge for the floating bubble and WhatsApp integration.
//
// Usage:
//   final overlay = OverlayChannel();
//   await overlay.requestOverlayPermission();
//   await overlay.startOverlayService();
//
//   // From anywhere:
//   await overlay.sendToWhatsApp("مرحبا بكم");

import 'package:flutter/services.dart';

class OverlayChannel {
  static final OverlayChannel _instance = OverlayChannel._();
  factory OverlayChannel() => _instance;
  OverlayChannel._();

  static const _channel = MethodChannel('voicebridge/overlay');
  static const _eventChannel = EventChannel('voicebridge/overlay_events');

  Stream<String>? _eventStream;

  // ── Permissions ───────────────────────────────────────────────────────

  /// Returns true if SYSTEM_ALERT_WINDOW is granted.
  Future<bool> checkOverlayPermission() async {
    final result = await _channel.invokeMethod<bool>('checkOverlayPermission');
    return result ?? false;
  }

  /// Opens Android Settings to grant overlay permission.
  Future<void> requestOverlayPermission() =>
      _channel.invokeMethod('requestOverlayPermission');

  /// Returns true if VoiceBridge Accessibility Service is enabled.
  Future<bool> checkAccessibility() async {
    final result = await _channel.invokeMethod<bool>('checkAccessibility');
    return result ?? false;
  }

  /// Opens Android Accessibility Settings.
  Future<void> requestAccessibility() =>
      _channel.invokeMethod('requestAccessibility');

  // ── Bubble service ────────────────────────────────────────────────────

  /// Starts the floating bubble. Returns false if overlay permission missing.
  Future<bool> startOverlayService() async {
    final result = await _channel.invokeMethod<bool>('startOverlayService');
    return result ?? false;
  }

  /// Stops the floating bubble.
  Future<void> stopOverlayService() =>
      _channel.invokeMethod('stopOverlayService');

  // ── WhatsApp integration ──────────────────────────────────────────────

  /// Sends [text] to the active WhatsApp chat.
  ///
  /// Returns true  = Accessibility Service pasted + clicked Send automatically.
  /// Returns false = clipboard fallback (user may need to paste manually).
  Future<bool> sendToWhatsApp(String text) async {
    final result = await _channel.invokeMethod<bool>(
      'sendToWhatsApp',
      {'text': text},
    );
    return result ?? false;
  }

  /// Copies [text] to system clipboard.
  Future<void> copyToClipboard(String text) =>
      _channel.invokeMethod('copyToClipboard', {'text': text});

  /// Brings WhatsApp to the foreground (or minimises VoiceBridge).
  Future<void> goBackToWhatsApp() => _channel.invokeMethod('goBackToWhatsApp');

  // ── Event stream ──────────────────────────────────────────────────────

  /// Stream of events from native → Flutter.
  /// Currently emits: "show_drawer" (when bubble is tapped).
  Stream<String> get events {
    _eventStream ??=
        _eventChannel.receiveBroadcastStream().map((e) => e.toString());
    return _eventStream!;
  }
}
