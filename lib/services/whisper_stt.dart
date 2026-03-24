// lib/services/whisper_stt.dart
// On-device Whisper (small, ONNX) speech-to-text.
// Dart port of LocalWhisperSTT.kt — same mel spectrogram, same FFT,
// same greedy decoder, same byte-level BPE vocab decode.
//
// Model files (auto-downloaded to <documents>/ai_model/whisper/):
//   whisper-encoder.onnx  (~30 MB)
//   whisper-decoder.onnx  (~120 MB)
//   whisper-vocab.json    (~800 KB)

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:onnxruntime/onnxruntime.dart';
import 'model_manager.dart';

// ── Constants ────────────────────────────────────────────────────────────────
const int _sampleRate  = 16000;
const int _melBins     = 80;
const int _nFft        = 400;
const int _hopLength   = 160;
const int _winLength   = 400;
const int _melFrames   = 3000;
const int _fftSize     = 512;
const int _nFreqBins   = _nFft ~/ 2 + 1; // 201

const int _sotToken        = 50258;
const int _eotToken        = 50257;
const int _transcribeToken = 50359;
const int _noTimestamps    = 50363;

const Map<String, int> _langTokens = {
  'ur': 50001, 'en': 50259, 'ar': 50272, 'hi': 50276,
  'fr': 50265, 'es': 50262, 'de': 50261, 'tr': 50268,
  'zh': 50260, 'ru': 50263, 'pt': 50264, 'ja': 50266,
  'ko': 50267, 'it': 50274, 'fa': 50300, 'bn': 50295,
  'nl': 50271, 'pl': 50270,
};

// ── WhisperSTT ────────────────────────────────────────────────────────────────

class WhisperSTT {
  static final WhisperSTT _instance = WhisperSTT._();
  factory WhisperSTT() => _instance;
  WhisperSTT._();

  OrtSession? _encoderSession;
  OrtSession? _decoderSession;
  Map<int, String> _idToToken = {};

  // Pre-computed DSP tables
  late final Float32List _hannWindow    = _buildHannWindow();
  late final Float32List _melFilterbank = _buildMelFilterbank();
  late final Map<String, int> _unicodeToByte = _buildUnicodeToByte();

  bool _loaded = false;
  bool get isLoaded => _loaded;

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> load() async {
    try {
      final mm  = ModelManager();
      if (!mm.isWhisperReady) throw Exception('Whisper model files not found');

      // Load vocab
      final vocabRaw = await File(mm.whisperVocabPath).readAsString();
      final vocabMap = jsonDecode(vocabRaw) as Map<String, dynamic>;
      _idToToken = { for (final e in vocabMap.entries) e.value as int: e.key };

      final opts = OrtSessionOptions()
        ..setIntraOpNumThreads(2)
        ..setInterOpNumThreads(2);

      _encoderSession = OrtSession.fromFile(mm.whisperEncoderPath as File, opts);
      _decoderSession = OrtSession.fromFile(mm.whisperDecoderPath as File, opts);
      _loaded = true;
    } catch (e) {
      _loaded = false;
      rethrow;
    }
  }

  void close() {
    _encoderSession?.release();
    _decoderSession?.release();
    _encoderSession = null;
    _decoderSession = null;
    _loaded = false;
  }

  // ── Transcribe audio file ─────────────────────────────────────────────────

  /// Transcribe a 16 kHz mono 16-bit PCM WAV file.
  Future<String> transcribeWav(String wavPath, String language) async {
    if (!_loaded) throw Exception('Whisper not loaded');
    final pcmFloat = await _loadWavAsPcmFloat(wavPath);
    return _transcribe(pcmFloat, language);
  }

  /// Transcribe raw Float32 PCM samples recorded at 16 kHz.
  Future<String> transcribePcm(Float32List samples, String language) async {
    if (!_loaded) throw Exception('Whisper not loaded');
    return _transcribe(samples, language);
  }

  // ── Core inference ────────────────────────────────────────────────────────

  String _transcribe(Float32List audio, String language) {
    final enc  = _encoderSession!;
    final dec  = _decoderSession!;

    try {
      // ── Step 1: Mel spectrogram ─────────────────────────────────────────
      final mel = _computeMelSpectrogram(audio);

      final encInput = OrtValueTensor.createTensorWithDataList(mel, [1, _melBins, _melFrames]);
      final encOut   = enc.run(OrtRunOptions(), {'input_features': encInput});
      encInput.release();

      final encHidden = encOut.first as OrtValueTensor;

      // ── Step 2: Greedy decode ────────────────────────────────────────────
      final langTok  = _langTokens[language] ?? _langTokens['en']!;
      final initIds  = [_sotToken, langTok, _transcribeToken, _noTimestamps];
      final tokenIds = List<int>.from(initIds);
      final decoded  = <int>[];

      for (int step = 0; step < 224; step++) {
        // On step 0 send all 4 init tokens; after that send only the last
        final feedIds = step == 0 ? tokenIds : [tokenIds.last];
        final decLen  = feedIds.length;
        final idData  = Int64List.fromList(feedIds);

        final idTensor  = OrtValueTensor.createTensorWithDataList(idData, [1, decLen]);
        final decOut    = dec.run(OrtRunOptions(), {
          'input_ids':             idTensor,
          'encoder_hidden_states': encHidden,
        });
        idTensor.release();

        // logits: [1, decLen, vocabSize]  — pick last position
        final logitsTensor = decOut.first as OrtValueTensor;
        final logits = logitsTensor.value as List<dynamic>;
        final lastPos = (logits[0] as List<dynamic>).last as List<dynamic>;

        int nextToken = 0;
        double maxVal = double.negativeInfinity;
        for (int i = 0; i < lastPos.length; i++) {
          final v = (lastPos[i] as num).toDouble();
          if (v > maxVal) { maxVal = v; nextToken = i; }
        }
        logitsTensor.release();

        if (nextToken == _eotToken) break;
        // Skip special tokens (>= 50257) in output, but push to tokenIds for context
        if (nextToken < 50257) decoded.add(nextToken);
        tokenIds.add(nextToken);
      }

      encHidden.release();
      return _decodeTokens(decoded);

    } catch (e) {
      return '';
    }
  }

  // ── Mel spectrogram ───────────────────────────────────────────────────────
  // Exact port of computeMelSpectrogram() from LocalWhisperSTT.kt

  Float32List _computeMelSpectrogram(Float32List audio) {
    final targetLen = 30 * _sampleRate;
    // Pad / trim to exactly 30 s
    final padded = Float32List(targetLen);
    final copyLen = math.min(audio.length, targetLen);
    for (int i = 0; i < copyLen; i++) padded[i] = audio[i];

    // Reflection-pad the edges (N_FFT/2 = 200 samples each side)
    final reflPad = _nFft ~/ 2;
    final sig = Float32List(targetLen + 2 * reflPad);
    for (int i = 0; i < reflPad; i++) sig[i] = padded[reflPad - i];
    for (int i = 0; i < targetLen; i++) sig[reflPad + i] = padded[i];
    for (int i = 0; i < reflPad; i++) sig[targetLen + reflPad + i] = padded[targetLen - 2 - i];

    // STFT output buffer
    final fftBuf  = Float64List(_fftSize * 2); // interleaved [re,im,...] pairs
    final power   = Float64List(_nFreqBins);
    // mel_matrix[frame][bin] — stored flat as [frame * _melBins + bin]
    final melMatrix = Float32List(_melFrames * _melBins);

    for (int f = 0; f < _melFrames; f++) {
      final start = f * _hopLength;
      // Clear buffer
      for (int i = 0; i < fftBuf.length; i++) fftBuf[i] = 0;
      // Apply Hann window
      for (int i = 0; i < _winLength; i++) {
        fftBuf[2 * i] = sig[start + i] * _hannWindow[i];
      }
      // In-place FFT
      _fft(fftBuf, _fftSize);
      // Power spectrum
      for (int k = 0; k < _nFreqBins; k++) {
        final re = fftBuf[2 * k], im = fftBuf[2 * k + 1];
        power[k] = re * re + im * im;
      }
      // Mel filterbank
      final rowBase = f * _melBins;
      for (int m = 0; m < _melBins; m++) {
        double v = 0;
        final fb = m * _nFreqBins;
        for (int k = 0; k < _nFreqBins; k++) v += _melFilterbank[fb + k] * power[k];
        melMatrix[rowBase + m] = math.log(math.max(v, 1e-10)) / math.ln10;
      }
    }

    // Find max for normalisation
    double maxVal = double.negativeInfinity;
    for (final v in melMatrix) if (v > maxVal) maxVal = v;

    // Output shape: [melBins, melFrames] (transposed)
    // Normalise: max(mel, maxVal-8) + 4) / 4 → roughly [-1,1]
    final output = Float32List(_melBins * _melFrames);
    for (int m = 0; m < _melBins; m++) {
      for (int f = 0; f < _melFrames; f++) {
        output[m * _melFrames + f] =
            (math.max(melMatrix[f * _melBins + m], maxVal - 8.0) + 4.0) / 4.0;
      }
    }
    return output;
  }

  // ── In-place Cooley-Tukey FFT (Dart port from Kotlin) ────────────────────
  // buf: interleaved [re0, im0, re1, im1, ...], length = n*2

  void _fft(Float64List buf, int n) {
    // Bit-reversal permutation
    int j = 0;
    for (int i = 1; i < n; i++) {
      int bit = n >> 1;
      while ((j & bit) != 0) { j ^= bit; bit >>= 1; }
      j ^= bit;
      if (i < j) {
        double t;
        t = buf[2*i];   buf[2*i]   = buf[2*j];   buf[2*j]   = t;
        t = buf[2*i+1]; buf[2*i+1] = buf[2*j+1]; buf[2*j+1] = t;
      }
    }
    // Butterfly passes
    int len = 2;
    while (len <= n) {
      final half = len ~/ 2;
      final ang  = -2.0 * math.pi / len;
      final wRe  = math.cos(ang), wIm = math.sin(ang);
      for (int i = 0; i < n; i += len) {
        double cRe = 1.0, cIm = 0.0;
        for (int k = 0; k < half; k++) {
          final uRe = buf[2*(i+k)],       uIm = buf[2*(i+k)+1];
          final vRe = buf[2*(i+k+half)],  vIm = buf[2*(i+k+half)+1];
          final tvRe = cRe*vRe - cIm*vIm, tvIm = cRe*vIm + cIm*vRe;
          buf[2*(i+k)]        = uRe + tvRe;  buf[2*(i+k)+1]        = uIm + tvIm;
          buf[2*(i+k+half)]   = uRe - tvRe;  buf[2*(i+k+half)+1]   = uIm - tvIm;
          final nc = cRe*wRe - cIm*wIm; cIm = cRe*wIm + cIm*wRe; cRe = nc;
        }
      }
      len <<= 1;
    }
  }

  // ── DSP tables ────────────────────────────────────────────────────────────

  Float32List _buildHannWindow() {
    final w = Float32List(_winLength);
    for (int i = 0; i < _winLength; i++) {
      w[i] = (0.5 * (1.0 - math.cos(2.0 * math.pi * i / _winLength))).toFloat();
    }
    return w;
  }

  Float32List _buildMelFilterbank() {
    final fMax   = _sampleRate / 2.0;
    final melMin = _hzToMel(0.0), melMax = _hzToMel(fMax);
    final melPts = List.generate(_melBins + 2, (i) => melMin + i * (melMax - melMin) / (_melBins + 1));
    final bins   = List.generate(_melBins + 2, (i) {
      return (_melToHz(melPts[i]) / fMax * _nFreqBins).round().clamp(0, _nFreqBins - 1);
    });

    final f = Float32List(_melBins * _nFreqBins);
    for (int m = 1; m <= _melBins; m++) {
      final lo = bins[m-1], ctr = bins[m], hi = bins[m+1];
      final off = (m-1) * _nFreqBins;
      if (ctr > lo) {
        for (int k = lo; k <= ctr; k++) f[off+k] = (k - lo) / (ctr - lo);
      }
      if (hi > ctr) {
        for (int k = ctr; k <= hi; k++) f[off+k] = (hi - k) / (hi - ctr);
      }
    }
    return f;
  }

  double _hzToMel(double hz)  => 2595.0 * math.log(1.0 + hz / 700.0) / math.ln10;
  double _melToHz(double mel) => 700.0 * (math.pow(10.0, mel / 2595.0) - 1.0);

  // ── Byte-level BPE decode ─────────────────────────────────────────────────

  String _decodeTokens(List<int> ids) {
    if (ids.isEmpty) return '';
    final sb = StringBuffer();
    for (final id in ids) sb.write(_idToToken[id] ?? '');
    return _byteLevelDecode(sb.toString());
  }

  String _byteLevelDecode(String s) {
    // Each Unicode char in the GPT-2 byte-level encoding maps to a byte 0-255
    final bytes = <int>[];
    for (final rune in s.runes) {
      final c = String.fromCharCode(rune);
      final b = _unicodeToByte[c];
      if (b != null && b < 256) bytes.add(b);
    }
    try {
      return utf8.decode(bytes, allowMalformed: true).trim();
    } catch (_) {
      return s.replaceAll('Ġ', ' ').replaceAll('Ċ', '\n').trim();
    }
  }

  // GPT-2 byte-to-unicode mapping (reversed for decoding)
  Map<String, int> _buildUnicodeToByte() {
    // Direct: printable ASCII + extended
    final direct = <int>[
      ...List.generate(126 - 33 + 1, (i) => 33 + i),
      ...List.generate(172 - 161 + 1, (i) => 161 + i),
      ...List.generate(255 - 174 + 1, (i) => 174 + i),
    ];
    final cs = List<int>.from(direct);
    int n = 256;
    for (int b = 0; b < 256; b++) {
      if (!direct.contains(b)) { direct.add(b); cs.add(n++); }
    }
    return { for (int i = 0; i < direct.length; i) String.fromCharCode(cs[i]): direct[i] };
  }

  // ── WAV loader ────────────────────────────────────────────────────────────

  Future<Float32List> _loadWavAsPcmFloat(String path) async {
    final bytes = await File(path).readAsBytes();
    if (bytes.length < 44) throw Exception('WAV too small');

    final header = ByteData.sublistView(Uint8List.fromList(bytes));
    // Scan for 'data' chunk
    int pos = 12, dataStart = -1, dataLen = 0;
    while (pos <= bytes.length - 8) {
      final id  = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final csz = header.getInt32(pos + 4, Endian.little);
      pos += 8;
      if (id == 'data') { dataStart = pos; dataLen = csz; break; }
      pos += csz.clamp(0, bytes.length - pos);
    }
    if (dataStart < 0) throw Exception('No data chunk');

    // Parse basic WAV header
    final numCh    = header.getInt16(22, Endian.little);
    final bits     = header.getInt16(34, Endian.little);
    final endPos   = math.min(dataStart + dataLen, bytes.length);
    final pcmBytes = bytes.sublist(dataStart, endPos);
    final n        = pcmBytes.length ~/ (bits ~/ 8) ~/ numCh;
    final samples  = Float32List(n);

    for (int i = 0; i < n; i++) {
      // Take first channel only (mono)
      final byteOffset = i * (bits ~/ 8) * numCh;
      int raw;
      if (bits == 16) {
        raw = ByteData.sublistView(Uint8List.fromList(pcmBytes))
                  .getInt16(byteOffset, Endian.little);
        samples[i] = raw / 32768.0;
      } else if (bits == 32) {
        raw = ByteData.sublistView(Uint8List.fromList(pcmBytes))
                  .getInt32(byteOffset, Endian.little);
        samples[i] = raw / 2147483648.0;
      } else {
        // 8-bit unsigned
        samples[i] = (pcmBytes[byteOffset] - 128) / 128.0;
      }
    }
    return samples;
  }
}

extension on double {
  double toFloat() => this;
}
