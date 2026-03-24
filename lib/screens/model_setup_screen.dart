// lib/screens/model_setup_screen.dart
// Handles model discovery and Whisper download.
// Equivalent to the AI model status section in Android's MainActivity.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/model_manager.dart';
import '../utils/app_theme.dart';

class ModelSetupScreen extends StatefulWidget {
  const ModelSetupScreen({super.key});

  @override
  State<ModelSetupScreen> createState() => _ModelSetupScreenState();
}

class _ModelSetupScreenState extends State<ModelSetupScreen> {
  bool   _downloading     = false;
  double _downloadProgress = 0;
  String _downloadLabel   = '';
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final status = state.modelStatus;

    return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Installed size ──────────────────────────────────────────────
          _InfoCard(
            icon: Icons.storage,
            title: 'Installed: ${state.installedModelsMb.toStringAsFixed(0)} MB',
            subtitle: 'Model files are stored in app documents directory',
            color: AppTheme.info,
          ),
          const SizedBox(height: 16),

          // ── Whisper STT ─────────────────────────────────────────────────
          _ModelCard(
            title: 'Whisper Small (STT)',
            description: 'On-device speech-to-text.\n~456 MB  ·  Supports 16+ languages  ·  Auto-download',
            status: status.whisper,
            isDownloading: _downloading,
            downloadProgress: _downloadProgress,
            downloadLabel: _downloadLabel,
            onDownload: _downloadWhisper,
            onRemove: () => _removeWhisper(state),
          ),
          const SizedBox(height: 12),

          // ── Marian translation ──────────────────────────────────────────
          _ModelCard(
            title: 'Marian MT (Translation)',
            description: 'On-device Urdu→English translation.\n'
                '~57 MB  ·  Place files manually in:\n'
                'Documents/ai_model/',
            status: status.marian,
            canDownload: false,
            helpText: _marianHelpText(state),
          ),
          const SizedBox(height: 12),

          // ── STT Correction ──────────────────────────────────────────────
          _ModelCard(
            title: 'STT Correction (Optional)',
            description: 'T5-based STT error correction.\n'
                '~60 MB  ·  Place files in:\n'
                'Documents/ai_model/stt/',
            status: status.stt,
            canDownload: false,
            optional: true,
          ),
          const SizedBox(height: 24),

          // ── File placement guide ────────────────────────────────────────
          _FilePlacementGuide(),

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.danger.withOpacity(0.4)),
              ),
              child: Text(_errorMessage!, style: const TextStyle(color: AppTheme.danger)),
            ),
          ],
        ],
    );
  }

  String _marianHelpText(AppState state) {
    final mm  = ModelManager();
    final dir = mm.isMarianReady ? '' : mm.modelDirectory.path;
    if (mm.isMarianReady) {
      return '✅ Files found';
    }
    return 'Required files:\n'
        '• marian-encoder.onnx\n'
        '• marian-decoder.onnx\n'
        '• marian-tokenizer.json\n\n'
        'Copy them to:\n$dir';
  }

  Future<void> _downloadWhisper() async {
    setState(() { _downloading = true; _errorMessage = null; _downloadProgress = 0; });
    final state = context.read<AppState>();
    try {
      await state.downloadWhisper(
        onProgress: (label, progress) {
          if (mounted) setState(() { _downloadLabel = label; _downloadProgress = progress; });
        },
      );
    } catch (e) {
      if (mounted) setState(() { _errorMessage = 'Download failed: $e'; });
    } finally {
      if (mounted) setState(() { _downloading = false; });
    }
  }

  Future<void> _removeWhisper(AppState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Whisper Model?'),
        content: const Text('This will delete the downloaded Whisper files (~456 MB). You can re-download them later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final dir = ModelManager().modelDirectory;
    final whisperDir = Directory('${dir.path}/whisper');
    if (whisperDir.existsSync()) whisperDir.deleteSync(recursive: true);
    await state.modelStatus.toString(); // trigger refresh
    setState(() {});
  }
}

// ── Model card ────────────────────────────────────────────────────────────────

class _ModelCard extends StatelessWidget {
  final String title;
  final String description;
  final ModelStatus status;
  final bool isDownloading;
  final double downloadProgress;
  final String downloadLabel;
  final VoidCallback? onDownload;
  final VoidCallback? onRemove;
  final bool canDownload;
  final bool optional;
  final String? helpText;

  const _ModelCard({
    required this.title,
    required this.description,
    required this.status,
    this.isDownloading    = false,
    this.downloadProgress = 0,
    this.downloadLabel    = '',
    this.onDownload,
    this.onRemove,
    this.canDownload = true,
    this.optional    = false,
    this.helpText,
  });

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isReady = status == ModelStatus.ready;
    final color   = isReady ? AppTheme.accent : (optional ? Colors.grey : AppTheme.warning);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isReady ? Icons.check_circle : (optional ? Icons.info_outline : Icons.download),
                color: color, size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (optional) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('optional', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Text(_statusLabel(), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            ])),
            if (isReady && onRemove != null)
              IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: onRemove),
          ]),
          const SizedBox(height: 10),
          Text(description, style: theme.textTheme.bodySmall),

          if (helpText != null && helpText!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(helpText!, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            ),
          ],

          // Download progress
          if (isDownloading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: downloadProgress,
              backgroundColor: Colors.grey.withOpacity(0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text(downloadLabel,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  overflow: TextOverflow.ellipsis)),
              Text('${(downloadProgress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accent)),
            ]),
          ],

          // Download button
          if (!isReady && canDownload && !isDownloading && onDownload != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Download Whisper Small (~456 MB)'),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  String _statusLabel() {
    if (isDownloading) return '⏳ Downloading…';
    switch (status) {
      case ModelStatus.ready:       return '✅ Ready';
      case ModelStatus.notFound:    return optional ? '⬜ Not installed' : '⚠️ Not found';
      case ModelStatus.downloading: return '⏳ Downloading…';
      case ModelStatus.error:       return '❌ Error';
    }
  }
}

// ── Info card ────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  const _InfoCard({required this.icon, required this.title, required this.subtitle, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(children: [
      Icon(icon, color: color),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        Text(subtitle, style: TextStyle(color: color.withOpacity(0.7), fontSize: 12)),
      ])),
    ]),
  );
}

// ── File placement guide ──────────────────────────────────────────────────────

class _FilePlacementGuide extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('📁 Model File Placement', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          const Text(
            'Copy your Marian ONNX model files to the device using adb or a file manager:\n',
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Android/data/com.voicebridge.flutter/files/ai_model/\n'
              '├── marian-encoder.onnx\n'
              '├── marian-decoder.onnx\n'
              '├── marian-tokenizer.json\n'
              '└── stt/  (optional)\n'
              '    ├── stt-encoder.onnx\n'
              '    ├── stt-decoder.onnx\n'
              '    ├── stt-vocab.json\n'
              '    └── stt-config.json',
              style: TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Or place them anywhere accessible and use the file picker in Settings → Import Models.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ]),
      ),
    );
  }
}
