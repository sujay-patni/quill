// Offline English dictionary: WordNet 3.0 (Princeton University; licence in
// assets/dictionary/LICENSE.txt), stored as text shards built by tools/build_dictionary_shards.py.
import 'package:flutter/services.dart' show rootBundle;

class DictionaryEntry {
  const DictionaryEntry(this.word, this.senses);

  /// The dictionary form that was found (may differ from what was looked up: "ran" → "run").
  final String word;

  /// (part of speech, definition) in WordNet's order.
  final List<(String, String)> senses;
}

class Dictionary {
  Dictionary({Future<String> Function(String asset)? load}) : _load = load ?? rootBundle.loadString;

  final Future<String> Function(String asset) _load;
  static const _shards = 64;
  final Map<int, Map<String, List<(String, String)>>> _cache = {};
  Map<String, List<String>>? _exceptions;

  static const credit = 'WordNet 3.0 · Princeton University';

  // Must match tools/build_dictionary_shards.py.
  static int shardOf(String word) {
    var h = 0;
    for (final unit in word.codeUnits) {
      h = (h * 31 + (unit & 0xff)) & 0x7FFFFFFF;
    }
    return h % _shards;
  }

  /// "Running," → "running"; multi-word entries use underscores, as in WordNet.
  static String normalise(String input) => input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r"[’']s$"), '')
      .replaceAll(RegExp(r'^[^a-z]+|[^a-z]+$'), '')
      .replaceAll(RegExp(r'\s+'), '_');

  Future<Map<String, List<(String, String)>>> _shard(int i) async {
    final hit = _cache[i];
    if (hit != null) return hit;
    final map = <String, List<(String, String)>>{};
    for (final line in (await _load('assets/dictionary/d${i.toString().padLeft(2, '0')}.txt')).split('\n')) {
      final a = line.indexOf('\t');
      if (a < 0) continue;
      final b = line.indexOf('\t', a + 1);
      if (b < 0) continue;
      (map[line.substring(0, a)] ??= []).add((line.substring(a + 1, b), line.substring(b + 1)));
    }
    if (_cache.length >= 6) _cache.remove(_cache.keys.first);
    return _cache[i] = map;
  }

  Future<List<String>> _irregular(String word) async {
    if (_exceptions == null) {
      final map = <String, List<String>>{};
      for (final line in (await _load('assets/dictionary/exceptions.txt')).split('\n')) {
        final t = line.indexOf('\t');
        if (t > 0) (map[line.substring(0, t)] ??= []).add(line.substring(t + 1));
      }
      _exceptions = map;
    }
    return _exceptions![word] ?? const [];
  }

  // WordNet's "morphy" endings: (suffix, replacement).
  static const _endings = [
    ('ies', 'y'), ('ches', 'ch'), ('shes', 'sh'), ('ses', 's'), ('xes', 'x'), ('zes', 'z'), ('men', 'man'), //
    ('es', 'e'), ('es', ''), ('s', ''), ('ed', 'e'), ('ed', ''), ('ing', 'e'), ('ing', ''), //
    ('est', ''), ('est', 'e'), ('er', ''), ('er', 'e'),
  ];

  /// The entry for [input], trying its dictionary forms; null when nothing is found.
  Future<DictionaryEntry?> lookup(String input) async {
    final word = normalise(input);
    if (word.isEmpty) return null;
    final candidates = <String>[
      word,
      ...await _irregular(word),
      for (final (suffix, to) in _endings)
        if (word.length > suffix.length + 1 && word.endsWith(suffix)) word.substring(0, word.length - suffix.length) + to,
    ];
    for (final c in candidates) {
      final senses = (await _shard(shardOf(c)))[c];
      if (senses != null && senses.isNotEmpty) return DictionaryEntry(c.replaceAll('_', ' '), senses);
    }
    return null;
  }
}
