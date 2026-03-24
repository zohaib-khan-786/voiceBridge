// lib/utils/translation_context.dart
// Lightweight session memory for the translation pipeline.
// Tracks conversation flow and topic for better translations.

enum Topic { greeting, work, personal, question, complaint, food, travel, general }

class TranslationEntry {
  final String source;
  final String target;
  final String sourceLang;
  final String targetLang;
  final Topic topic;
  final DateTime time;

  const TranslationEntry({
    required this.source, required this.target,
    required this.sourceLang, required this.targetLang,
    required this.topic, required this.time,
  });
}

class TranslationContext {
  static final TranslationContext _instance = TranslationContext._();
  factory TranslationContext() => _instance;
  TranslationContext._();

  static const int _maxSessionSize = 10;

  final List<TranslationEntry> _session = [];

  // ── Topic detection ───────────────────────────────────────────────────────

  static Topic detectTopic(String text) {
    final lower = text.toLowerCase();

    if (RegExp(r'\b(salaam|hello|hi|shukriya|thanks|bye|khuda hafiz)\b').hasMatch(lower)) {
      return Topic.greeting;
    }
    if (RegExp(r'\b(office|meeting|kaam|work|deadline|project|report|salary|boss|manager)\b').hasMatch(lower)) {
      return Topic.work;
    }
    if (RegExp(r'\b(ghar|family|mama|papa|bhai|behen|dost|yaar|wife|husband)\b').hasMatch(lower)) {
      return Topic.personal;
    }
    if (RegExp(r'\b(kya|kyun|kaise|kahan|kab|kaun|kitna|what|why|how|where|when|who)\b').hasMatch(lower)) {
      return Topic.question;
    }
    if (RegExp(r'\b(problem|mushkil|pareshaan|gussa|naraaz|issue|trouble|complaint)\b').hasMatch(lower)) {
      return Topic.complaint;
    }
    if (RegExp(r'\b(khana|roti|chai|dinner|lunch|breakfast|khao|piye)\b').hasMatch(lower)) {
      return Topic.food;
    }
    if (RegExp(r'\b(safar|gaadi|plane|train|station|airport|hotel|bahar|travel)\b').hasMatch(lower)) {
      return Topic.travel;
    }
    return Topic.general;
  }

  // ── Session management ────────────────────────────────────────────────────

  void recordTranslation({
    required String source, required String target,
    required String sourceLang, required String targetLang,
  }) {
    if (source.trim().isEmpty) return;
    final topic = detectTopic(source);
    _session.add(TranslationEntry(
      source: source, target: target,
      sourceLang: sourceLang, targetLang: targetLang,
      topic: topic, time: DateTime.now(),
    ));
    if (_session.length > _maxSessionSize) _session.removeAt(0);
  }

  void clearSession() => _session.clear();

  // Returns the dominant topic of the current session
  Topic get currentTopic {
    if (_session.isEmpty) return Topic.general;
    final counts = <Topic, int>{};
    for (final e in _session) {
      counts[e.topic] = (counts[e.topic] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  List<TranslationEntry> get recent => List.unmodifiable(_session.reversed.take(3).toList());

  // Detect if the same phrase is being said repeatedly (teach-me signal)
  bool isRepeated(String text) {
    final lower = text.toLowerCase().trim();
    int count = 0;
    for (final e in _session) {
      if (e.source.toLowerCase().trim() == lower) count++;
    }
    return count >= 2;
  }
}
