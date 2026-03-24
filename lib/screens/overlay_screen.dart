// lib/screens/overlay_screen.dart
// The bottom-drawer UI that slides up when the floating bubble is tapped.
//
// Flow:
//   1. Tap bubble → this screen opens as a modal bottom sheet.
//   2. Select source / target language (remembers last used).
//   3. Tap mic → record.
//   4. Tap stop → Whisper STT → Marian translate.
//   5. Tap "Send to WhatsApp" → auto-paste via Accessibility (or clipboard).
//   6. VoiceBridge minimises / returns to WhatsApp.
//
// Can also be opened from within the main app via:
//   OverlayScreen.show(context);

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:voicebridge/screens/overlay_channel.dart';

import '../providers/app_state.dart';
import '../services/audio_recorder.dart';
import '../services/overlay_channel.dart';
import '../utils/app_theme.dart';
import '../utils/language_constants.dart';

class OverlayScreen extends StatefulWidget {
  const OverlayScreen({super.key});

  /// Convenience: show as a modal bottom sheet from any context.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => const OverlayScreen(),
    );
  }

  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen>
    with SingleTickerProviderStateMixin {

  final AudioRecorderService _recorder = AudioRecorderService();
  final OverlayChannel       _overlay  = OverlayChannel();

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  bool   _isRecording  = false;
  bool   _isProcessing = false;
  bool   _hasSent      = false;
  String _timerLabel   = '0:00';
  int    _elapsedSecs  = 0;
  double _amplitude    = 0.0;

  // Streaming amplitude for waveform
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _pulseCtrl.stop();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _ampSub?.cancel();
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // ── Recording ─────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    final state = context.read<AppState>();
    if (!state.isWhisperReady) {
      _showSnack('⚠️ Whisper model not ready — download from AI Models tab');
      return;
    }
    if (!state.isMarianReady) {
      _showSnack('⚠️ Marian translation model not ready');
      return;
    }

    state.resetResult();
    await _recorder.start();

    _pulseCtrl.repeat(reverse: true);
    _elapsedSecs = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSecs++;
        final m = _elapsedSecs ~/ 60;
        final s = _elapsedSecs % 60;
        _timerLabel = '$m:${s.toString().padLeft(2, '0')}';
      });
    });

    _ampSub = _recorder.amplitudeStream.listen((amp) {
      if (!mounted) return;
      setState(() => _amplitude = ((amp.current + 40) / 40).clamp(0.0, 1.0));
    });

    setState(() { _isRecording = true; _hasSent = false; });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    _ampSub?.cancel();
    _pulseCtrl.stop();
    _pulseCtrl.reset();

    setState(() { _isRecording = false; _isProcessing = true; });

    final wavPath = await _recorder.stop();
    if (wavPath == null) {
      setState(() => _isProcessing = false);
      _showSnack('❌ Recording failed');
      return;
    }

    await context.read<AppState>().transcribeFile(wavPath);
    setState(() => _isProcessing = false);
  }

  // ── Send ──────────────────────────────────────────────────────────────

  Future<void> _sendToWhatsApp() async {
    final state = context.read<AppState>();
    final text  = state.translatedText;
    if (text.isEmpty) return;

    setState(() => _isProcessing = true);

    final accessOk = await _overlay.checkAccessibility();

    if (accessOk) {
      final sent = await _overlay.sendToWhatsApp(text);
      if (mounted) {
        setState(() { _isProcessing = false; _hasSent = true; });
        _showSnack(sent
            ? '✅ Sent to WhatsApp!'
            : '📋 Copied — WhatsApp opening…');
        if (sent) {
          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) Navigator.of(context).pop();
        }
      }
    } else {
      // No accessibility — copy to clipboard and open WhatsApp
      await _overlay.copyToClipboard(text);
      await _overlay.goBackToWhatsApp();
      if (mounted) {
        setState(() => _isProcessing = false);
        _showSnack('📋 Copied to clipboard — paste in WhatsApp');
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) Navigator.of(context).pop();
      }
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final sheetBg = isDark ? const Color(0xFF0D1117) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 24,
            offset: const Offset(0, -4),
          )
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drag handle ──────────────────────────────────────────
              _buildHandle(),
              const SizedBox(height: 8),

              // ── Header row ────────────────────────────────────────────
              _buildHeader(state, context),
              const SizedBox(height: 20),

              // ── Language selector ─────────────────────────────────────
              _buildLanguageRow(state),
              const SizedBox(height: 24),

              // ── Mic button + waveform ─────────────────────────────────
              _buildMicSection(state),
              const SizedBox(height: 20),

              // ── Results ───────────────────────────────────────────────
              if (state.transcribedText.isNotEmpty) ...[
                _buildResultCard(
                  label: 'Transcribed',
                  text: state.transcribedText,
                  textDir: state.sourceLang.isRtl
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  color: AppTheme.info.withOpacity(0.12),
                ),
                const SizedBox(height: 10),
              ],

              if (state.translatedText.isNotEmpty) ...[
                _buildResultCard(
                  label: 'Translation',
                  text: state.translatedText,
                  textDir: state.targetLang.isRtl
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  color: AppTheme.accent.withOpacity(0.12),
                ),
                const SizedBox(height: 16),

                // ── Send button ──────────────────────────────────────
                _buildSendButton(state),
                const SizedBox(height: 8),
              ],

              // ── Status ────────────────────────────────────────────────
              if (state.statusMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    state.statusMessage,
                    style: theme.textTheme.bodySmall,
                  ),
                ),

              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sub-widgets ───────────────────────────────────────────────────────

  Widget _buildHandle() => Center(
    child: Container(
      width: 40, height: 4,
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.4),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _buildHeader(AppState state, BuildContext context) => Row(
    children: [
      const Text('🌐', style: TextStyle(fontSize: 20)),
      const SizedBox(width: 8),
      const Text('VoiceBridge',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const Spacer(),
      // Accessibility hint button
      FutureBuilder<bool>(
        future: _overlay.checkAccessibility(),
        builder: (_, snap) {
          final ok = snap.data ?? false;
          return Tooltip(
            message: ok
                ? 'Auto-send enabled'
                : 'Enable Accessibility for auto-send',
            child: InkWell(
              onTap: ok ? null : _overlay.requestAccessibility,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (ok ? AppTheme.accent : AppTheme.warning)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(ok ? Icons.send : Icons.warning_amber_rounded,
                      size: 14,
                      color: ok ? AppTheme.accent : AppTheme.warning),
                  const SizedBox(width: 4),
                  Text(ok ? 'Auto-send' : 'Setup',
                      style: TextStyle(
                          fontSize: 11,
                          color: ok ? AppTheme.accent : AppTheme.warning)),
                ]),
              ),
            ),
          );
        },
      ),
      const SizedBox(width: 8),
      IconButton(
        icon: const Icon(Icons.close, size: 20),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  );

  Widget _buildLanguageRow(AppState state) => Row(
    children: [
      Expanded(child: _LangPicker(
        selected: state.sourceLang,
        onChanged: (l) => state.setSourceLang(l),
      )),
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          state.swapLanguages();
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.swap_horiz,
              color: AppTheme.accent, size: 20),
        ),
      ),
      Expanded(child: _LangPicker(
        selected: state.targetLang,
        onChanged: (l) => state.setTargetLang(l),
      )),
    ],
  );

  Widget _buildMicSection(AppState state) {
    final String label = _isRecording
        ? _timerLabel
        : _isProcessing
            ? 'Processing…'
            : 'Tap to record';

    return Column(
      children: [
        // Waveform bars
        if (_isRecording)
          _WaveformWidget(amplitude: _amplitude),

        const SizedBox(height: 12),

        // Mic button
        GestureDetector(
          onTap: _isProcessing
              ? null
              : (_isRecording ? _stopRecording : _startRecording),
          child: _isRecording
              ? ScaleTransition(
                  scale: _pulseAnim,
                  child: _MicCircle(
                      isRecording: true,
                      isProcessing: false,
                      amplitude: _amplitude),
                )
              : _MicCircle(
                  isRecording: false,
                  isProcessing: _isProcessing,
                  amplitude: 0),
        ),

        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            color: _isRecording ? AppTheme.danger : Colors.grey,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildResultCard({
    required String label,
    required String text,
    required TextDirection textDir,
    required Color color,
  }) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: Colors.grey)),
          const SizedBox(height: 4),
          Directionality(
            textDirection: textDir,
            child: Text(text,
                style: const TextStyle(fontSize: 15, height: 1.4)),
          ),
        ]),
      );

  Widget _buildSendButton(AppState state) => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: _isProcessing ? null : _sendToWhatsApp,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: _isProcessing
          ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Icon(Icons.send_rounded, size: 20),
      label: Text(
        _isProcessing ? 'Sending…' : 'Send to WhatsApp',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
  );

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}

// ── Language picker dropdown ───────────────────────────────────────────────

class _LangPicker extends StatelessWidget {
  final Language selected;
  final ValueChanged<Language> onChanged;

  const _LangPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: DropdownButton<Language>(
        value: selected,
        isExpanded: true,
        underline: const SizedBox(),
        dropdownColor: theme.cardColor,
        items: LanguageConstants.all.map((lang) => DropdownMenuItem(
          value: lang,
          child: Text('${lang.flag} ${lang.name}',
              style: const TextStyle(fontSize: 13)),
        )).toList(),
        onChanged: (l) { if (l != null) onChanged(l); },
      ),
    );
  }
}

// ── Mic circle ────────────────────────────────────────────────────────────────

class _MicCircle extends StatelessWidget {
  final bool isRecording;
  final bool isProcessing;
  final double amplitude;

  const _MicCircle({
    required this.isRecording,
    required this.isProcessing,
    required this.amplitude,
  });

  @override
  Widget build(BuildContext context) {
    final color = isRecording
        ? AppTheme.danger
        : isProcessing
            ? AppTheme.warning
            : AppTheme.accent;

    final size = 80.0 + amplitude * 16;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(isRecording ? 0.5 : 0.3),
            blurRadius: 16 + amplitude * 12,
            spreadRadius: amplitude * 4,
          ),
        ],
      ),
      child: isProcessing
          ? const Center(
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5))
          : Icon(
              isRecording ? Icons.stop_rounded : Icons.mic_rounded,
              color: Colors.white,
              size: 36,
            ),
    );
  }
}

// ── Animated waveform bars ────────────────────────────────────────────────────

class _WaveformWidget extends StatelessWidget {
  final double amplitude; // 0..1

  const _WaveformWidget({required this.amplitude});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(9, (i) {
        // Create varied heights based on position and amplitude
        final mid      = 4.0;
        final distance = (i - mid).abs() / mid; // 0 near center, 1 at edges
        final h = (4 + (1 - distance) * amplitude * 28).clamp(4.0, 36.0);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: 4,
          height: h,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: AppTheme.danger.withOpacity(0.7 + distance * 0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}