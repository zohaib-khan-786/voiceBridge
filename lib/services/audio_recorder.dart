// lib/services/audio_recorder.dart
// Records 16 kHz mono PCM audio and writes a WAV file.
// Uses the `record` package for cross-platform recording.
// WAV format is what Whisper expects — no additional transcoding needed.

import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  String? _currentPath;
  DateTime? _recordingStart;

  bool get isRecording => _isRecording;

  Duration get elapsed {
    if (_recordingStart == null) return Duration.zero;
    return DateTime.now().difference(_recordingStart!);
  }

  // ── Start recording ───────────────────────────────────────────────────────

  Future<void> start() async {
    if (_isRecording) return;

    final dir  = await getTemporaryDirectory();
    final path = '${dir.path}/vb_rec_${DateTime.now().millisecondsSinceEpoch}.wav';
    _currentPath = path;

    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.wav,     // raw PCM in WAV container
        sampleRate: 16000,             // Whisper requires 16 kHz
        numChannels: 1,                // mono
        bitRate: 256000,               // 16-bit PCM
        autoGain: false,               // NO auto-gain — kills speaker audio
        echoCancel: false,             // NO echo cancel — same reason
        noiseSuppress: false,          // NO noise suppression
      ),
      path: path,
    );

    _isRecording    = true;
    _recordingStart = DateTime.now();
  }

  // ── Stop recording → WAV path ─────────────────────────────────────────────

  Future<String?> stop() async {
    if (!_isRecording) return null;
    _isRecording = false;
    _recordingStart = null;
    final path = await _recorder.stop();
    return path ?? _currentPath;
  }

  // ── Cancel (delete file) ──────────────────────────────────────────────────

  Future<void> cancel() async {
    _isRecording    = false;
    _recordingStart = null;
    await _recorder.stop();
    if (_currentPath != null) {
      try { File(_currentPath!).deleteSync(); } catch (_) {}
      _currentPath = null;
    }
  }

  // ── Stream amplitude for waveform display ─────────────────────────────────

  Stream<Amplitude> get amplitudeStream =>
      Stream.periodic(const Duration(milliseconds: 100))
          .asyncMap((_) => _recorder.getAmplitude());

  // ── Cleanup ───────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await _recorder.dispose();
  }

  // ── WAV file writer (for writing PCM Float32 directly) ────────────────────
  // Used when you already have raw samples (e.g., from a stream processor).

  static Future<String> writeWavFile(
    Float32List samples,
    int sampleRate,
  ) async {
    final dir  = await getTemporaryDirectory();
    final path = '${dir.path}/vb_wav_${DateTime.now().millisecondsSinceEpoch}.wav';

    // Convert float [-1,1] → int16 PCM
    final pcm = Int16List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      pcm[i] = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    }

    final dataBytes = pcm.lengthInBytes;
    final header    = _buildWavHeader(sampleRate, 1, 16, dataBytes);

    final file = File(path);
    final sink = file.openWrite();
    sink.add(header);
    sink.add(pcm.buffer.asUint8List());
    await sink.flush();
    await sink.close();
    return path;
  }

  static Uint8List _buildWavHeader(
    int sampleRate, int channels, int bitsPerSample, int dataBytes,
  ) {
    final byteRate   = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;

    final header = ByteData(44);
    // RIFF chunk
    _writeStr(header, 0,  'RIFF');
    header.setInt32(4, dataBytes + 36, Endian.little);
    _writeStr(header, 8,  'WAVE');
    // fmt  sub-chunk
    _writeStr(header, 12, 'fmt ');
    header.setInt32(16, 16,            Endian.little); // PCM
    header.setInt16(20, 1,             Endian.little); // AudioFormat = 1 (PCM)
    header.setInt16(22, channels,      Endian.little);
    header.setInt32(24, sampleRate,    Endian.little);
    header.setInt32(28, byteRate,      Endian.little);
    header.setInt16(32, blockAlign,    Endian.little);
    header.setInt16(34, bitsPerSample, Endian.little);
    // data sub-chunk
    _writeStr(header, 36, 'data');
    header.setInt32(40, dataBytes, Endian.little);
    return header.buffer.asUint8List();
  }

  static void _writeStr(ByteData bd, int offset, String s) {
    for (int i = 0; i < s.length; i++) {
      bd.setUint8(offset + i, s.codeUnitAt(i));
    }
  }
}
