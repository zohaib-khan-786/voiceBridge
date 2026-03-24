// lib/utils/fuzzy_matcher.dart
// Pure Dart fuzzy correction for Roman Urdu STT output.
// Fixes phonetic mishearings before anything else sees the text.
// e.g. "meetng cancle kar do" → "meeting cancel kar do"

class FuzzyResult {
  final String corrected;
  final bool wasModified;
  final List<String> changesApplied;
  const FuzzyResult(this.corrected, this.wasModified, this.changesApplied);
}

class FuzzyMatcher {
  static const int _maxDist  = 2;    // max edit distance
  static const double _minRatio = 0.7; // min similarity ratio

  // Known-good Roman Urdu vocabulary (common words that STT misses)
  static const List<String> _dictionary = [
    // Common Roman Urdu words
    'aaj', 'kal', 'parso', 'abhi', 'yaar', 'bhai', 'dost', 'behen',
    'theek', 'theek hai', 'bilkul', 'zaroor', 'shayad', 'lagta', 'samajh',
    'meeting', 'cancel', 'postpone', 'confirm', 'complete', 'finish', 'done',
    'office', 'ghar', 'school', 'hospital', 'market', 'baazar', 'station',
    'phone', 'call', 'message', 'email', 'report', 'document', 'file',
    'kya', 'kyun', 'kaise', 'kahan', 'kab', 'kaun', 'kitna', 'kitni',
    'acha', 'accha', 'thoda', 'zyada', 'bohot', 'bilkul', 'sirf', 'bas',
    'hai', 'hain', 'tha', 'thi', 'the', 'ho', 'ho gaya', 'ho gayi',
    'kar', 'karo', 'karna', 'karein', 'kar do', 'kar dena',
    'batao', 'batana', 'dekho', 'dekhna', 'suno', 'sunna',
    'pahunch', 'pahuncha', 'pahunchna', 'aao', 'jana', 'jao', 'chalna',
    'ruk', 'ruko', 'rukna', 'wait', 'intezaar',
    'paise', 'rupees', 'raqam', 'takheen', 'jaldi', 'dheere',
    // English loanwords commonly in Roman Urdu
    'please', 'thanks', 'sorry', 'hello', 'bye', 'okay', 'ok',
    'actually', 'basically', 'seriously', 'definitely', 'probably',
    'problem', 'issue', 'solution', 'idea', 'plan', 'schedule',
    'appointment', 'interview', 'presentation', 'project', 'deadline',
    'payment', 'transfer', 'account', 'deposit', 'withdrawal',
  ];

  static final Set<String> _wordSet = Set.unmodifiable(_dictionary);

  // ── Main entry point ──────────────────────────────────────────────────────

  static FuzzyResult correct(String rawText) {
    if (rawText.trim().isEmpty) return FuzzyResult(rawText, false, []);

    final words    = rawText.split(RegExp(r'\s+'));
    final changes  = <String>[];
    bool modified  = false;

    final corrected = words.map((word) {
      final lower = word.toLowerCase();
      // Already a known word — no correction needed
      if (_wordSet.contains(lower)) return word;

      // Find closest match
      final best = _findBestMatch(lower);
      if (best != null && best != lower) {
        changes.add('$word → $best');
        modified = true;
        // Preserve original capitalisation
        if (word[0] == word[0].toUpperCase()) {
          return best[0].toUpperCase() + best.substring(1);
        }
        return best;
      }
      return word;
    }).join(' ');

    return FuzzyResult(corrected, modified, changes);
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  static String? _findBestMatch(String word) {
    if (word.length < 3) return null;
    String? bestWord;
    int    bestDist = _maxDist + 1;

    for (final candidate in _dictionary) {
      if ((candidate.length - word.length).abs() > _maxDist) continue;
      final dist = _levenshtein(word, candidate);
      if (dist < bestDist) {
        // Also check similarity ratio to avoid over-corrections
        final ratio = 1.0 - dist / [word.length, candidate.length].reduce((a, b) => a > b ? a : b);
        if (ratio >= _minRatio) {
          bestDist = dist;
          bestWord = candidate;
        }
      }
    }
    return bestWord;
  }

  static int _levenshtein(String a, String b) {
    final m = a.length, n = b.length;
    if (m == 0) return n;
    if (n == 0) return m;

    // Only keep two rows to save memory
    List<int> prev = List.generate(n + 1, (i) => i);
    List<int> curr = List.filled(n + 1, 0);

    for (int i = 1; i <= m; i++) {
      curr[0] = i;
      for (int j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost]
            .reduce((x, y) => x < y ? x : y);
      }
      final tmp = prev; prev = curr; curr = tmp;
    }
    return prev[n];
  }
}
