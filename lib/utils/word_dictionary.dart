// lib/utils/word_dictionary.dart
// Learns word-level pairs from verified translations.
// In production mode, known words are substituted before sending to Marian.

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class WordEntry {
  final String source;
  final String target;
  final String sourceLang;
  final String targetLang;
  final double confidence;
  final bool verified;
  int useCount;

  WordEntry({
    required this.source,
    required this.target,
    required this.sourceLang,
    required this.targetLang,
    required this.confidence,
    this.verified = false,
    this.useCount = 0,
  });

  Map<String, dynamic> toJson() => {
        's': source, 't': target, 'sl': sourceLang, 'tl': targetLang,
        'c': confidence, 'v': verified, 'u': useCount,
      };

  factory WordEntry.fromJson(Map<String, dynamic> j) => WordEntry(
        source: j['s'] ?? '', target: j['t'] ?? '',
        sourceLang: j['sl'] ?? '', targetLang: j['tl'] ?? '',
        confidence: (j['c'] ?? 0.5).toDouble(),
        verified: j['v'] ?? false, useCount: j['u'] ?? 0,
      );
}

class WordDictionary {
  static final WordDictionary _instance = WordDictionary._();
  factory WordDictionary() => _instance;
  WordDictionary._();

  static const String _fileName = 'word_dictionary.json';
  static const int _maxEntries  = 2000;

  // Nested: sourceLang → targetLang → sourceWord → WordEntry
  final Map<String, Map<String, Map<String, WordEntry>>> _dict = {};
  bool _loaded = false;

  Future<void> init() async {
    if (_loaded) return;
    await _load();
    _loaded = true;
  }

  int get size => _dict.values
      .expand((m) => m.values)
      .expand((m) => m.values)
      .length;

  // ── Word substitution pre-pass (production mode) ──────────────────────────
  // Returns text with known words/phrases substituted, plus a note if changed.

  ({String text, bool wasModified}) substituteKnownWords(
    String text,
    String sourceLang,
    String targetLang,
  ) {
    final slMap = _dict[sourceLang]?[targetLang];
    if (slMap == null || slMap.isEmpty) return (text: text, wasModified: false);

    String result = text;
    bool modified = false;

    // Try multi-word phrases first (longer matches win)
    final sortedKeys = slMap.keys.toList()
      ..sort((a, b) => b.split(' ').length - a.split(' ').length);

    for (final srcWord in sortedKeys) {
      final entry = slMap[srcWord]!;
      if (entry.confidence < 0.7) continue;
      // Case-insensitive whole-word replacement
      final pattern = RegExp(
        r'(?<![a-zA-Z\u0600-\u06FF])' +
            RegExp.escape(srcWord) +
            r'(?![a-zA-Z\u0600-\u06FF])',
        caseSensitive: false,
      );
      if (pattern.hasMatch(result)) {
        result = result.replaceAll(pattern, entry.target);
        entry.useCount++;
        modified = true;
      }
    }

    return (text: result, wasModified: modified);
  }

  // ── Learn from a verified translation pair ────────────────────────────────

  Future<void> learnFromTranslation({
    required String sourceText,
    required String targetText,
    required String sourceLang,
    required String targetLang,
    required bool verified,
  }) async {
    if (!verified) return;

    final srcWords = sourceText.toLowerCase().split(RegExp(r'\s+'));
    final tgtWords = targetText.toLowerCase().split(RegExp(r'\s+'));

    // Simple word alignment: align by position for same-length sentences
    if (srcWords.length == tgtWords.length && srcWords.length <= 10) {
      for (int i = 0; i < srcWords.length; i++) {
        final sw = srcWords[i].replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '');
        final tw = tgtWords[i].replaceAll(RegExp(r'[^\w]'), '');
        if (sw.length > 2 && tw.length > 2) {
          _addEntry(sw, tw, sourceLang, targetLang, 0.8, verified: true);
        }
      }
    }

    // Also store the full phrase if short enough
    if (srcWords.length <= 4) {
      _addEntry(
        sourceText.trim().toLowerCase(),
        targetText.trim(),
        sourceLang, targetLang, 0.9,
        verified: verified,
      );
    }

    await _save();
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _addEntry(
    String src, String tgt,
    String sl, String tl,
    double confidence, {
    bool verified = false,
  }) {
    if (src.isEmpty || tgt.isEmpty) return;
    _dict.putIfAbsent(sl, () => {});
    _dict[sl]!.putIfAbsent(tl, () => {});
    final existing = _dict[sl]![tl]![src];
    if (existing == null || confidence > existing.confidence) {
      _dict[sl]![tl]![src] = WordEntry(
        source: src, target: tgt,
        sourceLang: sl, targetLang: tl,
        confidence: confidence, verified: verified,
      );
    }
  }

  Future<void> _load() async {
    try {
      final dir  = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      if (!file.existsSync()) return;
      final list = jsonDecode(await file.readAsString()) as List<dynamic>;
      for (final item in list) {
        final e = WordEntry.fromJson(item as Map<String, dynamic>);
        _dict.putIfAbsent(e.sourceLang, () => {});
        _dict[e.sourceLang]!.putIfAbsent(e.targetLang, () => {});
        _dict[e.sourceLang]![e.targetLang]![e.source] = e;
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final all = _dict.values
          .expand((m) => m.values)
          .expand((m) => m.values)
          .toList();
      final dir  = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      await file.writeAsString(jsonEncode(all.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}
