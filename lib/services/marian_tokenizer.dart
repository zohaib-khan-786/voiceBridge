// lib/services/marian_tokenizer.dart
// Dart port of MarianTokenizer.kt
// Supports Unigram (SentencePiece) and BPE tokenizer.json formats.
// Used for Marian (opus-mt-ur-en) and T5 (STT correction) models.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

class MarianTokenizer {
  final Map<String, int> _vocab     = {};
  final Map<int, String> _idToToken = {};
  final List<(String, String)> _merges = []; // BPE merges
  final Map<String, double> _scores  = {};   // Unigram scores

  String _modelType = 'Unigram';

  int padId  = 65001;
  int eosId  = 0;
  int unkId  = 1;
  int vocabSize = 65002;

  static const String _wordBoundary = '▁'; // U+2581

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> load(String tokenizerPath) async {
    final raw  = await File(tokenizerPath).readAsString();
    final json = jsonDecode(raw) as Map<String, dynamic>;

    final model = json['model'] as Map<String, dynamic>?;
    
    // ── Handle two formats ────────────────────────────────────────────────────
    // Format 1: Full HuggingFace tokenizer.json with "model" key
    // Format 2: Simple vocab mapping {"token": id, ...} used by older Marian
    
    if (model != null) {
      // Full tokenizer.json format
      _modelType = model['type'] as String? ?? 'Unigram';

      if (_modelType == 'Unigram') {
        _loadUnigram(model);
      } else {
        _loadBpe(model);
      }

      // Override special tokens from added_tokens
      final added = json['added_tokens'] as List<dynamic>?;
      if (added != null) {
        for (final t in added) {
          final content = t['content'] as String?;
          final id      = t['id']      as int?;
          if (content != null && id != null) {
            _vocab[content]   = id;
            _idToToken[id]    = content;
            switch (content) {
              case '<pad>': padId = id;
              case '</s>':  eosId = id;
              case '<unk>': unkId = id;
            }
          }
        }
      }
    } else {
      // Simple vocab format: {"token": id, ...}
      _modelType = 'BPE'; // Default to BPE for simple vocab
      
      for (final entry in json.entries) {
        final token = entry.key;
        final id = entry.value as int;
        _vocab[token] = id;
        _idToToken[id] = token;
        
        // Detect special tokens
        switch (token) {
          case '<pad>': padId = id;
          case '</s>':  eosId = id;
          case '<unk>': unkId = id;
        }
      }
    }

    vocabSize = _idToToken.keys.fold(0, math.max) + 1;
  }

  void _loadUnigram(Map<String, dynamic> model) {
    final vocabArr = model['vocab'] as List<dynamic>?;
    if (vocabArr == null) return;
    for (int i = 0; i < vocabArr.length; i++) {
      final item  = vocabArr[i] as List<dynamic>;
      final token = item[0] as String;
      final score = (item[1] as num).toDouble();
      _vocab[token]   = i;
      _idToToken[i]   = token;
      _scores[token]  = score;
    }
  }

  void _loadBpe(Map<String, dynamic> model) {
    final vocabObj = model['vocab'] as Map<String, dynamic>?;
    if (vocabObj != null) {
      for (final e in vocabObj.entries) {
        final id = e.value as int;
        _vocab[e.key]  = id;
        _idToToken[id] = e.key;
      }
    }
    final mergesArr = model['merges'] as List<dynamic>?;
    if (mergesArr != null) {
      for (final m in mergesArr) {
        final parts = (m as String).split(' ');
        if (parts.length == 2) _merges.add((parts[0], parts[1]));
      }
    }
  }

  // ── Encode ────────────────────────────────────────────────────────────────

  List<int> encode(String text, [int maxTokens = 512]) {
    if (text.trim().isEmpty) return [];
    final words = text.trim().split(RegExp(r'\s+'));
    final ids   = <int>[];

    for (int wi = 0; wi < words.length && ids.length < maxTokens; wi++) {
      final word = (wi == 0 ? '' : _wordBoundary) + words[wi];
      if (_modelType == 'BPE') {
        ids.addAll(_encodeBpe(word));
      } else {
        ids.addAll(_encodeUnigram(word));
      }
    }

    if (ids.length > maxTokens) return ids.sublist(0, maxTokens);
    return ids;
  }

  // ── Decode ────────────────────────────────────────────────────────────────

  String decode(List<int> ids) {
    final sb = StringBuffer();
    for (final id in ids) {
      final token = _idToToken[id] ?? '';
      if (token == '</s>' || token == '<pad>') break;
      sb.write(token);
    }
    return sb.toString().replaceAll(_wordBoundary, ' ').trim();
  }

  // ── BPE encoding ──────────────────────────────────────────────────────────

  List<int> _encodeBpe(String word) {
    // Start with individual characters
    var symbols = word.characters.map((c) => c).toList();

    // Apply BPE merges greedily
    bool merged = true;
    while (merged && symbols.length > 1) {
      merged = false;
      int bestIdx = -1;
      int bestPriority = _merges.length + 1;

      for (int i = 0; i < symbols.length - 1; i++) {
        final pair = (symbols[i], symbols[i + 1]);
        final pri  = _merges.indexOf(pair);
        if (pri >= 0 && pri < bestPriority) {
          bestPriority = pri;
          bestIdx = i;
        }
      }

      if (bestIdx >= 0) {
        final merged_ = symbols[bestIdx] + symbols[bestIdx + 1];
        symbols = [
          ...symbols.sublist(0, bestIdx),
          merged_,
          ...symbols.sublist(bestIdx + 2),
        ];
        merged = true;
      }
    }

    return symbols.map((s) => _vocab[s] ?? unkId).toList();
  }

  // ── Unigram (Viterbi) encoding ────────────────────────────────────────────

  List<int> _encodeUnigram(String word) {
    final n    = word.length;
    // best[i] = best score to segment word[0..i]
    final best = List.filled(n + 1, double.negativeInfinity);
    final from = List.filled(n + 1, -1);
    final tok  = List.filled(n + 1, '');
    best[0] = 0.0;

    for (int i = 0; i < n; i++) {
      if (best[i].isInfinite && i != 0) continue;
      for (int j = i + 1; j <= n; j++) {
        final sub = word.substring(i, j);
        final sc  = _scores[sub] ?? _scores[_wordBoundary + sub];
        if (sc != null) {
          final newSc = best[i] + sc;
          if (newSc > best[j]) {
            best[j] = newSc;
            from[j] = i;
            tok[j]  = sub;
          }
        }
      }
    }

    // Fallback: character-level if Viterbi found nothing
    if (best[n].isInfinite) {
      return word.characters.map((c) => _vocab[c] ?? unkId).toList();
    }

    // Trace back
    final tokens = <String>[];
    int cur = n;
    while (cur > 0) {
      tokens.add(tok[cur]);
      cur = from[cur];
    }
    return tokens.reversed.map((t) => _vocab[t] ?? unkId).toList();
  }
}

// Extension for character iteration (needed for older Dart compat)
extension _CharExt on String {
  List<String> get characters {
    final result = <String>[];
    for (final rune in runes) {
      result.add(String.fromCharCode(rune));
    }
    return result;
  }
}