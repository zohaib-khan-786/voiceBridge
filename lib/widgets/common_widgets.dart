// lib/widgets/common_widgets.dart
// Reusable UI components used across all screens.

import 'package:flutter/material.dart';
import '../utils/language_constants.dart';
import '../utils/app_theme.dart';

// ── Language pair selector ────────────────────────────────────────────────────

class LanguagePairSelector extends StatelessWidget {
  final Language source;
  final Language target;
  final ValueChanged<Language> onSourceChanged;
  final ValueChanged<Language> onTargetChanged;
  final VoidCallback? onSwap;

  const LanguagePairSelector({
    super.key,
    required this.source,
    required this.target,
    required this.onSourceChanged,
    required this.onTargetChanged,
    this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _LangDropdown(selected: source, onChanged: onSourceChanged, label: 'From')),
        _SwapButton(onTap: onSwap),
        Expanded(child: _LangDropdown(selected: target, onChanged: onTargetChanged, label: 'To')),
      ],
    );
  }
}

class _LangDropdown extends StatelessWidget {
  final Language selected;
  final ValueChanged<Language> onChanged;
  final String label;
  const _LangDropdown({required this.selected, required this.onChanged, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Language>(
              value: selected,
              isExpanded: true,
              dropdownColor: theme.cardColor,
              items: LanguageConstants.all.map((lang) => DropdownMenuItem(
                value: lang,
                child: Text('${lang.flag} ${lang.name}',
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (l) { if (l != null) onChanged(l); },
            ),
          ),
        ),
      ],
    );
  }
}

class _SwapButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _SwapButton({this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: IconButton(
      icon: const Icon(Icons.swap_horiz, color: AppTheme.accent),
      tooltip: 'Swap languages',
      onPressed: onTap,
    ),
  );
}

// ── Waveform / recording indicator ───────────────────────────────────────────

class RecordingPulse extends StatefulWidget {
  final bool active;
  final String label;
  const RecordingPulse({super.key, required this.active, this.label = 'Recording…'});

  @override
  State<RecordingPulse> createState() => _RecordingPulseState();
}

class _RecordingPulseState extends State<RecordingPulse> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _pulse = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.active) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(RecordingPulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_ctrl.isAnimating) _ctrl.repeat(reverse: true);
    if (!widget.active && _ctrl.isAnimating)  _ctrl.stop();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Transform.scale(scale: _pulse.value, child: child),
      child: Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.active ? AppTheme.danger.withOpacity(0.15) : Colors.transparent,
          border: Border.all(
            color: widget.active ? AppTheme.danger : Colors.grey,
            width: 2,
          ),
        ),
        child: Icon(
          widget.active ? Icons.mic : Icons.mic_none,
          color: widget.active ? AppTheme.danger : Colors.grey,
          size: 36,
        ),
      ),
    ),
    const SizedBox(height: 8),
    Text(widget.label, style: TextStyle(
      color: widget.active ? AppTheme.danger : Colors.grey,
      fontWeight: FontWeight.w600,
    )),
  ]);
}

// ── Translation result card ───────────────────────────────────────────────────

class TranslationResultCard extends StatelessWidget {
  final String originalText;
  final String translatedText;
  final String sourceLangCode;
  final String targetLangCode;
  final bool fromCache;
  final String normNote;
  final String correctionNote;
  final VoidCallback? onSpeak;
  final VoidCallback? onCopy;
  final void Function(String corrected)? onUserCorrect;

  const TranslationResultCard({
    super.key,
    required this.originalText,
    required this.translatedText,
    required this.sourceLangCode,
    required this.targetLangCode,
    this.fromCache = false,
    this.normNote = '',
    this.correctionNote = '',
    this.onSpeak,
    this.onCopy,
    this.onUserCorrect,
  });

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final isRtlSrc = LanguageConstants.isRtl(sourceLangCode);
    final isRtlTgt = LanguageConstants.isRtl(targetLangCode);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Source ──────────────────────────────────────────────────────
          Row(children: [
            Text(LanguageConstants.displayName(sourceLangCode),
                style: theme.textTheme.labelSmall),
            const Spacer(),
            if (fromCache) _Badge('⚡ Cached', AppTheme.info),
            if (correctionNote.isNotEmpty) ...[
              const SizedBox(width: 4),
              _Badge('🔤 Fixed', AppTheme.warning),
            ],
          ]),
          const SizedBox(height: 6),
          Directionality(
            textDirection: isRtlSrc ? TextDirection.rtl : TextDirection.ltr,
            child: Text(originalText,
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
          ),

          if (correctionNote.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(correctionNote, style: TextStyle(fontSize: 11, color: AppTheme.warning)),
          ],
          if (normNote.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(normNote, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],

          Divider(height: 24, color: theme.dividerColor),

          // ── Target ──────────────────────────────────────────────────────
          Text(LanguageConstants.displayName(targetLangCode),
              style: theme.textTheme.labelSmall),
          const SizedBox(height: 6),
          Directionality(
            textDirection: isRtlTgt ? TextDirection.rtl : TextDirection.ltr,
            child: SelectableText(translatedText,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: AppTheme.accent, fontWeight: FontWeight.w600)),
          ),

          const SizedBox(height: 12),

          // ── Action buttons ───────────────────────────────────────────────
          Row(children: [
            if (onSpeak != null)
              _ActionBtn(icon: Icons.volume_up, label: 'Speak', onTap: onSpeak!),
            const SizedBox(width: 8),
            if (onCopy != null)
              _ActionBtn(icon: Icons.copy, label: 'Copy', onTap: onCopy!),
            const SizedBox(width: 8),
            if (onUserCorrect != null)
              _ActionBtn(
                icon: Icons.edit,
                label: 'Correct',
                onTap: () => _showCorrectionDialog(context),
              ),
          ]),
        ]),
      ),
    );
  }

  void _showCorrectionDialog(BuildContext context) {
    final ctrl = TextEditingController(text: translatedText);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Correct Translation'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Corrected translation'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onUserCorrect?.call(ctrl.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.4)),
    ),
    child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
  );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon:  Icon(icon, size: 16),
    label: Text(label, style: const TextStyle(fontSize: 13)),
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      side: BorderSide(color: Theme.of(context).dividerColor),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

// ── Model status banner ───────────────────────────────────────────────────────

class ModelStatusBanner extends StatelessWidget {
  final String label;
  final Color  color;
  final IconData icon;
  final VoidCallback? onTap;
  const ModelStatusBanner({
    super.key, required this.label, required this.color,
    required this.icon, this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13))),
        if (onTap != null) Icon(Icons.chevron_right, color: color, size: 18),
      ]),
    ),
  );
}
