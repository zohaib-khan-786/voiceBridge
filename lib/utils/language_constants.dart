// lib/utils/language_constants.dart
// All language codes, display names, TTS locales, and Whisper token IDs.

class Language {
  final String code;
  final String name;
  final String flag;
  final String ttsLocale;
  final double ttsRate;
  final double ttsPitch;
  final int whisperToken;   // Whisper special token ID for this language
  final bool isRtl;

  const Language({
    required this.code,
    required this.name,
    required this.flag,
    required this.ttsLocale,
    this.ttsRate = 1.0,
    this.ttsPitch = 1.0,
    required this.whisperToken,
    this.isRtl = false,
  });

  String get displayName => '$flag $name';

  @override
  String toString() => code;
}

class LanguageConstants {
  // ── All supported languages ────────────────────────────────────────────────
  static const List<Language> all = [
    Language(code: 'ur', name: 'Urdu',       flag: '🇵🇰', ttsLocale: 'ur-PK', ttsRate: 0.92, ttsPitch: 1.05, whisperToken: 50001, isRtl: true),
    Language(code: 'en', name: 'English',    flag: '🇬🇧', ttsLocale: 'en-GB', ttsRate: 1.00, ttsPitch: 1.00, whisperToken: 50259),
    Language(code: 'ar', name: 'Arabic',     flag: '🇸🇦', ttsLocale: 'ar-SA', ttsRate: 0.88, ttsPitch: 0.92, whisperToken: 50272, isRtl: true),
    Language(code: 'hi', name: 'Hindi',      flag: '🇮🇳', ttsLocale: 'hi-IN', ttsRate: 0.95, ttsPitch: 1.03, whisperToken: 50276),
    Language(code: 'fr', name: 'French',     flag: '🇫🇷', ttsLocale: 'fr-FR', ttsRate: 1.08, ttsPitch: 1.02, whisperToken: 50265),
    Language(code: 'es', name: 'Spanish',    flag: '🇪🇸', ttsLocale: 'es-MX', ttsRate: 1.05, ttsPitch: 1.00, whisperToken: 50262),
    Language(code: 'de', name: 'German',     flag: '🇩🇪', ttsLocale: 'de-DE', ttsRate: 0.95, ttsPitch: 0.97, whisperToken: 50261),
    Language(code: 'tr', name: 'Turkish',    flag: '🇹🇷', ttsLocale: 'tr-TR', ttsRate: 0.98, ttsPitch: 1.00, whisperToken: 50268),
    Language(code: 'zh', name: 'Chinese',    flag: '🇨🇳', ttsLocale: 'zh-CN', ttsRate: 0.90, ttsPitch: 1.04, whisperToken: 50260),
    Language(code: 'ru', name: 'Russian',    flag: '🇷🇺', ttsLocale: 'ru-RU', ttsRate: 0.93, ttsPitch: 0.96, whisperToken: 50263),
    Language(code: 'pt', name: 'Portuguese', flag: '🇧🇷', ttsLocale: 'pt-BR', ttsRate: 1.02, ttsPitch: 1.01, whisperToken: 50264),
    Language(code: 'ja', name: 'Japanese',   flag: '🇯🇵', ttsLocale: 'ja-JP', ttsRate: 0.92, ttsPitch: 1.05, whisperToken: 50266),
    Language(code: 'ko', name: 'Korean',     flag: '🇰🇷', ttsLocale: 'ko-KR', ttsRate: 0.97, ttsPitch: 1.00, whisperToken: 50267),
    Language(code: 'it', name: 'Italian',    flag: '🇮🇹', ttsLocale: 'it-IT', ttsRate: 1.02, ttsPitch: 1.00, whisperToken: 50274),
    Language(code: 'fa', name: 'Persian',    flag: '🇮🇷', ttsLocale: 'fa-IR', ttsRate: 0.88, ttsPitch: 0.95, whisperToken: 50300, isRtl: true),
    Language(code: 'bn', name: 'Bengali',    flag: '🇧🇩', ttsLocale: 'bn-BD', ttsRate: 0.95, ttsPitch: 1.00, whisperToken: 50295),
  ];

  static final Map<String, Language> _byCode = {
    for (final l in all) l.code: l,
  };

  static Language? fromCode(String code) => _byCode[code];

  static Language get defaultSource => _byCode['ur']!;
  static Language get defaultTarget => _byCode['en']!;

  // Whisper special tokens
  static const int sotToken        = 50258; // <|startoftranscript|>
  static const int eotToken        = 50257; // <|endoftext|>
  static const int transcribeToken = 50359; // <|transcribe|>
  static const int noTimestamps    = 50363; // <|notimestamps|>

  static bool isRtl(String code) => _byCode[code]?.isRtl ?? false;

  static String displayName(String code) => _byCode[code]?.displayName ?? code.toUpperCase();

  static int whisperToken(String code) => _byCode[code]?.whisperToken ?? sotToken + 1;
}
