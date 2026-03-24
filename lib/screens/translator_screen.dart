// lib/screens/translator_screen.dart
// Main translation UI — mirrors the Send Panel from Android's OverlayService.
// Record mic → Whisper STT → slang normalise → Marian translate → TTS/copy/share.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/audio_recorder.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';

class TranslatorScreen extends StatefulWidget {
  /// Callback to navigate to a specific tab index in the parent shell.
  final ValueChanged<int>? onNavigateToTab;

  const TranslatorScreen({super.key, this.onNavigateToTab});
  @override
  State<TranslatorScreen> createState() => _TranslatorScreenState();
}

class _TranslatorScreenState extends State<TranslatorScreen> {
  final AudioRecorderService _recorder = AudioRecorderService();
  final TextEditingController _textCtrl = TextEditingController();

  bool   _isRecording = false;
  bool   _isProcessing = false;
  String _timerLabel  = '0:00';
  int    _elapsedSecs = 0;

  @override
  void dispose() {
    _recorder.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  // ── Recording controls ────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    final state = context.read<AppState>();
    if (!state.isWhisperReady) {
      _showSnack('⚠️ Whisper model not downloaded yet — go to AI Models tab');
      return;
    }

    setState(() { _isRecording = true; _elapsedSecs = 0; _timerLabel = '0:00'; });
    await _recorder.start();
    state.resetResult();

    // Update timer every second
    _tickTimer();
  }

  void _tickTimer() {
    if (!_isRecording) return;
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || !_isRecording) return;
      setState(() {
        _elapsedSecs++;
        final m = _elapsedSecs ~/ 60;
        final s = _elapsedSecs % 60;
        _timerLabel = '$m:${s.toString().padLeft(2, '0')}';
      });
      _tickTimer();
    });
  }

  Future<void> _stopAndTranscribe() async {
    setState(() { _isRecording = false; _isProcessing = true; });
    final path = await _recorder.stop();
    if (path == null) {
      setState(() { _isProcessing = false; });
      _showSnack('❌ Recording failed');
      return;
    }
    final state = context.read<AppState>();
    await state.transcribeFile(path);
    setState(() { _isProcessing = false; });
  }

  Future<void> _cancelRecording() async {
    setState(() { _isRecording = false; });
    await _recorder.cancel();
  }

  // ── Text-mode translation ─────────────────────────────────────────────────

  Future<void> _translateText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    await context.read<AppState>().translateText(text);
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _copyTranslation() {
    final state = context.read<AppState>();
    if (state.translatedText.isEmpty) return;
    Clipboard.setData(ClipboardData(text: state.translatedText));
    _showSnack('✅ Copied to clipboard');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        // ── Language pair ─────────────────────────────────────────────────
        LanguagePairSelector(
          source: state.sourceLang,
          target: state.targetLang,
          onSourceChanged: context.read<AppState>().setSourceLang,
          onTargetChanged: context.read<AppState>().setTargetLang,
          onSwap: context.read<AppState>().swapLanguages,
        ),
        const SizedBox(height: 20),

        // ── Record button area ────────────────────────────────────────────
        Center(child: Column(children: [
          GestureDetector(
            onTapDown: (_) {
              if (!_isRecording && !_isProcessing) _startRecording();
            },
            onTapUp: (_) {
              if (_isRecording) _stopAndTranscribe();
            },
            child: RecordingPulse(
              active: _isRecording,
              label: _isRecording
                  ? '🔴 $_timerLabel  (tap to stop)'
                  : _isProcessing
                      ? '⏳ Processing…'
                      : 'Tap & hold to record',
            ),
          ),
          if (_isRecording) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _cancelRecording,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Cancel'),
              style: TextButton.styleFrom(foregroundColor: Colors.grey),
            ),
          ],
        ])),
        const SizedBox(height: 20),

        // ── Text input (type to translate) ────────────────────────────────
        if (!_isRecording) ...[
          Row(children: [
            Expanded(
              child: TextField(
                controller: _textCtrl,
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Or type text to translate…',
                  suffixIcon: _textCtrl.text.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                          _textCtrl.clear(); setState(() {});
                        })
                      : null,
                ),
                textDirection: TextDirection.ltr,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _translateText(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _textCtrl.text.trim().isNotEmpty ? _translateText : null,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(56, 56),
                padding: EdgeInsets.zero,
              ),
              child: const Icon(Icons.translate),
            ),
          ]),
          const SizedBox(height: 16),
        ],

        // ── Processing indicator ──────────────────────────────────────────
        if (state.recordingState == RecordingState.processing)
          Column(children: [
            const LinearProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
            ),
            const SizedBox(height: 8),
            Text(state.statusMessage, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
          ]),

        // ── Error state ───────────────────────────────────────────────────
        if (state.recordingState == RecordingState.error)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.danger.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(state.statusMessage, style: const TextStyle(color: AppTheme.danger)),
          ),

        // ── Translation result ────────────────────────────────────────────
        if (state.hasResult)
          TranslationResultCard(
            originalText:   state.transcribedText,
            translatedText: state.translatedText,
            sourceLangCode: state.sourceLang.code,
            targetLangCode: state.targetLang.code,
            fromCache:       state.fromCache,
            normNote:        state.normNote,
            correctionNote:  state.correctionNote,
            onSpeak:        state.speakTranslated,
            onCopy:         _copyTranslation,
            onUserCorrect:  (corrected) async {
              await state.userCorrect(corrected);
              _showSnack('✅ Correction saved');
            },
          ),

        // ── Model not loaded warning ──────────────────────────────────────
        if (!state.isMarianReady)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ModelStatusBanner(
              label: 'Marian translation model not found — tap to set up',
              color: AppTheme.warning,
              icon: Icons.warning_amber,
              onTap: () => widget.onNavigateToTab?.call(1),
            ),
          ),

        if (!state.isWhisperReady)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ModelStatusBanner(
              label: 'Whisper STT not downloaded — tap to download',
              color: AppTheme.info,
              icon: Icons.download,
              onTap: () => widget.onNavigateToTab?.call(1),
            ),
          ),

        const SizedBox(height: 80), // bottom padding for FAB
      ]),
    );
  }
}
