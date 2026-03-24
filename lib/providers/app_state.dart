// lib/providers/app_state.dart
// Central state management — equivalent to the combination of
// MainActivity state + OverlayService state from the Android app.
// Uses ChangeNotifier so all screens rebuild automatically.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/translation_engine.dart';
import '../services/whisper_stt.dart';
import '../services/tts_service.dart';
import '../services/model_manager.dart';
import '../utils/language_constants.dart';
import '../utils/translation_cache.dart';

// ── App mode (training vs production) ────────────────────────────────────────

enum AppMode { production, training }

// ── Recording / processing state ──────────────────────────────────────────────

enum RecordingState { idle, recording, processing, done, error }

// ── AppState ──────────────────────────────────────────────────────────────────

class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  // ── Services ──────────────────────────────────────────────────────────────
  final TranslationEngine _engine = TranslationEngine();
  final WhisperSTT        _whisper = WhisperSTT();
  final TtsService        _tts     = TtsService();
  final ModelManager      _models  = ModelManager();

  // ── Settings ──────────────────────────────────────────────────────────────
  Language _sourceLang = LanguageConstants.defaultSource;
  Language _targetLang = LanguageConstants.defaultTarget;
  AppMode  _appMode    = AppMode.production;
  bool     _isDarkMode = true;

  Language get sourceLang => _sourceLang;
  Language get targetLang => _targetLang;
  AppMode  get appMode    => _appMode;
  bool     get isDarkMode => _isDarkMode;

  // ── Model status ──────────────────────────────────────────────────────────
  ModelGroupStatus _modelStatus = const ModelGroupStatus(
    whisper: ModelStatus.notFound,
    marian:  ModelStatus.notFound,
    stt:     ModelStatus.notFound,
  );
  ModelGroupStatus get modelStatus => _modelStatus;

  bool get isMarianReady  => _models.isMarianReady;
  bool get isWhisperReady => _models.isWhisperReady;
  double get installedModelsMb => _models.installedSizeMb;

  // ── Recording / transcription ─────────────────────────────────────────────
  RecordingState _recordingState = RecordingState.idle;
  String _transcribedText        = '';
  String _translatedText         = '';
  String _statusMessage          = '';
  String _normNote               = '';
  String _correctionNote         = '';
  bool   _fromCache              = false;
  double _confidence             = 1.0;

  RecordingState get recordingState  => _recordingState;
  String get transcribedText         => _transcribedText;
  String get translatedText          => _translatedText;
  String get statusMessage           => _statusMessage;
  String get normNote                => _normNote;
  String get correctionNote          => _correctionNote;
  bool   get fromCache               => _fromCache;
  double get confidence              => _confidence;
  bool   get hasResult               => _translatedText.isNotEmpty;

  // ── Stats ─────────────────────────────────────────────────────────────────
  CacheStats get cacheStats => _engine.cacheStats;
  int        get dictSize   => _engine.dictionarySize;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    await _loadPrefs();
    await _models.init();

    // Subscribe to model status changes
    _models.statusStream.listen((status) {
      _modelStatus = status;
      notifyListeners();
    });
    _modelStatus = _models.currentStatus;

    // Init engine (loads Marian if available)
    await _engine.init();

    // Init whisper if ready
    if (_models.isWhisperReady) {
      try {
        await _whisper.load();
      } catch (_) {}
    }

    await _tts.init();
    notifyListeners();
  }

  // ── Language selection ────────────────────────────────────────────────────

  Future<void> setSourceLang(Language lang) async {
    _sourceLang = lang;
    await _savePrefs();
    notifyListeners();
  }

  Future<void> setTargetLang(Language lang) async {
    _targetLang = lang;
    await _savePrefs();
    notifyListeners();
  }

  void swapLanguages() {
    final tmp = _sourceLang;
    _sourceLang = _targetLang;
    _targetLang = tmp;
    _savePrefs();
    notifyListeners();
  }

  // ── App mode ──────────────────────────────────────────────────────────────

  Future<void> setAppMode(AppMode mode) async {
    _appMode = mode;
    await _savePrefs();
    notifyListeners();
  }

  // ── Theme ─────────────────────────────────────────────────────────────────

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    await _savePrefs();
    notifyListeners();
  }

  // ── Translation ───────────────────────────────────────────────────────────

  Future<void> translateText(String text) async {
    if (text.trim().isEmpty) return;
    _recordingState = RecordingState.processing;
    _statusMessage  = '⏳ Translating…';
    notifyListeners();

    try {
      final result = await _engine.translate(
        text:       text,
        sourceLang: _sourceLang.code,
        targetLang: _targetLang.code,
      );

      _transcribedText = result.original;
      _translatedText  = result.translated;
      _normNote        = result.normNote;
      _correctionNote  = result.correctionNote;
      _fromCache       = result.fromCache;
      _confidence      = result.confidence;
      _recordingState  = RecordingState.done;
      _statusMessage   = result.fromCache ? '⚡ From cache' : '✅ Translated';
    } catch (e) {
      _recordingState = RecordingState.error;
      _statusMessage  = '❌ Translation failed: $e';
      _translatedText = '';
    }
    notifyListeners();
  }

  // ── STT + translate pipeline ──────────────────────────────────────────────

  Future<String?> transcribeFile(String wavPath) async {
    if (!_whisper.isLoaded) {
      _statusMessage = '⚠️ Whisper model not loaded';
      notifyListeners();
      return null;
    }
    _recordingState = RecordingState.processing;
    _statusMessage  = '🎙 Transcribing…';
    notifyListeners();

    try {
      final text = await _whisper.transcribeWav(wavPath, _sourceLang.code);
      if (text.isNotEmpty) {
        _transcribedText = text;
        _statusMessage   = '✅ Transcribed';
        notifyListeners();
        await translateText(text);
      } else {
        _recordingState = RecordingState.error;
        _statusMessage  = '⚠️ No speech detected';
        notifyListeners();
      }
      return text.isEmpty ? null : text;
    } catch (e) {
      _recordingState = RecordingState.error;
      _statusMessage  = '❌ Transcription failed: $e';
      notifyListeners();
      return null;
    }
  }

  // ── TTS ───────────────────────────────────────────────────────────────────

  Future<void> speakTranslated() async {
    if (_translatedText.isEmpty) return;
    await _tts.speak(_translatedText, _targetLang.code);
  }

  Future<void> speakOriginal() async {
    if (_transcribedText.isEmpty) return;
    await _tts.speak(_transcribedText, _sourceLang.code);
  }

  Future<void> stopSpeaking() => _tts.stop();

  // ── User correction ───────────────────────────────────────────────────────

  Future<void> userCorrect(String corrected) async {
    await _engine.userCorrect(
      source:     _transcribedText,
      corrected:  corrected,
      sourceLang: _sourceLang.code,
      targetLang: _targetLang.code,
    );
    _translatedText = corrected;
    _statusMessage  = '✅ Correction saved';
    notifyListeners();
  }

  // ── Model download ────────────────────────────────────────────────────────

  Future<void> downloadWhisper({void Function(String label, double progress)? onProgress}) async {
    await _models.downloadWhisper(
      onProgress: (file, progress, label) => onProgress?.call(label, progress),
    );
    if (_models.isWhisperReady && !_whisper.isLoaded) {
      try { await _whisper.load(); } catch (_) {}
    }
    notifyListeners();
  }

  // ── Export training data ──────────────────────────────────────────────────

  Future<String> exportTrainingData() => _engine.exportTrainingData();

  // ── Reset UI state ────────────────────────────────────────────────────────

  void resetResult() {
    _recordingState  = RecordingState.idle;
    _transcribedText = '';
    _translatedText  = '';
    _statusMessage   = '';
    _normNote        = '';
    _correctionNote  = '';
    _fromCache       = false;
    _confidence      = 1.0;
    _engine.clearSession();
    notifyListeners();
  }

  // ── Prefs ─────────────────────────────────────────────────────────────────

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('source_lang', _sourceLang.code);
    await prefs.setString('target_lang', _targetLang.code);
    await prefs.setBool('dark_mode', _isDarkMode);
    await prefs.setString('app_mode', _appMode.name);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final srcCode = prefs.getString('source_lang') ?? 'ur';
    final tgtCode = prefs.getString('target_lang') ?? 'en';
    _sourceLang = LanguageConstants.fromCode(srcCode) ?? LanguageConstants.defaultSource;
    _targetLang = LanguageConstants.fromCode(tgtCode) ?? LanguageConstants.defaultTarget;
    _isDarkMode = prefs.getBool('dark_mode') ?? true;
    final modeStr = prefs.getString('app_mode') ?? 'production';
    _appMode = modeStr == 'training' ? AppMode.training : AppMode.production;
  }

  @override
  void dispose() {
    _engine.close();
    _tts.dispose();
    super.dispose();
  }
}
