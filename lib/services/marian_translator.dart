// lib/services/marian_translator.dart
// Dart port of MarianTranslator.kt
// On-device Urdu→English translation via Helsinki-NLP/opus-mt-ur-en ONNX.
//
// Pipeline:
//   text → MarianTokenizer.encode() → encoder ONNX → decoder ONNX (greedy) → decoded text
//
// Model files required (in <documents>/ai_model/):
//   marian-encoder.onnx  (~15 MB)
//   marian-decoder.onnx  (~40 MB)
//   marian-tokenizer.json

import 'dart:io';
import 'dart:typed_data';
import 'package:onnxruntime/onnxruntime.dart';
import 'marian_tokenizer.dart';
import 'model_manager.dart';

class MarianTranslator {
  static const int _maxDecSteps = 128;
  static const int _maxInputToks = 512;

  OrtSession? _encoderSession;
  OrtSession? _decoderSession;
  MarianTokenizer? _tokenizer;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> load() async {
    try {
      final mm = ModelManager();
      final tok = MarianTokenizer();
      await tok.load(mm.marianTokenizerPath);

      final opts = OrtSessionOptions()
        ..setIntraOpNumThreads(2)
        ..setInterOpNumThreads(2);

      _encoderSession = OrtSession.fromFile(File(mm.marianEncoderPath), opts);
      _decoderSession = OrtSession.fromFile(File(mm.marianDecoderPath), opts);
      _tokenizer = tok;
      _loaded = true;
    } catch (e) {
      _loaded = false;
      rethrow;
    }
  }

  // ── Translate ─────────────────────────────────────────────────────────────

  /// Translate [sourceText] (Urdu / Urdish) to English.
  /// Returns null if model is not loaded or inference fails.
  Future<String?> translateToEnglish(String sourceText) async {
    if (!_loaded || sourceText.trim().isEmpty) return null;
    final enc = _encoderSession!;
    final dec = _decoderSession!;
    final tok = _tokenizer!;

    try {
      // ── Step 1: Tokenize ─────────────────────────────────────────────────
      final inputIds = tok.encode(sourceText.trim(), _maxInputToks);
      if (inputIds.isEmpty) return null;

      final seqLen = inputIds.length;
      final idData =
          Int64List.fromList(inputIds.map((v) => v.toInt()).toList());
      final maskData = Int64List(seqLen)..fillRange(0, seqLen, 1);

      // ── Step 2: Encode ───────────────────────────────────────────────────
      final encIds =
          OrtValueTensor.createTensorWithDataList(idData, [1, seqLen]);
      final encMask =
          OrtValueTensor.createTensorWithDataList(maskData, [1, seqLen]);

      final encOut = enc.run(OrtRunOptions(), {
        'input_ids': encIds,
        'attention_mask': encMask,
      });

      encIds.release();
      encMask.release();

      // hidden_state shape: [1, seqLen, hiddenSize]
      final hiddenTensor = encOut.first as OrtValueTensor;

      // ── Step 3: Greedy decode ────────────────────────────────────────────
      // MarianMT decoder starts with padId (not a language tag)
      final generated = <int>[tok.padId];

      for (int step = 0; step < _maxDecSteps; step++) {
        final decLen = generated.length;
        final decIds =
            Int64List.fromList(generated.map((v) => v.toInt()).toList());
        final decMask = Int64List(seqLen)..fillRange(0, seqLen, 1);

        final decIdTensor =
            OrtValueTensor.createTensorWithDataList(decIds, [1, decLen]);
        final decMaskTensor =
            OrtValueTensor.createTensorWithDataList(decMask, [1, seqLen]);

        final decOut = dec.run(OrtRunOptions(), {
          'input_ids': decIdTensor,
          'encoder_hidden_states': hiddenTensor,
          'encoder_attention_mask': decMaskTensor,
        });

        decIdTensor.release();
        decMaskTensor.release();

        // logits shape: [1, decLen, vocabSize]  — take last position
        final logitsTensor = decOut.first as OrtValueTensor;
        final logits = logitsTensor.value as List<dynamic>;

        // logits[0][decLen-1] = float list over vocab
        final lastLogits = (logits[0] as List<dynamic>).last as List<dynamic>;
        int nextToken = 0;
        double maxVal = double.negativeInfinity;
        for (int i = 0; i < lastLogits.length; i++) {
          final v = (lastLogits[i] as num).toDouble();
          if (v > maxVal) {
            maxVal = v;
            nextToken = i;
          }
        }

        logitsTensor.release();

        if (nextToken == tok.eosId || nextToken == tok.padId) break;
        generated.add(nextToken);
      }

      hiddenTensor.release();

      // ── Step 4: Decode ───────────────────────────────────────────────────
      final outputIds = generated.skip(1).toList(); // drop leading padId
      final result = tok.decode(outputIds);
      return result.isEmpty ? null : result;
    } catch (e) {
      return null;
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  void close() {
    _encoderSession?.release();
    _decoderSession?.release();
    _encoderSession = null;
    _decoderSession = null;
    _tokenizer = null;
    _loaded = false;
  }
}
