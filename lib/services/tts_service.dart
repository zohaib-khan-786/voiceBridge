// lib/services/tts_service.dart
// Bilingual TTS — wraps flutter_tts with per-language acoustic profiles.
// Strategy:
//   1. Try Android built-in TTS with the language's native locale and
//      tuned speech-rate / pitch (same profiles as BilingualTTSEngine.kt).
//   2. If the language is not available on-device, fall back gracefully.
//
// Piper TTS (offline neural) is wired up here as a future extension point.
// When Piper model files are present in <documents>/ai_model/piper/,
// PiperTts.synthesize() will be called automatically.

import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/language_constants.dart';

// ── TTS result from synthesizeToFile ─────────────────────────────────────────

class TtsResult {
  final String? filePath;
  final String  engine;   // 'android_builtin' | 'piper'
  final bool    success;
  const TtsResult({required this.filePath, required this.engine, required this.success});
}

// ── TtsService singleton ──────────────────────────────────────────────────────

class TtsService {
  static final TtsService _instance = TtsService._();
  factory TtsService() => _instance;
  TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _initialized     = false;
  bool _speaking        = false;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    if (Platform.isAndroid) {
      await _tts.setEngine('com.google.android.tts');
    }
    await _tts.awaitSpeakCompletion(true);
    await _tts.setVolume(1.0);
    _initialized = true;
  }

  // ── Speak inline ──────────────────────────────────────────────────────────

  Future<void> speak(String text, String languageCode) async {
    if (text.trim().isEmpty) return;
    await init();
    if (_speaking) { await _tts.stop(); }
    _speaking = true;

    final lang = LanguageConstants.fromCode(languageCode);
    if (lang != null) {
      await _tts.setLanguage(lang.ttsLocale);
      await _tts.setSpeechRate(lang.ttsRate);
      await _tts.setPitch(lang.ttsPitch);
    }

    try {
      await _tts.speak(text);
    } finally {
      _speaking = false;
    }
  }

  // ── Stop ──────────────────────────────────────────────────────────────────

  Future<void> stop() async {
    _speaking = false;
    await _tts.stop();
  }

  // ── Synthesize to WAV file (for voice note sending) ───────────────────────

  Future<TtsResult> synthesizeToFile(String text, String languageCode) async {
    await init();

    // Try Piper first if available
    final piperResult = await _tryPiper(text, languageCode);
    if (piperResult != null) return piperResult;

    // Fall back to Android built-in TTS → file
    try {
      final lang = LanguageConstants.fromCode(languageCode);
      if (lang != null) {
        await _tts.setLanguage(lang.ttsLocale);
        await _tts.setSpeechRate(lang.ttsRate);
        await _tts.setPitch(lang.ttsPitch);
      }

      final dir  = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/vb_tts_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _tts.synthesizeToFile(text, path);
      final f = File(path);
      if (f.existsSync() && f.lengthSync() > 44) {
        return TtsResult(filePath: path, engine: 'android_builtin', success: true);
      }
    } catch (_) {}

    return const TtsResult(filePath: null, engine: 'android_builtin', success: false);
  }

  // ── Piper hook (auto-used when model is present) ──────────────────────────

  Future<TtsResult?> _tryPiper(String text, String languageCode) async {
    // Piper is an optional offline neural TTS.
    // If you add Piper ONNX models to <documents>/ai_model/piper/<lang>/,
    // this function will call PiperTts.synthesize().
    // For now we just check for presence.
    final docs = await getApplicationDocumentsDirectory();
    final piperModel = File('${docs.path}/ai_model/piper/$languageCode/model.onnx');
    if (!piperModel.existsSync()) return null;

    // TODO: integrate piper_flutter or custom ONNX Piper inference when models present.
    // Returning null here causes graceful fallback to Android TTS.
    return null;
  }

  // ── Check language availability ───────────────────────────────────────────

  Future<bool> isLanguageAvailable(String code) async {
    await init();
    final lang = LanguageConstants.fromCode(code);
    if (lang == null) return false;
    final result = await _tts.isLanguageAvailable(lang.ttsLocale);
    return result == 1;
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await _tts.stop();
  }
}
