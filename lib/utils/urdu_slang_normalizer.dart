// lib/utils/urdu_slang_normalizer.dart
// Dart port of VoiceBridge's UrduSlangNormalizer.kt
// Normalises casual Urdish / Roman Urdu to clean Urdu that the Marian
// translation model can process accurately.

class NormalizedResult {
  final String text;
  final String recommendedLangCode; // 'ur' or 'hi'
  final bool wasModified;
  const NormalizedResult(this.text, this.recommendedLangCode, this.wasModified);
}

class UrduSlangNormalizer {
  // ── Step 1: Slang idioms / phrases → standard Urdu ────────────────────────
  static const Map<String, String> _slangMap = {
    // Greetings & farewells
    'assalam alaikum': 'السلام علیکم',
    'assalamualaikum': 'السلام علیکم',
    'asslm': 'السلام علیکم',
    'aoa': 'السلام علیکم',
    'jazakallah': 'جزاک اللہ',
    'jzk': 'جزاک اللہ',
    'inshallah': 'ان شاء اللہ',
    'mashallah': 'ماشاءاللہ',
    'alhamdulillah': 'الحمد للہ',
    'subhanallah': 'سبحان اللہ',
    'khuda hafiz': 'خدا حافظ',
    'allah hafiz': 'اللہ حافظ',
    'fi amanillah': 'فی امان اللہ',

    // Agreement / response
    'ji haan': 'جی ہاں',
    'ji': 'جی',
    'theek hai': 'ٹھیک ہے',
    'thk': 'ٹھیک ہے',
    'bilkul': 'بالکل',
    'zaroor': 'ضرور',
    'accha': 'اچھا',
    'acha': 'اچھا',
    'ok yaar': 'ٹھیک ہے یار',
    'bas kar': 'بس کرو',

    // Common expressions
    'kya scene hai': 'کیا ہو رہا ہے',
    'kya ho raha hai': 'کیا ہو رہا ہے',
    'scene kya hai': 'کیا ہو رہا ہے',
    'kya chal raha hai': 'کیا ہو رہا ہے',
    'kya haal hai': 'کیا حال ہے',
    'kaise ho': 'کیسے ہو',
    'kaise hain': 'کیسے ہیں',
    'sab theek': 'سب ٹھیک',
    'mast hai': 'بہت اچھا ہے',
    'lag gayi': 'مصیبت آ گئی',
    'aa gayi': 'آ گئی',
    'ho gaya': 'ہو گیا',
    'ho gayi': 'ہو گئی',
    'yaar sun': 'یار سنو',
    'bhai sun': 'بھائی سنو',
    'bhai suno': 'بھائی سنو',
    'yaar suno': 'یار سنو',

    // Time expressions
    'kal tak': 'کل تک',
    'aaj tak': 'آج تک',
    'abhi tak': 'ابھی تک',
    'thodi der mein': 'تھوڑی دیر میں',
    'jaldi kar': 'جلدی کرو',
    'jaldi karo': 'جلدی کرو',
    'der ho gayi': 'دیر ہو گئی',
    'time nahi': 'وقت نہیں',
    'time hai': 'وقت ہے',

    // Emotions / reactions
    'bohat bura hua': 'بہت برا ہوا',
    'bohat acha hua': 'بہت اچھا ہوا',
    'mujhe pata nahi': 'مجھے پتہ نہیں',
    'pata nahi': 'پتہ نہیں',
    'nahi pata': 'نہیں پتہ',
    'samajh nahi aaya': 'سمجھ نہیں آئی',
    'chinta mat karo': 'فکر نہ کرو',
    'tension mat lo': 'فکر نہ کرو',
    'tension nahi leni': 'فکر نہیں کرنی',
    'fikr mat karo': 'فکر نہ کرو',

    // Work / professional
    'meeting cancel': 'ملاقات منسوخ',
    'meeting postpone': 'ملاقات ملتوی',
    'kaam ho gaya': 'کام ہو گیا',
    'kaam nahi hua': 'کام نہیں ہوا',
    'report submit': 'رپورٹ جمع',
    'deadline hai': 'آخری تاریخ ہے',
    'office mein': 'دفتر میں',
    'ghar se kaam': 'گھر سے کام',

    // Gen-Z / internet slang
    'no cap': 'سچ میں',
    'sach mein': 'سچ میں',
    'red flag': 'بری علامت',
    'green flag': 'اچھی علامت',
    'ghosted': 'جواب نہیں دیا',
    'cringe': 'شرمناک',
    'vibes': 'احساس',
    'vibe check': 'احساس دیکھنا',
    'lit hai': 'بہت مزے کا ہے',
    'lowkey': 'تھوڑا',
    'highkey': 'بہت',

    // Punjabi influence
    'kiddan': 'کیسے ہو',
    'kiddan yaar': 'کیسے ہو یار',
    'dasso': 'بتاؤ',
    'ki ban-na': 'کیا ہو رہا ہے',
    'tussi': 'آپ',
    'asi': 'ہم',

    // Karachi slang
    'bol yaar': 'بولو یار',
    'lagao mat': 'مت لگاؤ',
    'mast chal raha': 'اچھا چل رہا',
    'ekdum seedha': 'بالکل سیدھا',

    // Dismissal / refusal
    'nahi karna': 'نہیں کرنا',
    'nahi karunga': 'نہیں کروں گا',
    'mujhe nahi': 'مجھے نہیں',
    'chor do': 'چھوڑ دو',
    'rehne do': 'رہنے دو',
    'bhool jao': 'بھول جاؤ',
  };

  // ── Step 2: Urdish → Urdu script (English loanwords) ─────────────────────
  static const Map<String, String> _urdishMap = {
    'meeting': 'ملاقات',
    'cancel': 'منسوخ',
    'postpone': 'ملتوی',
    'confirm': 'تصدیق',
    'schedule': 'نظام الاوقات',
    'deadline': 'آخری تاریخ',
    'office': 'دفتر',
    'hospital': 'ہسپتال',
    'school': 'اسکول',
    'university': 'یونیورسٹی',
    'phone': 'فون',
    'mobile': 'موبائل',
    'problem': 'مسئلہ',
    'issue': 'مسئلہ',
    'solution': 'حل',
    'project': 'منصوبہ',
    'report': 'رپورٹ',
    'payment': 'ادائیگی',
    'transfer': 'منتقلی',
    'interview': 'انٹرویو',
    'presentation': 'پیشکش',
    'computer': 'کمپیوٹر',
    'internet': 'انٹرنیٹ',
    'email': 'ای میل',
    'message': 'پیغام',
    'password': 'پاس ورڈ',
    'update': 'تازہ کاری',
    'download': 'ڈاؤن لوڈ',
    'upload': 'اپ لوڈ',
  };

  // ── Step 3: Filler words / STT noise ─────────────────────────────────────
  static final RegExp _fillerPattern = RegExp(
    r'\b(uh+|um+|er+|ah+|hmm+|ahem|like like|you know|basically basically)\b',
    caseSensitive: false,
  );

  // ── Main entry ────────────────────────────────────────────────────────────

  static NormalizedResult normalize(String rawText, String declaredSourceLang) {
    if (declaredSourceLang != 'ur') {
      return NormalizedResult(rawText, declaredSourceLang, false);
    }

    String text     = rawText.trim();
    final original  = text;

    // Step 1: Replace slang idioms (longest match first)
    text = _replaceSlang(text);

    // Step 2: Replace English loanwords with Urdu
    text = _replaceUrdish(text);

    // Step 3: Remove filler words
    text = text.replaceAll(_fillerPattern, '').replaceAll(RegExp(r'  +'), ' ').trim();

    // Step 4: Decide model
    final recommended = _chooseBestModel(text);

    return NormalizedResult(text, recommended, text != original);
  }

  // ── Steps ─────────────────────────────────────────────────────────────────

  static String _replaceSlang(String text) {
    final lower = text.toLowerCase();
    // Sort by length descending so multi-word phrases match first
    final keys = _slangMap.keys.toList()
      ..sort((a, b) => b.length - a.length);
    String result = text;
    for (final k in keys) {
      if (lower.contains(k)) {
        result = result.replaceAll(
          RegExp(RegExp.escape(k), caseSensitive: false),
          _slangMap[k]!,
        );
      }
    }
    return result;
  }

  static String _replaceUrdish(String text) {
    // Only replace whole words that are in Latin script (not already Urdu)
    String result = text;
    for (final entry in _urdishMap.entries) {
      final pattern = RegExp(
        r'(?<![a-zA-Z])' + RegExp.escape(entry.key) + r'(?![a-zA-Z])',
        caseSensitive: false,
      );
      result = result.replaceAll(pattern, entry.value);
    }
    return result;
  }

  static String _chooseBestModel(String text) {
    // Count Urdu/Arabic script characters
    final urduChars = text.runes.where((r) => r >= 0x0600 && r <= 0x06FF).length;
    final totalAlpha = text.runes
        .where((r) => (r >= 0x0041 && r <= 0x005A) || (r >= 0x0061 && r <= 0x007A) || (r >= 0x0600 && r <= 0x06FF))
        .length;
    if (totalAlpha == 0) return 'ur';
    final urduRatio = urduChars / totalAlpha;
    // If mostly Roman Urdu (Urdish), Hindi model works better in practice
    return urduRatio < 0.3 ? 'hi' : 'ur';
  }

  static String describeChanges(String original, NormalizedResult result) {
    if (!result.wasModified) return '';
    return 'Normalised: "${original.length > 30 ? original.substring(0, 30) : original}…" → Urdu';
  }
}
