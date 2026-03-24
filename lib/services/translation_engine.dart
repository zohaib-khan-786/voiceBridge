// lib/services/translation_engine.dart
// Full translation pipeline — exact port of the Android pipeline:
//
//   Step 0: FuzzyMatcher      — fix STT spelling errors (Roman Urdu)
//   Step 1: UrduSlangNormalizer — slang/Urdish → standard Urdu
//   Step 2: WordDictionary    — substitute known words (production mode)
//   Step 3: TranslationCache  — return cached result if available
//   Step 4: MarianTranslator  — on-device Urdu→English ONNX
//   Step 5: Store result in cache + word dictionary
//
// No Google services. No network calls during translation.

import 'package:flutter/foundation.dart';
import 'marian_translator.dart';
import '../utils/fuzzy_matcher.dart';
import '../utils/urdu_slang_normalizer.dart';
import '../utils/word_dictionary.dart';
import '../utils/translation_cache.dart';
import '../utils/translation_context.dart';

// Re-export so callers only need to import this one file.
export '../utils/translation_cache.dart' show CacheStats, CacheEntryType;

// ── Result type ───────────────────────────────────────────────────────────────

class TranslationResult {
  final String original;
  final String translated;
  final String normNote;
  final String correctionNote;
  final bool   fromCache;
  final double confidence;
  final String sourceLang;
  final String targetLang;

  const TranslationResult({
    required this.original,
    required this.translated,
    this.normNote       = '',
    this.correctionNote = '',
    this.fromCache      = false,
    this.confidence     = 1.0,
    required this.sourceLang,
    required this.targetLang,
  });

  bool get hasTranslation => translated.isNotEmpty && translated != original;
}

// ── Engine singleton ──────────────────────────────────────────────────────────

class TranslationEngine {
  static final TranslationEngine _instance = TranslationEngine._();
  factory TranslationEngine() => _instance;
  TranslationEngine._();

  final MarianTranslator   _marian  = MarianTranslator();
  final WordDictionary     _dict    = WordDictionary();
  final TranslationCache   _cache   = TranslationCache();
  final TranslationContext _context = TranslationContext();

  bool _marianLoaded  = false;
  bool _initializing  = false;
  bool _isInitialized = false;

  bool get isMarianLoaded => _marianLoaded;
  bool get isInitialized  => _isInitialized;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initializing || _isInitialized) return;
    _initializing = true;

    await _cache.init();
    await _dict.init();

    try {
      await _marian.load();
      _marianLoaded = true;
      debugPrint('[TranslationEngine] Marian READY');
    } catch (e) {
      _marianLoaded = false;
      debugPrint('[TranslationEngine] Marian load failed: $e — cache only mode');
    }

    _initializing  = false;
    _isInitialized = true;
  }

  // ── Main translate ────────────────────────────────────────────────────────

  Future<TranslationResult> translate({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    if (text.trim().isEmpty) {
      return TranslationResult(
        original: text, translated: text,
        sourceLang: sourceLang, targetLang: targetLang,
      );
    }

    String working        = text.trim();
    String correctionNote = '';
    String normNote       = '';

    // Step 0: Fuzzy spelling correction (Roman Urdu only)
    if (sourceLang == 'ur') {
      final fuzzy = FuzzyMatcher.correct(working);
      if (fuzzy.wasModified) {
        working        = fuzzy.corrected;
        correctionNote = '🔤 ${fuzzy.changesApplied.take(2).join(', ')}';
      }
    }

    // Step 1: Slang / Urdish normalisation
    if (sourceLang == 'ur') {
      final normalized = UrduSlangNormalizer.normalize(working, sourceLang);
      if (normalized.wasModified) {
        normNote = UrduSlangNormalizer.describeChanges(working, normalized);
        working  = normalized.text;
      }
    }

    // Step 2: Cache lookup — must happen BEFORE word dict substitution.
    // userCorrect() keys the cache on the original (pre-dict) text, and also
    // writes that same text into the word dictionary. If word dict ran first it
    // would rewrite `working` to the target value, and the subsequent cache
    // lookup would miss. Checking the cache first avoids that race.
    final cached = _cache.lookup(working, sourceLang, targetLang);
    if (cached != null) {
      _context.recordTranslation(
        source: text, target: cached,
        sourceLang: sourceLang, targetLang: targetLang,
      );
      return TranslationResult(
        original: text, translated: cached,
        normNote: normNote, correctionNote: correctionNote,
        fromCache: true, sourceLang: sourceLang, targetLang: targetLang,
      );
    }

    // Step 3: Word dictionary substitution (improves model input quality)
    final dictResult = _dict.substituteKnownWords(working, sourceLang, targetLang);
    if (dictResult.wasModified) working = dictResult.text;

    // Step 4: Marian ONNX inference
    String? translated;
    if (_marianLoaded && sourceLang == 'ur') {
      translated = await _marian.translateToEnglish(working);
    }

    // Step 5: Fallback — return working text; UI shows "model not loaded" badge
    translated ??= (sourceLang == targetLang) ? text : working;
    final finalTranslation = translated;

    // Step 6: Cache it
    await _cache.store(
      source: working, target: finalTranslation,
      sourceLang: sourceLang, targetLang: targetLang,
      type: CacheEntryType.modelBasic,
    );

    // Step 7: Session context
    _context.recordTranslation(
      source: text, target: finalTranslation,
      sourceLang: sourceLang, targetLang: targetLang,
    );

    // Step 8: Learn word pairs
    await _dict.learnFromTranslation(
      sourceText: working, targetText: finalTranslation,
      sourceLang: sourceLang, targetLang: targetLang,
      verified: false,
    );

    return TranslationResult(
      original: text, translated: finalTranslation,
      normNote: normNote, correctionNote: correctionNote,
      fromCache: false,
      confidence: _marianLoaded ? 0.85 : 0.5,
      sourceLang: sourceLang, targetLang: targetLang,
    );
  }

  // ── User corrects a translation ──────────────────────────────────────────

  Future<void> userCorrect({
    required String source,
    required String corrected,
    required String sourceLang,
    required String targetLang,
  }) async {
    await _cache.userCorrect(
      source: source, corrected: corrected,
      sourceLang: sourceLang, targetLang: targetLang,
    );
    await _dict.learnFromTranslation(
      sourceText: source, targetText: corrected,
      sourceLang: sourceLang, targetLang: targetLang,
      verified: true,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void clearSession()              => _context.clearSession();
  CacheStats get cacheStats        => _cache.getStats();
  int        get dictionarySize    => _dict.size;

  Future<String> exportTrainingData() async {
    final file = await _cache.exportTrainingData();
    return file.path;
  }

  void close() {
    _marian.close();
    _marianLoaded  = false;
    _isInitialized = false;
  }
}