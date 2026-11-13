// Native engine: Liang hyphenation with the TeX American English patterns
// (assets/hyph-en-us.txt, permissive licence kept in that file).
import 'package:flutter/services.dart' show rootBundle;

class Hyphenator {
  Hyphenator(String data) {
    var exceptions = false;
    for (final raw in data.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line == '---') {
        exceptions = true;
        continue;
      }
      if (exceptions) {
        final word = line.replaceAll('-', '');
        final breaks = <int>[];
        var at = 0;
        for (final part in line.split('-')) {
          at += part.length;
          if (at < word.length) breaks.add(at);
        }
        _exceptions[word] = breaks;
      } else {
        // "a1b2c" → letters "abc", digits [0,1,2,0] (one more digit slot than letters).
        final letters = StringBuffer();
        final digits = <int>[0];
        for (final unit in line.codeUnits) {
          if (unit >= 0x30 && unit <= 0x39) {
            digits[digits.length - 1] = unit - 0x30;
          } else {
            letters.writeCharCode(unit);
            digits.add(0);
          }
        }
        final key = letters.toString();
        _patterns[key] = digits;
        if (key.length > _longest) _longest = key.length;
      }
    }
  }

  static Hyphenator? _english;
  static Future<Hyphenator>? _loading;

  /// The English hyphenator, loaded once from the app's assets.
  static Future<Hyphenator> english() =>
      _loading ??= rootBundle.loadString('assets/hyph-en-us.txt').then((data) => _english = Hyphenator(data));

  /// Installs [h] directly (tests).
  static void install(Hyphenator? h) => _english = h;

  /// Available after [english] has completed.
  static Hyphenator? get loaded => _english;

  final Map<String, List<int>> _patterns = {};
  final Map<String, List<int>> _exceptions = {};
  final Map<String, List<int>> _cache = {};
  var _longest = 0;

  static const leftMin = 2, rightMin = 3;

  /// Indices in [word] (lower-case a–z) before which a hyphen may go.
  List<int> breaks(String word) {
    if (word.length < leftMin + rightMin) return const [];
    final known = _exceptions[word] ?? _cache[word];
    if (known != null) return known;
    final s = '.$word.';
    final points = List<int>.filled(s.length + 1, 0);
    for (var i = 0; i < s.length; i++) {
      final end = i + _longest < s.length ? i + _longest : s.length;
      for (var j = i + 1; j <= end; j++) {
        final digits = _patterns[s.substring(i, j)];
        if (digits == null) continue;
        for (var k = 0; k < digits.length; k++) {
          if (digits[k] > points[i + k]) points[i + k] = digits[k];
        }
      }
    }
    final out = <int>[];
    for (var i = leftMin; i <= word.length - rightMin; i++) {
      if (points[i + 1].isOdd) out.add(i);
    }
    if (_cache.length > 20000) _cache.clear();
    return _cache[word] = out;
  }

  /// Offsets in [text] where a soft hyphen may be inserted (before the character at that offset).
  List<int> softBreaks(String text) {
    final out = <int>[];
    var start = -1;
    for (var i = 0; i <= text.length; i++) {
      final c = i < text.length ? text.codeUnitAt(i) | 0x20 : 0;
      final letter = c >= 0x61 && c <= 0x7a && (i == text.length || text.codeUnitAt(i) < 0x80);
      if (letter) {
        if (start < 0) start = i;
      } else if (start >= 0) {
        // Skip words joined to non-ASCII letters or digits (names with accents, codes).
        final beforeOk = start == 0 || !_wordish(text.codeUnitAt(start - 1));
        final afterOk = i == text.length || !_wordish(text.codeUnitAt(i));
        if (beforeOk && afterOk && i - start >= leftMin + rightMin) {
          for (final b in breaks(text.substring(start, i).toLowerCase())) {
            out.add(start + b);
          }
        }
        start = -1;
      }
    }
    return out;
  }

  static bool _wordish(int unit) => unit >= 0x80 || (unit >= 0x30 && unit <= 0x39);
}
