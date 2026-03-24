// lib/utils/translation_cache.dart
// Self-improving translation cache. Stores verified translations so the
// pipeline never re-translates a sentence it has seen before.
//
// Entry types (ascending quality):
//   MODEL_BASIC          — first inference result
//   MODEL_HIGH_CONFIDENCE — inference result with high confidence score
//   USER_VERIFIED        — user manually corrected the translation
//
// Storage: JSON file in app documents directory.

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

enum CacheEntryType { modelBasic, modelHighConfidence, userVerified }

class CacheEntry {
  final String source;
  final String target;
  final String sourceLang;
  final String targetLang;
  final CacheEntryType type;
  final DateTime timestamp;
  int useCount;

  CacheEntry({
    required this.source,
    required this.target,
    required this.sourceLang,
    required this.targetLang,
    required this.type,
    DateTime? timestamp,
    this.useCount = 0,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'src': source, 'tgt': target,
        'sl': sourceLang, 'tl': targetLang,
        'type': type.index,
        'ts': timestamp.millisecondsSinceEpoch,
        'uses': useCount,
      };

  factory CacheEntry.fromJson(Map<String, dynamic> j) => CacheEntry(
        source: j['src'] ?? '',
        target: j['tgt'] ?? '',
        sourceLang: j['sl'] ?? '',
        targetLang: j['tl'] ?? '',
        type: CacheEntryType.values[j['type'] ?? 0],
        timestamp: DateTime.fromMillisecondsSinceEpoch(j['ts'] ?? 0),
        useCount: j['uses'] ?? 0,
      );
}

class CacheStats {
  final int totalCached;
  final int userVerified;
  final int modelHighConf;

  const CacheStats({
    required this.totalCached,
    required this.userVerified,
    required this.modelHighConf,
  });
}

class TranslationCache {
  static final TranslationCache _instance = TranslationCache._();
  factory TranslationCache() => _instance;
  TranslationCache._();

  static const String _fileName = 'translation_cache.json';
  static const int _maxEntries  = 5000;

  final Map<String, CacheEntry> _cache = {};
  bool _loaded = false;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_loaded) return;
    await _load();
    _loaded = true;
  }

  // ── Lookup ────────────────────────────────────────────────────────────────

  String? lookup(String source, String sourceLang, String targetLang) {
    final key = _key(source.trim().toLowerCase(), sourceLang, targetLang);
    final entry = _cache[key];
    if (entry != null) {
      entry.useCount++;
      return entry.target;
    }
    return null;
  }

  // ── Store ─────────────────────────────────────────────────────────────────

  Future<void> store({
    required String source,
    required String target,
    required String sourceLang,
    required String targetLang,
    CacheEntryType type = CacheEntryType.modelBasic,
  }) async {
    final key = _key(source.trim().toLowerCase(), sourceLang, targetLang);
    final existing = _cache[key];

    // Only upgrade, never downgrade quality
    if (existing != null && existing.type.index >= type.index) return;

    _cache[key] = CacheEntry(
      source: source.trim(),
      target: target.trim(),
      sourceLang: sourceLang,
      targetLang: targetLang,
      type: type,
    );

    // Prune if too large (remove oldest basic entries)
    if (_cache.length > _maxEntries) _pruneOldest();

    await _save();
  }

  // ── User correction ───────────────────────────────────────────────────────

  Future<void> userCorrect({
    required String source,
    required String corrected,
    required String sourceLang,
    required String targetLang,
  }) => store(
        source: source,
        target: corrected,
        sourceLang: sourceLang,
        targetLang: targetLang,
        type: CacheEntryType.userVerified,
      );

  // ── Stats ─────────────────────────────────────────────────────────────────

  CacheStats getStats() {
    int userVerified = 0, highConf = 0;
    for (final e in _cache.values) {
      if (e.type == CacheEntryType.userVerified) userVerified++;
      if (e.type == CacheEntryType.modelHighConfidence) highConf++;
    }
    return CacheStats(
      totalCached: _cache.length,
      userVerified: userVerified,
      modelHighConf: highConf,
    );
  }

  // ── Export training data ──────────────────────────────────────────────────

  Future<File> exportTrainingData() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/training_export_${DateTime.now().millisecondsSinceEpoch}.jsonl');
    final sink = file.openWrite();
    for (final e in _cache.values) {
      if (e.type.index >= CacheEntryType.modelHighConfidence.index) {
        sink.writeln(jsonEncode({'src': e.source, 'tgt': e.target, 'sl': e.sourceLang, 'tl': e.targetLang}));
      }
    }
    await sink.flush();
    await sink.close();
    return file;
  }

  // ── Private ───────────────────────────────────────────────────────────────

  String _key(String src, String sl, String tl) => '$sl|$tl|$src';

  void _pruneOldest() {
    final entries = _cache.entries.toList()
      ..sort((a, b) {
        // Keep user verified entries last (highest priority)
        if (a.value.type != b.value.type) return a.value.type.index - b.value.type.index;
        return a.value.timestamp.compareTo(b.value.timestamp);
      });
    final toRemove = entries.take(entries.length - (_maxEntries * 9 ~/ 10)).map((e) => e.key);
    for (final k in toRemove) {
      _cache.remove(k);
    }
  }

  Future<void> _load() async {
    try {
      final dir  = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      if (!file.existsSync()) return;
      final list = jsonDecode(await file.readAsString()) as List<dynamic>;
      for (final item in list) {
        final e   = CacheEntry.fromJson(item as Map<String, dynamic>);
        final key = _key(e.source.toLowerCase(), e.sourceLang, e.targetLang);
        _cache[key] = e;
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final dir  = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      await file.writeAsString(jsonEncode(_cache.values.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}
