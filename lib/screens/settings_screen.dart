// lib/screens/settings_screen.dart
// Port of MainActivity's Settings/Configuration section.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [

        // ── Appearance ────────────────────────────────────────────────────
        _SectionHeader('Appearance'),
        _SettingCard(children: [
          SwitchListTile(
            title: const Text('Dark Mode'),
            subtitle: Text(state.isDarkMode ? '🌙 Dark theme active' : '☀️ Light theme active'),
            value: state.isDarkMode,
            activeColor: AppTheme.accent,
            onChanged: (_) => context.read<AppState>().toggleTheme(),
          ),
        ]),
        const SizedBox(height: 12),

        // ── Translation mode ──────────────────────────────────────────────
        _SectionHeader('Translation Mode'),
        _SettingCard(children: [
          SwitchListTile(
            title: const Text('Training Mode'),
            subtitle: Text(
              state.appMode == AppMode.training
                  ? '🎓 Active — corrections are being collected for retraining'
                  : '🚀 Production — using on-device models only',
            ),
            value: state.appMode == AppMode.training,
            activeColor: AppTheme.warning,
            onChanged: (v) => context.read<AppState>().setAppMode(
              v ? AppMode.training : AppMode.production,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              state.appMode == AppMode.training
                  ? 'Training mode collects your translation corrections locally. '
                    'No data leaves the device. Export the training data below '
                    'to improve the model yourself.'
                  : 'Production mode uses only on-device ONNX models and the '
                    'local translation cache — fully offline, no network required.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ]),
        const SizedBox(height: 12),

        // ── Stats ─────────────────────────────────────────────────────────
        _SectionHeader('Learned Data'),
        _SettingCard(children: [
          _StatRow('📦 Cached sentences', '${state.cacheStats.totalCached}'),
          _StatRow('✅ User-verified', '${state.cacheStats.userVerified}'),
          _StatRow('📖 Word pairs learned', '${state.dictSize}'),
        ]),
        const SizedBox(height: 12),

        // ── Export ────────────────────────────────────────────────────────
        _SectionHeader('Training Data'),
        _SettingCard(children: [
          ListTile(
            leading: const Icon(Icons.upload_file, color: AppTheme.accent),
            title: const Text('Export Training Data'),
            subtitle: const Text('Exports verified translations as JSONL for model retraining'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final path = await context.read<AppState>().exportTrainingData();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('✅ Exported to:\n$path'),
                  duration: const Duration(seconds: 5),
                  behavior: SnackBarBehavior.floating,
                ));
              }
            },
          ),
        ]),
        const SizedBox(height: 12),

        // ── About ─────────────────────────────────────────────────────────
        _SectionHeader('About'),
        _SettingCard(children: [
          _AboutRow('Version', '2.0.0'),
          _AboutRow('STT Engine', 'Whisper ONNX (small)'),
          _AboutRow('Translation', 'Marian MT (opus-mt-ur-en)'),
          _AboutRow('TTS', 'Android built-in + Piper (optional)'),
          _AboutRow('Network', 'None required after model download'),
        ]),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(title, style: TextStyle(
      color: AppTheme.accent,
      fontWeight: FontWeight.bold,
      fontSize: 13,
      letterSpacing: 0.5,
    )),
  );
}

// ── Card wrapper ──────────────────────────────────────────────────────────────

class _SettingCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingCard({required this.children});
  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Column(children: children),
  );
}

// ── Stat row ──────────────────────────────────────────────────────────────────

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(children: [
      Text(label, style: Theme.of(context).textTheme.bodyMedium),
      const Spacer(),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accent)),
    ]),
  );
}

// ── About row ─────────────────────────────────────────────────────────────────

class _AboutRow extends StatelessWidget {
  final String label;
  final String value;
  const _AboutRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(children: [
      Text(label, style: Theme.of(context).textTheme.bodyMedium),
      const Spacer(),
      Text(value, style: Theme.of(context).textTheme.bodySmall),
    ]),
  );
}
