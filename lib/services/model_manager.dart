// lib/services/model_manager.dart
// Manages all ONNX model files:
//   • Whisper small  → auto-download from HuggingFace
//   • Marian         → user-provided, checked in documents dir
//   • STT Correction → user-provided (optional)
//
// All models land in:  <documents>/ai_model/
//                      <documents>/ai_model/whisper/
//                      <documents>/ai_model/stt/

import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// ── File names (must match what LocalAIMiddleware expects) ────────────────────
class ModelFiles {
  // Marian translation
  static const String marianEncoder = 'marian-encoder.onnx';
  static const String marianDecoder = 'marian-decoder.onnx';
  static const String marianTokenizer = 'marian-tokenizer.json';

  // STT correction (T5) — optional
  static const String sttEncoder = 'stt-encoder.onnx';
  static const String sttDecoder = 'stt-decoder.onnx';
  static const String sttVocab = 'stt-vocab.json';
  static const String sttConfig = 'stt-config.json';

  // Whisper small (auto-download)
  static const String whisperEncoder = 'whisper-encoder.onnx';
  static const String whisperDecoder = 'whisper-decoder.onnx';
  static const String whisperVocab = 'whisper-vocab.json';
}

// ── HuggingFace download URLs ─────────────────────────────────────────────────
const _hfBase = 'https://huggingface.co';
const _whisperRepo = '$_hfBase/onnx-community/whisper-small/resolve/main/onnx';
const _whisperVocabUrl =
    '$_hfBase/openai/whisper-small/resolve/main/vocab.json';

const _whisperEncoderUrl = '$_whisperRepo/encoder_model_quantized.onnx';
const _whisperDecoderUrl = '$_whisperRepo/decoder_model_quantized.onnx';

// ── Status ────────────────────────────────────────────────────────────────────

enum ModelStatus { notFound, downloading, ready, error }

class ModelGroupStatus {
  final ModelStatus whisper;
  final ModelStatus marian;
  final ModelStatus stt; // optional
  final double whisperProgress; // 0..1
  final String? whisperProgressLabel;

  const ModelGroupStatus({
    required this.whisper,
    required this.marian,
    required this.stt,
    this.whisperProgress = 0.0,
    this.whisperProgressLabel,
  });

  bool get allCriticalReady =>
      marian == ModelStatus.ready && whisper == ModelStatus.ready;
}

// ── Download progress callback ────────────────────────────────────────────────

typedef DownloadProgressCallback = void Function(
    String file, double progress, String label);

// ── ModelManager singleton ────────────────────────────────────────────────────

class ModelManager {
  static final ModelManager _instance = ModelManager._();
  factory ModelManager() => _instance;
  ModelManager._();

  late Directory _modelDir;
  late Directory _whisperDir;
  late Directory _sttDir;

  bool _initialized = false;
  bool _downloading = false;

  final _statusController = StreamController<ModelGroupStatus>.broadcast();
  Stream<ModelGroupStatus> get statusStream => _statusController.stream;

  ModelGroupStatus _currentStatus = const ModelGroupStatus(
    whisper: ModelStatus.notFound,
    marian: ModelStatus.notFound,
    stt: ModelStatus.notFound,
  );
  ModelGroupStatus get currentStatus => _currentStatus;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    final docs = await getApplicationDocumentsDirectory();
    _modelDir = Directory('${docs.path}/ai_model')..createSync(recursive: true);
    _whisperDir = Directory('${_modelDir.path}/whisper')
      ..createSync(recursive: true);
    _sttDir = Directory('${_modelDir.path}/stt')..createSync(recursive: true);
    _initialized = true;

    // Extract bundled assets to app storage on first launch.
    // Mirrors Android's LocalAIMiddleware.extractBundledModels().
    // Skips files that already exist — fast on subsequent launches.
    await _extractBundledAssets();

    await refresh();
  }

  // ── Asset extraction ──────────────────────────────────────────────────────

  Future<void> _extractBundledAssets() async {
    final files = [
      ('assets/models/marian-encoder.onnx', marianEncoderPath),
      ('assets/models/marian-decoder.onnx', marianDecoderPath),
      ('assets/models/marian-tokenizer.json', marianTokenizerPath),
      ('assets/models/whisper/whisper-encoder.onnx', whisperEncoderPath),
      ('assets/models/whisper/whisper-decoder.onnx', whisperDecoderPath),
      ('assets/models/whisper/whisper-vocab.json', whisperVocabPath),
      // STT correction — optional, silently skipped if not bundled
      (
        'assets/models/stt/stt-encoder.onnx',
        '${_sttDir.path}/${ModelFiles.sttEncoder}'
      ),
      (
        'assets/models/stt/stt-decoder.onnx',
        '${_sttDir.path}/${ModelFiles.sttDecoder}'
      ),
      (
        'assets/models/stt/stt-vocab.json',
        '${_sttDir.path}/${ModelFiles.sttVocab}'
      ),
      (
        'assets/models/stt/stt-config.json',
        '${_sttDir.path}/${ModelFiles.sttConfig}'
      ),
    ];

    for (final (assetPath, destPath) in files) {
      final dest = File(destPath);
      if (dest.existsSync() && dest.lengthSync() > 1000)
        continue; // already extracted
      try {
        final data = await rootBundle.load(assetPath);
        final bytes = data.buffer.asUint8List();
        await dest.writeAsBytes(bytes, flush: true);
      } catch (_) {
        // Asset not bundled (e.g. STT files are optional) — skip silently
      }
    }
  }

  // ── Path helpers ──────────────────────────────────────────────────────────

  String get marianEncoderPath =>
      '${_modelDir.path}/${ModelFiles.marianEncoder}';
  String get marianDecoderPath =>
      '${_modelDir.path}/${ModelFiles.marianDecoder}';
  String get marianTokenizerPath =>
      '${_modelDir.path}/${ModelFiles.marianTokenizer}';

  String get whisperEncoderPath =>
      '${_whisperDir.path}/${ModelFiles.whisperEncoder}';
  String get whisperDecoderPath =>
      '${_whisperDir.path}/${ModelFiles.whisperDecoder}';
  String get whisperVocabPath =>
      '${_whisperDir.path}/${ModelFiles.whisperVocab}';

  String get sttEncoderPath => '${_sttDir.path}/${ModelFiles.sttEncoder}';
  String get sttDecoderPath => '${_sttDir.path}/${ModelFiles.sttDecoder}';
  String get sttVocabPath => '${_sttDir.path}/${ModelFiles.sttVocab}';

  Directory get modelDirectory => _modelDir;

  // ── Readiness checks ──────────────────────────────────────────────────────

  bool _fileReady(String path, {int minBytes = 1}) {
    final f = File(path);
    return f.existsSync() && f.lengthSync() >= minBytes;
  }

  // Then use smaller thresholds
  bool get isWhisperReady =>
      _fileReady(whisperEncoderPath) &&
      _fileReady(whisperDecoderPath) &&
      _fileReady(whisperVocabPath, minBytes: 1000);

  bool get isMarianReady =>
      _fileReady(marianEncoderPath) &&
      _fileReady(marianDecoderPath) &&
      _fileReady(marianTokenizerPath, minBytes: 1000);

  bool get isSttReady =>
      _fileReady(sttEncoderPath) && _fileReady(sttDecoderPath);

  double get installedSizeMb {
    double total = 0;
    for (final dir in [_modelDir, _whisperDir, _sttDir]) {
      if (dir.existsSync()) {
        for (final f in dir.listSync()) {
          if (f is File) total += f.lengthSync() / 1_000_000.0;
        }
      }
    }
    return total;
  }

  // ── Refresh status ────────────────────────────────────────────────────────

  Future<ModelGroupStatus> refresh() async {
    if (!_initialized) await init();
    final status = ModelGroupStatus(
      whisper: isWhisperReady ? ModelStatus.ready : ModelStatus.notFound,
      marian: isMarianReady ? ModelStatus.ready : ModelStatus.notFound,
      stt: isSttReady ? ModelStatus.ready : ModelStatus.notFound,
    );
    _emit(status);
    return status;
  }

  // ── Whisper auto-download ─────────────────────────────────────────────────

  Future<void> downloadWhisper({DownloadProgressCallback? onProgress}) async {
    if (_downloading) return;
    if (isWhisperReady) {
      await refresh();
      return;
    }
    _downloading = true;

    try {
      final files = [
        (
          url: _whisperEncoderUrl,
          path: whisperEncoderPath,
          label: 'Whisper encoder (~30 MB)'
        ),
        (
          url: _whisperDecoderUrl,
          path: whisperDecoderPath,
          label: 'Whisper decoder (~120 MB)'
        ),
        (
          url: _whisperVocabUrl,
          path: whisperVocabPath,
          label: 'Whisper vocab (~800 KB)'
        ),
      ];

      for (int i = 0; i < files.length; i++) {
        final item = files[i];
        if (_fileReady(item.path, minBytes: i == 2 ? 500_000 : 5_000_000)) {
          onProgress?.call(item.label, 1.0, '✅ Already downloaded');
          continue;
        }

        _emit(ModelGroupStatus(
          whisper: ModelStatus.downloading,
          marian: isMarianReady ? ModelStatus.ready : ModelStatus.notFound,
          stt: isSttReady ? ModelStatus.ready : ModelStatus.notFound,
          whisperProgress: i / files.length,
          whisperProgressLabel: 'Downloading ${item.label}…',
        ));

        await _downloadFile(
          url: item.url,
          savePath: item.path,
          onProgress: (received, total) {
            final pct = total > 0 ? received / total : 0.0;
            final baseProgress = i / files.length;
            final fileShare = 1.0 / files.length;
            onProgress?.call(item.label, pct,
                '${(pct * 100).toStringAsFixed(0)}%  —  ${item.label}');
            _emit(ModelGroupStatus(
              whisper: ModelStatus.downloading,
              marian: isMarianReady ? ModelStatus.ready : ModelStatus.notFound,
              stt: isSttReady ? ModelStatus.ready : ModelStatus.notFound,
              whisperProgress: baseProgress + pct * fileShare,
              whisperProgressLabel:
                  '${item.label}: ${(pct * 100).toStringAsFixed(0)}%',
            ));
          },
        );
      }

      _downloading = false;
      await refresh();
    } catch (e) {
      _downloading = false;
      _emit(ModelGroupStatus(
        whisper: ModelStatus.error,
        marian: isMarianReady ? ModelStatus.ready : ModelStatus.notFound,
        stt: isSttReady ? ModelStatus.ready : ModelStatus.notFound,
        whisperProgressLabel: '❌ Download failed: $e',
      ));
      rethrow;
    }
  }

  // ── Internal download helper ──────────────────────────────────────────────

  Future<void> _downloadFile({
    required String url,
    required String savePath,
    required void Function(int received, int total) onProgress,
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 20),
      headers: {'User-Agent': 'VoiceBridge-Flutter/2.0'},
    ));

    final tmpPath = '$savePath.part';
    try {
      await dio.download(
        url,
        tmpPath,
        onReceiveProgress: onProgress,
        options: Options(responseType: ResponseType.stream),
      );
      // Rename .part → final only after full download
      await File(tmpPath).rename(savePath);
    } catch (e) {
      File(tmpPath).deleteSync(recursive: false);
      rethrow;
    }
  }

  void _emit(ModelGroupStatus s) {
    _currentStatus = s;
    _statusController.add(s);
  }
}
